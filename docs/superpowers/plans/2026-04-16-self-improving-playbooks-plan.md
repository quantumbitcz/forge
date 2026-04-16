# Self-Improving Playbooks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the retrospective agent to analyze playbook runs and emit evidence-backed refinement proposals that push playbooks toward consistently producing near-perfect code. Add a new skill for interactive review and optional auto-apply at PREFLIGHT.

**Architecture:** Refinement analysis in `fg-700-retrospective` writes to `playbook_runs.refinement_suggestions` (run-history.db) and aggregates to `.forge/playbook-refinements/{playbook_id}.json`. New `forge-playbook-refine` skill for manual review. Optional auto-apply by orchestrator at PREFLIGHT. Rollback on regression.

**Tech Stack:** Markdown (agent/skill definitions), JSON Schema, bash (bats tests)

**Spec:** `docs/superpowers/specs/2026-04-16-self-improving-playbooks-design.md`
**Depends on:** Run History Store plan (needs `playbook_runs` table AND `state-schema.md` updates from Task 3 which adds `playbook-refinements/` entry), MCP Server plan (exposes analytics)

**Note:** Plan 1 (Run History Store) Task 3 already adds `playbook-refinements/` to `state-schema.md`. Plan 2 (MCP Server) already modified CLAUDE.md. When modifying shared files (CLAUDE.md, state-schema.md), add entries after those from preceding plans.

---

## File Map

| Action | File | Purpose |
|--------|------|---------|
| Create | `shared/schemas/playbook-refinement-schema.json` | JSON Schema for refinement proposals |
| Modify | `agents/fg-700-retrospective.md` | Add playbook refinement extraction step |
| Modify | `shared/playbooks.md` | Add "Self-Improvement" section |
| Create | `skills/forge-playbook-refine/SKILL.md` | New skill: interactive refinement review |
| Modify | `shared/preflight-constraints.md` | Add auto-refine config validation |
| Modify | `agents/fg-100-orchestrator.md` | Add auto-refine at PREFLIGHT |
| Create | `tests/contract/playbook-refinement.bats` | Contract tests |
| Modify | `CLAUDE.md` | Add skill, config, feature entry |

---

### Task 1: Create Refinement Proposal Schema

**Files:**
- Create: `shared/schemas/playbook-refinement-schema.json`

- [ ] **Step 1: Write the JSON Schema**

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "Playbook Refinement Proposals",
  "description": "Evidence-backed proposals for improving a playbook based on pipeline run outcomes.",
  "type": "object",
  "required": ["playbook_id", "playbook_version", "generated_at", "based_on_runs", "run_ids", "proposals"],
  "properties": {
    "playbook_id": {
      "type": "string",
      "description": "Playbook identifier (matches filename sans .md)"
    },
    "playbook_version": {
      "type": "string",
      "description": "Playbook version at time of analysis"
    },
    "generated_at": {
      "type": "string",
      "format": "date-time",
      "description": "ISO 8601 timestamp of generation"
    },
    "based_on_runs": {
      "type": "integer",
      "minimum": 3,
      "description": "Number of runs analyzed"
    },
    "run_ids": {
      "type": "array",
      "items": { "type": "string" },
      "description": "Run IDs that contributed to this analysis"
    },
    "proposals": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["id", "type", "description", "target", "evidence", "confidence", "agreement"],
        "properties": {
          "id": {
            "type": "string",
            "pattern": "^.+-REF-\\d{3}$",
            "description": "Unique proposal ID: {playbook_id}-REF-NNN"
          },
          "type": {
            "type": "string",
            "enum": ["scoring_gap", "stage_focus", "acceptance_gap", "parameter_default"],
            "description": "Refinement category"
          },
          "description": {
            "type": "string",
            "description": "Human-readable proposal summary"
          },
          "target": {
            "type": "string",
            "description": "Playbook field being modified (e.g., acceptance_criteria, stages_focus)"
          },
          "current_value": {
            "description": "Current value of the target field (null if new)"
          },
          "proposed_value": {
            "description": "Proposed new value"
          },
          "evidence": {
            "type": "string",
            "description": "Data backing the proposal (run counts, finding categories, scores)"
          },
          "confidence": {
            "type": "string",
            "enum": ["HIGH", "MEDIUM"],
            "description": "HIGH if agreement >= 90%, MEDIUM if >= 66%"
          },
          "agreement": {
            "type": "string",
            "pattern": "^\\d+/\\d+$",
            "description": "Fraction of runs supporting this proposal (e.g., 4/5)"
          },
          "impact_estimate": {
            "type": "string",
            "description": "Expected score impact description"
          },
          "status": {
            "type": "string",
            "enum": ["ready", "applied", "rejected", "deferred", "rolled_back"],
            "default": "ready"
          },
          "rollback_count": {
            "type": "integer",
            "default": 0,
            "description": "Times this proposal was rolled back. 2+ = permanently rejected."
          }
        }
      }
    }
  }
}
```

- [ ] **Step 2: Validate the schema is valid JSON**

```bash
python3 -c "import json; json.load(open('shared/schemas/playbook-refinement-schema.json')); print('OK')"
```

Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add shared/schemas/playbook-refinement-schema.json
git commit -m "feat(playbooks): add refinement proposal JSON schema"
```

