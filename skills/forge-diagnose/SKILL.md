---
name: forge-diagnose
description: "Diagnose why a pipeline run is stuck, broken, or behaving unexpectedly. Read-only health check of state.json integrity, recovery budget, convergence status, and stalled stages. Use when the pipeline seems stuck, a run failed with unclear errors, or before resuming. Trigger: /forge-diagnose, pipeline stuck, why did the run fail, what went wrong"
allowed-tools: ['Read', 'Bash', 'Glob', 'Grep']
---

# /forge-diagnose — Pipeline Health Diagnostic

You are a read-only diagnostic tool. Your job is to inspect the current pipeline state and report problems without changing anything. You never modify files, dispatch agents, or trigger recovery.

## Prerequisites

Before any action, verify:

1. **Git repository:** Run `git rev-parse --show-toplevel 2>/dev/null`. If fails: report "Not a git repository. Navigate to a project directory." and STOP.
2. **State file exists:** Check `.forge/state.json` exists. If not: report "No pipeline state found. Nothing to diagnose. Run `/forge-run` to start a pipeline." and STOP.

## Instructions

### 1. Gather State

1. Check if `.forge/state.json` exists.
   - If not: report "No pipeline state found. Nothing to diagnose. Run `/forge-run` to start a pipeline." and stop.
2. Read `.forge/state.json` and parse the full JSON.
3. Read `.claude/forge.local.md` (if it exists) for config reference.
4. Read `.claude/forge-config.md` (if it exists) for runtime parameter reference.

### 2. State Integrity Checks

Run these checks against `state.json` and report each as PASS or PROBLEM:

**Schema version:**
- PASS if `version` matches `"1.5.0"` (current schema version from `shared/state-schema.md`).
- PROBLEM if missing or mismatched: "State schema version {found} does not match expected 1.5.0. May indicate stale state from an older plugin version."

**Required fields:**
- Check these fields exist and are non-null: `story_id`, `requirement`, `story_state`, `mode`, `complete`.
- PROBLEM for each missing field: "Required field `{field}` is missing or null."

**Story state validity:**
- PASS if `story_state` is one of: `PREFLIGHT`, `EXPLORING`, `PLANNING`, `VALIDATING`, `IMPLEMENTING`, `VERIFYING`, `REVIEWING`, `DOCUMENTING`, `SHIPPING`, `LEARNING`, `COMPLETE`, `ABORTED`, `ESCALATED`, `DECOMPOSED`, `MIGRATING`, `MIGRATION_PAUSED`, `MIGRATION_CLEANUP`, `MIGRATION_VERIFY`.
- PROBLEM if not: "Invalid story_state: `{value}`. Not a recognized pipeline state."

**Mode validity:**
- PASS if `mode` is one of: `standard`, `bugfix`, `migration`, `bootstrap`, `testing`, `refactor`, `performance`.
- PROBLEM if not: "Invalid mode: `{value}`. Not a recognized pipeline mode."

**Sequence counter:**
- PASS if `_seq` is a positive integer.
- PROBLEM if missing, zero, or non-numeric: "`_seq` counter is invalid ({value}). State writes may not be functioning."

**Completion consistency:**
- PROBLEM if `complete: true` but `story_state` is not `COMPLETE` and `abort_reason` is empty: "State marked complete but story_state is `{story_state}` with no abort reason."
- PROBLEM if `complete: false` and `story_state` is `COMPLETE`: "Story state is COMPLETE but `complete` flag is false."

### 3. Counter Sanity Checks

Check iteration counters against configured maximums (from `forge-config.md` or defaults):

**Total retries:**
- Read `total_retries` and `total_retries_max` (default 10).
- PROBLEM if `total_retries > total_retries_max`: "Total retries ({total_retries}) exceeds maximum ({total_retries_max}). Pipeline should have escalated."
- WARNING if `total_retries >= total_retries_max * 0.8`: "Total retries at {pct}% of budget."

**Recovery budget:**
- Read `recovery_budget.total_weight` and `recovery_budget.max_weight` (default 5.5).
- PROBLEM if `total_weight > max_weight`: "Recovery budget ({total_weight}) exceeds ceiling ({max_weight})."
- WARNING if `total_weight >= max_weight * 0.8`: "Recovery budget at {pct}% of ceiling."

**Convergence counters:**
- Read `convergence.total_iterations` and compare against `max_iterations` from `forge-config.md` (default 8).
- PROBLEM if `total_iterations > max_iterations`: "Total iterations ({total_iterations}) exceeds max ({max_iterations}). Pipeline should have stopped."
- Read `convergence.safety_gate_failures`. PROBLEM if >= 2 and `convergence.safety_gate_passed` is false: "Safety gate failed {n} times without passing. Cross-phase oscillation likely."
- Read `convergence.plateau_count` and `plateau_patience` (default 2). WARNING if `plateau_count >= plateau_patience`: "Plateau patience exhausted ({plateau_count} >= {plateau_patience})."

### 4. Stalled Stage Detection

Detect whether the pipeline appears stuck:

