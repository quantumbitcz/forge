"""Layer-1 enforcement for fg-540 dispatch context.

Two responsibilities:

1. ``build_intent_verifier_context`` projects the orchestrator's full state
   snapshot down to a small allow-list of keys, then runs a deep-leak check
   that catches forbidden-marker substrings smuggled inside string values.
   This is the construction-site Layer-1 defense; ``fg-540-intent-verifier``
   owns Layer-2 (defense-in-depth) inside the agent's prompt.

2. ``_read_acs`` resolves the canonical AC list per Mega-spec §14:
   ``state.brainstorm.spec_path`` (when present and the file exists) wins;
   ``.forge/specs/index.json`` keyed by ``active_spec_slug`` is the fallback
   for bugfix/migration/bootstrap modes that never brainstormed.
"""
from __future__ import annotations

import json
import logging
import re
from pathlib import Path
from typing import Any

log = logging.getLogger(__name__)

ALLOWED_KEYS = frozenset({
    "requirement_text", "active_spec_slug", "ac_list",
    "runtime_config", "probe_sandbox", "mode",
})


class IntentContextLeak(Exception):
    """Raised when build_intent_verifier_context sees a forbidden key."""


_FORBIDDEN_MARKERS = (
    "stage_2_notes", "stage_4_notes", "stage_6_notes",
    "implementation_diff", "git_diff", "tdd_history",
    "prior_findings", "test_code",
)

# Scalar leaf types that are safe to ignore (no payload to walk).
_SCALAR_LEAVES: tuple[type, ...] = (bool, int, float, type(None))


def _check_string(value: str, path: str) -> None:
    low = value.lower()
    for marker in _FORBIDDEN_MARKERS:
        if marker in low:
            raise IntentContextLeak(f"marker {marker!r} found at {path}")


def _deep_leak_check(obj: Any, path: str = "") -> None:
    """Walk the built context; raise if any string value (including dict
    keys, tuple/set members, and decoded bytes) contains a forbidden marker
    substring. Unknown container types fail closed to surface schema drift.
    """
    if isinstance(obj, str):
        _check_string(obj, path)
        return
    if isinstance(obj, _SCALAR_LEAVES):
        return
    if isinstance(obj, (bytes, bytearray)):
        # Decode and recurse so binary smuggling can't bypass the check.
        decoded = bytes(obj).decode("utf-8", errors="replace")
        _check_string(decoded, f"{path}<bytes>")
        return
    if isinstance(obj, dict):
        for k, v in obj.items():
            # Dict keys can themselves carry markers — check before recursing.
            if isinstance(k, str):
                _check_string(k, f"{path}.<key:{k!r}>")
            _deep_leak_check(v, f"{path}.{k}")
        return
    if isinstance(obj, (list, tuple, set, frozenset)):
        for i, v in enumerate(obj):
            _deep_leak_check(v, f"{path}[{i}]")
        return
    # Fail closed: any unsupported container type would mask the leak check.
    raise IntentContextLeak(
        f"unsupported context type at {path}: {type(obj).__name__}"
    )


def build_intent_verifier_context(full_state_snapshot: dict[str, Any]) -> dict[str, Any]:
    """Project the caller's state snapshot onto ALLOWED_KEYS.

    The caller passes in whatever they have (including plan / diff / findings
    if they erroneously bundled them); this function constructively returns
    ONLY the allow-listed keys. The AC list is resolved here via ``_read_acs``
    so the orchestrator does not need to duplicate the precedence logic. If
    the caller tries to smuggle extras via a key-collision (e.g.
    ``{"requirement_text": {"plan": "..."}}``), the deep-leak check catches
    substring matches of forbidden markers — except for ``requirement_text``
    itself, which is user prose and may legitimately mention forbidden marker
    names without carrying their payloads.
    """
    built: dict[str, Any] = {}
    for key in ALLOWED_KEYS:
        value = full_state_snapshot.get(key)
        if value is None:
            continue
        built[key] = value
    # Resolve the canonical AC list (brainstorm spec wins; index.json fallback).
    built["ac_list"] = _read_acs(full_state_snapshot)
    # requirement_text is end-user prose — exempt from the substring marker
    # check (false positives on legitimate language like "the prior findings
    # showed..."). Every other field is allow-listed structured data and
    # MUST stay marker-free.
    check_target = {k: v for k, v in built.items() if k != "requirement_text"}
    _deep_leak_check(check_target)
    return built


