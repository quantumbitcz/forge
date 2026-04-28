"""Automation trigger dispatcher — replaces hooks/automation-trigger.sh.

Parses the `automations:` block out of forge-config.md (fenced YAML),
enforces per-rule cooldowns via .forge/automation-log.jsonl, and dispatches
matching skills. Stdlib-only; the YAML extraction uses a minimal regex-based
parser sufficient for the fenced `automations:` block used by forge-config.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path


@dataclass
class DispatchResult:
    exit_code: int
    dispatched: bool
    reason: str = ""
    skill: str | None = None
    log_entry: dict = field(default_factory=dict)


# --- Minimal YAML extraction (sufficient for forge-config.md's automations block) ---

_YAML_FENCE = re.compile(r"```ya?ml\n(.*?)\n```", re.DOTALL)


def _extract_automations(config_text: str) -> dict:
    """Pull the `automations:` mapping out of the fenced YAML in forge-config.md.

    The plugin already ships a strict config-validator; this parser only needs to
    read shape `enabled`, `cooldown_seconds`, and `rules: [ {trigger, skill} ]`.
    """
    out: dict = {}
    for block in _YAML_FENCE.findall(config_text):
        if "automations:" not in block:
            continue
        result = _parse_yaml_subset(block)
        auto = result.get("automations")
        if isinstance(auto, dict):
            out.update(auto)
    return out


def _parse_yaml_subset(text: str) -> dict:
    """Accept a very small YAML dialect sufficient for forge-config's automations:

      key: value
      key:
        nested: value
      key:
        - trigger: x
          skill: y
        - trigger: z
          skill: w

    No anchors, no flow-style, plain scalars only (numbers / bools / bare strings).
    """
    root: dict = {}
    # Stack frames: (indent, container, container_type) where container_type is
    # 'dict' or 'list'. The root is a dict at indent -1 so any top-level line
    # (indent 0) nests under it.
    stack: list[tuple[int, object, str]] = [(-1, root, "dict")]
    # When we see `key:` with no value, we don't yet know whether the child is
    # a dict or a list. We defer the decision: stash pending_key and create the
    # container on the first child line based on whether it starts with `- `.
    pending_key: str | None = None
    pending_owner: dict | None = None
    pending_indent: int = -1

    lines = text.splitlines()
    for raw in lines:
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        line = raw.strip()

        # If we have a pending key, the very next meaningful line with strictly
        # greater indent than the owner determines the child container's type.
        if pending_key is not None and indent > pending_indent:
            container: object
            if line.startswith("- "):
                container = []
                pending_owner[pending_key] = container  # type: ignore[index]
                stack.append((indent, container, "list"))
            else:
                container = {}
                pending_owner[pending_key] = container  # type: ignore[index]
                stack.append((indent, container, "dict"))
            pending_key = None
            pending_owner = None
            pending_indent = -1
        elif pending_key is not None:
            # Pending key had no children — leave it as empty dict.
            pending_owner[pending_key] = {}  # type: ignore[index]
            pending_key = None
            pending_owner = None
            pending_indent = -1

        # Pop frames whose indent is >= this line's indent (we've exited them).
        # For list items, the `- ` itself lives at the list's indent, so we pop
        # only when strictly less; for mapping keys, we pop when <= the frame.
        while stack and indent < stack[-1][0]:
            stack.pop()

        parent_indent, parent, parent_type = stack[-1]

        if line.startswith("- "):
            # List item. Parent must be a list frame at this indent (or we pop
            # one more level to reach it). If not a list, fall back: treat as
            # nested list under the nearest dict owner (should not happen in
            # valid input).
            if parent_type != "list" or parent_indent != indent:
                # Walk down until we find a matching list frame.
                while stack and not (stack[-1][2] == "list" and stack[-1][0] == indent):
                    if stack[-1][0] < indent:
                        break
                    stack.pop()
                if not stack or stack[-1][2] != "list":
                    continue  # malformed; skip
                parent_indent, parent, parent_type = stack[-1]

            item: dict = {}
            parent.append(item)  # type: ignore[attr-defined]
            rest = line[2:]
            k, sep, v = rest.partition(":")
            if sep:
                k = k.strip()
                v = v.strip()
                if v:
                    item[k] = _coerce(v)
                    # Item continuation lines (same-indent `  key: val`) target this item
                    # at indent + 2 (the two spaces after `- `). Push the item as a dict
                    # frame at that deeper indent.
                    stack.append((indent + 2, item, "dict"))
                else:
                    # `- key:` with child dict/list — pending handling.
                    stack.append((indent + 2, item, "dict"))
                    pending_key = k
                    pending_owner = item
                    pending_indent = indent + 2
            continue

        # Plain `key: value` or `key:` line.
        k, sep, v = line.partition(":")
        if not sep:
            continue  # malformed
        k = k.strip()
        v = v.strip()

        # The target container is the nearest frame whose indent is < this line's.
        # For a dict frame, append key. For a list frame, ignore (shouldn't happen
        # since list items start with `-`).
        if parent_type != "dict":
            # Unwind until we find a dict frame.
            while stack and stack[-1][2] != "dict":
                stack.pop()
            if not stack:
                continue
            parent_indent, parent, parent_type = stack[-1]

        if v:
            parent[k] = _coerce(v)  # type: ignore[index]
        else:
            # Defer deciding child container type until we see the next line.
            pending_key = k
            pending_owner = parent  # type: ignore[assignment]
            pending_indent = indent

    # Clean up a trailing pending key (no children at EOF).
    if pending_key is not None and pending_owner is not None:
        pending_owner.setdefault(pending_key, {})

    return root


def _coerce(v: str):
    low = v.lower()
    if low in ("true", "yes", "on"):
        return True
    if low in ("false", "no", "off"):
        return False
    try:
        return int(v)
    except ValueError:
        pass
    try:
        return float(v)
    except ValueError:
        pass
    return v.strip('"').strip("'")


# --- Cooldown bookkeeping ---


def _last_dispatch(log_path: Path, *, trigger: str, skill: str) -> datetime | None:
    if not log_path.exists():
        return None
    last = None
    for line in log_path.read_text().splitlines():
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        if entry.get("trigger") == trigger and entry.get("skill") == skill:
            ts = entry.get("timestamp")
            if ts:
                try:
                    last = datetime.fromisoformat(ts.replace("Z", "+00:00"))
                except ValueError:
                    continue
    return last


def _append_log(log_path: Path, entry: dict) -> None:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with open(log_path, "a", encoding="utf-8") as fp:
        fp.write(json.dumps(entry) + "\n")


# --- Public API ---


def run(
    *,
    trigger: str,
    payload: dict,
    forge_dir: Path,
    config_path: Path | None = None,
) -> DispatchResult:
    cfg_text = config_path.read_text() if config_path and config_path.exists() else ""
    auto = _extract_automations(cfg_text)
    if not auto.get("enabled", False):
        return DispatchResult(exit_code=2, dispatched=False, reason="disabled")
    cooldown = int(auto.get("cooldown_seconds", 300))
    rules = auto.get("rules") or []
    matched = [r for r in rules if isinstance(r, dict) and r.get("trigger") == trigger]
    if not matched:
        return DispatchResult(exit_code=2, dispatched=False, reason="no_match")
    log_path = forge_dir / "automation-log.jsonl"
    now = datetime.now(timezone.utc)
    # Dispatch the first matched rule (preserves legacy shell behavior).
    rule = matched[0]
    skill = rule.get("skill")
    last = _last_dispatch(log_path, trigger=trigger, skill=skill)
    if last and (now - last).total_seconds() < cooldown:
        return DispatchResult(
            exit_code=0, dispatched=False, reason="cooldown", skill=skill,
        )
    entry = {
        "timestamp": now.isoformat(),
        "trigger": trigger,
        "skill": skill,
        "payload": payload,
    }
    _append_log(log_path, entry)
    return DispatchResult(
        exit_code=0, dispatched=True, reason="dispatched", skill=skill, log_entry=entry,
    )


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Dispatches forge skills based on automation trigger events."
    )
    ap.add_argument("--trigger", required=True)
    ap.add_argument("--payload", default="{}")
    ap.add_argument("--forge-dir", default=".forge")
    ap.add_argument("--config", default=".claude/forge-admin config.md")
    args = ap.parse_args()
    try:
        payload = json.loads(args.payload)
    except json.JSONDecodeError:
        print("ERROR: --payload must be valid JSON", file=sys.stderr)
        return 1
    result = run(
        trigger=args.trigger,
        payload=payload,
        forge_dir=Path(args.forge_dir),
        config_path=Path(args.config),
    )
    if result.dispatched:
        print(f"dispatched: {result.skill}")
    else:
        print(f"skipped: {result.reason}")
    return result.exit_code


if __name__ == "__main__":
    sys.exit(main())
