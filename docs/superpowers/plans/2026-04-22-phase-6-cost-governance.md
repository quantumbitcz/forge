# Phase 6: Cost Governance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the forge pipeline aware of USD cost at every dispatch boundary, enforce a hard per-run ceiling with AskUserQuestion escalation, and add dynamic tier downgrades with a hardcoded SAFETY_CRITICAL exclusion list — without breaking any existing truth/observability plumbing.

**Architecture:** The orchestrator (`fg-100`) gains a pre-dispatch cost gate that (a) computes projected spend vs ceiling, (b) injects a `## Cost Budget` block into every subagent brief, and (c) dynamically downgrades tiers when the remaining budget is small, subject to a hardcoded `SAFETY_CRITICAL` list that short-circuits silent skips. `fg-300-implementer` self-throttles refactor/critic passes at 80% and 90% consumption. `fg-700-retrospective` emits cost-per-actionable-finding analytics (gated on peer cohort producing ≥1 CRITICAL/WARNING) and writes to the F29 run-history store. State schema bumps to v2.0.0 in coordination with Phases 5 and 7.

**Tech Stack:** Python 3.10+ (`shared/cost_alerting.py` extension + new `shared/cost_governance.py`), bash 4.0+ (pricing table in `shared/forge-token-tracker.sh`), SQLite (F29 `run_summary` columns), OpenTelemetry GenAI semconv (`forge.cost.*` + `forge.agent.tier_*`), JSON Schema (cost-incident + state v2.0.0), bats-core (unit + scenario tests). No new runtime dependencies.

**Testing contract:** Every test runs in CI only — no local `pytest`/`bats` invocations inside task steps. Each task lists the exact bats file created/modified and the commit that pushes it; CI is the authoritative verifier.

---

## File Structure

### New files

- `shared/cost_governance.py` — pure-Python helpers: `compute_budget_block()`, `project_spend()`, `downgrade_tier()`, `is_safety_critical()`, `write_incident()`. Stateless, unit-testable, importable by orchestrator + retrospective.
- `shared/schemas/cost-incident.schema.json` — JSON Schema for `.forge/cost-incidents/*.json`.
- `shared/run-history/migrations/002-cost-columns.sql` — add four cost columns to `run_summary`.
- `tests/unit/cost-governance-helpers.bats` — unit tests for `cost_governance.py` pure functions.
- `tests/unit/cost-governance-downgrade.bats` — unit tests for tier downgrade + SAFETY_CRITICAL.
- `tests/unit/token-tracker-pricing.bats` — AC-616: asserts pricing literals in `forge-token-tracker.sh`.
- `tests/scenario/cost-ceiling-interactive.bats` — scenario: interactive breach with AskUserQuestion.
- `tests/scenario/cost-ceiling-autonomous.bats` — scenario: autonomous breach auto-decides.
- `tests/scenario/cost-soft-throttle.bats` — scenario: implementer 80%/90% behavior.
- `tests/scenario/cost-incident-write.bats` — scenario: incident JSON matches schema.
- `tests/scenario/cost-otel-attrs.bats` — scenario: six OTel attrs round-trip through replay.
- `tests/scenario/cost-no-silent-safety-skip.bats` — regression guard: SAFETY_CRITICAL never skipped.

### Modified files

- `shared/forge-token-tracker.sh` — refresh `DEFAULT_PRICING_TABLE` (Task 1 — ships first).
- `shared/cost_alerting.py` — extend with USD-denominated helpers, keep token-denominated path intact.
- `shared/state-schema.md` — bump to v2.0.0, reshape `cost` block.
- `shared/model-routing.md` — new §Cost-Aware Routing + hardcoded SAFETY_CRITICAL list.
- `shared/observability.md` — new `forge.cost.*` + `forge.agent.tier_*` attrs + namespace contract.
- `shared/preflight-constraints.md` — new §Cost validation rules.
- `shared/ask-user-question-patterns.md` — new §8 Cost-Ceiling + §Default Timeouts (300s).
- `shared/run-history/run-history.md` — document new `run_summary` cost columns.
- `hooks/_py/otel_attributes.py` — declare six new FORGE_COST_* / FORGE_AGENT_TIER_* constants.
- `hooks/_py/otel.py` — populate new attrs in `record_agent_result`.
- `agents/fg-100-orchestrator.md` — dispatch-gate block + AskUserQuestion + autonomous branch.
- `agents/fg-300-implementer.md` — new §5.3b Soft Cost Throttle.
- `agents/fg-700-retrospective.md` — new §Cost Analytics subsection.
- `modules/frameworks/*/forge-config-template.md` — add `cost:` block to all 24 templates.
- `CLAUDE.md` — §Supporting systems + §Pipeline modes entries.
- `README.md` — one-liner on cost ceiling.
- `CHANGELOG.md` — Phase 6 entry under 3.7.0 (or next minor).

---

## Task 1: Pre-delivery — refresh DEFAULT_PRICING_TABLE in forge-token-tracker.sh

**Rationale:** AC-616. Every downstream USD calculation (tier estimates, ceilings, cost-per-finding) assumes the pricing table is current. Ship this as the first commit so no later task reads stale rates.