---

### Task 2: Update Retrospective Agent

**Files:**
- Modify: `agents/fg-700-retrospective.md`

- [ ] **Step 1: Add playbook refinement extraction step**

After the run history write step (Output 2.5, added in the Run History Store plan), add:

```markdown
### Output 2.6: Playbook Refinement Analysis

When `state.json.playbook_id` is set, analyze run outcomes against playbook expectations and generate refinement proposals. Schema: `shared/schemas/playbook-refinement-schema.json`.

**Per-run analysis:**
1. Load playbook definition (project `.claude/forge-playbooks/` first, fall back to `shared/playbooks/`)
2. Compute refinement suggestions across 4 categories:
   - **Scoring gap:** If score < pass_threshold, identify top finding categories causing deductions. For each unaddressed category, propose an acceptance criterion that prevents recurrence. NEVER propose lowering thresholds.
   - **Stage focus:** Compare stage timing distribution vs `stages_focus`. If a non-focused stage takes >25% wall time, propose adding it. If a focused stage takes <2% across 3+ runs, propose removing (never VERIFYING/REVIEWING/SHIPPING).
   - **Acceptance gaps:** Cross-reference finding categories with acceptance criteria text. Unmatched categories with 2+ occurrences → propose new criterion. Criteria with 0 relevant findings across 3+ runs → flag as potential noise.
   - **Parameter defaults:** Compare parameter values used vs defaults. Same value in >=80% of runs → propose as new default.
3. Write suggestions to `playbook_runs.refinement_suggestions` in run-history.db (JSON array)

**Aggregation (3+ runs of same playbook):**
4. Query all `refinement_suggestions` for this playbook from `playbook_runs` table
5. Group by (type, target). Count agreement across runs.
6. Proposals with agreement >= `playbooks.refine_agreement` (default 0.66):
   - Set confidence: HIGH if agreement >= 0.90, MEDIUM if >= 0.66
   - Mark status: `ready`
7. Write ready proposals to `.forge/playbook-refinements/{playbook_id}.json`
8. Log to forge-log.md: `[REFINE] {playbook_id}: {N} proposals ready ({types})`
9. Skip aggregation if <3 runs exist — log: `"Insufficient data for {playbook_id} refinement ({N}/3 runs)."`

**Guard rails:**
- Never propose lowering `pass_threshold` or `concerns_threshold`
- Never propose `scoring.category_overrides` to suppress findings
- Never propose removing VERIFYING, REVIEWING, or SHIPPING stages
- Proposals with `rollback_count >= max_rollbacks_before_reject` are permanently marked `rejected`

**Config:** `playbooks.refine_min_runs` (default 3), `playbooks.refine_agreement` (default 0.66).
```

- [ ] **Step 2: Commit**

```bash
git add agents/fg-700-retrospective.md
git commit -m "feat(retrospective): add playbook refinement analysis step"
```

---

### Task 3: Update Playbooks Documentation

