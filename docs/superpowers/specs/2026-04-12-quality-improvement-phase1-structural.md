# Phase 1: Structural Fixes

**Parent:** [Umbrella Spec](./2026-04-12-quality-improvement-umbrella-design.md)
**Priority:** Highest — largest grade impact per effort.
**Approach:** Test-gated. Write failing BATS tests first, then apply fixes.

## Item 1.1: Remove `ui:` blocks from 12 Tier 4 agents

**Rationale:** CLAUDE.md defines Tier 4 as "(none)" for UI capabilities. The `ui: {ask: false, tasks: false, plan_mode: false}` blocks add 4 lines per agent (48 lines total) of system prompt tokens with zero information — the agent's capabilities are already determined by its `tools:` list. Token efficiency is explicitly valued per CLAUDE.md: "Agent `.md` = subagent system prompt (every line = tokens)."

**Category:** Optimization (not a structural violation — current state is functional).

**Affected agents (12):**
- fg-210-validator
- fg-101-worktree-manager
- fg-102-conflict-resolver
- fg-410-code-reviewer
- fg-411-security-reviewer
- fg-412-architecture-reviewer
- fg-413-frontend-reviewer
- fg-416-backend-performance-reviewer
- fg-417-version-compat-reviewer
- fg-418-docs-consistency-reviewer
- fg-419-infra-deploy-reviewer
- fg-420-dependency-reviewer

**Change per agent:** Delete these 4 lines from YAML frontmatter:
```yaml
ui:
  ask: false
  tasks: false
  plan_mode: false
```

**Existing test impact:** `ui-frontmatter-consistency.bats` only checks `true` values against tools lists. Removing all-false blocks does not affect any existing test.

**New test:** `tests/contract/tier4-no-ui-block.bats`
- Defines Tier 4 agents list (sourced from agent filenames matching the 12 above)
- For each Tier 4 agent, extracts YAML frontmatter and asserts no `ui:` key is present
- Test must FAIL before fix is applied, PASS after

## Item 1.2: Fix marketplace.json version mismatch

**Rationale:** `plugin.json` declares version `1.13.0` but `.claude-plugin/marketplace.json` declares `1.12.0`. This causes distribution inconsistency — the marketplace shows the wrong version.

**Category:** Bug fix.

**Change:** In `.claude-plugin/marketplace.json`, change:
```json
"version": "1.12.0"
```
to:
```json
"version": "1.13.0"
```

**New test:** `tests/contract/version-sync.bats`
- Extracts version from `plugin.json` using jq
- Extracts version from `.claude-plugin/marketplace.json` using jq
- Asserts they are equal
- Test must FAIL before fix, PASS after

## Item 1.3: Expand Tier 1 agent descriptions (fg-160, fg-200)

**Rationale:** CLAUDE.md specifies "Tier 1 (entry, 6): description + example." Four of six Tier 1 agents (fg-010, fg-015, fg-050, fg-090) already have `<example>` blocks. Two do not: fg-160-migration-planner (15 words, no example) and fg-200-planner (17 words, no example).

**Category:** Spec compliance.

**Change for fg-160-migration-planner:** Expand description to include example block matching existing Tier 1 format (see fg-010-shaper for reference):
```yaml
description: |
  Plans and orchestrates multi-phase library migrations and major upgrades with per-batch rollback.

  <example>
  Context: Developer wants to upgrade a major framework version
  user: "migrate: Spring Boot 2.7 to 3.2"
  assistant: "I'll dispatch the migration planner to analyze the upgrade path, identify breaking changes, and create a phased migration plan with rollback points."
  </example>
```

**Change for fg-200-planner:** Expand description to include example block:
```yaml
description: |
  Decomposes a requirement into a risk-assessed implementation plan with stories, tasks, and parallel groups.

  <example>
  Context: Developer wants to implement a new feature
  user: "Implement plan comment feature"
  assistant: "I'll dispatch the planner to decompose this into stories, assess risk per task, and identify which tasks can run in parallel."
  </example>
```

**New test:** `tests/contract/tier1-description-examples.bats`
- Defines Tier 1 agents list: fg-010, fg-015, fg-050, fg-090, fg-160, fg-200
- For each, extracts description from YAML frontmatter
- Asserts description contains `<example>` substring
- Test must FAIL for fg-160/fg-200 before fix, PASS after

## Phase 1 Verification Checklist

- [ ] 3 new BATS tests written and failing (red)
- [ ] 12 agent `ui:` blocks removed
- [ ] marketplace.json version updated
- [ ] fg-160 and fg-200 descriptions expanded
- [ ] 3 new BATS tests passing (green)
- [ ] All existing tests passing (`./tests/run-all.sh`)
- [ ] `/requesting-code-review` passes