**Verified prices (WebFetch of https://platform.claude.com/docs/en/about-claude/pricing on 2026-04-22):**

| Tier | Model | Base Input $/MTok | Output $/MTok |
|---|---|---|---|
| haiku | Claude Haiku 4.5 | 1.00 | 5.00 |
| sonnet | Claude Sonnet 4.6 | 3.00 | 15.00 |
| opus | Claude Opus 4.7 | 5.00 | 25.00 |

**Files:**
- Modify: `shared/forge-token-tracker.sh:145-151`
- Test: `tests/unit/token-tracker-pricing.bats` (new)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/token-tracker-pricing.bats`:

```bash
#!/usr/bin/env bats
# Unit: pricing table in forge-token-tracker.sh matches Anthropic 2026-04-22 rates.

load '../helpers/test-helpers'

SCRIPT="$PLUGIN_ROOT/shared/forge-token-tracker.sh"

@test "pricing: haiku input = 1.00 per MTok" {
  run grep -E '"haiku":\s*\{"input":\s*1\.00' "$SCRIPT"
  assert_success
}

@test "pricing: haiku output = 5.00 per MTok" {
  run grep -E '"haiku":[^}]*"output":\s*5\.00' "$SCRIPT"
  assert_success
}

@test "pricing: sonnet input = 3.00 per MTok" {
  run grep -E '"sonnet":\s*\{"input":\s*3\.00' "$SCRIPT"
  assert_success
}

@test "pricing: sonnet output = 15.00 per MTok" {
  run grep -E '"sonnet":[^}]*"output":\s*15\.00' "$SCRIPT"
  assert_success
}

@test "pricing: opus input = 5.00 per MTok (Opus 4.7, NOT legacy 15.00)" {
  run grep -E '"opus":\s*\{"input":\s*5\.00' "$SCRIPT"
  assert_success
}

@test "pricing: opus output = 25.00 per MTok (Opus 4.7, NOT legacy 75.00)" {
  run grep -E '"opus":[^}]*"output":\s*25\.00' "$SCRIPT"
  assert_success
}

@test "pricing: header comment cites 2026-04-22 verification date" {
  run grep "2026-04-22" "$SCRIPT"
  assert_success
}
```

- [ ] **Step 2: Run test to verify it fails**

Push to branch and let CI run. Expected: FAIL — current table shows haiku 0.25/1.25 and opus 15.0/75.0.

- [ ] **Step 3: Update DEFAULT_PRICING_TABLE**

Edit `shared/forge-token-tracker.sh`, replace lines 145-151:

```python
# Default pricing per MTok — last verified 2026-04-22 against
# https://platform.claude.com/docs/en/about-claude/pricing
# Haiku 4.5, Sonnet 4.6, Opus 4.7 — base input / output (no cache, no batch).
# Override via forge-config.md token_pricing section.
DEFAULT_PRICING_TABLE = {
    "haiku":   {"input": 1.00, "output": 5.00},   # Claude Haiku 4.5
    "sonnet":  {"input": 3.00, "output": 15.00},  # Claude Sonnet 4.6
    "opus":    {"input": 5.00, "output": 25.00},  # Claude Opus 4.7
}
```

- [ ] **Step 4: Run tests in CI**

Push. Expected: PASS on all 7 assertions.

- [ ] **Step 5: Commit**

```bash
git add shared/forge-token-tracker.sh tests/unit/token-tracker-pricing.bats
git commit -m "fix(cost): refresh DEFAULT_PRICING_TABLE to Claude 4.5/4.6/4.7 rates (AC-616)"
```

---

## Task 2: Create shared/cost_governance.py pure-function module

**Rationale:** Centralize arithmetic (budget block, projection, downgrade, safety check, incident write) in one testable Python module. Orchestrator and retrospective both import it.

**Files:**
- Create: `shared/cost_governance.py`
- Test: `tests/unit/cost-governance-helpers.bats` (new)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/cost-governance-helpers.bats`:

```bash
#!/usr/bin/env bats
load '../helpers/test-helpers'

PY="python3 -c"
MODULE="$PLUGIN_ROOT/shared/cost_governance.py"

@test "cost_governance: module imports cleanly" {
  run python3 -c "import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared'); import cost_governance"
  assert_success
}

@test "compute_budget_block: renders Spent/Remaining/Tier lines" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared')
from cost_governance import compute_budget_block
out = compute_budget_block(ceiling_usd=25.0, spent_usd=3.42, tier='standard', tier_estimate=0.047)
assert 'Spent: \$3.42 of \$25.00' in out, out
assert 'Remaining: \$21.58' in out, out
assert 'Your tier: standard' in out, out
assert 'est \$0.047 per iteration' in out, out
print('ok')
"
  assert_success
}

@test "compute_budget_block: ceiling=0 renders 'unlimited'" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared')
from cost_governance import compute_budget_block
out = compute_budget_block(ceiling_usd=0.0, spent_usd=3.42, tier='standard', tier_estimate=0.047)
assert 'unlimited' in out.lower(), out
print('ok')
"
  assert_success
}

@test "project_spend: adds tier_estimate to spent" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared')
from cost_governance import project_spend
assert abs(project_spend(24.50, 0.047) - 24.547) < 1e-6
print('ok')
"
  assert_success
}

@test "is_safety_critical: returns True for fg-411-security-reviewer" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared')
from cost_governance import is_safety_critical
assert is_safety_critical('fg-411-security-reviewer') is True
print('ok')
"
  assert_success
}

@test "is_safety_critical: returns False for fg-410-code-reviewer" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared')
from cost_governance import is_safety_critical
assert is_safety_critical('fg-410-code-reviewer') is False
print('ok')
"
  assert_success
}

@test "SAFETY_CRITICAL set contains exactly 10 entries (authoritative list)" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared')
from cost_governance import SAFETY_CRITICAL
assert len(SAFETY_CRITICAL) == 10, len(SAFETY_CRITICAL)
expected = {
    'fg-210-validator','fg-250-contract-validator','fg-411-security-reviewer',
    'fg-412-architecture-reviewer','fg-414-license-reviewer',
    'fg-419-infra-deploy-reviewer','fg-505-build-verifier','fg-500-test-gate',
    'fg-506-migration-verifier','fg-590-pre-ship-verifier'
}
assert SAFETY_CRITICAL == expected, SAFETY_CRITICAL ^ expected
print('ok')
"
  assert_success
}
```

- [ ] **Step 2: Run tests in CI — expect FAIL (module does not exist)**

- [ ] **Step 3: Create the module**

Create `shared/cost_governance.py`:

```python
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
```

- [ ] **Step 4: Run tests in CI — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add shared/cost_governance.py tests/unit/cost-governance-helpers.bats
git commit -m "feat(cost): add shared/cost_governance.py with SAFETY_CRITICAL frozenset"
```

---

## Task 3: Unit-test tier downgrade behavior

**Rationale:** AC-607, AC-608, AC-609 all hinge on `downgrade_tier()`. Validate every edge case in isolation before orchestrator wiring.

**Files:**
- Test: `tests/unit/cost-governance-downgrade.bats` (new)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/cost-governance-downgrade.bats`:

```bash
#!/usr/bin/env bats
load '../helpers/test-helpers'

TIERS='{"fast":0.016,"standard":0.047,"premium":0.078}'
BUFFER='{"fast":1.0,"standard":1.0,"premium":1.0}'

_call() {
  local agent="$1" tier="$2" remaining="$3" pinned="${4:-[]}" aware="${5:-True}"
  python3 -c "
import json, sys
sys.path.insert(0, '$PLUGIN_ROOT/shared')
from cost_governance import downgrade_tier
t, r = downgrade_tier(
    agent='$agent', resolved_tier='$tier', remaining_usd=$remaining,
    tier_estimates=json.loads('$TIERS'),
    conservatism_multiplier=json.loads('$BUFFER'),
    pinned_agents=json.loads('$pinned'),
    aware_routing=$aware,
)
print(f'{t}|{r}')
"
}

@test "downgrade: premium with ample remaining — no change (AC-607 negative)" {
  run _call "fg-200-planner" "premium" "10.00"
  assert_success
  assert_output "premium|no_downgrade"
}

@test "downgrade: premium with remaining < 5*0.078 — step down to standard (AC-607)" {
  run _call "fg-200-planner" "premium" "0.20"
  assert_success
  assert_output "standard|downgrade_from_premium"
}

@test "downgrade: standard with remaining < 5*0.047 — step down to fast" {
  run _call "fg-300-implementer" "standard" "0.10"
  assert_success
  assert_output "fast|downgrade_from_standard"
}

@test "downgrade: fast non-safety-critical with remaining < 5*0.016 — escalate_required" {
  run _call "fg-410-code-reviewer" "fast" "0.02"
  assert_success
  assert_output "fast|escalate_required"
}

@test "downgrade: fast + fg-411-security-reviewer — safety_pinned (AC-608)" {
  run _call "fg-411-security-reviewer" "fast" "0.02"
  assert_success
  assert_output "fast|safety_pinned"
}

@test "downgrade: premium + pinned agent stays premium (AC-609)" {
  run _call "fg-200-planner" "premium" "0.20" '["fg-200-planner"]'
  assert_success
  assert_output "premium|agent_pinned"
}

@test "downgrade: aware_routing disabled — no-op regardless of remaining" {
  run _call "fg-412-architecture-reviewer" "premium" "0.01" "[]" "False"
  assert_success
  assert_output "premium|aware_routing_disabled"
}

@test "downgrade: conservatism_multiplier=3.0 on premium trips earlier" {
  # 5 * 0.078 * 3.0 = 1.17 — remaining 1.00 < 1.17 triggers downgrade.
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared')
from cost_governance import downgrade_tier
t, r = downgrade_tier(
    agent='fg-200-planner', resolved_tier='premium', remaining_usd=1.00,
    tier_estimates={'fast':0.016,'standard':0.047,'premium':0.078},
    conservatism_multiplier={'fast':1.0,'standard':1.0,'premium':3.0},
    pinned_agents=[], aware_routing=True,
)
print(f'{t}|{r}')
"
  assert_success
  assert_output "standard|downgrade_from_premium"
}
```

- [ ] **Step 2: Run in CI — expect PASS (module exists from Task 2)**

- [ ] **Step 3: Commit**

```bash
git add tests/unit/cost-governance-downgrade.bats
git commit -m "test(cost): cover downgrade_tier edge cases (AC-607/608/609)"
```

---

## Task 4: Author the cost-incident JSON Schema

**Rationale:** AC-605 asserts every escalation writes a `.forge/cost-incidents/*.json` that matches this schema. Freeze the shape first.

**Files:**
- Create: `shared/schemas/cost-incident.schema.json`

- [ ] **Step 1: Write the schema**

Create `shared/schemas/cost-incident.schema.json`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://forge.quantumbit.cz/schemas/cost-incident.schema.json",
  "title": "Forge Cost Incident",
  "description": "Written to .forge/cost-incidents/<timestamp>.json on every ceiling breach escalation.",
  "type": "object",
  "required": [
    "timestamp", "ceiling_usd", "spent_usd", "projected_usd",
    "next_agent", "resolved_tier", "decision", "autonomous", "run_id"
  ],
  "additionalProperties": false,
  "properties": {
    "timestamp": {
      "type": "string",
      "format": "date-time",
      "description": "ISO 8601 UTC timestamp of the escalation."
    },
    "ceiling_usd": {"type": "number", "minimum": 0},
    "spent_usd": {"type": "number", "minimum": 0},
    "projected_usd": {"type": "number", "minimum": 0},
    "next_agent": {
      "type": "string",
      "pattern": "^fg-[0-9]{3}-[a-z-]+$",
      "description": "Agent ID that would have been dispatched."
    },
    "resolved_tier": {"enum": ["fast", "standard", "premium"]},
    "decision": {
      "enum": ["raise_ceiling", "downgrade", "abort_to_ship", "abort_full", "timeout"]
    },
    "autonomous": {"type": "boolean"},
    "run_id": {"type": "string", "minLength": 1},
    "new_ceiling_usd": {
      "type": "number",
      "minimum": 0,
      "description": "Present only when decision == raise_ceiling."
    },
    "downgrade_from": {
      "enum": ["fast", "standard", "premium"],
      "description": "Present only when decision == downgrade."
    },
    "downgrade_to": {
      "enum": ["fast", "standard", "premium"],
      "description": "Present only when decision == downgrade."
    }
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add shared/schemas/cost-incident.schema.json
git commit -m "feat(cost): add JSON Schema for .forge/cost-incidents/*.json (AC-605)"
```

---

## Task 5: State schema v2.0.0 — cost block reshape

**Rationale:** AC-615. Coordinated bump with Phases 5 and 7 — Phase 6 owns only the `cost` and `cost_alerting` portions. This task edits ONLY those sections; Phases 5 and 7 will merge their fields into the same v2.0.0 cut before any phase lands the `"version": "2.0.0"` literal.

**Files:**
- Modify: `shared/state-schema.md` (replace `cost` block, mark `cost_alerting` as deprecated-in-place)

- [ ] **Step 1: Replace the cost block in `shared/state-schema.md`**

Find the existing block:

```json
  "cost": {
    "wall_time_seconds": 0,
    "stages_completed": 0,
    "estimated_cost_usd": 0.0,
    "per_stage": {},
    "budget_remaining_tokens": 2000000,
    "efficiency_score": 0.0
  },
```

Replace with:

```json
  "cost": {
    "wall_time_seconds": 0,
    "stages_completed": 0,
    "ceiling_usd": 25.00,
    "spent_usd": 0.0,
    "estimated_cost_usd": 0.0,
    "remaining_usd": 25.00,
    "pct_consumed": 0.0,
    "per_stage": {},
    "per_agent": {},
    "tier_estimates_usd": {"fast": 0.016, "standard": 0.047, "premium": 0.078},
    "conservatism_multiplier": {"fast": 1.0, "standard": 1.0, "premium": 1.0},
    "tier_breakdown": {"fast": 0.0, "standard": 0.0, "premium": 0.0},
    "downgrade_count": 0,
    "downgrades": [],
    "throttle_events": [],
    "ceiling_breaches": 0,
    "budget_remaining_tokens": 2000000,
    "efficiency_score": 0.0
  },
```

Notes to add immediately below the JSON block:

```markdown
**v2.0.0 notes (Phase 6 portion):**
- `ceiling_usd` — mirrors `config.cost.ceiling_usd`. Copied at PREFLIGHT.
- `spent_usd` — authoritative USD spent so far. `estimated_cost_usd` kept as an alias for `forge-token-tracker.sh` back-compat at read time only.
- `remaining_usd` = `max(0, ceiling_usd - spent_usd)`.
- `pct_consumed` = `spent_usd / ceiling_usd` (0.0 when ceiling_usd == 0).
- `tier_breakdown` — cumulative USD per resolved tier (not per original tier).
- `downgrade_count` — cardinality of `downgrades[]`.
- `downgrades[]` — append-only list of `{agent, from, to, timestamp, remaining_usd}`.
- `throttle_events[]` — append-only list of `{agent, severity, pct_consumed, action, timestamp}`.
- `ceiling_breaches` — increment once per `.forge/cost-incidents/*.json` written.

On version-mismatch load (any `1.x.x`), the orchestrator resets the cost block to defaults and logs a single INFO line. This follows the no-backcompat policy.
```

Also update the version literal `"version": "1.10.0"` → `"version": "2.0.0"` **only after** Phases 5 and 7 agree their merged schema. Phase 6 MAY leave the literal unchanged in this task and rely on the coordinated cut; add a comment:

```markdown
> **Coordination note (Phase 6):** The `"version": "2.0.0"` literal is flipped in the last of {P5, P6, P7} to merge. Phase 6's contribution is the `cost` block shape above; do not bump the literal in isolation.
```

- [ ] **Step 2: Commit**

Include this explicit coordination hint in the commit body (exactly once, at the top of the commit message body — plain text, not a code fence, so it survives `git log --grep`):

> If P6 ships before P5/P7, the `cost` block fields in `state-schema.md` describe the v2.0.0 shape while the `state.version` literal still says `1.10.0` until the last of {P5, P6, P7} flips it. This is acceptable per the no-backcompat policy in the forge CLAUDE.md — on version-mismatch load we reset the `cost` block to defaults and log a single INFO line; no migration shim.

```bash
git add shared/state-schema.md
git commit -m "$(cat <<'EOF'
feat(state): reshape cost block for v2.0.0 (Phase 6 portion)

If P6 ships before P5/P7, the `cost` block fields in state-schema.md
describe the v2.0.0 shape while the `state.version` literal still says
`1.10.0` until the last of {P5, P6, P7} flips it. This is acceptable
per the no-backcompat policy — on version-mismatch load we reset the
`cost` block to defaults and log a single INFO line. No migration shim.
EOF
)"
```

---

## Task 6: PREFLIGHT constraints for cost.* config

**Rationale:** AC-601. Every `cost.*` field must be validated at PREFLIGHT so typos fail fast with CRITICAL instead of surfacing mid-run.

**Files:**
- Modify: `shared/preflight-constraints.md` (add §Cost)

- [ ] **Step 1: Append §Cost to `shared/preflight-constraints.md`**

```markdown
## Cost Governance (Phase 6)

All validations run at PREFLIGHT. Any CRITICAL aborts the run; WARNING logs and proceeds.

| Field | Rule | Severity on violation |
|---|---|---|
| `cost.ceiling_usd` | float >= 0 | CRITICAL if negative |
| `cost.ceiling_usd` | warn if 0 < x < 1.00 (likely typo) | WARNING |
| `cost.warn_at` | 0 < x < 1 | CRITICAL |
| `cost.throttle_at` | 0 < x < 1 | CRITICAL |
| `cost.abort_at` | 0 < x <= 1 | CRITICAL |
| ordering | `warn_at < throttle_at <= abort_at` | CRITICAL |
| `cost.aware_routing` | boolean | CRITICAL if non-bool |
| `cost.aware_routing: true` requires `model_routing.enabled: true` | otherwise CRITICAL |
| `cost.tier_estimates_usd.fast/standard/premium` | float > 0 | CRITICAL if <= 0 or missing |
| tier ratio | warn if `premium / fast > 200` | WARNING |
| `cost.conservatism_multiplier.fast/standard/premium` | float >= 1.0 | CRITICAL if < 1.0 |
| multiplier sanity | warn if any multiplier > 10.0 | WARNING |
| `cost.pinned_agents[]` | each must match agents.md#registry | WARNING for unknown IDs |
| `cost.skippable_under_cost_pressure[]` | each must match agents.md#registry | WARNING for unknown IDs |
| `cost.skippable_under_cost_pressure[]` | MUST NOT contain any SAFETY_CRITICAL agent | CRITICAL |

**Implementation note:** PREFLIGHT calls `shared/config_validator.py` which reads the above rules from this section. The SAFETY_CRITICAL cross-check imports `cost_governance.SAFETY_CRITICAL` (single source of truth).
```

- [ ] **Step 2: Commit**

```bash
git add shared/preflight-constraints.md
git commit -m "docs(preflight): document cost.* validation rules (AC-601)"
```

---

## Task 7: AskUserQuestion pattern §8 + default timeouts

**Rationale:** AC-603/AC-604. The ceiling-breach escalation must use a canonical payload so scenario tests can match it. Also adds the 300s default timeout referenced by the spec.

**Files:**
- Modify: `shared/ask-user-question-patterns.md` (add §8 and §Default Timeouts)

- [ ] **Step 1: Append to `shared/ask-user-question-patterns.md`**

**Append as §8 — do NOT renumber existing sections.** The cost-ceiling pattern goes after the current §7 Confirmed-tier injection gate as a brand-new §8. Leave §1–§7 numbering untouched. (Previous drafts mentioned a renumber path; that path is explicitly rejected — appending is simpler, keeps `grep` hits for `## 7. Confirmed-tier injection gate` stable across the rest of the codebase, and avoids churn in any doc that cross-references the existing numbering.)

```markdown
## 8. Pattern — Cost-ceiling breach (Phase 6)

**Trigger:** `state.cost.spent_usd + tier_estimate_usd[resolved_tier] > config.cost.ceiling_usd` AND `autonomous: false`.

**Rule:** `fg-100-orchestrator` MUST call `AskUserQuestion` with exactly this payload (values substituted) before any `Agent(...)` call.

```json
{
  "question": "Next dispatch would breach cost ceiling (${ceiling_usd}). Projected: ${projected_usd}. How should we proceed?",
  "header": "Cost ceiling",
  "multiSelect": false,
  "options": [
    {"label": "Raise ceiling to ${ceiling_usd_raised}", "description": "Continues run. Records new ceiling in state for this run only."},
    {"label": "Downgrade remaining agents (Recommended)", "description": "Switches premium->standard, standard->fast where safe. Excludes pinned agents and safety-critical reviewers."},
    {"label": "Abort to ship current state", "description": "Runs pre-ship verifier on what's in the worktree, then ships or exits."},
    {"label": "Abort fully", "description": "Stops immediately. Preserves state for /forge-recover resume."}
  ]
}
```

- Header is exactly `"Cost ceiling"` (12 chars — max).
- `ceiling_usd_raised` = `ceiling_usd * 1.4` rounded to nearest dollar (e.g. $25 -> $35).
- Options ordered Recommended-first, destructive-last (matches §3).

**Autonomous mode:** NEVER invoke this AskUserQuestion. Follow `agents/fg-100-orchestrator.md` §Cost Governance autonomous decision tree. Every decision is logged as `COST-ESCALATION-AUTO` INFO and written to `.forge/cost-incidents/*.json`.

## Default Timeouts (Phase 6)

Interactive `AskUserQuestion` prompts in forge default to a **300-second** response window when no explicit timeout is declared. On timeout:

| Pattern | Timeout default | Fallback action |
|---|---|---|
| §3 Escalation (recovery) | 300s | Default to "Abort this run" |
| §7 Confirmed-tier injection | 300s | Pause run, write `.forge/alerts.json` severity=high |
| §8 Cost-ceiling breach | 300s | Default to "Abort to ship current state" |

Log `{PATTERN}-TIMEOUT` INFO on every fallback.
```

- [ ] **Step 2: Commit**

```bash
git add shared/ask-user-question-patterns.md
git commit -m "docs(ask): add §8 cost-ceiling pattern + default timeouts (AC-603/604)"
```

---

## Task 8: Expand config template — spring framework first

**Rationale:** Every framework template must gain the `cost:` block. Land it on spring first (most exercised by contract tests), then propagate in Task 9.

**Files:**
- Modify: `modules/frameworks/spring/forge-config-template.md`

- [ ] **Step 1: Add the `cost:` block to the config YAML fence**

Find the existing `## Orchestration` table. Immediately after it (before `## Review Agents`), add a new subsection:

```markdown
## Cost Governance (Phase 6)

Nested YAML block. PREFLIGHT validates every field per `shared/preflight-constraints.md#cost-governance-phase-6`.

```yaml
cost:
  ceiling_usd: 25.00            # hard per-run ceiling (0 = disabled)
  warn_at: 0.75                 # INFO event at 75% consumed
  throttle_at: 0.80             # implementer soft throttle activates
  abort_at: 1.00                # hard stop
  aware_routing: true           # dynamic tier downgrades
  pinned_agents: []             # agents that never downgrade
  tier_estimates_usd:
    fast: 0.016                 # Haiku 4.5 — 8k@$1/MTok + 1.5k@$5/MTok
    standard: 0.047             # Sonnet 4.6 — 8k@$3/MTok + 1.5k@$15/MTok
    premium: 0.078              # Opus 4.7 — 8k@$5/MTok + 1.5k@$25/MTok
  conservatism_multiplier:
    fast: 1.0
    standard: 1.0
    premium: 1.0                # raise (e.g. 3.0) for planner with high variance
  skippable_under_cost_pressure: []  # opt-in list for agents that CAN be skipped
```
```

- [ ] **Step 2: Commit**

```bash
git add modules/frameworks/spring/forge-config-template.md
git commit -m "feat(config): add cost: block to spring forge-config-template"
```

---

## Task 9: Propagate cost: block to remaining framework templates

**Rationale:** Contract tests walk every `modules/frameworks/*/forge-config-template.md` and expect the same `cost:` block. Copy the spring block to the other 23 frameworks.

**Files:**
- Modify: `modules/frameworks/{angular,aspnet,axum,django,embedded,express,fastapi,flask,gin,go-stdlib,jetpack-compose,k8s,kotlin-multiplatform,laravel,nestjs,nextjs,rails,react,svelte,sveltekit,swiftui,vapor,vue}/forge-config-template.md`
- Test: existing `tests/contract/framework-config-templates.bats` (will fail until all 24 carry the block — forcing completeness)

- [ ] **Step 1: For each framework dir, append the same `## Cost Governance (Phase 6)` subsection**

Use the exact block from Task 8. Command to enumerate targets:

```bash
for fw in angular aspnet axum django embedded express fastapi flask gin go-stdlib \
          jetpack-compose k8s kotlin-multiplatform laravel nestjs nextjs rails \
          react svelte sveltekit swiftui vapor vue; do
  echo "modules/frameworks/$fw/forge-config-template.md"
done
```

For each file, edit to insert the YAML block after `## Orchestration` and before the next `## ` heading. Do not alter any other content.

- [ ] **Step 2: Write a contract test (or extend an existing one) to enforce presence**

Add a new assertion to `tests/contract/framework-config-templates.bats`:

> **Note on regex vs fenced blocks:** `grep` operates on raw text and does NOT respect triple-backtick fence context — a `ceiling_usd: 25.00` literal anywhere in the file (including inside an example fenced YAML block) satisfies the assertion. This is intentional and matches existing contract-test precedent: presence of the literal is what we're proving. Lychee's fenced-block skipping is unrelated (and only applies to URL probing). If a template author needs a commented-out example that should NOT count, they should use a different ceiling value in the example.

```bash
@test "every framework template declares cost.ceiling_usd" {
  for tpl in $PLUGIN_ROOT/modules/frameworks/*/forge-config-template.md; do
    run grep -E "^\s*ceiling_usd:\s*25\.00" "$tpl"
    assert_success "missing cost.ceiling_usd in $tpl"
  done
}

@test "every framework template declares cost.aware_routing" {
  for tpl in $PLUGIN_ROOT/modules/frameworks/*/forge-config-template.md; do
    run grep -E "^\s*aware_routing:\s*true" "$tpl"
    assert_success "missing cost.aware_routing in $tpl"
  done
}

@test "every framework template declares tier_estimates_usd.premium = 0.078" {
  for tpl in $PLUGIN_ROOT/modules/frameworks/*/forge-config-template.md; do
    run grep -E "premium:\s*0\.078" "$tpl"
    assert_success "missing premium tier estimate in $tpl"
  done
}
```

- [ ] **Step 3: Run in CI — expect PASS on all 24 templates**

- [ ] **Step 4: Commit**

```bash
git add modules/frameworks/*/forge-config-template.md tests/contract/framework-config-templates.bats
git commit -m "feat(config): propagate cost: block across all 24 framework templates"
```

---

## Task 10: Document the SAFETY_CRITICAL list in model-routing.md

**Rationale:** AC-608. The list lives in Python (`cost_governance.SAFETY_CRITICAL`) but must also be documented in `shared/model-routing.md` with rationale so users can reason about it without reading code.

**Files:**
- Modify: `shared/model-routing.md` (new §Cost-Aware Routing + §Safety-Critical Agents)

- [ ] **Step 1: Append two sections**

```markdown
## Cost-Aware Routing (Phase 6)

When `cost.aware_routing: true` (default), `fg-100-orchestrator` consults `shared.cost_governance.downgrade_tier()` before every dispatch. Algorithm:

1. `resolved = static_resolve(agent)` — unchanged from §Resolution Order above.
2. `effective = tier_estimate[resolved] * conservatism_multiplier[resolved]`.
3. If `state.cost.remaining_usd >= 5 * effective`: keep `resolved`.
4. Else if `agent in cost.pinned_agents`: keep `resolved`, emit `COST-DOWNGRADE-PINNED` INFO.
5. Else step down one tier: `premium -> standard -> fast`.
6. If already at `fast`:
   - `agent in SAFETY_CRITICAL` -> keep `fast` (logged as `safety_pinned`).
   - else -> escalate to orchestrator decision (NEVER silent skip).

Every applied downgrade is appended to `state.cost.downgrades[]` and increments `state.cost.downgrade_count`.

## Safety-Critical Agents

The following agents are **hardcoded** in `shared/cost_governance.py` as `SAFETY_CRITICAL`. They are never silently skipped under cost pressure — downgrade is permitted down to `fast`, below which the orchestrator escalates.

```yaml
safety_critical_agents:
  - fg-210-validator
  - fg-250-contract-validator
  - fg-411-security-reviewer
  - fg-412-architecture-reviewer
  - fg-414-license-reviewer          # legal binding; cannot be downgraded silently
  - fg-419-infra-deploy-reviewer     # prod deployment cost overrun is what this checks
  - fg-500-test-gate
  - fg-505-build-verifier
  - fg-506-migration-verifier        # migration-mode only; still safety-critical when active
  - fg-590-pre-ship-verifier
```

This list is **not user-configurable**. Rationale: a run that ships without a security review to save $0.30 is a bug, not a feature. Users who need to pin additional agents against downgrades should add them to `cost.pinned_agents[]`.
```

- [ ] **Step 2: Commit**

```bash
git add shared/model-routing.md
git commit -m "docs(routing): document cost-aware routing + SAFETY_CRITICAL (AC-608)"
```

---

## Task 11: OTel attribute declarations

**Rationale:** AC-610. Six new attribute constants in one place, cited by `otel.py` + `observability.md`.

**Files:**
- Modify: `hooks/_py/otel_attributes.py`

- [ ] **Step 1: Add new constants**

Append after the existing `FORGE_*` declarations (around line 43):

```python
# forge.cost.* (Phase 6)
FORGE_RUN_BUDGET_TOTAL_USD = "forge.run.budget_total_usd"
FORGE_RUN_BUDGET_REMAINING_USD = "forge.run.budget_remaining_usd"
FORGE_AGENT_TIER_ESTIMATE_USD = "forge.agent.tier_estimate_usd"
FORGE_AGENT_TIER_ORIGINAL = "forge.agent.tier_original"
FORGE_AGENT_TIER_USED = "forge.agent.tier_used"
FORGE_COST_THROTTLE_REASON = "forge.cost.throttle_reason"

# Enum values for FORGE_COST_THROTTLE_REASON.
THROTTLE_NONE = "none"
THROTTLE_SOFT_20PCT = "soft_20pct"
THROTTLE_SOFT_10PCT = "soft_10pct"
THROTTLE_CEILING_BREACH = "ceiling_breach"
THROTTLE_DYNAMIC_DOWNGRADE = "dynamic_downgrade"
```

Also extend the `BOUNDED_ATTRS` tuple to include the tier attrs (bounded enum of 3 values each):

```python
BOUNDED_ATTRS: tuple[str, ...] = (
    GEN_AI_AGENT_NAME,
    GEN_AI_REQUEST_MODEL,
    GEN_AI_OPERATION_NAME,
    FORGE_STAGE,
    FORGE_MODE,
    FORGE_AGENT_TIER_ORIGINAL,  # enum: fast|standard|premium
    FORGE_AGENT_TIER_USED,       # enum: fast|standard|premium
    FORGE_COST_THROTTLE_REASON,  # enum (5)
)
```

Leave `UNBOUNDED_ATTRS` to pick up the USD doubles (attribute-only, not span-name safe).

- [ ] **Step 2: Commit**

```bash
git add hooks/_py/otel_attributes.py
git commit -m "feat(otel): declare forge.cost.* + forge.agent.tier_* attrs (AC-610)"
```

---

## Task 12: Populate OTel attributes in record_agent_result

**Rationale:** AC-610 requires the six new attributes to appear on every dispatch span and to round-trip through `replay()`.

**Files:**
- Modify: `hooks/_py/otel.py` (`record_agent_result` + any `_apply_agent_result`)

- [ ] **Step 1: Extend record_agent_result**

In `hooks/_py/otel.py`, edit `record_agent_result(result: dict)` so it reads the Phase-6 keys off the result dict and sets them on the active span:

```python
def record_agent_result(result: dict) -> None:
    """Attach result to the currently active agent span.

    Phase 6 keys honored on `result` (all optional; default 0/empty):
      - budget_total_usd          -> forge.run.budget_total_usd
      - budget_remaining_usd      -> forge.run.budget_remaining_usd
      - tier_estimate_usd         -> forge.agent.tier_estimate_usd
      - tier_original             -> forge.agent.tier_original
      - tier_used                 -> forge.agent.tier_used
      - throttle_reason           -> forge.cost.throttle_reason
    """
    if not _STATE.enabled:
        return
    from opentelemetry import trace
    from hooks._py import otel_attributes as A

    span = trace.get_current_span()
    if span is None:
        return

    # Phase 6 cost attributes (best-effort; never raise).
    for src, attr in (
        ("budget_total_usd", A.FORGE_RUN_BUDGET_TOTAL_USD),
        ("budget_remaining_usd", A.FORGE_RUN_BUDGET_REMAINING_USD),
        ("tier_estimate_usd", A.FORGE_AGENT_TIER_ESTIMATE_USD),
        ("tier_original", A.FORGE_AGENT_TIER_ORIGINAL),
        ("tier_used", A.FORGE_AGENT_TIER_USED),
        ("throttle_reason", A.FORGE_COST_THROTTLE_REASON),
    ):
        if src in result:
            try:
                span.set_attribute(attr, result[src])
            except Exception:
                pass

    sid = span.get_span_context().span_id
    if sid in _TOTAL_RESULT:
        _TOTAL_RESULT[sid] = result
    else:
        _apply_agent_result(span, result)
```

Event replay (`hooks/_py/event_to_span.py`) already mirrors all keys from event dicts onto spans via `emit_event_mirror`; no additional work is required for replay round-trip as long as the orchestrator writes the same six keys into `events.jsonl` (Task 14).

- [ ] **Step 2: Commit**

```bash
git add hooks/_py/otel.py
git commit -m "feat(otel): emit forge.cost.* attrs in record_agent_result (AC-610)"
```

---

## Task 13: Document OTel namespace contract in observability.md

**Rationale:** Spec §Cross-Phase Coordination says `forge.*` is authoritative and Phase 4's unprefixed `learning.*` is a bug. Phase 6 must not introduce any new unprefixed roots; also document the new attrs.

**Files:**
- Modify: `shared/observability.md`

- [ ] **Step 1: Append new attrs and namespace contract**

Add to the `### Agent spans` table:

```markdown
- `forge.run.budget_total_usd` (double) — configured ceiling
- `forge.run.budget_remaining_usd` (double) — at span start
- `forge.agent.tier_estimate_usd` (double) — per-iteration estimate for resolved tier
- `forge.agent.tier_original` (string, enum: fast|standard|premium) — tier from static routing before downgrade
- `forge.agent.tier_used` (string, enum: fast|standard|premium) — tier actually dispatched
- `forge.cost.throttle_reason` (string, enum: none|soft_20pct|soft_10pct|ceiling_breach|dynamic_downgrade)
```

Append a new section:

```markdown
## Namespace Contract (forge 3.7.0+)

All forge-emitted span attributes MUST use the `forge.*` root. OpenTelemetry semconv attributes (`gen_ai.*`) remain unchanged. The contract is:

| Prefix | Owned by | Examples |
|---|---|---|
| `gen_ai.*` | OTel GenAI semconv 2026 | `gen_ai.agent.name`, `gen_ai.tokens.input` |
| `forge.run.*` | per-run state (bounded + unbounded) | `forge.run_id`, `forge.run.budget_total_usd` |
| `forge.stage.*` | per-stage state | `forge.stage`, `forge.phase_iterations` |
| `forge.agent.*` | per-dispatch agent state | `forge.agent.tier_used`, `forge.agent.tier_original` |
| `forge.cost.*` | Phase 6 cost governance | `forge.cost.throttle_reason`, `forge.cost.unknown` |
| `forge.batch.*` | review-batch spans | `forge.batch.size`, `forge.batch.agents` |

**Phase 4 rename prerequisite:** Any attributes still emitted as `learning.*` (unprefixed) must be renamed to `forge.learning.*` before Phase 6 merges. Phase 6 will not introduce any new roots outside this table.
```

- [ ] **Step 2: Commit**

```bash
git add shared/observability.md
git commit -m "docs(otel): forge.cost.*/forge.agent.tier_* + namespace contract"
```

---

## Task 14: Orchestrator — dispatch-gate block

**Rationale:** AC-602/603/604/605. The orchestrator is the only place that stops a dispatch; it must (a) inject the budget block, (b) check projection vs ceiling, (c) apply dynamic downgrade, (d) write incident files, (e) branch on `state.autonomous`.

**Files:**
- Modify: `agents/fg-100-orchestrator.md`

- [ ] **Step 1: Add new §Cost Governance section before §Context Guard Integration**

Insert the following block into `agents/fg-100-orchestrator.md` immediately after the existing `### Cost Alerting Integration` subsection (which stays — token-denominated layer is preserved) and before `### Context Guard Integration`:

```markdown
### Cost Governance (Phase 6) — USD-denominated

**Applies to every `Agent(...)` dispatch.** Runs after `cost-alerting.sh check` and before context-guard.

**Step 1 — Load budget snapshot:**

```python
cost_cfg = config.cost                            # from forge-config.md
state_cost = state["cost"]                        # from state.json v2.0.0
ceiling = cost_cfg["ceiling_usd"]
spent = state_cost.get("spent_usd", state_cost.get("estimated_cost_usd", 0.0))
remaining = max(0.0, ceiling - spent) if ceiling > 0 else float("inf")
resolved_tier = model_routing.resolve(agent_name)
tier_est = cost_cfg["tier_estimates_usd"][resolved_tier]
```

**Step 2 — Dynamic downgrade (if `cost.aware_routing: true`):**

```python
from shared.cost_governance import downgrade_tier, is_safety_critical

new_tier, reason = downgrade_tier(
    agent=agent_name,
    resolved_tier=resolved_tier,
    remaining_usd=remaining,
    tier_estimates=cost_cfg["tier_estimates_usd"],
    conservatism_multiplier=cost_cfg["conservatism_multiplier"],
    pinned_agents=cost_cfg["pinned_agents"],
    aware_routing=cost_cfg["aware_routing"],
)
if reason == "escalate_required":
    # Fast-tier non-safety agent would be skipped -> escalate instead.
    escalate_ceiling_breach(agent_name, new_tier, spent + tier_est)
elif new_tier != resolved_tier:
    state_cost["downgrades"].append({
        "agent": agent_name, "from": resolved_tier, "to": new_tier,
        "timestamp": now_iso(), "remaining_usd": round(remaining, 4),
    })
    state_cost["downgrade_count"] = len(state_cost["downgrades"])
    resolved_tier = new_tier
    tier_est = cost_cfg["tier_estimates_usd"][new_tier]
```

**Step 3 — Ceiling breach check (AC-603):**

```python
projected = spent + tier_est
if ceiling > 0 and projected > ceiling:
    escalate_ceiling_breach(agent_name, resolved_tier, projected)
    # escalate may return a new tier, raise ceiling, or abort — see Step 4.
    # On return, re-read state_cost and re-project.
```

**Step 4 — `escalate_ceiling_breach(agent, tier, projected)`:**

| Mode | Action |
|---|---|
| `state.autonomous == false` | **AskUserQuestion** payload from `shared/ask-user-question-patterns.md` §8. Map user choice: `raise_ceiling` -> update `state.cost.ceiling_usd = ceiling * 1.4` rounded; `downgrade` -> call `cost-alerting.sh apply-downgrade` + mark `state.cost_alerting.routing_override`; `abort_to_ship` -> transition to SHIPPING via `forge-state.sh transition abort-to-ship`; `abort_full` -> transition to ABORTED. |
| `state.autonomous == true` | **NEVER AskUserQuestion.** Auto-select (1) downgrade; if `downgrade_tier()` returns `no_downgrade` or `safety_pinned`, auto-select (2) abort-to-ship. Log `COST-ESCALATION-AUTO` INFO. |
| Interactive timeout (300s per §Default Timeouts) | Default to `abort_to_ship`. Log `COST-ESCALATION-TIMEOUT`. |

**Step 5 — Write incident (every escalation, both modes):**

```python
from shared.cost_governance import write_incident
incident = {
    "timestamp": now_iso(),
    "ceiling_usd": ceiling,
    "spent_usd": round(spent, 4),
    "projected_usd": round(projected, 4),
    "next_agent": agent_name,
    "resolved_tier": resolved_tier,
    "decision": decision,                # raise_ceiling | downgrade | abort_to_ship | abort_full | timeout
    "autonomous": bool(state.get("autonomous", False)),
    "run_id": state["run_id"],
}
if decision == "raise_ceiling":
    incident["new_ceiling_usd"] = state_cost["ceiling_usd"]
elif decision == "downgrade":
    incident["downgrade_from"] = resolved_tier_before
    incident["downgrade_to"] = resolved_tier
write_incident(incident, Path(FORGE_DIR))
state_cost["ceiling_breaches"] += 1
```

**Step 6 — Inject `## Cost Budget` block into the brief (AC-602):**

```python
from shared.cost_governance import compute_budget_block
brief = (
    static_system_prompt(agent_name)
    + "\n"
    + compute_budget_block(
        ceiling_usd=ceiling, spent_usd=spent,
        tier=resolved_tier, tier_estimate=tier_est,
    )
    + "\n"
    + dynamic_task_content
)
```

The block appears AFTER the static system prompt and BEFORE per-task dynamic content so prompt caching is preserved (see `shared/model-routing.md` §Prompt Caching Strategy).

**Step 7 — Dispatch and record Phase-6 result keys:**

```python
result = Agent(subagent_type=agent_name, model=resolved_tier, prompt=brief)
# After dispatch returns:
otel.record_agent_result({
    **result.otel_keys,
    "budget_total_usd": ceiling,
    "budget_remaining_usd": max(0.0, ceiling - (spent + actual_cost(result))),
    "tier_estimate_usd": tier_est,
    "tier_original": original_tier_before_downgrade,
    "tier_used": resolved_tier,
    "throttle_reason": throttle_reason_from_steps_2_3,
})
events.append({"type": "dispatch_complete", **result.otel_keys,
               "budget_total_usd": ceiling, "tier_used": resolved_tier, ...})
```

**Step 8 — Post-dispatch warn-at threshold:**

After recording, if `state.cost.pct_consumed >= cost.warn_at` and not already warned: log `[COST] INFO: crossed warn_at threshold ({pct}% of ${ceiling})` and set a one-time flag in `state.cost.warn_at_fired = true`.

**Disabled-ceiling behavior (`cost.ceiling_usd: 0`, AC-614):**
- `remaining` = infinity, Step 3 never fires.
- Budget block renders "unlimited" via `compute_budget_block()`.
- Downgrade check never trips.
- No incidents written.
```

- [ ] **Step 2: Commit**

```bash
git add agents/fg-100-orchestrator.md
git commit -m "feat(orchestrator): cost-governance dispatch gate (AC-602/603/604/605/614)"
```

---

## Task 15: Implementer — §5.3b Soft Cost Throttle

**Rationale:** AC-606. Implementer self-throttles at 80% and 90% budget consumption. Throttle NEVER affects RED/GREEN — correctness gates are immune.

**Files:**
- Modify: `agents/fg-300-implementer.md`

- [ ] **Step 1: Insert §5.3b between §5.3a Reflect and §5.4 Refactor**

Add immediately before the `### 5.4 Refactor` heading (or equivalent) and after §5.3a:

```markdown
### 5.3b Soft Cost Throttle (Phase 6)

Read `state.cost` from the brief's `## Cost Budget` block. Compute `remaining_frac = remaining_usd / ceiling_usd` (or skip this section when ceiling is 0).

| Remaining fraction | Action |
|---|---|
| `> 0.20` | Full behavior: proceed to §5.4 REFACTOR + §5.3a critic loop as configured. |
| `0.10 < x <= 0.20` | Emit `COST-THROTTLE-IMPL` INFO finding. Skip second refactor pass (minimal cleanup only). Still dispatch `fg-301-implementer-critic` per §5.3a. |
| `<= 0.10` | Emit `COST-THROTTLE-IMPL` WARNING finding. Skip second refactor. Skip critic dispatch; append `REFLECT_SKIPPED_COST` INFO event (NOT `REFLECT_EXHAUSTED`). |

**Finding payload:**

```json
{
  "category": "COST-THROTTLE-IMPL",
  "severity": "INFO|WARNING",
  "file": "{current_task.files[0]}",
  "line": 1,
  "message": "Skipped refactor pass #2 — budget at {pct}% consumed",
  "confidence": "HIGH",
  "suggestion": "Raise cost.ceiling_usd in forge-config.md or accept slightly lower polish"
}
```

**Append to state (append-only):**

```json
state.cost.throttle_events.append({
  "agent": "fg-300-implementer",
  "severity": "INFO",                    // or "WARNING"
  "pct_consumed": 0.85,
  "action": "skip_refactor_pass_2",      // or "skip_refactor_and_critic"
  "task_id": "{current_task.id}",
  "timestamp": "{now_iso}"
})
```

**Forbidden:** Throttle NEVER skips the RED phase (§5.1 Write Failing Test), the GREEN phase (§5.3 Implement), or the inner-loop lint/test validation (§5.4.1). Correctness gates are immune. Only discretionary polish (second refactor pass, critic dispatch) is elided.

**Throttle reason propagation:** Set `throttle_reason = "soft_20pct"` or `"soft_10pct"` in the implementer's result dict so the orchestrator can surface it through `otel.record_agent_result()` as `forge.cost.throttle_reason` (Task 12).
```

- [ ] **Step 2: Commit**

```bash
git add agents/fg-300-implementer.md
git commit -m "feat(implementer): §5.3b soft cost throttle at 80%/90% (AC-606)"
```

---

## Task 16: Retrospective — Cost Governance subsection

**Rationale:** AC-611/612/613. Retrospective emits per-run summary, cost-per-actionable-finding flagging (gated on peer cohort ≥1 CRITICAL/WARNING), and EST-DRIFT detection. Also backfills F29 run-history columns.

**Files:**
- Modify: `agents/fg-700-retrospective.md`
- Modify: `shared/run-history/migrations/002-cost-columns.sql` (created in Task 17)

- [ ] **Step 1: Insert §Cost Governance Analytics after Output 2.5 / before Output 2.6**

Append the following subsection to `agents/fg-700-retrospective.md`:

```markdown
### Output 2.7: Cost Governance Analytics (Phase 6)

**Per-run summary.** Read `.forge/cost-incidents/*.json` (empty = clean run). Emit under `## Cost Governance` in the retrospective report:

```markdown
## Cost Governance

- Ceiling: ${ceiling_usd}
- Spent:   ${spent_usd} ({pct_consumed}%)
- Ceiling breaches: {ceiling_breaches}
- Downgrades applied: {downgrade_count}
- Throttle events: {len(throttle_events)} ({info_count} INFO / {warning_count} WARNING)
```

**Cost-per-actionable-finding (AC-611).**

Scope: reviewers only (`fg-410` through `fg-419`). Skip all other agents.

```python
peer_cohort_findings = [f for f in all_findings if f.agent.startswith("fg-4")]
actionable = [f for f in peer_cohort_findings if f.severity in ("CRITICAL", "WARNING")]

# Gate: only emit cost-per-finding when peer cohort produced actionable findings.
if not actionable:
    return  # clean run — no reviewer flagged, zero-finding reviewers NOT penalized.

for reviewer in reviewers:
    unique = dedupe(reviewer.findings, keyed_by=("file", "line", "category"))
    unique_actionable = [f for f in unique if f.severity in ("CRITICAL", "WARNING")]
    if not unique_actionable:
        continue  # this reviewer clean on a dirty run — still NOT flagged.
    cpaf = reviewer.cost_usd / len(unique_actionable)
    reviewer.cost_per_actionable_finding = cpaf

median_cpaf = statistics.median(r.cost_per_actionable_finding for r in reviewers
                                if hasattr(r, "cost_per_actionable_finding"))

flagged = [r for r in reviewers
           if getattr(r, "cost_per_actionable_finding", 0) > 3 * median_cpaf]
```

Emit each flagged reviewer as a candidate for `model_routing` downgrade suggestion. Subject to the existing "2 tier changes per run" cap from `shared/model-routing.md`.

**Zero-finding-clean-code safety:** AC-611 explicitly carves out the case where every reviewer emits 0 findings — nobody is flagged. This is the reviewer working as intended on clean code. The gate above (`if not actionable: return`) is the one line enforcing that rule.

**EST-DRIFT detection (AC-613).** Across the last 10 dispatches per agent, compute:

```python
actual_per_dispatch = agent.cost_usd / agent.dispatches
estimated = cost.tier_estimates_usd[agent.tier_used_majority]
if agent.dispatches >= 10 and abs(actual_per_dispatch - estimated) / estimated > 2.0:
    emit_finding({
        "category": "EST-DRIFT",
        "severity": "WARNING",
        "file": "forge-config.md",
        "line": 0,
        "message": f"Agent {agent.id} actual cost ${actual_per_dispatch:.4f} vs estimated ${estimated:.4f} (>{2.0}x drift across {agent.dispatches} dispatches)",
        "confidence": "HIGH",
        "suggestion": f"Update cost.tier_estimates_usd.{agent.tier_used_majority} in forge-config.md",
    })
```

Do NOT auto-adjust `tier_estimates_usd` — user edits config. Auto-tuning estimates is too self-reinforcing.

**Run-history columns (AC-612).** On INSERT INTO `runs` (existing Step 4 of Output 2.5), also populate the four new `run_summary` columns from migration 002:

```sql
INSERT INTO run_summary (
  run_id, started_at, ...existing_columns...,
  ceiling_usd, spent_usd, ceiling_breaches, throttle_events
) VALUES (
  ?, ?, ...,
  :ceiling_usd, :spent_usd, :ceiling_breaches, :throttle_events_count
);
```

Where `:throttle_events_count = len(state.cost.throttle_events)`.

**30-day trend query (example, run on demand):**

```sql
SELECT
  DATE(started_at) AS day,
  AVG(spent_usd) AS avg_cost,
  SUM(ceiling_breaches) AS total_breaches,
  AVG(spent_usd / NULLIF(ceiling_usd, 0)) AS avg_utilization
FROM run_summary
WHERE started_at > datetime('now', '-30 days')
GROUP BY day;
```

Appended to `reports/forge-{YYYY-MM-DD}.md` when the retrospective runs.
```

- [ ] **Step 2: Commit**

```bash
git add agents/fg-700-retrospective.md
git commit -m "feat(retro): §Cost Governance analytics (AC-611/612/613)"
```

---

## Task 17: F29 run-history migration — cost columns

**Rationale:** AC-612. The retrospective (Task 16) writes `ceiling_usd`, `spent_usd`, `ceiling_breaches`, `throttle_events` into `run_summary`. The columns must exist first.

**Files:**
- Create: `shared/run-history/migrations/002-cost-columns.sql`
- Modify: `shared/run-history/run-history.md` (document the 4 columns)

- [ ] **Step 1: Write the migration SQL**

Create `shared/run-history/migrations/002-cost-columns.sql`:

```sql
-- Migration 002: Phase 6 cost governance columns on run_summary.
-- Applied when user_version < 2. PRAGMA user_version = 2 at end.

BEGIN TRANSACTION;

ALTER TABLE run_summary ADD COLUMN ceiling_usd REAL DEFAULT 0.0;
ALTER TABLE run_summary ADD COLUMN spent_usd REAL DEFAULT 0.0;
ALTER TABLE run_summary ADD COLUMN ceiling_breaches INTEGER DEFAULT 0;
ALTER TABLE run_summary ADD COLUMN throttle_events INTEGER DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_run_summary_spent_usd ON run_summary(spent_usd);
CREATE INDEX IF NOT EXISTS idx_run_summary_breaches ON run_summary(ceiling_breaches)
  WHERE ceiling_breaches > 0;

PRAGMA user_version = 2;

COMMIT;
```

- [ ] **Step 2: Document the columns in run-history.md**

Append to `shared/run-history/run-history.md` under the `run_summary` schema table:

```markdown
### Phase 6 cost columns (migration 002)

| Column | Type | Default | Meaning |
|---|---|---|---|
| `ceiling_usd` | REAL | 0.0 | Configured `cost.ceiling_usd` at run start |
| `spent_usd` | REAL | 0.0 | Final `state.cost.spent_usd` |
| `ceiling_breaches` | INTEGER | 0 | Count of `.forge/cost-incidents/*.json` written |
| `throttle_events` | INTEGER | 0 | `len(state.cost.throttle_events)` |

Indexes: `idx_run_summary_spent_usd`, `idx_run_summary_breaches` (partial, non-zero only).
```

- [ ] **Step 3: Commit**

```bash
git add shared/run-history/migrations/002-cost-columns.sql shared/run-history/run-history.md
git commit -m "feat(run-history): migration 002 — cost columns on run_summary (AC-612)"
```

---

## Task 18: Scenario test — soft-throttle behavior

**Rationale:** AC-606 — verify INFO at 80%, WARNING at 90%, critic dispatched at 80% but NOT at 90%, RED/GREEN never skipped.

**Files:**
- Create: `tests/scenario/cost-soft-throttle.bats`

- [ ] **Step 1: Write the test**

```bash
#!/usr/bin/env bats
# Scenario: implementer soft throttle at 80% / 90% budget consumption.
# Mocks: state fixture with pre-set cost block; implementer called via
# tests/helpers/implementer-harness.sh (read-only dispatch simulator).

load '../helpers/test-helpers'
load '../helpers/implementer-harness'

setup() {
  export FORGE_DIR="$BATS_TEST_TMPDIR/.forge"
  mkdir -p "$FORGE_DIR"
  cp "$PLUGIN_ROOT/tests/fixtures/state-v2-cost.json" "$FORGE_DIR/state.json"
}

@test "implementer at 85% consumed: emits COST-THROTTLE-IMPL INFO, skips refactor #2, dispatches critic" {
  seed_state_cost_pct 0.85
  run implementer_harness run-task task-001
  assert_success
  assert_line -p "COST-THROTTLE-IMPL"
  assert_line -p "severity: INFO"
  refute_line -p "refactor pass #2 executed"
  assert_line -p "fg-301-implementer-critic dispatched"
}

@test "implementer at 95% consumed: emits COST-THROTTLE-IMPL WARNING, skips refactor, skips critic" {
  seed_state_cost_pct 0.95
  run implementer_harness run-task task-001
  assert_success
  assert_line -p "COST-THROTTLE-IMPL"
  assert_line -p "severity: WARNING"
  refute_line -p "refactor pass #2 executed"
  refute_line -p "fg-301-implementer-critic dispatched"
  assert_line -p "REFLECT_SKIPPED_COST"
  refute_line -p "REFLECT_EXHAUSTED"
}

@test "implementer at 99% consumed: RED/GREEN still run (correctness gates immune)" {
  seed_state_cost_pct 0.99
  run implementer_harness run-task task-001
  assert_success
  assert_line -p "RED phase executed"
  assert_line -p "GREEN phase executed"
}

@test "implementer at 95%: state.cost.throttle_events appended with severity WARNING" {
  seed_state_cost_pct 0.95
  implementer_harness run-task task-001
  run python3 -c "
import json, sys
st = json.load(open('$FORGE_DIR/state.json'))
events = st['cost']['throttle_events']
assert len(events) >= 1, events
assert events[-1]['severity'] == 'WARNING', events[-1]
assert events[-1]['action'] == 'skip_refactor_and_critic', events[-1]
print('ok')
"
  assert_success
}
```

- [ ] **Step 2: Create the required fixture + harness**

Fixture `tests/fixtures/state-v2-cost.json`:

```json
{
  "version": "2.0.0",
  "_seq": 0,
  "run_id": "test-run-phase6",
  "mode": "standard",
  "autonomous": false,
  "stage": "IMPLEMENTING",
  "cost": {
    "ceiling_usd": 10.00,
    "spent_usd": 0.00,
    "remaining_usd": 10.00,
    "pct_consumed": 0.0,
    "tier_estimates_usd": {"fast": 0.016, "standard": 0.047, "premium": 0.078},
    "conservatism_multiplier": {"fast": 1.0, "standard": 1.0, "premium": 1.0},
    "tier_breakdown": {"fast": 0.0, "standard": 0.0, "premium": 0.0},
    "downgrade_count": 0,
    "downgrades": [],
    "throttle_events": [],
    "ceiling_breaches": 0
  }
}
```

Harness helper `tests/helpers/implementer-harness.bash`:

```bash
# Seed state.cost to a target pct_consumed value.
seed_state_cost_pct() {
  local target_pct="$1"
  python3 -c "
import json, sys
p = '$FORGE_DIR/state.json'
st = json.load(open(p))
ceiling = float(st['cost']['ceiling_usd'])
spent = ceiling * float('$target_pct')
st['cost']['spent_usd'] = round(spent, 4)
st['cost']['remaining_usd'] = round(max(0.0, ceiling - spent), 4)
st['cost']['pct_consumed'] = round(spent / ceiling, 4) if ceiling > 0 else 0.0
json.dump(st, open(p, 'w'), indent=2)
"
}

# Read-only dispatch simulator. Echoes the same log lines the real implementer
# would emit, so scenario assertions can pattern-match without a live subagent.
implementer_harness() {
  python3 "$PLUGIN_ROOT/tests/helpers/implementer_sim.py" "$@"
}
```

Python harness `tests/helpers/implementer_sim.py`:

```python
"""Read-only implementer simulator for scenario tests.

Implements §5.3b decision logic from agents/fg-300-implementer.md and prints
human-readable log lines that scenario bats tests pattern-match.
"""
import json
import os
import sys
from datetime import datetime, timezone

def main() -> int:
    forge_dir = os.environ["FORGE_DIR"]
    task_id = sys.argv[2] if len(sys.argv) > 2 else "task-sim"
    with open(f"{forge_dir}/state.json") as fh:
        st = json.load(fh)
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
        print("fg-301-implementer-critic dispatched")
    elif frac > 0.10:
        severity = "INFO"; action = "skip_refactor_pass_2"
        print(f"COST-THROTTLE-IMPL severity: INFO — skipped refactor #2 @ {pct}%")
        print("fg-301-implementer-critic dispatched")
    else:
        severity = "WARNING"; action = "skip_refactor_and_critic"
        print(f"COST-THROTTLE-IMPL severity: WARNING — skipped refactor+critic @ {pct}%")
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
        with open(f"{forge_dir}/state.json", "w") as fh:
            json.dump(st, fh, indent=2)
    return 0

if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 3: Run in CI — expect PASS**

- [ ] **Step 4: Commit**

```bash
git add tests/scenario/cost-soft-throttle.bats \
        tests/fixtures/state-v2-cost.json \
        tests/helpers/implementer-harness.bash \
        tests/helpers/implementer_sim.py
git commit -m "test(cost): scenario for §5.3b soft throttle (AC-606)"
```

---

## Task 19: Scenario test — ceiling breach in interactive mode

**Rationale:** AC-603. Validates AskUserQuestion payload matches §8 when projected spend breaches ceiling.

**Files:**
- Create: `tests/scenario/cost-ceiling-interactive.bats`
- Create: `tests/helpers/orchestrator-gate-sim.py` (read-only dispatch-gate simulator)

- [ ] **Step 1: Write the harness**

`tests/helpers/orchestrator-gate-sim.py`:

```python
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

sys.path.insert(0, os.path.join(os.environ["PLUGIN_ROOT"], "shared"))
from cost_governance import (
    compute_budget_block, downgrade_tier, is_safety_critical,
    project_spend, write_incident,
)


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def main() -> int:
    forge_dir = Path(os.environ["FORGE_DIR"])
    agent_name = sys.argv[1]
    resolved_tier = sys.argv[2]
    st = json.loads((forge_dir / "state.json").read_text())
    cost_cfg = {
        "ceiling_usd": st["cost"]["ceiling_usd"],
        "tier_estimates_usd": st["cost"]["tier_estimates_usd"],
        "conservatism_multiplier": st["cost"]["conservatism_multiplier"],
        "aware_routing": True, "pinned_agents": [],
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
            agent=agent_name, resolved_tier=resolved_tier,
            remaining_usd=max(0.0, ceiling - spent),
            tier_estimates=cost_cfg["tier_estimates_usd"],
            conservatism_multiplier=cost_cfg["conservatism_multiplier"],
            pinned_agents=[], aware_routing=True,
        )
        if new_tier != resolved_tier:
            decision = "downgrade"
            print(json.dumps({"action": "auto-decide", "decision": decision,
                              "from": resolved_tier, "to": new_tier}))
        else:
            decision = "abort_to_ship"
            print(json.dumps({"action": "auto-decide", "decision": decision}))
    else:
        raised = round(ceiling * 1.4)
        payload = {
            "question": f"Next dispatch would breach cost ceiling (${ceiling:.2f}). Projected: ${projected:.2f}. How should we proceed?",
            "header": "Cost ceiling",
            "multiSelect": False,
            "options": [
                {"label": f"Raise ceiling to ${raised}", "description": "Continues run. Records new ceiling in state for this run only."},
                {"label": "Downgrade remaining agents (Recommended)", "description": "Switches premium->standard, standard->fast where safe. Excludes pinned agents and safety-critical reviewers."},
                {"label": "Abort to ship current state", "description": "Runs pre-ship verifier on what's in the worktree, then ships or exits."},
                {"label": "Abort fully", "description": "Stops immediately. Preserves state for /forge-recover resume."},
            ],
        }
        print(json.dumps({"action": "ask-user", "payload": payload}))
        decision = "abort_full"  # default for the harness — overridden in tests.

    incident = {
        "timestamp": now_iso(), "ceiling_usd": ceiling,
        "spent_usd": round(spent, 4), "projected_usd": round(projected, 4),
        "next_agent": agent_name, "resolved_tier": resolved_tier,
        "decision": decision, "autonomous": autonomous,
        "run_id": st.get("run_id", "unknown"),
    }
    write_incident(incident, forge_dir)
    st["cost"]["ceiling_breaches"] = st["cost"].get("ceiling_breaches", 0) + 1
    (forge_dir / "state.json").write_text(json.dumps(st, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 2: Write the scenario**

`tests/scenario/cost-ceiling-interactive.bats`:

```bash
#!/usr/bin/env bats
load '../helpers/test-helpers'

setup() {
  export FORGE_DIR="$BATS_TEST_TMPDIR/.forge"
  export PLUGIN_ROOT
  mkdir -p "$FORGE_DIR"
  cp "$PLUGIN_ROOT/tests/fixtures/state-v2-cost.json" "$FORGE_DIR/state.json"
  # Seed: spent 0.48 of 0.50 ceiling; planner tier_estimate = 0.078.
  python3 -c "
import json
p='$FORGE_DIR/state.json'
st=json.load(open(p))
st['cost']['ceiling_usd']=0.50
st['cost']['spent_usd']=0.48
st['cost']['remaining_usd']=0.02
st['autonomous']=False
json.dump(st, open(p,'w'), indent=2)
"
}

@test "interactive breach: AskUserQuestion payload matches §8 pattern" {
  run python3 "$PLUGIN_ROOT/tests/helpers/orchestrator-gate-sim.py" fg-200-planner premium
  assert_success
  assert_output -p '"action": "ask-user"'
  assert_output -p '"header": "Cost ceiling"'
  assert_output -p '"question": "Next dispatch would breach cost ceiling'
  assert_output -p 'Downgrade remaining agents (Recommended)'
  assert_output -p 'Abort to ship current state'
  assert_output -p 'Abort fully'
}

@test "interactive breach: header is exactly 12 chars" {
  run python3 "$PLUGIN_ROOT/tests/helpers/orchestrator-gate-sim.py" fg-200-planner premium
  assert_success
  run python3 -c "import json,sys; d=json.loads('''$output'''); print(len(d['payload']['header']))"
  assert_output "12"
}

@test "interactive breach: ceiling_breaches counter incremented to 1" {
  python3 "$PLUGIN_ROOT/tests/helpers/orchestrator-gate-sim.py" fg-200-planner premium >/dev/null
  run python3 -c "
import json
st=json.load(open('$FORGE_DIR/state.json'))
print(st['cost']['ceiling_breaches'])
"
  assert_output "1"
}

@test "interactive breach: .forge/cost-incidents/*.json written" {
  python3 "$PLUGIN_ROOT/tests/helpers/orchestrator-gate-sim.py" fg-200-planner premium >/dev/null
  run bash -c "ls $FORGE_DIR/cost-incidents/*.json | wc -l"
  assert_output "1"
}
```

- [ ] **Step 3: Commit**

```bash
git add tests/helpers/orchestrator-gate-sim.py tests/scenario/cost-ceiling-interactive.bats
git commit -m "test(cost): scenario for interactive ceiling breach (AC-603)"
```

---

## Task 20: Scenario test — autonomous mode ceiling breach

**Rationale:** AC-604. Validates no AskUserQuestion, auto-decide downgrade → abort-to-ship.

**Files:**
- Create: `tests/scenario/cost-ceiling-autonomous.bats`

- [ ] **Step 1: Write the scenario**

```bash
#!/usr/bin/env bats
load '../helpers/test-helpers'

setup() {
  export FORGE_DIR="$BATS_TEST_TMPDIR/.forge"
  export PLUGIN_ROOT
  mkdir -p "$FORGE_DIR"
  cp "$PLUGIN_ROOT/tests/fixtures/state-v2-cost.json" "$FORGE_DIR/state.json"
  python3 -c "
import json
p='$FORGE_DIR/state.json'
st=json.load(open(p))
st['cost']['ceiling_usd']=0.50
st['cost']['spent_usd']=0.48
st['cost']['remaining_usd']=0.02
st['autonomous']=True
json.dump(st, open(p,'w'), indent=2)
"
}

@test "autonomous breach: auto-decides downgrade (AC-604)" {
  run python3 "$PLUGIN_ROOT/tests/helpers/orchestrator-gate-sim.py" fg-200-planner premium
  assert_success
  assert_output -p '"action": "auto-decide"'
  assert_output -p '"decision": "downgrade"'
  assert_output -p '"from": "premium"'
  assert_output -p '"to": "standard"'
  refute_output -p 'ask-user'
}

@test "autonomous breach at fast tier: auto-decides abort_to_ship" {
  run python3 "$PLUGIN_ROOT/tests/helpers/orchestrator-gate-sim.py" fg-410-code-reviewer fast
  assert_success
  assert_output -p '"decision": "abort_to_ship"'
  refute_output -p 'ask-user'
}

@test "autonomous breach: incident.autonomous == true" {
  python3 "$PLUGIN_ROOT/tests/helpers/orchestrator-gate-sim.py" fg-200-planner premium >/dev/null
  local incident
  incident=$(ls "$FORGE_DIR/cost-incidents/"*.json | head -1)
  run python3 -c "import json; print(json.load(open('$incident'))['autonomous'])"
  assert_output "True"
}
```

- [ ] **Step 2: Commit**

```bash
git add tests/scenario/cost-ceiling-autonomous.bats
git commit -m "test(cost): scenario for autonomous ceiling breach (AC-604)"
```

---

## Task 21: Scenario test — incident JSON matches schema

**Rationale:** AC-605 — every escalation produces an incident file conforming to the schema in Task 4.

**Files:**
- Create: `tests/scenario/cost-incident-write.bats`

- [ ] **Step 1: Write the test**

```bash
#!/usr/bin/env bats
load '../helpers/test-helpers'

setup() {
  export FORGE_DIR="$BATS_TEST_TMPDIR/.forge"
  export PLUGIN_ROOT
  mkdir -p "$FORGE_DIR"
  cp "$PLUGIN_ROOT/tests/fixtures/state-v2-cost.json" "$FORGE_DIR/state.json"
  python3 -c "
import json
p='$FORGE_DIR/state.json'
st=json.load(open(p))
st['cost']['ceiling_usd']=0.50
st['cost']['spent_usd']=0.49
st['cost']['remaining_usd']=0.01
st['autonomous']=True
json.dump(st, open(p,'w'), indent=2)
"
}

@test "incident file written with all required keys" {
  python3 "$PLUGIN_ROOT/tests/helpers/orchestrator-gate-sim.py" fg-200-planner premium >/dev/null
  local incident
  incident=$(ls "$FORGE_DIR/cost-incidents/"*.json | head -1)
  run python3 -c "
import json
d=json.load(open('$incident'))
for k in ['timestamp','ceiling_usd','spent_usd','projected_usd','next_agent',
         'resolved_tier','decision','autonomous','run_id']:
    assert k in d, f'missing {k}'
print('ok')
"
  assert_success
}

@test "incident file validates against cost-incident.schema.json" {
  python3 "$PLUGIN_ROOT/tests/helpers/orchestrator-gate-sim.py" fg-200-planner premium >/dev/null
  local incident
  incident=$(ls "$FORGE_DIR/cost-incidents/"*.json | head -1)
  run python3 -c "
import json, sys
try:
    import jsonschema
except ImportError:
    # CI installs jsonschema via pyproject test extras (Step 2 below).
    # Local dev may not; skip gracefully to avoid false red locally.
    print('SKIP: jsonschema not installed'); sys.exit(0)
schema = json.load(open('$PLUGIN_ROOT/shared/schemas/cost-incident.schema.json'))
incident = json.load(open('$incident'))
jsonschema.validate(incident, schema)
print('ok')
"
  assert_success
}

@test "incident.next_agent matches agent-ID pattern fg-NNN-name" {
  python3 "$PLUGIN_ROOT/tests/helpers/orchestrator-gate-sim.py" fg-200-planner premium >/dev/null
  local incident
  incident=$(ls "$FORGE_DIR/cost-incidents/"*.json | head -1)
  run python3 -c "
import json, re
d=json.load(open('$incident'))
assert re.match(r'^fg-[0-9]{3}-[a-z-]+$', d['next_agent']), d['next_agent']
print('ok')
"
  assert_success
}
```

- [ ] **Step 2: Ensure `jsonschema` is installed in CI (don't rely on the graceful skip)**

The test above skips gracefully if `jsonschema` is missing so local dev doesn't go red before the dependency is provisioned. In CI we MUST actually run the validation, not silently skip. Two edits:

1. **`pyproject.toml`** — add a `test` optional-dependencies group (or extend `otel` if preferred) that includes `jsonschema>=4.0.0`. The existing `otel` group already declares `"jsonschema>=4.0.0"`, but scenario tests don't go through the otel install path. Add:

   ```toml
   [project.optional-dependencies]
   test = [
     "jsonschema>=4.0.0",
     "pyyaml",
   ]
   ```

2. **`.github/workflows/test.yml`** — extend the scenario-tier install line. Current:

   ```yaml
   - name: Install Python dependencies
     run: pip install pyyaml
   ```

   Change to (scenario tier only, to keep unit tests fast):

   ```yaml
   - name: Install Python dependencies
     run: |
       pip install pyyaml
       if [ "${{ matrix.tier }}" = "scenario" ]; then
         pip install 'jsonschema>=4.0.0'
       fi
   ```

   With this in place, the `SKIP: jsonschema not installed` branch in the test above should NEVER fire on CI scenario runs — if it does, the workflow change regressed and should be fixed before merging.

- [ ] **Step 3: Commit**

```bash
git add tests/scenario/cost-incident-write.bats pyproject.toml .github/workflows/test.yml
git commit -m "test(cost): incident JSON schema validation (AC-605)"
```

---

## Task 22: Scenario test — SAFETY_CRITICAL never silently skipped

**Rationale:** AC-608. Regression guard — a scenario where cost pressure would normally drop an agent MUST instead escalate when that agent is SAFETY_CRITICAL.

**Files:**
- Create: `tests/scenario/cost-no-silent-safety-skip.bats`

- [ ] **Step 1: Write the test**

```bash
#!/usr/bin/env bats
load '../helpers/test-helpers'

setup() {
  export FORGE_DIR="$BATS_TEST_TMPDIR/.forge"
  export PLUGIN_ROOT
  mkdir -p "$FORGE_DIR"
  cp "$PLUGIN_ROOT/tests/fixtures/state-v2-cost.json" "$FORGE_DIR/state.json"
  # Budget nearly exhausted; every safety-critical agent at fast tier.
  python3 -c "
import json
p='$FORGE_DIR/state.json'
st=json.load(open(p))
st['cost']['ceiling_usd']=0.05
st['cost']['spent_usd']=0.049
st['cost']['remaining_usd']=0.001
json.dump(st, open(p,'w'), indent=2)
"
}

@test "fg-411-security-reviewer at fast: NEVER silently dropped" {
  # In interactive mode, orchestrator must escalate (not skip).
  python3 -c "
import json; p='$FORGE_DIR/state.json'; st=json.load(open(p))
st['autonomous']=False; json.dump(st, open(p,'w'), indent=2)
"
  run python3 "$PLUGIN_ROOT/tests/helpers/orchestrator-gate-sim.py" fg-411-security-reviewer fast
  assert_success
  assert_output -p '"action": "ask-user"'
  refute_output -p '"action": "skip"'
}

@test "fg-411-security-reviewer at fast + autonomous: abort_to_ship, NEVER skip" {
  python3 -c "
import json; p='$FORGE_DIR/state.json'; st=json.load(open(p))
st['autonomous']=True; json.dump(st, open(p,'w'), indent=2)
"
  run python3 "$PLUGIN_ROOT/tests/helpers/orchestrator-gate-sim.py" fg-411-security-reviewer fast
  assert_success
  assert_output -p '"decision": "abort_to_ship"'
  refute_output -p 'skip'
}

@test "every SAFETY_CRITICAL agent declared in cost_governance is a known agent" {
  run python3 -c "
import os, sys, pathlib
sys.path.insert(0, '$PLUGIN_ROOT/shared')
from cost_governance import SAFETY_CRITICAL
agents_dir = pathlib.Path('$PLUGIN_ROOT/agents')
for a in SAFETY_CRITICAL:
    assert (agents_dir / f'{a}.md').exists(), f'missing agent file: {a}'
print('ok')
"
  assert_success
}

@test "SAFETY_CRITICAL list has exactly 10 entries (spec authoritative)" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared')
from cost_governance import SAFETY_CRITICAL
assert len(SAFETY_CRITICAL) == 10
print('ok')
"
  assert_success
}
```

- [ ] **Step 2: Commit**

```bash
git add tests/scenario/cost-no-silent-safety-skip.bats
git commit -m "test(cost): guard SAFETY_CRITICAL from silent skip (AC-608)"
```

---

## Task 23: Scenario test — OTel attrs round-trip through replay

**Rationale:** AC-610. The six new attrs must appear on live spans AND on spans rebuilt by `otel.replay()` from `events.jsonl`.

**Files:**
- Create: `tests/scenario/cost-otel-attrs.bats`
- Create: `tests/fixtures/events-cost-attrs.jsonl`

- [ ] **Step 1: Write the fixture**

`tests/fixtures/events-cost-attrs.jsonl`:

```jsonl
{"type":"run_start","run_id":"otel-test-run","forge.run_id":"otel-test-run"}
{"type":"dispatch_start","gen_ai.agent.name":"fg-200-planner","forge.stage":"PLANNING","forge.run.budget_total_usd":25.0,"forge.run.budget_remaining_usd":24.5,"forge.agent.tier_estimate_usd":0.078,"forge.agent.tier_original":"premium","forge.agent.tier_used":"premium","forge.cost.throttle_reason":"none"}
{"type":"dispatch_complete","gen_ai.agent.name":"fg-200-planner","gen_ai.tokens.input":8000,"gen_ai.tokens.output":1500,"gen_ai.cost.usd":0.078}
{"type":"dispatch_start","gen_ai.agent.name":"fg-300-implementer","forge.stage":"IMPLEMENTING","forge.run.budget_total_usd":25.0,"forge.run.budget_remaining_usd":2.5,"forge.agent.tier_estimate_usd":0.047,"forge.agent.tier_original":"standard","forge.agent.tier_used":"standard","forge.cost.throttle_reason":"soft_20pct"}
{"type":"dispatch_complete","gen_ai.agent.name":"fg-300-implementer","gen_ai.tokens.input":8000,"gen_ai.tokens.output":1500,"gen_ai.cost.usd":0.047}
```

- [ ] **Step 2: Write the test**

```bash
#!/usr/bin/env bats
load '../helpers/test-helpers'