**Files:**
- Modify: `shared/playbooks.md`

- [ ] **Step 1: Add Self-Improvement section**

At the end of `shared/playbooks.md`, before any appendix or reference section, add:

```markdown
## Self-Improvement

Playbooks improve over time based on pipeline run outcomes. The retrospective agent (`fg-700`) analyzes each playbook run and generates refinement proposals.

### How It Works

1. After each run using a playbook, the retrospective computes refinement suggestions
2. Suggestions accumulate in `run-history.db` (`playbook_runs.refinement_suggestions`)
3. When 3+ runs of the same playbook exist, suggestions are aggregated
4. Proposals with sufficient agreement (default 66%) become `ready`
5. Ready proposals are written to `.forge/playbook-refinements/{playbook_id}.json`

### Refinement Categories

| Category | What It Detects | What It Proposes |
|----------|----------------|------------------|
| Scoring gap | Runs consistently below `pass_threshold` | Acceptance criteria addressing top deduction categories |
| Stage focus | Non-focused stages consuming >25% wall time | Adding stage to `stages_focus` |
| Acceptance gap | Finding categories not covered by criteria | New acceptance criterion |
| Parameter default | Same parameter value in 80%+ of runs | Updated default value |

### Philosophy

**Make the code meet the bar, never move the bar to meet the code.**

Refinements always push quality up — adding preventive criteria, fixing blind spots, improving focus. They never lower thresholds, suppress findings, or remove safety stages.

### Applying Refinements

**Manual (default):** Review and apply via `/forge-playbook-refine [playbook_id]`

**Auto-apply (opt-in):** Set `playbooks.auto_refine: true` in `forge-config.md`. Only HIGH confidence proposals are auto-applied (max 2 per run). Changes are logged with `[AUTO-REFINE]` marker.

**Rollback:** If a refined playbook's next run scores >10 points below the pre-refinement average, changes are automatically reverted and logged with `[REFINE-ROLLBACK]`.

### File Locations

- Proposals: `.forge/playbook-refinements/{playbook_id}.json` (survives `/forge-reset`)
- Schema: `shared/schemas/playbook-refinement-schema.json`
- Analytics: `.forge/playbook-analytics.json` (version history for rollback)

### Configuration

```yaml
playbooks:
  auto_refine: false              # Auto-apply HIGH confidence refinements
  refine_min_runs: 3              # Minimum runs before proposing
  refine_agreement: 0.66          # Agreement threshold (0.5-1.0)
  max_auto_refines_per_run: 2     # Cap on automatic changes
  rollback_threshold: 10          # Score regression triggering rollback
  max_rollbacks_before_reject: 2  # Permanent rejection after N rollbacks
```

### Auto-Apply File Rules

Auto-apply only modifies project-level playbooks in `.claude/forge-playbooks/`. If a built-in playbook (in `shared/playbooks/`) has refinement proposals, auto-apply first copies it to `.claude/forge-playbooks/` (creating a project override), then applies refinements to the project copy. The plugin directory is never modified.
```

- [ ] **Step 2: Commit**

```bash
git add shared/playbooks.md
git commit -m "docs(playbooks): add self-improvement section"
```

---

### Task 4: Create forge-playbook-refine Skill

**Files:**
- Create: `skills/forge-playbook-refine/SKILL.md`

- [ ] **Step 1: Write the skill**