1. Read `stage_timestamps` from state.json.
2. Identify the most recent timestamp.
3. If the most recent timestamp is more than 30 minutes old and `complete` is false:
   - PROBLEM: "Pipeline appears stalled. Last stage activity was at {timestamp} ({minutes_ago} minutes ago) in stage {stage}."
4. If `.forge/.lock` exists:
   - Read PID from lock file (if present).
   - Check if PID is still running: `kill -0 $pid 2>/dev/null`
   - If not running: WARNING: "Lock file exists but PID {pid} is not running. Lock is stale."
   - If running: INFO: "Lock file held by active PID {pid}."

### 5. Score Trend Analysis

If `score_history` has 2+ entries:
1. Report the trend: "Score history: {scores}"
2. Detect oscillation: if scores alternate up/down for 3+ consecutive entries, WARNING: "Score oscillation detected: {pattern}. May indicate conflicting review findings."
3. Detect regression: if the last score is lower than the first by more than `oscillation_tolerance` (default 5), WARNING: "Overall score regression from {first} to {last}."
4. Detect plateau: if last 3+ scores differ by <= `plateau_threshold` (default 2), INFO: "Score plateaued around {avg}."

### 6. Integration Status

Report which integrations are available vs configured:
- Read `integrations` from state.json.
- For each integration (linear, playwright, slack, figma, context7, neo4j): report "available" or "unavailable".
- If `integrations.linear.available` is true but `linear.epic_id` is empty: WARNING: "Linear available but no epic linked."
- If `integrations.neo4j.available` is true but `integrations.neo4j.node_count` is 0: WARNING: "Neo4j available but graph is empty."

### 7. Evidence Status

Check `.forge/evidence.json` if it exists:
- Read `evidence.timestamp` and `evidence.verdict`.
- If `verdict` is `"SHIP"`: report "Evidence: SHIP (generated {timestamp})"
- If `verdict` is `"BLOCK"`: report "Evidence: BLOCKED — reasons: {block_reasons}"
- Compute evidence age: `now - evidence.timestamp`. If age > 30 minutes (default `evidence_max_age_minutes`): WARNING: "Evidence is stale ({age} minutes old). Pipeline will re-verify before shipping."
- If file does not exist and `story_state` is `SHIPPING`: WARNING: "In SHIPPING state but no evidence.json found."

### 8. Report

Present results in this format:

```
## Pipeline Diagnostic Report

**State file:** .forge/state.json
**Story:** {story_id}
**Stage:** {story_state}
**Mode:** {mode}
**Complete:** {complete}

### Integrity Checks
- {check_name}: PASS / PROBLEM: {detail}
- ...

### Counter Health
- Total retries: {n}/{max} {status}
- Recovery budget: {weight}/{max_weight} {status}
- Convergence iterations: {n}/{max} {status}
- Plateau count: {n}/{patience}
- Safety gate failures: {n}

### Stalled Stage Detection
- Last activity: {timestamp} ({minutes_ago} minutes ago)
- Lock file: {status}

### Score Trend
- History: {scores}
- Trend: {assessment}

### Integrations
| Integration | Status |
|-------------|--------|
| Linear      | {status} |
| Playwright  | {status} |
| Slack       | {status} |
| Figma       | {status} |
| Context7    | {status} |
| Neo4j       | {status} |

### Summary
- {total_problems} problems, {total_warnings} warnings, {total_info} informational
- Recommendation: {recommendation}
```

**Recommendations:**
- 0 problems: "Pipeline state looks healthy."
- Problems with stale lock: "Run `/forge-reset` to clear stale state, or `/forge-repair-state` to fix specific issues."
- Problems with counter overflows: "State counters are inconsistent. Run `/forge-repair-state` to attempt automatic correction."
- Problems with invalid state: "State is corrupted. Run `/forge-reset` to start fresh (preserves learnings)."

## Important

- NEVER modify any files. This is read-only.
- NEVER dispatch agents or trigger recovery.
- NEVER attempt to fix problems. Report them and recommend the appropriate skill.
- If state.json is unparseable JSON, report "state.json is not valid JSON" and recommend `/forge-reset`.

## Error Handling

| Condition | Action |
|-----------|--------|
| state.json missing | Report "No pipeline state found. Nothing to diagnose. Run `/forge-run` to start a pipeline." and STOP |
| state.json unparseable JSON | Report "state.json is not valid JSON. Run `/forge-reset` to start fresh." and STOP |
| forge-config.md missing | Use default values for all parameter checks. Note in report that config file is absent |
| Lock file PID check fails | Report lock file status as "unknown" and note the check could not be performed |

## See Also

- `/forge-repair-state` -- Fix specific state.json issues found by this diagnostic
- `/forge-resume` -- Resume an aborted pipeline after confirming health with diagnose
- `/forge-reset` -- Clear all state when diagnose shows corruption beyond repair
- `/forge-status` -- Quick overview of pipeline state (less detailed than diagnose)
- `/forge-profile` -- Performance analysis of pipeline execution (complementary to health diagnostic)