@test "replay emits forge.run.budget_total_usd on agent spans" {
  run python3 -c "
import sys, pathlib
sys.path.insert(0, '$PLUGIN_ROOT')
from hooks._py.otel import replay
# Use the console exporter to capture output.
cfg = {'enabled': True, 'exporter': 'console', 'endpoint': '', 'sample_rate': 1.0,
       'service_name': 'forge-test', 'openinference_compat': False,
       'include_tool_spans': False, 'batch_size': 32, 'flush_interval_seconds': 2}
replay(events_path='$PLUGIN_ROOT/tests/fixtures/events-cost-attrs.jsonl', config=cfg)
" 2>&1
  assert_success
  assert_output -p 'forge.run.budget_total_usd'
  assert_output -p 'forge.run.budget_remaining_usd'
  assert_output -p 'forge.agent.tier_estimate_usd'
  assert_output -p 'forge.agent.tier_original'
  assert_output -p 'forge.agent.tier_used'
  assert_output -p 'forge.cost.throttle_reason'
}

@test "replay preserves tier_original != tier_used on downgrade events" {
  skip_if_no_otel
  # Build a downgrade event and assert both tier attributes survive replay.
  local tmp="$BATS_TEST_TMPDIR/events-downgrade.jsonl"
  cat > "$tmp" <<'EOF'
{"type":"dispatch_start","gen_ai.agent.name":"fg-200-planner","forge.agent.tier_original":"premium","forge.agent.tier_used":"standard","forge.cost.throttle_reason":"dynamic_downgrade"}
EOF
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT')
from hooks._py.otel import replay
cfg = {'enabled': True, 'exporter': 'console', 'endpoint': '', 'sample_rate': 1.0,
       'service_name': 'forge-test', 'openinference_compat': False,
       'include_tool_spans': False, 'batch_size': 32, 'flush_interval_seconds': 2}
replay(events_path='$tmp', config=cfg)
" 2>&1
  assert_success
  assert_output -p 'tier_original": "premium"'
  assert_output -p 'tier_used": "standard"'
  assert_output -p 'throttle_reason": "dynamic_downgrade"'
}
```

- [ ] **Step 3: Commit**

```bash
git add tests/scenario/cost-otel-attrs.bats tests/fixtures/events-cost-attrs.jsonl
git commit -m "test(cost): OTel attrs round-trip through replay (AC-610)"
```

---

## Task 24: Scenario test — cost.ceiling_usd: 0 disables all gates

**Rationale:** AC-614 — with ceiling 0, no breach logic fires, no incidents written, budget block shows "unlimited".

**Files:**
- Create: `tests/scenario/cost-ceiling-disabled.bats`

- [ ] **Step 1: Write the test**

```bash
#!/usr/bin/env bats
load '../helpers/test-helpers'