# ---------------------------------------------------------------------------
# AC resolution (Mega-spec §14)
# ---------------------------------------------------------------------------

# Applied line-by-line; do not switch to multi-line search without re.MULTILINE.
# Tightened to require an explicit terminator (``:``, ``.``, or ``)``) AFTER the
# AC ID and at least one non-whitespace character of body. This rejects
# reference-style mentions like "Section AC-001 covers..." that previously
# parsed as ACs.
_AC_HEADING_RE = re.compile(
    r"^\s*(?:[-*]\s+)?(?:\*\*)?(AC-\d{3,})(?:\*\*)?[:.)]\s+(\S.+?)\s*$"
)
_AC_TEXT_MAX_LEN = 500


def _read_acs(state: dict[str, Any]) -> list[dict[str, Any]]:
    """Resolve the canonical AC list for this run.

    Precedence (Mega-spec §14):
      1. ``state["brainstorm"]["spec_path"]`` — when present AND the file
         exists, parse AC-NNN bullets from the spec and return that list.
         This is the canonical source whenever BRAINSTORMING ran.
      2. ``.forge/specs/index.json`` keyed by ``state["active_spec_slug"]``
         — fallback for bugfix/migration/bootstrap modes (no brainstorm
         spec) and for runs predating the Mega rollout.

    Returns ``[]`` when neither source yields ACs (caller decides whether
    to emit ``INTENT-NO-ACS``).
    """
    brainstorm = state.get("brainstorm") or {}
    spec_path = brainstorm.get("spec_path")
    if spec_path:
        p = Path(spec_path)
        # Path.is_file() returns False for non-existent paths, so the explicit
        # exists() check is redundant.
        if p.is_file():
            acs = _parse_acs_from_spec(p.read_text(encoding="utf-8"))
            if acs:
                return acs

    return _read_acs_from_index(state.get("active_spec_slug"))


def _parse_acs_from_spec(spec_text: str) -> list[dict[str, Any]]:
    """Extract AC-NNN bullets from a brainstorm spec markdown body.

    Format: any line of the form ``- AC-NNN: text`` or ``- **AC-NNN**: text``
    or ``* AC-NNN. text`` is treated as an acceptance criterion. AC IDs
    follow the existing ``AC-NNN`` convention (3+ digits). Body text is
    capped at ``_AC_TEXT_MAX_LEN`` to bound downstream context size.
    """
    acs: list[dict[str, Any]] = []
    seen: set[str] = set()
    for line in spec_text.splitlines():
        m = _AC_HEADING_RE.match(line)
        if not m:
            continue
        ac_id = m.group(1)
        text = m.group(2).strip()[:_AC_TEXT_MAX_LEN]
        if ac_id in seen:
            continue
        seen.add(ac_id)
        acs.append({"ac_id": ac_id, "text": text})
    return acs


def _read_acs_from_index(slug: str | None) -> list[dict[str, Any]]:
    """Fallback: read ACs from .forge/specs/index.json by slug."""
    if not slug:
        return []
    index = Path(".forge") / "specs" / "index.json"
    if not index.exists():
        return []
    try:
        data = json.loads(index.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return []
    spec = (data.get("specs") or {}).get(slug) or {}
    raw = spec.get("acceptance_criteria") or []
    if not raw:
        log.info("ac_resolution_empty", extra={"slug": slug})
    out: list[dict[str, Any]] = []
    for entry in raw:
        if isinstance(entry, dict) and "ac_id" in entry:
            out.append({"ac_id": entry["ac_id"], "text": entry.get("text", "")})
    return out
