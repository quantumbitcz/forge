# Phase 5: Agent & Learning Enhancements

**Status:** Approved  
**Date:** 2026-04-15  
**Depends on:** Phase 3 (v1.6.0 schema migration adds `critic_revisions` field), Phase 4 (circuit breaker flapping logic documented)  
**Unlocks:** Phase 6  
**Schema note:** All new state fields (`critic_revisions`) are added in Phase 3's single v1.5.0→v1.6.0 migration. No additional schema version bump needed.

## Problem

1. **No pre-execution plan review:** The pipeline goes directly from PLANNING to VALIDATING. Google Jules' Planning Critic reduces task failure by 9.5%. Forge has no equivalent — bad plans waste implementation cycles.

2. **Agent behavioral test depth:** While all 41 agents have test references, `tests/unit/agent-behavior/untested-agents.bats` flags 10 agents with only structural checks (frontmatter/naming), not behavioral assertions about their actual dispatch contracts or output formats.

3. **PREEMPT decay is context-blind:** A Spring-specific PREEMPT rule decays during React projects because "unused" counts are global, not framework-scoped. This causes valuable rules to archive prematurely.

4. **No cross-project learning:** Learnings are per-project only. If you learn something about Spring patterns in Project A, Project B starts from zero.

## Solution

### 1. Create Planning Critic Agent (`fg-205-planning-critic`)

**File:** `agents/fg-205-planning-critic.md`

```yaml
---
name: fg-205-planning-critic
description: Reviews implementation plans for feasibility, risk gaps, and scope issues before validation
tools: [Read, Grep, Glob]
---
```

**Role:** Independent review of the plan produced by `fg-200-planner`, BEFORE the plan enters `fg-210-validator`. The critic focuses on different concerns than the validator:

| Concern | Critic (fg-205) | Validator (fg-210) |
|---------|-----------------|-------------------|
| **Feasibility** | Can this plan actually be implemented with the available tools and codebase? | Is the plan complete and well-structured? |
| **Risk blind spots** | What could go wrong that the plan doesn't address? | Are risks formally assessed? |
| **Scope creep** | Is the plan doing more than the requirement asks? | Does the plan match the requirement? |
| **Codebase fit** | Does the plan conflict with existing patterns? | Does the plan follow conventions? |
| **Challenge brief** | Is the challenge brief honest about difficulty? | Is the challenge brief present? |

**Output format:**
```markdown
## Planning Critic Review

**Verdict:** PROCEED | REVISE | RESHAPE

### Findings (if REVISE or RESHAPE)
1. [FEASIBILITY] Description of concern
2. [RISK] Description of missing risk mitigation
3. [SCOPE] Description of scope issue

### Recommendation
Specific guidance on what to fix before re-planning.
```

**Dispatch integration:**
- Orchestrator dispatches `fg-205-planning-critic` after `fg-200-planner` completes
- If verdict is `PROCEED`: orchestrator proceeds to VALIDATING stage normally
- If verdict is `REVISE`: orchestrator sends plan back to `fg-200-planner` with critic feedback as context. Increments `critic_revisions` counter (per-story, resets when story_state leaves PLANNING). Max 2 critic-driven revisions before proceeding to validator regardless. Does NOT increment `total_retries` (critic revisions are pre-validation, not convergence retries).
- If verdict is `RESHAPE`: orchestrator escalates to user with critic's findings. User can approve plan anyway, revise requirement, or abort.

**Note:** Critic verdicts (`PROCEED`/`REVISE`/`RESHAPE`) are distinct from validator verdicts (`GO`/`REVISE`/`NOGO`) and convergence events (`score_improving`/`score_plateau`/`score_regressing`). They occupy different stages and don't interact.

**State integration:**
- Add `critic_revisions` counter to state.json (resets per planning cycle)
- Track in `stage_timestamps.critic_review`

### 2. Enhance agent behavioral tests

For the 10 agents flagged in `untested-agents.bats`, add meaningful test files:

| Agent | Test File | Key Assertions |
|-------|-----------|----------------|
| `fg-101-worktree-manager` | `tests/unit/agent-behavior/worktree-manager.bats` | Branch naming pattern matches `{type}/{ticket}-{slug}`, worktree path is `.forge/worktree`, collision detection with epoch suffix |
| `fg-102-conflict-resolver` | `tests/unit/agent-behavior/conflict-resolver.bats` | Parallel groups output format, serial chains have ordering, file-level conflict detection for shared files |
| `fg-103-cross-repo-coordinator` | `tests/unit/agent-behavior/cross-repo-coordinator.bats` | Lock ordering is alphabetical, timeout default is 30min, PR linking format |
| `fg-140-deprecation-refresh` | `tests/unit/agent-behavior/deprecation-refresh.bats` | known-deprecations.json v2 schema validated, Context7 MCP graceful skip when unavailable |
| `fg-150-test-bootstrapper` | `tests/unit/agent-behavior/test-bootstrapper.bats` | Prioritizes recently changed files, generates in batches, respects coverage threshold |
| `fg-160-migration-planner` | `tests/unit/agent-behavior/migration-planner.bats` | Migration phases output format, rollback points identified, breaking changes listed |
| `fg-250-contract-validator` | `tests/unit/agent-behavior/contract-validator.bats` | Detects breaking changes in OpenAPI/Protobuf, consumer notification format |
| `fg-610-infra-deploy-verifier` | `tests/unit/agent-behavior/infra-deploy-verifier.bats` | Tier selection (T1-T5) based on config, INFRA-* finding categories used |
| `fg-620-deploy-verifier` | `tests/unit/agent-behavior/deploy-verifier.bats` | Canary/blue-green/rolling strategy detection, health check format |
| `fg-650-preview-validator` | `tests/unit/agent-behavior/preview-validator.bats` | Lighthouse audit format, FAIL blocks Stage 8, fix loop cap respected |