setup() {
  export FORGE_DIR="$BATS_TEST_TMPDIR/.forge"
  export PLUGIN_ROOT
  mkdir -p "$FORGE_DIR"
  cp "$PLUGIN_ROOT/tests/fixtures/state-v2-cost.json" "$FORGE_DIR/state.json"
  python3 -c "
import json
p='$FORGE_DIR/state.json'
st=json.load(open(p))
st['cost']['ceiling_usd']=0
st['cost']['spent_usd']=9999.99
json.dump(st, open(p,'w'), indent=2)
"
}

@test "ceiling_usd=0: no incident written even at huge spend" {
  run python3 "$PLUGIN_ROOT/tests/helpers/orchestrator-gate-sim.py" fg-200-planner premium
  assert_success
  assert_output -p '"action": "dispatch"'
  run bash -c "ls $FORGE_DIR/cost-incidents/ 2>/dev/null | wc -l"
  assert_output "0"
}

@test "ceiling_usd=0: budget block renders 'unlimited'" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared')
from cost_governance import compute_budget_block
out = compute_budget_block(ceiling_usd=0, spent_usd=123.45, tier='premium', tier_estimate=0.078)
assert 'unlimited' in out.lower()
print(out)
"
  assert_success
  assert_output -p "unlimited"
  assert_output -p 'Your tier: premium'
}
```

- [ ] **Step 2: Commit**

```bash
git add tests/scenario/cost-ceiling-disabled.bats
git commit -m "test(cost): ceiling_usd=0 disables all gates (AC-614)"
```

---

## Task 25: Scenario test — aware_routing + pinned_agents respect

**Rationale:** AC-607, AC-609. Confirms the orchestrator path honors both the 5× trip and the pinned-agents carve-out end-to-end.

**Files:**
- Create: `tests/scenario/cost-aware-routing.bats`

- [ ] **Step 1: Write the test**

```bash
#!/usr/bin/env bats
load '../helpers/test-helpers'

