"""Read-only implementer simulator for scenario tests.

Implements §5.3b decision logic from agents/fg-300-implementer.md and prints
human-readable log lines that scenario bats tests pattern-match.
"""
from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path


def main() -> int:
    forge_dir = Path(os.environ["FORGE_DIR"])
    task_id = sys.argv[2] if len(sys.argv) > 2 else "task-sim"
    state_path = forge_dir / "state.json"
    st = json.loads(state_path.read_text())
    cost = st["cost"]
    ceiling = float(cost.get("ceiling_usd", 0))
    remaining = float(cost.get("remaining_usd", 0))
    frac = remaining / ceiling if ceiling > 0 else 1.0
    pct = round((1.0 - frac) * 100, 1)

    print("RED phase executed")
    print("GREEN phase executed")

    severity = None
    action = None
    if frac > 0.20:
        print("refactor pass #2 executed")
        print("fg-301-implementer-judge dispatched")
    elif frac > 0.10:
        severity = "INFO"
        action = "skip_refactor_pass_2"
        print(f"COST-THROTTLE-IMPL severity: INFO — skipped refactor #2 @ {pct}%")
        print("fg-301-implementer-judge dispatched")
    else:
        severity = "WARNING"
        action = "skip_refactor_and_judge"
        print(f"COST-THROTTLE-IMPL severity: WARNING — skipped refactor+judge @ {pct}%")
        print("REFLECT_SKIPPED_COST")

    if severity:
        cost.setdefault("throttle_events", []).append({
            "agent": "fg-300-implementer",
            "severity": severity,
            "pct_consumed": round(1.0 - frac, 4),
            "action": action,
            "task_id": task_id,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        })
        st["cost"] = cost
        state_path.write_text(json.dumps(st, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