Each test file should have 5-8 assertions covering:
- Frontmatter `name` matches filename
- Frontmatter `tools` list is valid (no tools outside Claude Code's tool set)
- Agent `.md` contains its expected sections (documented in `shared/agent-philosophy.md`)
- Output format matches agent-io-contracts (where documented)
- Key behavioral rules from the agent's body are present (grep for specific patterns)

Also add `fg-205-planning-critic` tests after creating the agent.

### 3. Context-aware PREEMPT decay

**File:** `shared/convergence-engine.md` — PREEMPT section

Add `applicable_context` field to PREEMPT items:

```json
{
  "rule": "Always check for N+1 queries in Spring repositories",
  "source": "retrospective",
  "confidence": "HIGH",
  "unused_count": 0,
  "applicable_context": {
    "framework": "spring",
    "language": ["kotlin", "java"]
  }
}
```

**Decay logic change:**

```
Before (context-blind):
  On each pipeline run where rule is not applied:
    unused_count += 1

After (context-aware):
  On each pipeline run:
    if applicable_context is empty OR current project matches applicable_context:
      if rule was not applied:
        unused_count += 1
    # else: skip — rule wasn't relevant to this project
```

**Context matching:**
- `framework` field: match against `components.*.framework` in forge-config
- `language` field: match against `components.*.language` in forge-config
- If multiple components exist (monorepo), match if ANY component matches (e.g., a Spring rule is applicable during a Spring+React monorepo run)
- Missing `applicable_context` (legacy items created before v1.6.0): decay normally on every run (backward compatible)

**Document in convergence-engine.md:**
```markdown
### Context-Aware PREEMPT Decay

PREEMPT items with `applicable_context` only decay when the current project's tech stack matches. A Spring-specific rule won't decay during React projects.

Context matching uses the `components` section from `forge.local.md`. If any component matches the rule's framework or language, the rule is considered applicable for that run.

Items without `applicable_context` (created before v1.6.0) decay on every run (legacy behavior).
```

### 4. Cross-project learnings

**New file:** `shared/cross-project-learnings.md`

**Storage location:** `~/.claude/forge-learnings/`

**Structure:**
```
~/.claude/forge-learnings/
├── spring.md        # Spring-specific learnings
├── react.md         # React-specific learnings
├── typescript.md    # Language-specific learnings
├── general.md       # Framework-agnostic learnings
└── _index.json      # Metadata: last update timestamps, entry counts
```

**Write path (fg-700-retrospective):**
1. After writing per-project learnings to `shared/learnings/{framework}.md`
2. Also append validated HIGH-confidence learnings to `~/.claude/forge-learnings/{framework}.md`
3. Deduplicate: if a learning with the same core pattern already exists in the cross-project file, update rather than append
4. Tag each learning with project name and date for provenance

**Read path (fg-100-orchestrator at PREFLIGHT):**
1. Detect project's framework(s) from `forge.local.md`
2. If `~/.claude/forge-learnings/{framework}.md` exists, load it
3. Also load `~/.claude/forge-learnings/general.md` if it exists
4. Inject as additional PREEMPT items with `source: cross-project` and initial confidence `MEDIUM` (not HIGH — needs validation in new project context)
5. Cross-project items that prove useful promote to HIGH after 2 successful applications — "successful" means the rule was applied (matched and used by an agent) AND the pipeline run reached at least REVIEWING stage without the rule being flagged as a false positive. Faster promotion than auto-discovered items (which start at MEDIUM and need 3)

**Opt-out:** Add `cross_project_learnings.enabled: false` to `forge-config.md` to disable. Default: `true`.

**Privacy:** Cross-project files contain generic patterns, not project-specific code or secrets. Example: "Spring @Transactional should be on use case implementations, not repository methods" — no file paths, no business logic.

## Files Changed

| File | Action |
|------|--------|
| `agents/fg-205-planning-critic.md` | **Create** — new planning critic agent |
| `agents/fg-100-orchestrator.md` | **Modify** — add critic dispatch between PLANNING and VALIDATING |
| `shared/agent-registry.md` | **Modify** — add fg-205 entry |
| `shared/convergence-engine.md` | **Modify** — add context-aware PREEMPT decay section |
| `shared/cross-project-learnings.md` | **Create** — cross-project learning system design |
| `shared/state-schema.md` | **Modify** — add `critic_revisions` field |
| 10+ test files in `tests/unit/agent-behavior/` | **Create** — behavioral tests for untested agents |
| `tests/lib/module-lists.bash` | **Modify** — bump MIN_UNIT_TESTS count |

## Testing

- All existing agent tests must pass
- New tests per agent (see table above): ~60 new assertions total
- New tests for planning critic:
  - `tests/unit/agent-behavior/planning-critic.bats`: Verify frontmatter, output format, verdict values
  - `tests/contract/planning-critic-dispatch.bats`: Verify orchestrator integrates critic between PLANNING and VALIDATING
- New tests for context-aware decay:
  - `tests/unit/preempt-context-decay.bats`: Spring rule doesn't decay during React run, rule without context decays normally
- New tests for cross-project learnings:
  - `tests/unit/cross-project-learnings.bats`: Verify file structure, dedup logic, confidence levels
- Bump `MIN_UNIT_TESTS` in `module-lists.bash` to account for new test files

## Risks

- **Planning critic adds latency:** One additional agent dispatch per planning cycle. Mitigation: critic is read-only (Read, Grep, Glob only), runs fast. Max 2 revisions before proceeding.
- **Cross-project learning contamination:** A bad learning from Project A could degrade Project B. Mitigation: cross-project items start at MEDIUM confidence and must prove themselves (2 successful applications to promote). Items that cause issues are demoted normally.
- **Cross-project file location:** `~/.claude/forge-learnings/` is outside the project directory. If the user's home directory is read-only or on a network mount, writes fail silently. Mitigation: wrap in try/catch at PREFLIGHT; skip if unavailable.

## Success Criteria

1. Planning critic agent exists and is dispatched between PLANNING and VALIDATING
2. All 41 agents have meaningful behavioral tests (not just structural)
3. PREEMPT decay is context-aware — framework-specific rules don't decay during unrelated projects
4. Cross-project learnings flow from retrospective to future PREFLIGHTs
5. `validate-plugin.sh` passes with new agent