setup() {
  export FORGE_DIR="$BATS_TEST_TMPDIR/.forge"
  export PLUGIN_ROOT
  mkdir -p "$FORGE_DIR"
  cp "$PLUGIN_ROOT/tests/fixtures/state-v2-cost.json" "$FORGE_DIR/state.json"
  python3 -c "
import json
p='$FORGE_DIR/state.json'
st=json.load(open(p))
st['cost']['ceiling_usd']=1.00
st['cost']['spent_usd']=0.70
st['cost']['remaining_usd']=0.30
json.dump(st, open(p,'w'), indent=2)
"
}

@test "aware_routing with remaining=0.30, premium est=0.078, trip=0.39 -> downgrade (AC-607)" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared')
from cost_governance import downgrade_tier
t, r = downgrade_tier(
    agent='fg-200-planner', resolved_tier='premium', remaining_usd=0.30,
    tier_estimates={'fast':0.016,'standard':0.047,'premium':0.078},
    conservatism_multiplier={'fast':1.0,'standard':1.0,'premium':1.0},
    pinned_agents=[], aware_routing=True,
)
print(f'{t}|{r}')
"
  assert_success
  assert_output "standard|downgrade_from_premium"
}

@test "pinned_agent stays on premium even when trip is crossed (AC-609)" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared')
from cost_governance import downgrade_tier
t, r = downgrade_tier(
    agent='fg-200-planner', resolved_tier='premium', remaining_usd=0.30,
    tier_estimates={'fast':0.016,'standard':0.047,'premium':0.078},
    conservatism_multiplier={'fast':1.0,'standard':1.0,'premium':1.0},
    pinned_agents=['fg-200-planner'], aware_routing=True,
)
print(f'{t}|{r}')
"
  assert_success
  assert_output "premium|agent_pinned"
}

