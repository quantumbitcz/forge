# Q01: Skill Quality Overhaul

## Status
DRAFT — 2026-04-13

## Problem Statement

Skills scored B (78/100) in the system review — the weakest dimension in the entire plugin. Root causes:

1. **Weak trigger descriptions:** 15/32 skills lack a "Use when..." clause, making Claude Code unreliable at auto-triggering the correct skill.
2. **Missing Prerequisites:** 15/32 skills have no `## Prerequisites` section — they start executing and fail mid-way when config files or state are missing.
3. **Missing Error Handling:** 20/32 skills have no `## Error Handling` section — failures produce cryptic output or silent hangs.
4. **Inconsistent YAML quoting:** 19 descriptions are quoted, 12 are unquoted, 1 uses pipe (`|`). This inconsistency risks YAML parsing edge cases.
5. **Inconsistent section headers:** 8/32 skills use `## What to do` instead of the canonical `## Instructions`.
6. **Thin launcher skills:** 4 skills (bootstrap-project, forge-shape, forge-profile, forge-history) have minimal content — some under 25 lines of instructions.
7. **No cross-referencing:** Skills operate in isolation. A user running `/forge-diagnose` is not pointed toward `/repair-state` or `/forge-resume`.

Bottom-scoring skills: `/bootstrap-project` (1.6), `/forge-history` (1.6), `/forge-profile` (1.6), `/forge-shape` (1.6).
Top-scoring skills: `/deep-health` (5.0), `/forge-diagnose` (4.6), `/forge-run` (4.4), `/forge-insights` (4.2).

## Target

Skills B (78) --> A+ (95+)

## Detailed Changes

### 1. Canonical Skill Template

Every skill MUST follow this structure. This is the reference template for all 32 skills:

```markdown
---
name: <skill-name>
description: "<One sentence summary>. Use when <specific trigger scenario 1>, <trigger scenario 2>, or <trigger scenario 3>."
allowed-tools: [<tool-list>]  # Optional — only if restricting tools
---

# /<skill-name> — <Human-Readable Title>

## Prerequisites

Before any action, verify:

1. **Git repository:** Run `git rev-parse --show-toplevel 2>/dev/null`. If fails: report "Not a git repository. Navigate to a project directory." and STOP.
2. **Forge initialized:** Check `.claude/forge.local.md` exists. If not: report "Forge not initialized. Run /forge-init first." and STOP.
3. [Additional prerequisites specific to this skill]

## Instructions

[Main body — what the skill does, step by step]

## Error Handling

| Condition | Action |
|-----------|--------|
| Prerequisites fail | Report specific error message and STOP |
| Agent dispatch fails | [Skill-specific recovery] |
| State corruption | Run /repair-state, then retry or STOP |
| [Skill-specific errors] | [Skill-specific handling] |

## See Also

- `/related-skill-1` — One-line description of when to use it instead
- `/related-skill-2` — One-line description of relationship
```

### 2. Description Trigger Clause Standard

Every `description:` field MUST contain a "Use when" clause. Format:

```yaml
description: "<Summary sentence>. Use when <scenario 1>, <scenario 2>, or <scenario 3>."
```

All descriptions MUST use double-quoted YAML strings. No unquoted, no pipe (`|`), no folded (`>`).

### 3. Skill-by-Skill Remediation Plan

#### Pipeline Execution Skills

| Skill | Score | Issues | Required Changes |
|-------|-------|--------|-----------------|
| `forge-run` | 4.4 | Description good but unquoted YAML | Quote description, verify Error Handling section completeness |
| `forge-fix` | 3.8 | Thin launcher, missing Error Handling | Add Error Handling table, add See Also (forge-run, forge-diagnose), expand launcher with source resolution validation |
| `forge-shape` | 1.6 | Thin launcher (8 lines of instructions), no Prerequisites, no Error Handling, no See Also | Expand with: Prerequisites, input validation (empty input handling), Error Handling (shaper dispatch failure), See Also (forge-run, forge-sprint) |
| `forge-sprint` | 3.6 | Pipe-style description, missing Error Handling | Convert description to quoted string with "Use when", add Error Handling, add See Also |
| `bootstrap-project` | 1.6 | Thinnest skill (9 lines of instructions), no Prerequisites, no Error Handling, no See Also | Expand with: Prerequisites (verify empty/near-empty project), input validation, Error Handling (bootstrapper failure), See Also (forge-init, forge-run) |
| `migration` | 3.2 | "## Usage" instead of "## Instructions", no Prerequisites, no Error Handling | Rename header, add Prerequisites, add Error Handling, add See Also |

