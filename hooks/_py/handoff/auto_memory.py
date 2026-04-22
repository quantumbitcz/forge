"""Auto-memory promotion from terminal handoffs."""
from __future__ import annotations

import hashlib
import os
import re
from pathlib import Path

from hooks._py.handoff.frontmatter import _safe_yaml_scalar


def _memory_root() -> Path:
    env = os.environ.get("FORGE_AUTO_MEMORY_ROOT")
    if env:
        return Path(env)
    home = Path(os.environ.get("HOME", "."))
    # Claude Code per-project memory convention: ~/.claude/projects/<hash>/memory/
    # where <hash> is cwd with '/' replaced by '-'.
    cwd = Path.cwd().resolve()
    project_hash = str(cwd).replace("/", "-")
    return home / ".claude" / "projects" / project_hash / "memory"


def _slug(text: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")
    base = (s[:30] or "entry").rstrip("_")
    # Short hash suffix to prevent collisions on long or similar texts
    suffix = hashlib.sha1(text.encode("utf-8")).hexdigest()[:6]
    return f"{base}_{suffix}"


def promote_from_terminal_handoff(
    run_id: str,
    preempts: list[dict],
    user_decisions: list[str],
) -> list[Path]:
    root = _memory_root()
    root.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []

    top = [p for p in preempts if str(p.get("confidence", "")).upper() == "HIGH"][:3]
    for p in top:
        text = str(p.get("text", "")).strip()
        if not text:
            continue
        path = root / f"forge_handoff_preempt_{_slug(text)}.md"
        path.write_text(
            "---\n"
            f"name: {_safe_yaml_scalar('PREEMPT — ' + text)}\n"
            "description: Auto-promoted from forge terminal handoff\n"
            "type: project\n"
            "---\n\n"
            f"{text}\n\n"
            f"**Why:** Promoted from run `{run_id}` terminal handoff.\n"
            "**How to apply:** Treat as a HIGH-confidence rule for this repo.\n"
        )
        written.append(path)

    for decision in user_decisions:
        text = decision.strip()
        if not text:
            continue
        path = root / f"forge_handoff_user_{_slug(text)}.md"
        path.write_text(
            "---\n"
            f"name: {_safe_yaml_scalar('User directive — ' + text[:40])}\n"
            "description: Auto-promoted user decision from forge terminal handoff\n"
            "type: project\n"
            "---\n\n"
            f"{text}\n\n"
            f"**Why:** Captured from run `{run_id}` user_decisions tag.\n"
            "**How to apply:** Respect this directive in future work on this repo.\n"
        )
        written.append(path)

    return written