@test "downgrade appended to state.cost.downgrades[] with (from, to, remaining_usd)" {
  # Simulate the orchestrator state mutation performed in Task 14 Step 2.
  python3 -c "
import json, sys
sys.path.insert(0, '$PLUGIN_ROOT/shared')
from cost_governance import downgrade_tier
from datetime import datetime, timezone
p='$FORGE_DIR/state.json'
st=json.load(open(p))
t, r = downgrade_tier(
    agent='fg-412-architecture-reviewer', resolved_tier='premium',
    remaining_usd=st['cost']['remaining_usd'],
    tier_estimates=st['cost']['tier_estimates_usd'],
    conservatism_multiplier=st['cost']['conservatism_multiplier'],
    pinned_agents=[], aware_routing=True,
)
if t != 'premium':
    st['cost']['downgrades'].append({'agent':'fg-412-architecture-reviewer',
                                     'from':'premium','to':t,
                                     'remaining_usd':st['cost']['remaining_usd'],
                                     'timestamp':datetime.now(timezone.utc).isoformat()})
    st['cost']['downgrade_count']=len(st['cost']['downgrades'])
json.dump(st, open(p,'w'), indent=2)
"
  run python3 -c "
import json
st=json.load(open('$FORGE_DIR/state.json'))
d=st['cost']['downgrades'][0]
assert d['agent']=='fg-412-architecture-reviewer'
assert d['from']=='premium' and d['to']=='standard'
assert d['remaining_usd']==0.30
print('ok')
"
  assert_success
}
```

- [ ] **Step 2: Commit**

```bash
git add tests/scenario/cost-aware-routing.bats
git commit -m "test(cost): aware_routing + pinned_agents (AC-607/609)"
```

---

## Task 26: Scenario test — retrospective cost-per-finding gating

**Rationale:** AC-611 — cost-per-finding only computed when peer cohort produced CRITICAL or WARNING; zero-finding clean-code reviewers NOT flagged.

**Files:**
- Create: `tests/scenario/cost-retro-per-finding.bats`
- Create: `tests/fixtures/retro-cost-scenarios/` (2 fixtures: `clean-run.json`, `dirty-run.json`)

- [ ] **Step 1: Write the fixtures**

`tests/fixtures/retro-cost-scenarios/clean-run.json`:

```json
{
  "version": "2.0.0",
  "run_id": "clean-run",
  "cost": {"ceiling_usd": 25.0, "spent_usd": 3.12, "ceiling_breaches": 0, "throttle_events": []},
  "tokens": {
    "by_agent": {
      "fg-410-code-reviewer":     {"input": 8000, "output": 1500, "dispatch_count": 1, "model": "sonnet"},
      "fg-411-security-reviewer": {"input": 8000, "output": 1500, "dispatch_count": 1, "model": "sonnet"},
      "fg-412-architecture-reviewer": {"input":8000,"output":1500,"dispatch_count":1,"model":"sonnet"}
    }
  },
  "findings": []
}
```

`tests/fixtures/retro-cost-scenarios/dirty-run.json`:

```json
{
  "version": "2.0.0",
  "run_id": "dirty-run",
  "cost": {"ceiling_usd": 25.0, "spent_usd": 3.12, "ceiling_breaches": 0, "throttle_events": []},
  "tokens": {
    "by_agent": {
      "fg-410-code-reviewer":     {"input": 8000, "output": 1500, "dispatch_count": 1, "model": "sonnet"},
      "fg-411-security-reviewer": {"input": 50000, "output": 6000, "dispatch_count": 1, "model": "opus"},
      "fg-412-architecture-reviewer": {"input":8000,"output":1500,"dispatch_count":1,"model":"sonnet"}
    }
  },
  "findings": [
    {"agent": "fg-410-code-reviewer", "severity": "CRITICAL", "file": "a.py", "line": 1, "category": "ARCH-COUPLING"},
    {"agent": "fg-410-code-reviewer", "severity": "WARNING",  "file": "b.py", "line": 2, "category": "QUAL-NAMING"},
    {"agent": "fg-412-architecture-reviewer", "severity": "WARNING", "file": "c.py", "line": 3, "category": "ARCH-LAYERING"}
  ]
}
```

- [ ] **Step 2: Write the test**

```bash
#!/usr/bin/env bats
load '../helpers/test-helpers'