```markdown
---
name: forge-playbook-refine
description: "Review and apply playbook refinement proposals. Use when playbooks have accumulated run data and proposals are ready for review. Trigger: /forge-playbook-refine [playbook_id]"
allowed-tools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'AskUserQuestion']
ui: { ask: true }
---

# /forge-playbook-refine — Interactive Playbook Refinement

Review and apply improvement proposals generated from pipeline run data. Proposals are evidence-backed suggestions for making playbooks produce better code.

## Prerequisites

1. **Forge initialized:** `.claude/forge.local.md` exists
2. **Run history exists:** `.forge/run-history.db` exists
3. **Proposals available:** `.forge/playbook-refinements/` has at least one file

If prerequisites fail, STOP with guidance:
- No run history → "Run the pipeline first to generate data."
- No proposals → "No refinement proposals yet. Run playbooks 3+ times to generate proposals."

## Arguments

`$ARGUMENTS` = optional playbook_id. If omitted, list playbooks with pending proposals.

## Flow

### No playbook_id provided

1. List all `.forge/playbook-refinements/*.json` files
2. For each, show: playbook_id, proposal count, confidence distribution
3. Ask user to select one

### Playbook selected

1. Read `.forge/playbook-refinements/{playbook_id}.json`
2. Filter to `status: ready` proposals only
3. If no ready proposals: "All proposals for {playbook_id} have been processed."
4. For each ready proposal, present via AskUserQuestion:

```
## Proposal: {id}
**Type:** {type}
**Target:** {target}
**Confidence:** {confidence} ({agreement})

**Current:** {current_value}
**Proposed:** {proposed_value}

**Evidence:** {evidence}
**Expected Impact:** {impact_estimate}
```

Options:
- **Accept** — Apply this refinement to the playbook
- **Reject** — Dismiss this proposal permanently
- **Modify** — Accept with changes (ask for modified value)
- **Defer** — Skip for now, revisit later

### Applying accepted proposals

1. Locate playbook file:
   - Project: `.claude/forge-playbooks/{playbook_id}.md`
   - Built-in: `shared/playbooks/{playbook_id}.md`
   - If built-in, copy to `.claude/forge-playbooks/` first (project override)
2. Edit the playbook frontmatter/body per proposal type:
   - `scoring_gap` / `acceptance_gap` → append to `acceptance_criteria:` list
   - `stage_focus` → modify `stages.focus` array
   - `parameter_default` → modify `parameters[].default`
3. Increment `version` in playbook frontmatter
4. Update `.forge/playbook-refinements/{playbook_id}.json`:
   - Set accepted proposals to `status: applied`
   - Set rejected proposals to `status: rejected`
   - Set deferred proposals to `status: deferred`
5. Log to `forge-log.md`: `[REFINE-APPLIED] {playbook_id} v{old}→v{new}: {proposal_ids}`

## Guard Rails

- Respect `<!-- locked -->` fences in playbook files — skip proposals targeting locked sections
- Never modify `pass_threshold`, `concerns_threshold`, or scoring weights
- Never remove VERIFYING, REVIEWING, or SHIPPING from stages

## Error Handling

- Playbook file not found → STOP: "Playbook {id} not found in project or built-in playbooks."
- Locked section targeted → skip proposal, inform user: "Proposal {id} targets a locked section. Skipped."
- Write fails → STOP with error, do not update refinement file status
```

- [ ] **Step 2: Commit**

```bash
git add skills/forge-playbook-refine/
git commit -m "feat(skills): add forge-playbook-refine interactive refinement skill"
```

---

### Task 5: Add PREFLIGHT Auto-Refine and Config Validation

**Files:**
- Modify: `shared/preflight-constraints.md`
- Modify: `agents/fg-100-orchestrator.md`

- [ ] **Step 1: Add auto-refine config validation to preflight-constraints.md**

Add a new section:

```markdown
### Playbook Self-Improvement

| Field | Type | Default | Valid Range | Validation |
|-------|------|---------|-------------|------------|
| `playbooks.auto_refine` | boolean | `false` | true/false | — |
| `playbooks.refine_min_runs` | integer | `3` | 2-20 | WARN if >10 (slow feedback loop) |
| `playbooks.refine_agreement` | float | `0.66` | 0.5-1.0 | WARN if <0.5 (low evidence bar) |
| `playbooks.max_auto_refines_per_run` | integer | `2` | 1-5 | — |
| `playbooks.rollback_threshold` | integer | `10` | 5-30 | — |
| `playbooks.max_rollbacks_before_reject` | integer | `2` | 1-5 | — |

**Cross-field:** If `auto_refine: true`, `refine_agreement` must be >= 0.66 (prevent low-confidence auto-changes).
```

- [ ] **Step 2: Add auto-refine step to orchestrator PREFLIGHT**

In `agents/fg-100-orchestrator.md`, in the PREFLIGHT stage section, add after existing PREFLIGHT steps:

```markdown
### Playbook Auto-Refine (PREFLIGHT)

When `playbooks.auto_refine: true` AND a playbook is being used for this run:

1. Check `.forge/playbook-refinements/{playbook_id}.json` for `ready` proposals
2. Filter to `confidence: HIGH` only
3. Apply max `playbooks.max_auto_refines_per_run` proposals:
   a. If playbook is built-in (in `shared/playbooks/`), copy to `.claude/forge-playbooks/` first
   b. Modify playbook frontmatter/body per proposal type
   c. Respect `<!-- locked -->` fences — skip proposals targeting locked sections
   d. Increment version in frontmatter
   e. Update proposal status to `applied` in refinement file
   f. Store pre-refinement playbook version in `state.json.playbook_pre_refine_version` (for rollback)
4. Log `[AUTO-REFINE] {playbook_id}: applied {N} proposals ({ids})`

### Playbook Rollback Detection (LEARN — in fg-700)

After a run that used an auto-refined playbook:
1. Compare score with average of last 3 pre-refinement runs (from `run-history.db`)
2. If score dropped by > `playbooks.rollback_threshold` points:
   a. Revert playbook to pre-refinement version (from `playbook-analytics.json.version_history`)
   b. Increment `rollback_count` on the applied proposals
   c. If `rollback_count >= max_rollbacks_before_reject`, set status to `rejected`
   d. Log `[REFINE-ROLLBACK] {playbook_id}: reverted {proposal_ids}, reason: score dropped {delta} points`
```

- [ ] **Step 3: Commit**

```bash
git add shared/preflight-constraints.md agents/fg-100-orchestrator.md
git commit -m "feat(orchestrator): add playbook auto-refine at PREFLIGHT with rollback"
```

---

### Task 6: Write Contract Tests

**Files:**
- Create: `tests/contract/playbook-refinement.bats`

- [ ] **Step 1: Write the test file**

```bash
#!/usr/bin/env bats
# Contract tests: self-improving playbooks system.

load '../helpers/test-helpers'

SCHEMA="$PLUGIN_ROOT/shared/schemas/playbook-refinement-schema.json"
PLAYBOOKS_DOC="$PLUGIN_ROOT/shared/playbooks.md"
RETROSPECTIVE="$PLUGIN_ROOT/agents/fg-700-retrospective.md"
ORCHESTRATOR="$PLUGIN_ROOT/agents/fg-100-orchestrator.md"
SKILL="$PLUGIN_ROOT/skills/forge-playbook-refine/SKILL.md"
PREFLIGHT="$PLUGIN_ROOT/shared/preflight-constraints.md"
STATE_SCHEMA="$PLUGIN_ROOT/shared/state-schema.md"

# ---------------------------------------------------------------------------
# 1. Schema exists and is valid JSON
# ---------------------------------------------------------------------------
@test "playbook-refinement: schema file exists" {
  [[ -f "$SCHEMA" ]]
}

@test "playbook-refinement: schema is valid JSON" {
  python3 -c "import json; json.load(open('$SCHEMA'))" 2>/dev/null \
    || fail "Schema is not valid JSON"
}

# ---------------------------------------------------------------------------
# 2. Schema defines required fields
# ---------------------------------------------------------------------------
@test "playbook-refinement: schema requires playbook_id" {
  grep -q '"playbook_id"' "$SCHEMA" \
    || fail "Schema missing playbook_id field"
}

@test "playbook-refinement: schema defines 4 refinement types" {
  grep -q '"scoring_gap"' "$SCHEMA" || fail "Missing scoring_gap type"
  grep -q '"stage_focus"' "$SCHEMA" || fail "Missing stage_focus type"
  grep -q '"acceptance_gap"' "$SCHEMA" || fail "Missing acceptance_gap type"
  grep -q '"parameter_default"' "$SCHEMA" || fail "Missing parameter_default type"
}

@test "playbook-refinement: schema defines proposal status values" {
  grep -q '"ready"' "$SCHEMA" || fail "Missing ready status"
  grep -q '"applied"' "$SCHEMA" || fail "Missing applied status"
  grep -q '"rejected"' "$SCHEMA" || fail "Missing rejected status"
  grep -q '"rolled_back"' "$SCHEMA" || fail "Missing rolled_back status"
}

# ---------------------------------------------------------------------------
# 3. Skill exists with correct frontmatter
# ---------------------------------------------------------------------------
@test "playbook-refinement: skill file exists" {
  [[ -f "$SKILL" ]]
}

@test "playbook-refinement: skill has name in frontmatter" {
  grep -q "name: forge-playbook-refine" "$SKILL" \
    || fail "Skill missing name frontmatter"
}

@test "playbook-refinement: skill has AskUserQuestion in allowed-tools" {
  grep -q "AskUserQuestion" "$SKILL" \
    || fail "Skill missing AskUserQuestion in allowed-tools"
}

# ---------------------------------------------------------------------------
# 4. Integration: retrospective references refinement
# ---------------------------------------------------------------------------
@test "playbook-refinement: retrospective agent references playbook refinement" {
  grep -qi "playbook.*refine\|refinement" "$RETROSPECTIVE" \
    || fail "fg-700-retrospective.md does not reference playbook refinement"
}

# ---------------------------------------------------------------------------
# 5. Integration: playbooks.md includes self-improvement section
# ---------------------------------------------------------------------------
@test "playbook-refinement: playbooks.md includes Self-Improvement section" {
  grep -q "Self-Improvement" "$PLAYBOOKS_DOC" \
    || fail "shared/playbooks.md missing Self-Improvement section"
}

# ---------------------------------------------------------------------------
# 6. Integration: orchestrator references auto-refine
# ---------------------------------------------------------------------------
@test "playbook-refinement: orchestrator references auto-refine" {
  grep -qi "auto.refine\|auto_refine" "$ORCHESTRATOR" \
    || fail "fg-100-orchestrator.md does not reference auto-refine"
}

# ---------------------------------------------------------------------------
# 7. Integration: preflight-constraints includes playbook refinement config
# ---------------------------------------------------------------------------
@test "playbook-refinement: preflight-constraints includes refine config" {
  grep -q "auto_refine" "$PREFLIGHT" \
    || fail "preflight-constraints.md missing auto_refine validation"
}

# ---------------------------------------------------------------------------
# 8. Integration: state-schema documents playbook-refinements directory
# ---------------------------------------------------------------------------
@test "playbook-refinement: state-schema documents playbook-refinements" {
  grep -q "playbook-refinements" "$STATE_SCHEMA" \
    || fail "state-schema.md missing playbook-refinements directory"
}

# ---------------------------------------------------------------------------
# 9. Guard rails: no threshold lowering in retrospective
# ---------------------------------------------------------------------------
@test "playbook-refinement: retrospective forbids lowering thresholds" {
  grep -qi "never.*lower.*threshold\|never.*pass_threshold" "$RETROSPECTIVE" \
    || fail "Retrospective does not explicitly forbid lowering thresholds"
}
```

- [ ] **Step 2: Verify tests pass**

```bash
./tests/lib/bats-core/bin/bats tests/contract/playbook-refinement.bats
```

- [ ] **Step 3: Commit**

```bash
git add tests/contract/playbook-refinement.bats
git commit -m "test(playbooks): add contract tests for self-improving playbooks"
```

---

### Task 7: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add to skill selection guide**

Add row to the skill selection guide table:

```
| Review playbook refinements | `/forge-playbook-refine` | Interactive review/apply of improvement proposals |
```

- [ ] **Step 2: Update skills count**

Change "40 total" to "41 total" in the Skills section header, and add `forge-playbook-refine` to the skill list.

- [ ] **Step 3: Add to v2.0 features table**

```
| Self-improving playbooks (F31) | `playbooks.*` | Refinement proposals from run data. Auto-apply, rollback. `.forge/playbook-refinements/` |
```

- [ ] **Step 4: Add playbook-refinements to survival list**

In the Gotchas > Structural section, add `playbook-refinements/` to the list of files surviving `/forge-reset`.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(claude-md): add self-improving playbooks feature and forge-playbook-refine skill"
```
