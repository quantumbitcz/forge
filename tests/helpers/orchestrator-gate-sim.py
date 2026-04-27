"""Read-only simulator for fg-100-orchestrator's §Cost Governance dispatch gate.

Executes Steps 1-5 from agents/fg-100-orchestrator.md §Cost Governance but
instead of dispatching a real subagent, emits the AskUserQuestion payload (or
autonomous decision log) to stdout as JSON. Scenario tests match against it.
"""
from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(os.environ["PLUGIN_ROOT"]) / "shared"))
from cost_governance import (  # noqa: E402  (path injection above)
    SAFETY_CRITICAL,
    compute_budget_block,
    downgrade_tier,
    is_safety_critical,
    project_spend,
    write_incident,
)


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def main() -> int:
    forge_dir = Path(os.environ["FORGE_DIR"])
    agent_name = sys.argv[1]
    resolved_tier = sys.argv[2]
    state_path = forge_dir / "state.json"
    st = json.loads(state_path.read_text())
    cost_cfg = {
        "ceiling_usd": st["cost"]["ceiling_usd"],
        "tier_estimates_usd": st["cost"]["tier_estimates_usd"],
        "conservatism_multiplier": st["cost"]["conservatism_multiplier"],
        "aware_routing": True,
        "pinned_agents": [],
    }
    ceiling = cost_cfg["ceiling_usd"]
    spent = st["cost"]["spent_usd"]
    tier_est = cost_cfg["tier_estimates_usd"][resolved_tier]
    projected = project_spend(spent, tier_est)

    if ceiling == 0 or projected <= ceiling:
        print(json.dumps({"action": "dispatch", "agent": agent_name, "tier": resolved_tier}))
        return 0

    # Breach.
    autonomous = bool(st.get("autonomous", False))
    if autonomous:
        new_tier, reason = downgrade_tier(
            agent=agent_name,
            resolved_tier=resolved_tier,
            remaining_usd=max(0.0, ceiling - spent),
            tier_estimates=cost_cfg["tier_estimates_usd"],
            conservatism_multiplier=cost_cfg["conservatism_multiplier"],
            pinned_agents=[],
            aware_routing=True,
        )
        if new_tier != resolved_tier:
            decision = "downgrade"
            print(json.dumps({
                "action": "auto-decide",
                "decision": decision,
                "from": resolved_tier,
                "to": new_tier,
            }))
        else:
            decision = "abort_to_ship"
            print(json.dumps({"action": "auto-decide", "decision": decision}))
    else:
        raised = round(ceiling * 1.4)
        payload = {
            "question": (
                f"Next dispatch would breach cost ceiling (${ceiling:.2f}). "
                f"Projected: ${projected:.2f}. How should we proceed?"
            ),
            "header": "Cost ceiling",
            "multiSelect": False,
            "options": [
                {
                    "label": f"Raise ceiling to ${raised}",
                    "description": "Continues run. Records new ceiling in state for this run only.",
                },
                {
                    "label": "Downgrade remaining agents (Recommended)",
                    "description": (
                        "Switches premium->standard, standard->fast where safe. "
                        "Excludes pinned agents and safety-critical reviewers."
                    ),
                },
                {
                    "label": "Abort to ship current state",
                    "description": "Runs pre-ship verifier on what's in the worktree, then ships or exits.",
                },
                {
                    "label": "Abort fully",
                    "description": "Stops immediately. Preserves state for /forge-recover resume.",
                },
            ],
        }
        print(json.dumps({"action": "ask-user", "payload": payload}))
        decision = "abort_full"  # default for the harness — overridden in tests.

    incident = {
        "timestamp": now_iso(),
        "ceiling_usd": ceiling,
        "spent_usd": round(spent, 4),
        "projected_usd": round(projected, 4),
        "next_agent": agent_name,
        "resolved_tier": resolved_tier,
        "decision": decision,
        "autonomous": autonomous,
        "run_id": st.get("run_id", "unknown"),
    }
    write_incident(incident, forge_dir)
    st["cost"]["ceiling_breaches"] = st["cost"].get("ceiling_breaches", 0) + 1
    state_path.write_text(json.dumps(st, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