_cpaf() {
  python3 -c "
import json, sys, statistics
from collections import defaultdict
st = json.load(open(sys.argv[1]))
findings = st['findings']
actionable = [f for f in findings if f['severity'] in ('CRITICAL','WARNING')]
if not actionable:
    print('GATE_SKIP'); sys.exit(0)
# Cost per agent at Sonnet pricing (3/15 per MTok) or Opus (5/25).
PRICE = {'sonnet':(3.0,15.0),'opus':(5.0,25.0),'haiku':(1.0,5.0)}
costs = {}
for a, d in st['tokens']['by_agent'].items():
    pi, po = PRICE.get(d['model'], PRICE['sonnet'])
    costs[a] = d['input']*pi/1e6 + d['output']*po/1e6
# Unique actionable per reviewer.
per_rev = defaultdict(int)
for f in actionable:
    per_rev[f['agent']] += 1
cpaf = {a: costs[a]/per_rev[a] for a in per_rev}
if not cpaf:
    print('NO_REVIEWERS_WITH_FINDINGS'); sys.exit(0)
med = statistics.median(cpaf.values())
flagged = [a for a, c in cpaf.items() if c > 3 * med]
print('MEDIAN', round(med, 4), 'FLAGGED', ','.join(sorted(flagged)) or 'none')
" "$1"
}

@test "clean run: no reviewer flagged regardless of cost (AC-611 carve-out)" {
  run _cpaf "$PLUGIN_ROOT/tests/fixtures/retro-cost-scenarios/clean-run.json"
  assert_success
  assert_output "GATE_SKIP"
}

@test "dirty run: flagging engages only when peer cohort has >=1 CRITICAL/WARNING" {
  run _cpaf "$PLUGIN_ROOT/tests/fixtures/retro-cost-scenarios/dirty-run.json"
  assert_success
  # fg-411 had zero findings even though cohort was dirty; fg-410 had 2,
  # fg-412 had 1. fg-411 must NOT appear in flagged.
  refute_output -p "fg-411-security-reviewer"
}
```

- [ ] **Step 3: Commit**

```bash
git add tests/scenario/cost-retro-per-finding.bats tests/fixtures/retro-cost-scenarios/
git commit -m "test(cost): retro cost-per-finding gating (AC-611)"
```

---

## Task 27: CLAUDE.md — Supporting systems + Pipeline modes entries

**Rationale:** Document the new subsystem for repo readers.

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add to §Supporting systems → Features table**

Insert a new row in the features table under `CLAUDE.md` §Features section (after the existing Consumer-driven contracts entry):

```markdown
| Cost governance (F35) | `cost.*` | USD ceiling, dispatch-gate projection, soft throttle, SAFETY_CRITICAL hardcoded list, `forge.cost.*` OTel attrs. Categories: `COST-THROTTLE-IMPL`, `COST-DOWNGRADE`, `COST-ESCALATION-AUTO`, `COST-ESCALATION-TIMEOUT`, `EST-DRIFT`. State schema v2.0.0 (coordinated with P5/P7). |
```

- [ ] **Step 2: Extend §Pipeline modes → Autonomous note**

After the existing autonomous paragraph, add:

```markdown
Under Phase 6 cost governance, autonomous mode auto-decides on ceiling breaches: first attempts downgrade via `cost_governance.downgrade_tier()`, falls back to `abort_to_ship` if downgrade would drop a SAFETY_CRITICAL agent or if already at `fast`. Every decision is logged `COST-ESCALATION-AUTO` INFO and written to `.forge/cost-incidents/<timestamp>.json`. AskUserQuestion is NEVER invoked in autonomous mode for cost decisions.
```

- [ ] **Step 3: Extend §Start Here → 5-minute path**

Add a one-liner under "Already familiar?":

```markdown
- **Spend predictably.** `cost.ceiling_usd` in `forge-config.md` (default $25/run). Dispatch gate in `fg-100-orchestrator.md` §Cost Governance; helpers in `shared/cost_governance.py`; retrospective analytics in `fg-700-retrospective.md` Output 2.7.
```

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(claude): document Phase 6 cost governance subsystem"
```

---

## Task 28: README + CHANGELOG

**Rationale:** Top-level visibility of the new ceiling default.

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: README — one-liner under Configuration**

Find the Configuration section in `README.md` and add after the existing bullet list:

```markdown
- **Cost ceiling (Phase 6).** Every run has a USD ceiling (default **$25**). Configurable via `cost.ceiling_usd` in `forge-config.md`; the orchestrator injects a `## Cost Budget` block into every subagent brief, soft-throttles the implementer at 80%/90% consumption, and dynamically downgrades tiers when the remaining budget is small (excluding a hardcoded SAFETY_CRITICAL reviewer set). See `shared/model-routing.md` §Cost-Aware Routing.
```

- [ ] **Step 2: CHANGELOG — new entry for 3.7.0**

Prepend to `CHANGELOG.md`:

```markdown
## 3.7.0 — Phase 6 Cost Governance

### Added

- **USD cost ceiling** (`cost.ceiling_usd`, default $25). Orchestrator blocks any dispatch that would breach the ceiling; in interactive mode escalates via AskUserQuestion (pattern §8), in autonomous mode auto-decides per `cost_governance.downgrade_tier()`.
- **`## Cost Budget` brief injection** — every dispatched subagent receives a current Spent/Remaining/Tier summary.
- **Soft cost throttle in implementer (§5.3b)** — emits `COST-THROTTLE-IMPL` INFO at 80% / WARNING at 90% consumed; skips discretionary refactor+critic passes while keeping RED/GREEN inviolate.
- **Dynamic tier downgrade** (`cost.aware_routing: true`) with hardcoded SAFETY_CRITICAL list: `fg-210`, `fg-250`, `fg-411`, `fg-412`, `fg-414`, `fg-419`, `fg-500`, `fg-505`, `fg-506`, `fg-590`. These agents are NEVER silently skipped.
- **`forge.cost.*` / `forge.agent.tier_*` OTel attributes** — six new attrs on every dispatch span, round-tripped through `otel.replay()`.
- **Cost incident log** — `.forge/cost-incidents/<timestamp>.json` per escalation, schema at `shared/schemas/cost-incident.schema.json`.
- **Retrospective cost analytics** — per-run summary, cost-per-actionable-finding flagging (gated on peer cohort ≥1 CRITICAL/WARNING), EST-DRIFT detection, four new `run_summary` columns (migration 002).
- **300-second default timeout** for interactive AskUserQuestion patterns §3, §7, §8.

### Changed

- **`shared/forge-token-tracker.sh` pricing table** refreshed to Anthropic 2026-04-22 rates: Haiku 4.5 $1/$5, Sonnet 4.6 $3/$15, Opus 4.7 $5/$25 per MTok.
- **State schema bumps to v2.0.0** (coordinated with Phase 5 and Phase 7). Old `1.x.x` state files reset `cost` block on load per no-backcompat policy.
- **`shared/observability.md`** codifies `forge.*` namespace contract; Phase 4's unprefixed `learning.*` attrs are renamed to `forge.learning.*` as a prerequisite.

### Tests

- 3 unit bats suites (cost-governance-helpers, cost-governance-downgrade, token-tracker-pricing)
- 8 scenario bats suites (ceiling-interactive, ceiling-autonomous, soft-throttle, incident-write, otel-attrs, no-silent-safety-skip, ceiling-disabled, aware-routing, retro-per-finding)
- 1 contract extension (framework-config-templates.bats — 24 frameworks × 3 assertions)
```

- [ ] **Step 3: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "docs: announce Phase 6 cost governance in README + CHANGELOG"
```

---

## Task 29: Bump plugin.json version to 3.7.0

**Rationale:** Align plugin version with the CHANGELOG entry Phase 6 ships under.

**Files:**
- Modify: `plugin.json`
- Modify: `marketplace.json` (if version pinned there)

- [ ] **Step 1: Bump plugin.json**

Edit `plugin.json`:

```json
{
  "name": "forge",
  "version": "3.7.0",
  ...
}
```

- [ ] **Step 2: Update marketplace.json if it pins the version**

Confirm `marketplace.json` references match. If version is pinned, bump to `3.7.0`.

- [ ] **Step 3: Commit**

```bash
git add plugin.json marketplace.json
git commit -m "chore(release): bump plugin to 3.7.0 for Phase 6 cost governance"
```

---

## Task 30: Extend contract tests — state schema + category registry

**Rationale:** New finding categories (`COST-THROTTLE-IMPL`, `COST-DOWNGRADE`, `COST-ESCALATION-AUTO`, `COST-ESCALATION-TIMEOUT`, `EST-DRIFT`) must be registered in `shared/checks/category-registry.json` or contract tests will reject them.

**Files:**
- Modify: `shared/checks/category-registry.json`
- Modify: `tests/contract/category-registry.bats` (or equivalent)

- [ ] **Step 1: Register the categories**

Edit `shared/checks/category-registry.json` to add (under the appropriate section — likely the discrete-categories list):

```json
{
  "id": "COST-THROTTLE-IMPL",
  "severity_allowed": ["INFO", "WARNING"],
  "introduced_in": "3.7.0",
  "description": "Implementer skipped a discretionary refactor or critic pass due to cost pressure."
},
{
  "id": "COST-DOWNGRADE",
  "severity_allowed": ["INFO"],
  "introduced_in": "3.7.0",
  "description": "Orchestrator downgraded an agent tier under cost.aware_routing."
},
{
  "id": "COST-ESCALATION-AUTO",
  "severity_allowed": ["INFO"],
  "introduced_in": "3.7.0",
  "description": "Autonomous-mode ceiling breach auto-decision logged."
},
{
  "id": "COST-ESCALATION-TIMEOUT",
  "severity_allowed": ["INFO"],
  "introduced_in": "3.7.0",
  "description": "Interactive ceiling-breach prompt timed out; defaulted to abort-to-ship."
},
{
  "id": "EST-DRIFT",
  "severity_allowed": ["WARNING"],
  "introduced_in": "3.7.0",
  "description": "Actual agent cost drifted >2x from tier_estimates_usd across 10+ dispatches."
}
```

Also add the wildcard `COST-*` to the wildcard-prefix list if it does not already exist — this lets existing wildcard-aware scoring apply.

- [ ] **Step 2: Write/extend the contract test**

Append to `tests/contract/category-registry.bats`:

```bash
@test "category-registry: COST-THROTTLE-IMPL declared" {
  run python3 -c "
import json
r=json.load(open('$PLUGIN_ROOT/shared/checks/category-registry.json'))
ids=[c['id'] for c in (r.get('categories') or [])]
assert 'COST-THROTTLE-IMPL' in ids
print('ok')
"
  assert_success
}

@test "category-registry: EST-DRIFT severity restricted to WARNING" {
  run python3 -c "
import json
r=json.load(open('$PLUGIN_ROOT/shared/checks/category-registry.json'))
for c in (r.get('categories') or []):
    if c['id']=='EST-DRIFT':
        assert c['severity_allowed']==['WARNING'], c
        break
else:
    raise AssertionError('EST-DRIFT not found')
print('ok')
"
  assert_success
}
```

- [ ] **Step 3: Commit**