#### Pipeline Management Skills

| Skill | Score | Issues | Required Changes |
|-------|-------|--------|-----------------|
| `forge-status` | 3.0 | Uses "## What to do", no Prerequisites, no Error Handling | Rename to "## Instructions", add Prerequisites, add Error Handling, add See Also (forge-history, forge-diagnose) |
| `forge-history` | 1.6 | Uses "## What to do", no Prerequisites, no Error Handling, thin content | Rename header, add Prerequisites, expand with trend analysis instructions, add Error Handling, add See Also (forge-status, forge-insights) |
| `forge-resume` | 3.8 | Missing Error Handling section, description unquoted | Add Error Handling, quote description, add See Also |
| `forge-abort` | 3.6 | Missing Error Handling section | Add Error Handling (state write failure, lock file issues), add See Also (forge-resume, forge-reset) |
| `forge-reset` | 2.8 | Uses "## What to do", no Prerequisites, no Error Handling | Full template rewrite: add Prerequisites, rename header, add Error Handling, add See Also (forge-abort, forge-resume) |
| `forge-rollback` | 3.0 | Uses "## What to do", no Prerequisites | Rename header, add Prerequisites, add Error Handling, add See Also (forge-reset, forge-abort) |

#### Quality & Review Skills

| Skill | Score | Issues | Required Changes |
|-------|-------|--------|-----------------|
| `forge-review` | 4.0 | Missing Error Handling section | Add Error Handling (no changed files, agent failure, score stagnation), add See Also |
| `codebase-health` | 3.6 | Uses "## What to do" (second occurrence after Prerequisites), missing Error Handling | Remove duplicate header, add Error Handling, add See Also (deep-health, forge-review) |
| `deep-health` | 5.0 | Reference skill — highest score | Add See Also section only |
| `verify` | 3.2 | Uses "## What to do", missing Error Handling, description unquoted | Rename header, add Error Handling, add See Also (forge-review, codebase-health) |
| `security-audit` | 3.0 | Uses "## What to do", minimal Prerequisites, missing Error Handling | Rename header, expand Prerequisites, add Error Handling, add See Also |

#### Configuration & Diagnostics Skills

| Skill | Score | Issues | Required Changes |
|-------|-------|--------|-----------------|
| `forge-init` | 3.8 | Missing Error Handling section, description missing "Use when" | Add "Use when" trigger, add Error Handling, add See Also |
| `config-validate` | 3.6 | Missing Error Handling, description unquoted | Add Error Handling, quote description, add See Also (forge-init, forge-diagnose) |
| `forge-diagnose` | 4.6 | Missing See Also | Add See Also (repair-state, forge-resume, forge-status) |
| `repair-state` | 4.0 | Missing Error Handling | Add Error Handling (unparseable JSON, WAL missing), add See Also |
| `forge-profile` | 1.6 | No title header, no Prerequisites beyond inline checks, no Error Handling, no See Also, thin content | Full template rewrite: add title, expand analysis instructions (bottleneck identification, recommendations), add Error Handling, add See Also (forge-insights, forge-history) |

#### Documentation & Deployment Skills

| Skill | Score | Issues | Required Changes |
|-------|-------|--------|-----------------|
| `docs-generate` | 4.0 | Missing Prerequisites, missing Error Handling | Add Prerequisites, add Error Handling, add See Also |
| `deploy` | 3.4 | Missing Prerequisites, missing Error Handling | Add Prerequisites (verify deploy config exists), add Error Handling (deploy failure, rollback), add See Also (forge-rollback) |

#### Graph Skills

| Skill | Score | Issues | Required Changes |
|-------|-------|--------|-----------------|
| `graph-init` | 3.6 | Missing Error Handling | Add Error Handling (Docker not available, container start failure, import failure), add See Also |
| `graph-status` | 3.4 | Missing Error Handling | Add Error Handling, add See Also (graph-debug, graph-rebuild) |
| `graph-query` | 3.6 | Missing Error Handling | Add Error Handling (invalid Cypher, connection failure), add See Also |
| `graph-rebuild` | 3.2 | Missing Error Handling | Add Error Handling, add See Also (graph-status, graph-debug) |
| `graph-debug` | 3.8 | Missing Error Handling | Add Error Handling, add See Also (graph-status, graph-rebuild) |

#### Automation & Analytics Skills

