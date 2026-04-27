"""Cost governance primitives — pure functions for Phase 6.

Imported by fg-100-orchestrator dispatch path and fg-700-retrospective analytics.
No I/O here except write_incident() which writes a single file atomically.
All other functions are pure: take values, return values, no side effects.
"""
from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path
from typing import Any

# Authoritative SAFETY_CRITICAL set. Hardcoded, NOT user-configurable.
# Rationale: a run that ships without a security review to save $0.30 is a bug.
# fg-506-migration-verifier is only dispatched when state.mode == "migration";
# listing it here ensures it is never silently dropped during migration runs
# under cost pressure.
SAFETY_CRITICAL: frozenset[str] = frozenset({
    "fg-210-validator",
    "fg-250-contract-validator",
    "fg-411-security-reviewer",
    "fg-412-architecture-reviewer",
    "fg-414-license-reviewer",
    "fg-419-infra-deploy-reviewer",
    "fg-500-test-gate",
    "fg-505-build-verifier",
    "fg-506-migration-verifier",
    "fg-590-pre-ship-verifier",
})

# Tier ordering for downgrade resolution.
_TIER_DOWNGRADE_CHAIN = {"premium": "standard", "standard": "fast", "fast": None}


def compute_budget_block(
    *, ceiling_usd: float, spent_usd: float, tier: str, tier_estimate: float
) -> str:
    """Return the `## Cost Budget` markdown block for injection into a dispatch brief.

    Staleness contract: `spent_usd` is last-recorded (1 dispatch stale is acceptable).
    The tier_estimate is listed separately so the agent can project on its own.
    """
    if ceiling_usd <= 0:
        return (
            "## Cost Budget\n"
            "- Spent: ${:.2f} (unlimited — no ceiling configured)\n"
            "- Your tier: {} (est ${:.3f} per iteration)\n"
        ).format(spent_usd, tier, tier_estimate)

    remaining = max(0.0, ceiling_usd - spent_usd)
    pct = (spent_usd / ceiling_usd * 100.0) if ceiling_usd > 0 else 0.0
    per_iter = tier_estimate if tier_estimate > 0 else 0.001
    permits = int(remaining / per_iter) if per_iter > 0 else 0

    return (
        "## Cost Budget\n"
        "- Spent: ${:.2f} of ${:.2f} ceiling ({:.1f}%)\n"
        "- Remaining: ${:.2f}\n"
        "- Your tier: {} (est ${:.3f} per iteration)\n"
        "- Budget permits ~{} more iterations at your tier. Act accordingly.\n"
    ).format(spent_usd, ceiling_usd, pct, remaining, tier, tier_estimate, permits)


def project_spend(spent_usd: float, tier_estimate: float) -> float:
    """Projected spend = last-recorded + tier estimate for impending dispatch."""
    return spent_usd + tier_estimate


def downgrade_tier(
    *,
    agent: str,
    resolved_tier: str,
    remaining_usd: float,
    tier_estimates: dict[str, float],
    conservatism_multiplier: dict[str, float],
    pinned_agents: list[str],
    aware_routing: bool,
) -> tuple[str, str]:
    """Compute the (new_tier, reason) for an impending dispatch.

    Returns (resolved_tier, "no_downgrade") when no change is needed.
    Returns (new_tier, "downgrade_from_{orig}") when a step-down applies.
    Returns (resolved_tier, "safety_pinned") when agent is SAFETY_CRITICAL at fast tier.
    Returns (resolved_tier, "escalate_required") when the normal downgrade would
    drop a SAFETY_CRITICAL agent below fast — caller must escalate.
    """
    if not aware_routing:
        return resolved_tier, "aware_routing_disabled"
    if agent in pinned_agents:
        return resolved_tier, "agent_pinned"

    base_estimate = tier_estimates.get(resolved_tier, 0.047)
    buffer = conservatism_multiplier.get(resolved_tier, 1.0)
    effective = base_estimate * max(1.0, buffer)
    trip = 5.0 * effective

    if remaining_usd >= trip:
        return resolved_tier, "no_downgrade"

    next_tier = _TIER_DOWNGRADE_CHAIN.get(resolved_tier)
    if next_tier is None:
        # Already at fast.
        if agent in SAFETY_CRITICAL:
            return resolved_tier, "safety_pinned"
        return resolved_tier, "escalate_required"

    return next_tier, f"downgrade_from_{resolved_tier}"


def is_safety_critical(agent: str) -> bool:
    """True if agent is in the hardcoded SAFETY_CRITICAL set."""
    return agent in SAFETY_CRITICAL


def write_incident(incident: dict[str, Any], forge_dir: Path) -> Path:
    """Atomically write a cost-incident JSON file under .forge/cost-incidents/.

    File name: <ISO8601-with-colons-replaced>.json to keep it Windows-safe.
    Returns the full path. Never raises on I/O — falls back to a temp path and
    logs stderr so the pipeline is not blocked by a filesystem hiccup.
    """
    target_dir = forge_dir / "cost-incidents"
    target_dir.mkdir(parents=True, exist_ok=True)
    ts = incident.get("timestamp", "unknown")
    safe_ts = ts.replace(":", "-").replace(".", "-")
    dest = target_dir / f"{safe_ts}.json"
    payload = json.dumps(incident, indent=2, sort_keys=True) + "\n"

    # Atomic write: tmp in same dir, then os.replace.
    fd, tmp = tempfile.mkstemp(prefix=".incident-", dir=str(target_dir))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(payload)
        os.replace(tmp, dest)
    except OSError:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    return dest