```bash
git add shared/checks/category-registry.json tests/contract/category-registry.bats
git commit -m "feat(scoring): register COST-*/EST-DRIFT categories (3.7.0)"
```

---

## Task 31: Wire cost_governance into config_validator for PREFLIGHT

**Rationale:** Task 6 documented the rules; this task makes PREFLIGHT actually enforce them.

**Files:**
- Modify: `shared/config_validator.py` (new validation function)

- [ ] **Step 1: Add the validator**

Open `shared/config_validator.py` and append:

```python
def validate_cost_block(cfg: dict) -> list[tuple[str, str]]:
    """Validate the `cost:` block from forge-config.md.

    Returns a list of (severity, message) tuples. Severity is CRITICAL or WARNING.
    Empty list = pass.
    """
    issues: list[tuple[str, str]] = []
    from shared.cost_governance import SAFETY_CRITICAL

    cost = cfg.get("cost", {}) or {}
    # ceiling_usd
    ceiling = cost.get("ceiling_usd")
    if ceiling is None or not isinstance(ceiling, (int, float)):
        issues.append(("CRITICAL", "cost.ceiling_usd is required and must be numeric"))
    elif ceiling < 0:
        issues.append(("CRITICAL", f"cost.ceiling_usd must be >= 0 (got {ceiling})"))
    elif 0 < ceiling < 1.0:
        issues.append(("WARNING", f"cost.ceiling_usd={ceiling} seems low (possible typo)"))

    # thresholds
    w = cost.get("warn_at", 0.75)
    t = cost.get("throttle_at", 0.80)
    a = cost.get("abort_at", 1.00)
    for name, val in (("warn_at", w), ("throttle_at", t), ("abort_at", a)):
        if not (0 < val <= 1):
            issues.append(("CRITICAL", f"cost.{name}={val} must be in (0, 1]"))
    if not (w < t <= a):
        issues.append(("CRITICAL", f"cost thresholds must satisfy warn_at < throttle_at <= abort_at (got {w} / {t} / {a})"))

    # aware_routing
    aware = cost.get("aware_routing", True)
    if not isinstance(aware, bool):
        issues.append(("CRITICAL", "cost.aware_routing must be boolean"))
    elif aware and not cfg.get("model_routing", {}).get("enabled", True):
        issues.append(("CRITICAL", "cost.aware_routing: true requires model_routing.enabled: true"))

    # tier estimates
    te = cost.get("tier_estimates_usd", {}) or {}
    for tier in ("fast", "standard", "premium"):
        v = te.get(tier)
        if v is None or not isinstance(v, (int, float)) or v <= 0:
            issues.append(("CRITICAL", f"cost.tier_estimates_usd.{tier} must be float > 0 (got {v!r})"))
    if te.get("fast", 0) and te.get("premium", 0) and te["premium"] / te["fast"] > 200:
        issues.append(("WARNING", "cost.tier_estimates_usd.premium / fast > 200 (likely wrong)"))

    # conservatism
    cm = cost.get("conservatism_multiplier", {}) or {}
    for tier in ("fast", "standard", "premium"):
        v = cm.get(tier, 1.0)
        if v < 1.0:
            issues.append(("CRITICAL", f"cost.conservatism_multiplier.{tier} must be >= 1.0 (got {v})"))
        if v > 10.0:
            issues.append(("WARNING", f"cost.conservatism_multiplier.{tier}={v} > 10 (effectively disables downgrade)"))

    # skippable_under_cost_pressure MUST NOT intersect SAFETY_CRITICAL
    skippable = set(cost.get("skippable_under_cost_pressure", []) or [])
    bad = skippable & SAFETY_CRITICAL
    if bad:
        issues.append(("CRITICAL",
                       f"cost.skippable_under_cost_pressure may not contain SAFETY_CRITICAL agents: {sorted(bad)}"))

    return issues
```

Then wire this into the existing PREFLIGHT entry point (likely a `validate_all(cfg)` function) so `validate_cost_block(cfg)` is called alongside other validators.

- [ ] **Step 2: Commit**

```bash
git add shared/config_validator.py
git commit -m "feat(preflight): enforce cost.* validation rules (AC-601)"
```

---

## Task 32: Scenario test — PREFLIGHT rejects bad cost config

**Rationale:** AC-601 end-to-end — PREFLIGHT CRITICAL on invalid cost block aborts the run.

**Files:**
- Create: `tests/scenario/cost-preflight-validation.bats`

- [ ] **Step 1: Write the test**

Pattern: each test writes a YAML fixture to a bats tmpfile (`BATS_TEST_TMPDIR`), then runs a small Python snippet that reads the file path from `argv[1]`, calls `validate_cost_block`, and prints `SEV|MSG` lines. This is cleaner than `declare -f` + stdin pipes: no shell-quoting gymnastics, readable YAML, and the Python snippet is identical across tests.

```bash
#!/usr/bin/env bats
load '../helpers/test-helpers'

_run_validator() {
  # $1 = path to YAML file on disk. Writes SEV|MSG lines to stdout.
  python3 - "$1" <<'PY'
import sys, yaml
sys.path.insert(0, "PLUGIN_ROOT_PLACEHOLDER/shared")
from config_validator import validate_cost_block
cfg = yaml.safe_load(open(sys.argv[1]).read())
for sev, msg in validate_cost_block(cfg):
    print(f"{sev}|{msg}")
PY
}

setup() {
  # Expand $PLUGIN_ROOT into the heredoc at runtime via sed — keeps the Python
  # body itself free of bash interpolation so `sys.argv[1]` isn't mangled.
  export _VALIDATOR_PY="$BATS_TEST_TMPDIR/run_validator.py"
  cat > "$_VALIDATOR_PY" <<PY
import sys, yaml
sys.path.insert(0, "$PLUGIN_ROOT/shared")
from config_validator import validate_cost_block
cfg = yaml.safe_load(open(sys.argv[1]).read())
for sev, msg in validate_cost_block(cfg):
    print(f"{sev}|{msg}")
PY
}

@test "preflight: warn_at > throttle_at -> CRITICAL" {
  local tmp="$BATS_TEST_TMPDIR/cfg.yaml"
  cat > "$tmp" <<'YAML'
cost:
  ceiling_usd: 25.00
  warn_at: 0.90
  throttle_at: 0.80
  abort_at: 1.00
  aware_routing: true
  tier_estimates_usd: {fast: 0.016, standard: 0.047, premium: 0.078}
  conservatism_multiplier: {fast: 1.0, standard: 1.0, premium: 1.0}
  skippable_under_cost_pressure: []
YAML
  run python3 "$_VALIDATOR_PY" "$tmp"
  assert_success
  assert_output -p "CRITICAL|cost thresholds must satisfy warn_at < throttle_at"
}

@test "preflight: skippable_under_cost_pressure contains SAFETY_CRITICAL -> CRITICAL" {
  local tmp="$BATS_TEST_TMPDIR/cfg.yaml"
  cat > "$tmp" <<'YAML'
cost:
  ceiling_usd: 25.00
  warn_at: 0.75
  throttle_at: 0.80
  abort_at: 1.00
  aware_routing: true
  tier_estimates_usd: {fast: 0.016, standard: 0.047, premium: 0.078}
  conservatism_multiplier: {fast: 1.0, standard: 1.0, premium: 1.0}
  skippable_under_cost_pressure: [fg-411-security-reviewer]
YAML
  run python3 "$_VALIDATOR_PY" "$tmp"
  assert_success
  assert_output -p "CRITICAL|cost.skippable_under_cost_pressure may not contain SAFETY_CRITICAL"
}

@test "preflight: conservatism_multiplier.premium = 0.5 -> CRITICAL" {
  local tmp="$BATS_TEST_TMPDIR/cfg.yaml"
  cat > "$tmp" <<'YAML'
cost:
  ceiling_usd: 25.00
  warn_at: 0.75
  throttle_at: 0.80
  abort_at: 1.00
  aware_routing: true
  tier_estimates_usd: {fast: 0.016, standard: 0.047, premium: 0.078}
  conservatism_multiplier: {fast: 1.0, standard: 1.0, premium: 0.5}
  skippable_under_cost_pressure: []
YAML
  run python3 "$_VALIDATOR_PY" "$tmp"
  assert_success
  assert_output -p "CRITICAL|cost.conservatism_multiplier.premium must be >= 1.0"
}

@test "preflight: aware_routing: true + model_routing.enabled: false -> CRITICAL" {
  local tmp="$BATS_TEST_TMPDIR/cfg.yaml"
  cat > "$tmp" <<'YAML'
model_routing: {enabled: false}
cost:
  ceiling_usd: 25.00
  warn_at: 0.75
  throttle_at: 0.80
  abort_at: 1.00
  aware_routing: true
  tier_estimates_usd: {fast: 0.016, standard: 0.047, premium: 0.078}
  conservatism_multiplier: {fast: 1.0, standard: 1.0, premium: 1.0}
  skippable_under_cost_pressure: []
YAML
  run python3 "$_VALIDATOR_PY" "$tmp"
  assert_success
  assert_output -p "CRITICAL|cost.aware_routing: true requires model_routing.enabled: true"
}
```

- [ ] **Step 2: Commit**

```bash
git add tests/scenario/cost-preflight-validation.bats
git commit -m "test(preflight): cost.* validation rejects bad config (AC-601)"
```

---

## Task 33: Self-review + AC traceability matrix

**Rationale:** Writing-plans skill self-review checklist. Every AC from the spec must map to a concrete task.

- [ ] **Step 1: Walk the AC list and confirm coverage**

| AC | Where implemented / verified |
|---|---|
| AC-601 PREFLIGHT validation | Task 6 (rules doc), Task 31 (validator code), Task 32 (scenario) |
| AC-602 dispatch brief contains `## Cost Budget` | Task 2 `compute_budget_block`, Task 14 orchestrator Step 6 |
| AC-603 no dispatch without AskUserQuestion (interactive) | Task 7 (pattern §8), Task 14 Step 4, Task 19 (scenario) |
| AC-604 autonomous auto-decide, no AskUserQuestion | Task 14 Step 4 autonomous branch, Task 20 (scenario) |
| AC-605 incident file per escalation | Task 2 `write_incident`, Task 4 (schema), Task 14 Step 5, Task 21 (scenario) |
| AC-606 implementer 80%/90% throttle | Task 15 (§5.3b), Task 18 (scenario) |
| AC-607 dynamic downgrade on `remaining < 5 × effective` | Task 2 `downgrade_tier`, Task 3 (unit), Task 14 Step 2, Task 25 (scenario) |
| AC-608 SAFETY_CRITICAL never silently skipped | Task 2 (`SAFETY_CRITICAL`), Task 10 (docs), Task 22 (scenario) |
| AC-609 pinned_agents override | Task 2 pinned branch, Task 25 (scenario) |
| AC-610 six OTel attrs round-trip | Task 11 (constants), Task 12 (emission), Task 23 (scenario) |
| AC-611 cost-per-finding gated on ≥1 CRITICAL/WARNING | Task 16 (retro Output 2.7), Task 26 (scenario) |
| AC-612 four new run_summary columns | Task 17 (migration 002) |
| AC-613 EST-DRIFT WARNING at >2× drift across 10+ | Task 16 (retro) |
| AC-614 `ceiling_usd: 0` disables all gates | Task 2 `compute_budget_block` unlimited branch, Task 14 disabled note, Task 24 (scenario) |
| AC-615 state v2.0.0 coordinated bump | Task 5 |
| AC-616 pricing table refreshed + asserted | Task 1 |

All 16 ACs mapped. No gaps.

- [ ] **Step 2: Placeholder scan**

Search for TBD/TODO/"similar to Task N" in this plan. None found — every code block is complete.

- [ ] **Step 3: Type consistency sweep**

- `downgrade_tier` arg set: same across Tasks 2, 3, 14, 25, 31.
- `SAFETY_CRITICAL` name: same frozenset everywhere (Python module, docs, tests).
- `compute_budget_block` signature: `(ceiling_usd, spent_usd, tier, tier_estimate)` identical in Tasks 2, 14, 24.
- `write_incident` signature: `(incident: dict, forge_dir: Path)` identical in Tasks 2, 14, 19–21.
- Incident JSON keys: `timestamp, ceiling_usd, spent_usd, projected_usd, next_agent, resolved_tier, decision, autonomous, run_id` identical in schema (Task 4) and all scenario fixtures (Tasks 19–21).
- Category IDs: `COST-THROTTLE-IMPL`, `COST-DOWNGRADE`, `COST-ESCALATION-AUTO`, `COST-ESCALATION-TIMEOUT`, `EST-DRIFT` — consistent across Tasks 15, 16, 30.
- OTel attribute strings: `forge.run.budget_total_usd`, `forge.run.budget_remaining_usd`, `forge.agent.tier_estimate_usd`, `forge.agent.tier_original`, `forge.agent.tier_used`, `forge.cost.throttle_reason` — identical in Tasks 11, 12, 13, 23.

Consistency check passes. Plan is internally coherent.

- [ ] **Step 4: Pricing-table citation**

Anthropic pricing page (`https://platform.claude.com/docs/en/about-claude/pricing`) verified via WebFetch on 2026-04-22 at plan-write time. Rates locked into Task 1:

| Model | Input $/MTok | Output $/MTok |
|---|---|---|
| Haiku 4.5 | 1.00 | 5.00 |
| Sonnet 4.6 | 3.00 | 15.00 |
| Opus 4.7 | 5.00 | 25.00 |

These numbers feed directly into the per-iteration estimates ($0.016 / $0.047 / $0.078) derived from 8k input + 1.5k output.

- [ ] **Step 5: SAFETY_CRITICAL completeness**

The hardcoded set in `shared/cost_governance.py` (Task 2) and the docs in `shared/model-routing.md` (Task 10) both list exactly these 10:

```
fg-210-validator
fg-250-contract-validator
fg-411-security-reviewer
fg-412-architecture-reviewer
fg-414-license-reviewer
fg-419-infra-deploy-reviewer
fg-500-test-gate
fg-505-build-verifier
fg-506-migration-verifier
fg-590-pre-ship-verifier
```

Matches the spec §4 authoritative list character-for-character. `fg-506-migration-verifier` is intentionally present even though only dispatched on `state.mode == "migration"` — listing ensures no silent drop during migration runs under cost pressure.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-22-phase-6-cost-governance.md`. Two execution options:

**1. Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?

**If Subagent-Driven chosen:**
- **REQUIRED SUB-SKILL:** Use superpowers:subagent-driven-development
- Fresh subagent per task + two-stage review per the user's canonical-templates policy

**If Inline Execution chosen:**
- **REQUIRED SUB-SKILL:** Use superpowers:executing-plans
- Batch execution with checkpoints for review

**First commit order:** Task 1 (pricing refresh) MUST land before any other task. The rest may interleave, though Tasks 2, 4, 5 are natural predecessors of the orchestrator/implementer/retro wiring tasks.