| Skill | Score | Issues | Required Changes |
|-------|-------|--------|-----------------|
| `forge-automation` | 3.4 | Missing Error Handling | Add Error Handling, add See Also |
| `forge-insights` | 4.2 | Missing Error Handling | Add Error Handling, add See Also (forge-history, forge-profile) |
| `forge-ask` | 3.8 | Missing Error Handling | Add Error Handling (no data sources available, empty results), add See Also |

### 4. Thin Launcher Skill Policy

The 4 thin launcher skills (`bootstrap-project`, `forge-shape`, `forge-fix`, `forge-history`) MUST be expanded:

**Option A (recommended): Expand with validation and context.** Even launcher skills should validate inputs, provide helpful error messages, and document their relationship to the target agent. Minimum content: Prerequisites, input validation, dispatch, Error Handling, See Also. Target: 40+ lines of instructions.

**Option B: Mark as launcher explicitly.** Add a `type: launcher` frontmatter field and a standardized launcher disclaimer. Launchers still require Prerequisites and Error Handling but can have shorter Instructions. This requires a new test to validate launcher skills have the `type: launcher` field.

Recommendation: Option A. The cost of a few extra lines per skill is negligible, and it ensures every skill provides a good user experience even before the target agent runs.

### 5. Skill Groups for Cross-Referencing

Define canonical skill groups. Every skill's `## See Also` MUST reference at least one skill from its group:

| Group | Skills | Relationship |
|-------|--------|-------------|
| **Pipeline Execution** | forge-run, forge-fix, forge-shape, forge-sprint, bootstrap-project, migration | Entry points for different pipeline modes |
| **Pipeline Management** | forge-status, forge-history, forge-resume, forge-abort, forge-reset, forge-rollback | Lifecycle management of pipeline runs |
| **Quality** | forge-review, codebase-health, deep-health, verify, security-audit | Code quality at different scopes |
| **Graph** | graph-init, graph-status, graph-query, graph-rebuild, graph-debug | Knowledge graph operations |
| **Configuration** | forge-init, config-validate | Project setup |
| **Diagnostics** | forge-diagnose, repair-state, forge-profile | Pipeline health inspection |
| **Analytics** | forge-insights, forge-history, forge-ask | Cross-run analysis |
| **Deployment** | deploy, docs-generate | Post-pipeline operations |
| **Automation** | forge-automation | Event-driven triggers |

### 6. Skill Quality Bats Test

Add `tests/contract/skill-quality.bats` with these validations:

```bash
# For each skill .md file in skills/:
@test "skill-quality: all descriptions use double-quoted YAML strings"
@test "skill-quality: all descriptions contain 'Use when' or 'use when'"
@test "skill-quality: all descriptions are at least 80 characters"
@test "skill-quality: all skills have ## Prerequisites section"
@test "skill-quality: all skills have ## Instructions section (not '## What to do')"
@test "skill-quality: all skills have ## Error Handling section"
@test "skill-quality: all skills have ## See Also section"
@test "skill-quality: no skill uses '## What to do' header"
@test "skill-quality: all Prerequisites check git repository"
@test "skill-quality: all Prerequisites check forge initialization"
@test "skill-quality: See Also references are valid skill names"
@test "skill-quality: minimum skill count guard (32 skills)"
```

Estimated: 12-15 test cases.

## Testing Approach

1. Run new `tests/contract/skill-quality.bats` — all tests must pass
2. Run existing `tests/contract/skill-frontmatter.bats` — no regressions
3. Manual verification: invoke each skill with missing prerequisites and verify error messages are clear
4. Verify Claude Code skill list shows improved descriptions (check `description:` renders correctly)

## Acceptance Criteria

- [ ] All 32 skills follow the canonical template
- [ ] All descriptions are double-quoted and contain "Use when" trigger clause
- [ ] All skills have `## Prerequisites`, `## Instructions`, `## Error Handling`, `## See Also`
- [ ] Zero skills use `## What to do` header
- [ ] 4 thin launcher skills expanded to 40+ lines of instructions each
- [ ] `tests/contract/skill-quality.bats` passes with 12+ test cases
- [ ] All See Also references are valid skill names
- [ ] Existing tests continue to pass (no regressions)

## Effort Estimate

**L** (Large) — 32 skills to update, each requiring 4-6 changes. New test file. Estimated: 4-6 hours of focused editing.

## Dependencies

- None. This is a standalone quality improvement.
- Should be done BEFORE Q02 (agent quality) since skill descriptions affect how agents are triggered.
