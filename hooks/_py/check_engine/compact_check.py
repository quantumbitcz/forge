"""PostToolUse(Agent) compaction hint + handoff trigger."""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import IO

from hooks._py.handoff.config import load_handoff_config
from hooks._py.handoff.triggers import TriggerContext, decide_trigger
from hooks._py.handoff.writer import WriteRequest, write_handoff
from hooks._py.platform_support import forge_dir

SUGGEST_THRESHOLD_TOKENS = 180_000
# Conservative default context window when model is unknown. Matches
# shared/context-condensation.md.
DEFAULT_MODEL_WINDOW = 200_000


def main(stdin: IO[str] | None = None) -> int:
    stdin = stdin or sys.stdin
    _ = stdin.read()
    fdir = forge_dir()
    if not fdir.exists():
        return 0
    state_path = fdir / "state.json"
    if not state_path.exists():
        return 0
    try:
        doc = json.loads(state_path.read_text())
    except json.JSONDecodeError:
        return 0

    total = ((doc.get("tokens") or {}).get("total") or {})
    used = int(total.get("prompt", 0)) + int(total.get("completion", 0))

    # Preserve legacy stderr hint
    if used >= SUGGEST_THRESHOLD_TOKENS:
        print(
            f"forge: context at {used:,} tokens — consider /compact to free room",
            file=sys.stderr,
        )

    # New: handoff trigger
    run_id = doc.get("run_id")
    if not run_id:
        return 0

    cfg_path = Path(".claude/forge-config.md")
    cfg = load_handoff_config(cfg_path if cfg_path.exists() else None)

    ctx = TriggerContext(
        autonomous=bool(doc.get("autonomous", False)),
        background=bool(doc.get("background", False)),
        model_window_tokens=DEFAULT_MODEL_WINDOW,
        estimated_tokens=used,
        last_written_at=None,  # writer re-checks state.json directly
        now=datetime.now(timezone.utc),
    )
    decision = decide_trigger(ctx, cfg)
    if decision.level is None:
        return 0

    req = WriteRequest(
        run_id=str(run_id),
        level=decision.level,
        reason=decision.reason,
        variant="light" if decision.level == "soft" else "full",
        trigger_threshold_pct=int(decision.utilisation_pct),
        trigger_tokens=used,
    )
    try:
        write_handoff(req, forge_dir=fdir)
    except Exception as e:
        print(f"forge: handoff writer failed: {e}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
