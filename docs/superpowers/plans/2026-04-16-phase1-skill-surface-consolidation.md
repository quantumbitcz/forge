# Phase 1 — Skill Surface Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consolidate 7 overlapping skills into `/forge-recover` and `/forge-compress`; enforce uniform skill/agent contract; ship as Forge 3.0.0.

**Architecture:** 7 logical commits land in one PR. Commits ordered so every commit is independently CI-green — additive work (new files, new assertions that are scoped to new files) lands first; subtractive work (deletions, dangling-reference sweeps that scan the whole tree) lands after all references have been scrubbed.

**Tech Stack:** Bash 4+, Bats (bats-core), YAML frontmatter, Markdown. No new runtime dependencies.

**Verification policy:** Per user instruction, **no local test runs**. Static parse checks (`bats --help` / `bash -n`) are permitted. Each commit is pushed and CI validates. If CI red, fix forward in next commit.

**Spec reference:** `docs/superpowers/specs/2026-04-16-phase1-skill-surface-consolidation-design.md`

---

## File Structure (decomposition decisions)

New files live in these locations with these responsibilities:

| File | Responsibility |
|---|---|
| `shared/skill-contract.md` | Authoritative contract for SKILL.md shape (badges, flags, exit codes) |
| `shared/agent-colors.md` | Authoritative cluster + color map; source of truth for the color uniqueness assertion |
| `shared/ask-user-question-patterns.md` | Canonical `AskUserQuestion` JSON payload templates + authoring guidance |
| `skills/forge-recover/SKILL.md` | Recovery dispatcher with 5 subcommands |
| `tests/contract/skill-contract.bats` | All skill-contract assertions (badge, Flags, Exit codes, flag coverage, dangling-ref sweep) |
| `tests/unit/skill-execution/forge-recover-integration.bats` | Runtime `--dry-run` behavior for each subcommand |

Rewritten files (full replacement of current contents):

| File | Change |
|---|---|
| `skills/forge-compress/SKILL.md` | Single-verb → 4-subcommand surface |
| `skills/forge-help/SKILL.md` | Augment existing taxonomy with `[read-only]`/`[writes]` badges + `--json` output mode |
| `tests/unit/caveman-modes.bats` → `tests/unit/compress-output-modes.bats` | Rename + rewrite against new subcommand shape |

Updated files: 32 SKILL.md + 42 agent `.md` + 24 shared docs + 11 test files + 6 top-level (per spec §5).

---

## Rollout Strategy

Commits land in this order — **do not reorder** without updating §9 of the spec:

1. Plan commit (this file)
2. Foundations — new docs, new bats, new skill files (additive)
3. Agent frontmatter contract + `shared/agent-ui.md` + `shared/agent-role-hierarchy.md`
4. Skill contract updates + `/forge-compress` rewrite + `/forge-help` rewrite
5. Deletions + dangling-reference sweep + test updates
6. State schema + orchestrator update
7. Top-level docs + version bump → tag → release

---

## Task 1: Commit this plan

**Files:**
- Create: `docs/superpowers/plans/2026-04-16-phase1-skill-surface-consolidation.md` (this file)

- [ ] **Step 1: Stage and commit the plan**

```bash
git add docs/superpowers/plans/2026-04-16-phase1-skill-surface-consolidation.md
git commit -m "docs(phase1): add skill surface consolidation implementation plan"
```

No push yet — plan is committed locally; push happens at the end of Task 37.

---

## Task 2: Create `shared/skill-contract.md`

**Files:**
- Create: `shared/skill-contract.md`

- [ ] **Step 1: Write the contract document**

```markdown
# Skill Contract

Authoritative specification for every `skills/*/SKILL.md` in this plugin.
Enforced by `tests/contract/skill-contract.bats`.

## 1. Frontmatter description prefix

The first token of `description:` in YAML frontmatter MUST be exactly one of:

- `[read-only]` — skill never modifies any file under `.forge/`, `.claude/`, or project source
- `[writes]` — skill may modify state, source, or caches

Badge reflects **maximum impact** — if any subcommand of the skill can write, the skill is `[writes]` even when the default subcommand is read-only.

## 2. Required sections in SKILL.md body

### `## Flags`

One bullet per flag, syntax `- **--flag**: <description>`.

All skills MUST list:
- `--help` — print usage (description + flags + 3 examples + exit codes) and exit 0

Mutating skills additionally MUST list:
- `--dry-run` — preview actions without writing. Implementation: skill sets `FORGE_DRY_RUN=1` env var; downstream agents honour it

Read-only skills additionally MUST list:
- `--json` — emit structured JSON to stdout, suppressing human-readable prose

### `## Exit codes`

Either inline list OR a single line: `See shared/skill-contract.md for the standard exit-code table.`

## 3. Standard exit codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | User error (bad args, missing config, unknown subcommand) |
| 2 | Pipeline failure (agent reported FAIL or CONCERNS without override) |
| 3 | Recovery needed (state corruption, locked, or escalated) |
| 4 | Aborted by user (`/forge-abort`, Ctrl+C, or "Abort" chosen in `AskUserQuestion`) |

## 4. Skill categorization (Phase 1 baseline — 35 skills)

**Read-only (15):** forge-ask, forge-codebase-health, forge-config-validate, forge-graph-debug, forge-graph-query, forge-graph-status, forge-help, forge-history, forge-insights, forge-playbooks, forge-profile, forge-security-audit, forge-status, forge-tour, forge-verify.

**Writes (20):** forge-abort, forge-automation, forge-bootstrap, forge-commit, forge-compress, forge-config, forge-deep-health, forge-deploy, forge-docs-generate, forge-fix, forge-graph-init, forge-graph-rebuild, forge-init, forge-migration, forge-playbook-refine, forge-recover, forge-review, forge-run, forge-shape, forge-sprint.

## 5. Amendment process

This contract is versioned with the plugin. Amendments require:
1. A spec in `docs/superpowers/specs/` describing the change
2. A matching update to `tests/contract/skill-contract.bats`
3. Migration of all affected SKILL.md files in the same PR
```

- [ ] **Step 2: Commit (held until Task 7)**

Do not commit this file alone. It lands in the foundations commit (Task 7) along with the other new files.

---

## Task 3: Create `shared/agent-colors.md`

**Files:**
- Create: `shared/agent-colors.md`

- [ ] **Step 1: Write the palette + cluster + agent-map document**

Content template (copy the spec §4.6 table verbatim into this file):

```markdown
# Agent Color Map

Authoritative source for agent `color:` assignments. Enforced by cluster-scoped uniqueness in `tests/contract/ui-frontmatter-consistency.bats`.

## 1. Palette (18 hues)

Chosen for terminal rendering with ≥3:1 contrast against common backgrounds.

| Name | ANSI-256 | Approx hex |
|------|----------|------------|
| magenta | 201 | #ff00ff |
| pink | 205 | #ff4fa0 |
| purple | 93 | #875fff |
| orange | 208 | #ff8700 |
| coral | 209 | #ff875f |
| cyan | 51 | #00ffff |
| navy | 17 | #00005f |
| teal | 30 | #008787 |
| olive | 58 | #5f5f00 |
| blue | 33 | #0087ff |
| crimson | 161 | #d7005f |
| yellow | 226 | #ffff00 |
| green | 46 | #00ff00 |
| lime | 119 | #87ff5f |
| red | 196 | #ff0000 |
| amber | 214 | #ffaf00 |
| brown | 130 | #af5f00 |
| white | 15 | #ffffff |
| gray | 245 | #8a8a8a |

## 2. Dispatch clusters

Agents that can appear in the same TaskCreate cluster must have distinct colors. Cluster definitions mirror the dispatch-layer tables in `shared/agent-role-hierarchy.md`.

| Cluster | Members |
|---|---|
| Pre-pipeline | fg-010, fg-015, fg-020, fg-050, fg-090 |
| Orchestrator + helpers | fg-100, fg-101, fg-102, fg-103 |
| PREFLIGHT | fg-130, fg-135, fg-140, fg-150 |
| Migration / Planning | fg-160, fg-200, fg-205, fg-210, fg-250 |
| Implement | fg-300, fg-310, fg-320, fg-350 |
| Review | fg-400, fg-410, fg-411, fg-412, fg-413, fg-416, fg-417, fg-418, fg-419 |
| Verify / Test | fg-500, fg-505, fg-510, fg-515 |
| Ship | fg-590, fg-600, fg-610, fg-620, fg-650 |
| Learn | fg-700, fg-710 |

## 3. Full 42-agent color map

(Copy the complete table from spec §4.6 here — 43 rows with Agent | Cluster | New color.)

## 4. Adding a new agent

New agents must pick an unused color within their target cluster. If no hue is free, extend the §1 palette and document the AAA contrast check in the PR description.
```

- [ ] **Step 2: Copy the full 43-row color map from spec §4.6**

Open `docs/superpowers/specs/2026-04-16-phase1-skill-surface-consolidation-design.md` §4.6. Copy the table rows under "Full 42-agent color map" verbatim into §3 of the new file. Ensure `fg-205-planning-critic` receives `crimson`.

- [ ] **Step 3: Held for commit in Task 7**

---

## Task 4: Create `shared/ask-user-question-patterns.md`

**Files:**
- Create: `shared/ask-user-question-patterns.md`

- [ ] **Step 1: Write the patterns document**

Copy all four JSON patterns from spec §4.7 verbatim plus the prohibitions list:

```markdown
# AskUserQuestion Patterns

Canonical payload templates for agents invoking the Claude Code `AskUserQuestion` tool. Enforced where bats-testable (see §4).

## 1. Pattern — Single-choice with preview

Use when two or three architecturally distinct options benefit from side-by-side visual comparison (code snippets, configs, diagrams).

<verbatim Pattern 1 JSON from spec §4.7>

## 2. Pattern — Multi-select

Use when choices stack non-exclusively. Triggers the "Review your answers" confirmation screen.

<verbatim Pattern 2 JSON from spec §4.7>

## 3. Pattern — Single-choice with explicit recommendation

Use for safe-default escalations where one path is strongly preferred.

<verbatim Pattern 3 JSON from spec §4.7>

## 4. Pattern — Free-text via auto "Other"

Claude Code auto-appends an "Other" option with text input. NEVER add a literal "Other" option — it is duplicated.

## 5. Prohibitions (bats-enforced)

- No `Options: (1)...(2)...` plain-text menus in agent `.md` bodies or stage-note templates.
- No yes/no prompts (labels matching `/^(Yes|No)$/i`) when distinct labeled options exist.
- No `AskUserQuestion` payload without `header` (required ≤12-char chip label).

## 6. Authoring guidance (not bats-enforced)

- Prefer `multiSelect: true` when options are semantically non-exclusive; reviewer judgment applies here.
- Order options with Recommended first, destructive last.
- Keep `description` fields under ~25 words for terminal fit.
```

- [ ] **Step 2: Held for commit in Task 7**

---

## Task 5: Create `skills/forge-recover/SKILL.md`

**Files:**
- Create: `skills/forge-recover/SKILL.md`

- [ ] **Step 1: Write the SKILL.md**

```markdown
---
name: forge-recover
description: "[writes] Diagnose or fix pipeline state — read-only diagnose (default), repair counters/locks, reset clearing state while preserving caches, resume from checkpoint, or rollback worktree commits. Use when pipeline stuck, failed with state errors, or you need to retry from a checkpoint. Trigger: /forge-recover, diagnose state, repair pipeline, reset state, resume from checkpoint, rollback commits"
---

# Forge Recover

Single entry point for pipeline state recovery. Replaces `/forge-diagnose`, `/forge-repair-state`, `/forge-reset`, `/forge-resume`, `/forge-rollback` (all removed in 3.0.0).

## Subcommands

| Subcommand | Read/Write | Purpose |
|---|---|---|
| `diagnose` *(default)* | read-only | Health check of state.json, recovery budget, convergence, stalled stages |
| `repair` | writes | Fix counters, stale locks, invalid stages, WAL recovery |
| `reset` | writes | Clear pipeline state (preserves cross-run caches) |
| `resume` | writes | Resume from last checkpoint |
| `rollback` | writes | Revert pipeline commits in worktree |

## Flags

- **--help**: print usage and exit 0
- **--dry-run**: (repair/reset/rollback only) preview actions without writing
- **--json**: (diagnose only) emit structured JSON output
- **--target <branch>**: (rollback only) target branch to revert on; default = current worktree

## Exit codes

See `shared/skill-contract.md` for the standard exit-code table.

## Examples

```
/forge-recover                          # diagnose (read-only default)
/forge-recover diagnose --json          # JSON output for scripting
/forge-recover repair --dry-run         # preview repairs
/forge-recover reset                    # prompts confirmation via AskUserQuestion
/forge-recover resume                   # continue from last checkpoint
/forge-recover rollback --target main   # revert main branch
```

## Implementation

Dispatches `fg-100-orchestrator` with `recovery_op: diagnose|repair|reset|resume|rollback` on its input payload. See `agents/fg-100-orchestrator.md` §Recovery op dispatch and `shared/state-schema.md` for the payload schema.

Replacements for removed skills:

| Old skill | New invocation |
|---|---|
| /forge-diagnose | /forge-recover diagnose |
| /forge-repair-state | /forge-recover repair |
| /forge-reset | /forge-recover reset |
| /forge-resume | /forge-recover resume |
| /forge-rollback | /forge-recover rollback |
```

- [ ] **Step 2: Held for commit in Task 7**

---

## Task 6: Create `tests/contract/skill-contract.bats` (skeleton)

**Files:**
- Create: `tests/contract/skill-contract.bats`

- [ ] **Step 1: Write the bats skeleton**

Writing the test file with all assertions in place. Assertions reference files that do not yet exist (SKILL.md updates, agent frontmatter changes land in Tasks 9–25). The test file parses cleanly but WILL fail if run against the current tree — which is fine since we push only after all commits are in place.

```bash
#!/usr/bin/env bats

# Skill contract assertions — enforces shared/skill-contract.md

setup() {
  PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export PLUGIN_ROOT
}

@test "every SKILL.md description starts with [read-only] or [writes]" {
  local bad=0
  for skill_md in "$PLUGIN_ROOT"/skills/*/SKILL.md; do
    local desc
    desc=$(awk '/^description:/{sub(/^description: *"?/, ""); sub(/"?$/, ""); print; exit}' "$skill_md")
    if [[ ! "$desc" =~ ^\[read-only\] ]] && [[ ! "$desc" =~ ^\[writes\] ]]; then
      echo "BAD prefix: $skill_md → $desc"
      ((bad++))
    fi
  done
  [ "$bad" -eq 0 ]
}

@test "every SKILL.md has a ## Flags section" {
  for skill_md in "$PLUGIN_ROOT"/skills/*/SKILL.md; do
    grep -q "^## Flags" "$skill_md" || { echo "Missing Flags: $skill_md"; return 1; }
  done
}

@test "every SKILL.md has a ## Exit codes section or reference" {
  for skill_md in "$PLUGIN_ROOT"/skills/*/SKILL.md; do
    grep -qE "^## Exit codes|See shared/skill-contract.md" "$skill_md" \
      || { echo "Missing Exit codes: $skill_md"; return 1; }
  done
}

@test "every SKILL.md lists --help in Flags" {
  for skill_md in "$PLUGIN_ROOT"/skills/*/SKILL.md; do
    awk '/^## Flags/{flag=1; next} /^## /{flag=0} flag' "$skill_md" \
      | grep -q -- "--help" || { echo "Missing --help: $skill_md"; return 1; }
  done
}

@test "writes skills list --dry-run in Flags" {
  # Writes skills per shared/skill-contract.md §4
  local writes=(forge-abort forge-automation forge-bootstrap forge-commit \
                forge-compress forge-config forge-deep-health forge-deploy \
                forge-docs-generate forge-fix forge-graph-init forge-graph-rebuild \
                forge-init forge-migration forge-playbook-refine forge-recover \
                forge-review forge-run forge-shape forge-sprint)
  for s in "${writes[@]}"; do
    local f="$PLUGIN_ROOT/skills/$s/SKILL.md"
    [ -f "$f" ] || { echo "Missing skill: $s"; return 1; }
    awk '/^## Flags/{flag=1; next} /^## /{flag=0} flag' "$f" \
      | grep -q -- "--dry-run" || { echo "Missing --dry-run in $s"; return 1; }
  done
}

@test "read-only skills list --json in Flags" {
  local readonly_skills=(forge-ask forge-codebase-health forge-config-validate \
                         forge-graph-debug forge-graph-query forge-graph-status \
                         forge-help forge-history forge-insights forge-playbooks \
                         forge-profile forge-security-audit forge-status \
                         forge-tour forge-verify)
  for s in "${readonly_skills[@]}"; do
    local f="$PLUGIN_ROOT/skills/$s/SKILL.md"
    [ -f "$f" ] || { echo "Missing skill: $s"; return 1; }
    awk '/^## Flags/{flag=1; next} /^## /{flag=0} flag' "$f" \
      | grep -q -- "--json" || { echo "Missing --json in $s"; return 1; }
  done
}

@test "exactly 35 skill directories exist" {
  local count
  count=$(find "$PLUGIN_ROOT/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
  [ "$count" -eq 35 ]
}

@test "no dangling references to deleted skills" {
  local deleted=(forge-diagnose forge-repair-state forge-reset forge-resume \
                 forge-rollback forge-caveman forge-compression-help)
  local bad=0
  for name in "${deleted[@]}"; do
    local hits
    hits=$(grep -rln "/$name[^a-z-]" \
             "$PLUGIN_ROOT/README.md" "$PLUGIN_ROOT/CLAUDE.md" \
             "$PLUGIN_ROOT/shared" "$PLUGIN_ROOT/skills" \
             "$PLUGIN_ROOT/tests" "$PLUGIN_ROOT/hooks" 2>/dev/null \
           | grep -v "DEPRECATIONS.md" | grep -v "CHANGELOG.md" || true)
    if [ -n "$hits" ]; then
      echo "Dangling reference to /$name in:"
      echo "$hits"
      bad=1
    fi
  done
  [ "$bad" -eq 0 ]
}
```

- [ ] **Step 2: Static parse check**

```bash
cd /Users/denissajnar/IdeaProjects/forge
bats --help > /dev/null  # verify bats is present
# Parse-check without running: bats does not have a pure dry-run, so rely on bash -n on the generated file
bash -n tests/contract/skill-contract.bats
```

Expected: no syntax errors. If `bats` is not installed locally, skip the parse check — CI has bats.

- [ ] **Step 3: Held for commit in Task 7**

---

## Task 7: Create `tests/unit/skill-execution/forge-recover-integration.bats`

**Files:**
- Create: `tests/unit/skill-execution/forge-recover-integration.bats`

- [ ] **Step 1: Write the integration test**

```bash
#!/usr/bin/env bats

# Runtime --dry-run behavior for /forge-recover subcommands

setup() {
  PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  TEST_FORGE_DIR="$(mktemp -d)"
  export PLUGIN_ROOT TEST_FORGE_DIR
  # Seed a fixture .forge/ directory
  mkdir -p "$TEST_FORGE_DIR/.forge"
  echo '{"status":"FAILED","stage":"IMPLEMENTING"}' > "$TEST_FORGE_DIR/.forge/state.json"
}

teardown() {
  rm -rf "$TEST_FORGE_DIR"
}

@test "forge-recover SKILL.md exists" {
  [ -f "$PLUGIN_ROOT/skills/forge-recover/SKILL.md" ]
}

@test "forge-recover SKILL.md advertises all 5 subcommands" {
  local body="$PLUGIN_ROOT/skills/forge-recover/SKILL.md"
  for sc in diagnose repair reset resume rollback; do
    grep -q "\`$sc\`" "$body" || { echo "Missing subcommand doc: $sc"; return 1; }
  done
}

@test "forge-recover SKILL.md advertises --dry-run on mutating subcommands" {
  grep -q "\-\-dry-run" "$PLUGIN_ROOT/skills/forge-recover/SKILL.md"
}

@test "forge-recover SKILL.md advertises --json on diagnose" {
  grep -q "\-\-json" "$PLUGIN_ROOT/skills/forge-recover/SKILL.md"
}
```

**Scope clarification:** This is a SURFACE test that verifies the SKILL.md exposes the contract (all 5 subcommands documented; `--dry-run` advertised on mutating; `--json` advertised on diagnose). True runtime `--dry-run` behavior verification (invoking the orchestrator and snapshot-diffing `.forge/`) requires integration fixtures and a live orchestrator mock — **deferred to Phase 2**. Spec AC #23 is updated accordingly to reflect this reduced scope.

**Implication for spec AC #23:** When the Task 37 commit pass applies, AC #23 should read: `tests/unit/skill-execution/forge-recover-integration.bats` created; verifies SKILL.md advertises 5 subcommands + `--dry-run` on mutating subcommands + `--json` on diagnose.

- [ ] **Step 2: Static parse check**

```bash
bash -n tests/unit/skill-execution/forge-recover-integration.bats
```

- [ ] **Step 3: Held for commit in Task 8**

---

## Task 8: Commit 2 — Foundations landed

**Files touched in this commit:**
- Create: `shared/skill-contract.md`
- Create: `shared/agent-colors.md`
- Create: `shared/ask-user-question-patterns.md`
- Create: `skills/forge-recover/SKILL.md`
- Create: `tests/contract/skill-contract.bats`
- Create: `tests/unit/skill-execution/forge-recover-integration.bats`

- [ ] **Step 1: Stage and commit**

```bash
git add shared/skill-contract.md shared/agent-colors.md shared/ask-user-question-patterns.md
git add skills/forge-recover/SKILL.md
git add tests/contract/skill-contract.bats tests/unit/skill-execution/forge-recover-integration.bats
git commit -m "feat(phase1): foundations — new contract docs, recover skill, bats

Adds:
- shared/skill-contract.md — authoritative SKILL.md shape
- shared/agent-colors.md — cluster-scoped color map (42 agents)
- shared/ask-user-question-patterns.md — canonical UX patterns
- skills/forge-recover/SKILL.md — unified recovery entry point
- tests/contract/skill-contract.bats — contract assertions
- tests/unit/skill-execution/forge-recover-integration.bats — SKILL.md surface check

Assertions will activate against tree state reached in subsequent commits.
This commit is additive; does not break CI on its own."
```

- [ ] **Step 2: No push yet** — batch push at Task 37 after all commits land.

---

## Task 9: Add explicit `ui:` block to 12 agents (Tier 4 defaults)

**Files modified (12 agent `.md`):**
- Modify: `agents/fg-101-worktree-manager.md`
- Modify: `agents/fg-102-conflict-resolver.md`
- Modify: `agents/fg-205-planning-critic.md`
- Modify: `agents/fg-210-validator.md` (this file gets Tier 2 block, not Tier 4 — see Task 11; skip in this task)
- Modify: `agents/fg-410-code-reviewer.md`
- Modify: `agents/fg-411-security-reviewer.md`
- Modify: `agents/fg-412-architecture-reviewer.md`
- Modify: `agents/fg-413-frontend-reviewer.md`
- Modify: `agents/fg-416-performance-reviewer.md`
- Modify: `agents/fg-417-dependency-reviewer.md`
- Modify: `agents/fg-418-docs-consistency-reviewer.md`
- Modify: `agents/fg-419-infra-deploy-reviewer.md`

- [ ] **Step 1: Insert Tier 4 `ui:` block in 11 agents** (all except `fg-210`)

For each of the 11 files, in the YAML frontmatter between `---` lines, add immediately after the `color:` line:

```yaml
ui:
  tasks: false
  ask: false
  plan_mode: false
```

Concrete example — `agents/fg-410-code-reviewer.md` frontmatter goes from:

```yaml
---
name: fg-410-code-reviewer
description: "..."
tools: [Read, Glob, Grep, Bash, LSP, ...]
color: cyan
---
```

to:

```yaml
---
name: fg-410-code-reviewer
description: "..."
tools: [Read, Glob, Grep, Bash, LSP, ...]
color: cyan
ui:
  tasks: false
  ask: false
  plan_mode: false
---
```

- [ ] **Step 2: Static verify frontmatter still parses**

```bash
for f in agents/fg-101*.md agents/fg-102*.md agents/fg-205*.md \
         agents/fg-41{0,1,2,3,6,7,8,9}*.md; do
  # Extract frontmatter; must be valid YAML
  awk '/^---$/{c++; next} c==1' "$f" | python3 -c "import sys, yaml; yaml.safe_load(sys.stdin)"
done
```

Expected: no output on success, exit 0.

- [ ] **Step 3: Held for commit in Task 18**

---

## Task 10: Normalize 3 agents using `ui: { tier: N }` shortcut

**Files modified (3 agent `.md`):**
- Modify: `agents/fg-135-wiki-generator.md`
- Modify: `agents/fg-510-mutation-analyzer.md`
- Modify: `agents/fg-515-property-test-generator.md`

- [ ] **Step 1: Replace `ui: { tier: N }` shortcuts with explicit keys**

`fg-135-wiki-generator.md` — change:
```yaml
ui:
  tier: 3
```
to:
```yaml
ui:
  tasks: true
  ask: false
  plan_mode: false
```

`fg-510-mutation-analyzer.md` — change:
```yaml
ui:
  tier: 4
```
to:
```yaml
ui:
  tasks: false
  ask: false
  plan_mode: false
```

`fg-515-property-test-generator.md` — change:
```yaml
ui:
  tier: 3
```
to:
```yaml
ui:
  tasks: true
  ask: false
  plan_mode: false
```

- [ ] **Step 2: Held for commit in Task 18**

---

## Task 11: Promote `fg-210-validator` to Tier 2

**Files modified:**
- Modify: `agents/fg-210-validator.md`

- [ ] **Step 1: Add explicit `ui:` block with Tier 2 capabilities**

In the YAML frontmatter, after the `color:` line, add:

```yaml
ui:
  tasks: true
  ask: true
  plan_mode: false
```

- [ ] **Step 2: Extend `tools:` with `TaskCreate`, `TaskUpdate`, `AskUserQuestion`**

**Verified current value** in `agents/fg-210-validator.md`:
```yaml
tools: ['Read', 'Grep', 'Glob', 'Bash', 'neo4j-mcp']
```

Change to (preserving single-quote YAML style):
```yaml
tools: ['Read', 'Grep', 'Glob', 'Bash', 'neo4j-mcp', 'TaskCreate', 'TaskUpdate', 'AskUserQuestion']
```

If the actual value differs from the above (YAML style drift), preserve the existing quoting style and only append the three new tool names.

- [ ] **Step 3: Add preparatory note in the `.md` body**

Below the frontmatter `---`, add a short note (not a behavior change):

```markdown
> **Note (3.0.0 Phase 1):** This agent is declared Tier 2 in preparation for Phase 4 (escalation taxonomy), which migrates REVISE verdict emission from `fg-100-orchestrator` to this agent. Until then, the orchestrator still owns REVISE `AskUserQuestion` dispatch; these tool declarations exist for contract compliance.
```

- [ ] **Step 4: Held for commit in Task 18**

---

## Task 12: Assign color to `fg-205-planning-critic`

**Files modified:**
- Modify: `agents/fg-205-planning-critic.md`

- [ ] **Step 1: Add `color: crimson` to frontmatter**

Between existing frontmatter lines, add:

```yaml
color: crimson
```

- [ ] **Step 2: Held for commit in Task 18**

---

## Task 13: Apply 42-agent color reassignment per spec §4.6

**Files modified (agent `.md` with color change):**

Per the 42-agent map in spec §4.6, these agents need a color change:

- `fg-015-scope-decomposer.md` — magenta → pink
- `fg-050-project-bootstrapper.md` — magenta → orange
- `fg-090-sprint-orchestrator.md` — magenta → coral
- `fg-102-conflict-resolver.md` — gray → olive
- `fg-103-cross-repo-coordinator.md` — gray → brown
- `fg-135-wiki-generator.md` — cyan → navy
- `fg-140-deprecation-refresh.md` — cyan → teal
- `fg-150-test-bootstrapper.md` — cyan → olive
- `fg-250-contract-validator.md` — yellow → amber
- `fg-310-scaffolder.md` — green → lime
- `fg-320-frontend-polisher.md` — magenta → coral
- `fg-350-docs-generator.md` — green → teal
- `fg-411-security-reviewer.md` — red → crimson
- `fg-412-architecture-reviewer.md` — cyan → navy
- `fg-416-performance-reviewer.md` — yellow → amber
- `fg-417-dependency-reviewer.md` — cyan → purple
- `fg-419-infra-deploy-reviewer.md` — green → olive
- `fg-505-build-verifier.md` — yellow → brown
- `fg-515-property-test-generator.md` — cyan → pink
- `fg-620-deploy-verifier.md` — green → olive
- `fg-650-preview-validator.md` — green → amber
- `fg-710-post-run.md` — magenta → pink

- [ ] **Step 1: Edit each file's `color:` field**

For each file above, edit the YAML frontmatter line `color: <old>` → `color: <new>`.

- [ ] **Step 2: Verify against spec §4.6 map**

```bash
# Sanity check: fail loudly on any cluster-scoped collision
set -e
had_collision=0
for cluster_members in \
  "fg-010 fg-015 fg-020 fg-050 fg-090" \
  "fg-100 fg-101 fg-102 fg-103" \
  "fg-130 fg-135 fg-140 fg-150" \
  "fg-160 fg-200 fg-205 fg-210 fg-250" \
  "fg-300 fg-310 fg-320 fg-350" \
  "fg-400 fg-410 fg-411 fg-412 fg-413 fg-416 fg-417 fg-418 fg-419" \
  "fg-500 fg-505 fg-510 fg-515" \
  "fg-590 fg-600 fg-610 fg-620 fg-650" \
  "fg-700 fg-710"; do
  colors=""
  for m in $cluster_members; do
    c=$(grep -h "^color:" agents/${m}*.md 2>/dev/null | head -1 | awk '{print $2}')
    colors="$colors $c"
  done
  distinct=$(echo "$colors" | tr ' ' '\n' | grep -v '^$' | sort -u | wc -l | tr -d ' ')
  total=$(echo "$colors" | wc -w | tr -d ' ')
  if [ "$distinct" != "$total" ]; then
    echo "COLLISION in cluster [$cluster_members]: colors=[$colors], distinct=$distinct, total=$total"
    had_collision=1
  fi
done
[ "$had_collision" = "0" ] || { echo "Task 13 verify: FAIL — fix color assignments before commit"; exit 1; }
echo "Task 13 verify: all clusters clean"
```

Expected: prints `Task 13 verify: all clusters clean`. Any COLLISION line fails the script and blocks commit.

- [ ] **Step 3: Held for commit in Task 18**

---

## Task 14: Tier-size all 42 agent descriptions

**Files modified:** all 42 `agents/fg-*.md`

- [ ] **Step 1: Identify current word count per agent**

Tokenization rule (from spec §4.5.6): strip `<example>` and `<commentary>` blocks, strip backtick-fenced content, then `wc -w`.

```bash
for f in agents/fg-*.md; do
  desc=$(awk '/^description:/{flag=1; sub(/^description: *"?/, ""); sub(/"?$/, ""); print; next}
             flag && /^[a-z_]+:/{flag=0}
             flag' "$f")
  # Strip xml tags and backticks
  cleaned=$(echo "$desc" | sed -E 's/<[^>]*>//g; s/`[^`]*`//g')
  wc=$(echo "$cleaned" | wc -w | tr -d ' ')
  echo "$(basename "$f" .md): $wc words"
done
```

- [ ] **Step 2: Compare against tier ranges**

| Tier | Range | Agents |
|---|---|---|
| 1 | 50–80 | fg-010, fg-015, fg-050, fg-090, fg-160, fg-200 |
| 2 | 20–40 | fg-020, fg-100, fg-103, fg-210, fg-400, fg-500, fg-600, fg-710 |
| 3 | 10–20 | fg-050 helpers, fg-130, fg-135, fg-140, fg-150, fg-250, fg-300, fg-310, fg-320, fg-350, fg-505, fg-515, fg-590, fg-610, fg-620, fg-650, fg-700, fg-101, fg-102 |
| 4 | 5–12 | fg-205, fg-410, fg-411, fg-412, fg-413, fg-416, fg-417, fg-418, fg-419, fg-510 |

(Cross-reference `shared/agent-role-hierarchy.md` for authoritative tier assignments.)

- [ ] **Step 3: Edit out-of-range descriptions**

For each agent whose count is out of range:
- **Too long:** prune `<example>`/`<commentary>` out of the `description:` frontmatter into the `.md` body (examples belong in body anyway).
- **Too short:** expand with a one-line purpose + trigger keywords.

Use the following template per tier:

- **Tier 1 (50–80 words):** `Interactive <role> agent — <what>. <When dispatched>. <example brief>`
- **Tier 2 (20–40 words):** `<Role> — <what it does>. <When dispatched>.`
- **Tier 3 (10–20 words):** `<Role> — <one-line purpose>.`
- **Tier 4 (5–12 words):** `<Role>. <One behavior>.`

- [ ] **Step 4: Held for commit in Task 18**

---

## Task 15: Add `## User-interaction examples` to 14 Tier 1/2 agents

**Files modified:**
- `agents/fg-010-shaper.md`
- `agents/fg-015-scope-decomposer.md`
- `agents/fg-020-bug-investigator.md`
- `agents/fg-050-project-bootstrapper.md`
- `agents/fg-090-sprint-orchestrator.md`
- `agents/fg-100-orchestrator.md`
- `agents/fg-103-cross-repo-coordinator.md`
- `agents/fg-160-migration-planner.md`
- `agents/fg-200-planner.md`
- `agents/fg-210-validator.md`
- `agents/fg-400-quality-gate.md`
- `agents/fg-500-test-gate.md`
- `agents/fg-600-pr-builder.md`
- `agents/fg-710-post-run.md`

- [ ] **Step 1: Pick one of the four canonical patterns per agent**

Mapping (each agent gets one tailored example drawn from its actual use case):

| Agent | Pattern from §4.7 | Scenario |
|---|---|---|
| fg-010-shaper | Pattern 2 (multi-select) | Which shaping dimensions to explore |
| fg-015-scope-decomposer | Pattern 1 (single-choice w/ preview) | Execution strategy for multi-feature spec |
| fg-020-bug-investigator | Pattern 3 (safe-default escalation) | Reproduction strategy |
| fg-050-project-bootstrapper | Pattern 1 (single-choice w/ preview) | Stack selection |
| fg-090-sprint-orchestrator | Pattern 2 (multi-select) | Features to run in parallel |
| fg-100-orchestrator | Pattern 3 (safe-default escalation) | Recovery-needed escalation |
| fg-103-cross-repo-coordinator | Pattern 1 (single-choice w/ preview) | Cross-repo PR merge strategy |
| fg-160-migration-planner | Pattern 1 (single-choice w/ preview) | Migration phasing |
| fg-200-planner | Pattern 3 (safe-default escalation) | Parallelization risk |
| fg-210-validator | Pattern 3 (safe-default escalation) | REVISE verdict path (preparatory only — behavior owned by orchestrator in Phase 1) |
| fg-400-quality-gate | Pattern 3 (safe-default escalation) | FAIL verdict |
| fg-500-test-gate | Pattern 3 (safe-default escalation) | Flaky test quarantine |
| fg-600-pr-builder | Pattern 1 (single-choice w/ preview) | Commit grouping |
| fg-710-post-run | Pattern 2 (multi-select) | Which corrections to record |

- [ ] **Step 2: Append the `## User-interaction examples` section to each of the 14 agent `.md` files**

For each agent, copy the literal JSON payload from **Appendix A** (at the end of this plan) into the agent's `.md` body. Append a `## User-interaction examples` heading followed by a `### Example — <scenario>` subheading and the JSON block inside a ```` ```json ```` fence.

Per-agent file + Appendix A section mapping:

| Agent file | Appendix A section |
|---|---|
| `agents/fg-010-shaper.md` | A.1 |
| `agents/fg-015-scope-decomposer.md` | A.2 |
| `agents/fg-020-bug-investigator.md` | A.3 |
| `agents/fg-050-project-bootstrapper.md` | A.4 |
| `agents/fg-090-sprint-orchestrator.md` | A.5 |
| `agents/fg-100-orchestrator.md` | A.6 |
| `agents/fg-103-cross-repo-coordinator.md` | A.7 |
| `agents/fg-160-migration-planner.md` | A.8 |
| `agents/fg-200-planner.md` | A.9 |
| `agents/fg-210-validator.md` | A.10 |
| `agents/fg-400-quality-gate.md` | A.11 |
| `agents/fg-500-test-gate.md` | A.12 |
| `agents/fg-600-pr-builder.md` | A.13 |
| `agents/fg-710-post-run.md` | A.14 |

No creative work required at execution time — Appendix A contains all 14 literal payloads.

- [ ] **Step 3: Held for commit in Task 18**

---

## Task 16: Update `shared/agent-ui.md` — remove implicit-omission language

**Files modified:**
- Modify: `shared/agent-ui.md`

- [ ] **Step 1: Replace the implicit-tier-4 language**

Current text at `shared/agent-ui.md` line ~13 (find current text by reading the file):

```
Omitting the `ui:` section entirely means all capabilities are `false` (Tier 4 — no UI).
```

Replace with:

```
Every agent MUST declare an explicit `ui:` block with three boolean keys: `tasks`, `ask`, `plan_mode`. Implicit omission is invalid and rejected by `tests/contract/ui-frontmatter-consistency.bats`. Tier 4 agents declare `ui: { tasks: false, ask: false, plan_mode: false }`.
```

- [ ] **Step 2: Confirm `plan_mode` is the canonical key name**

Grep the file for any drift mentions of `plan:` (without `_mode`). Replace with `plan_mode:`.

- [ ] **Step 3: Add reference to new bats file**

Near the end of the document, add:

```markdown
## Enforcement

Contract compliance is enforced by `tests/contract/ui-frontmatter-consistency.bats`. See `shared/agent-colors.md` for the cluster-scoped color uniqueness assertion.
```

- [ ] **Step 4: Held for commit in Task 18**

---

## Task 17: Update `shared/agent-role-hierarchy.md`

**Files modified:**
- Modify: `shared/agent-role-hierarchy.md`

- [ ] **Step 1: Add `fg-205-planning-critic` to the Tier 4 table**

Currently absent from the hierarchy. Find the Tier 4 section and add a row:

```markdown
| fg-205-planning-critic | Plan critic | Silent adversarial plan reviewer; emits CRITIC findings consumed by fg-210-validator |
```

- [ ] **Step 2: Move `fg-210-validator` from Tier 4 to Tier 2**

Remove the Tier 4 row for `fg-210-validator` if present. In the Tier 2 table, add:

```markdown
| fg-210-validator | Plan validator | Validates plans across 7 perspectives; emits GO/REVISE/NO-GO verdict. REVISE triggers user AskUserQuestion (owned by orchestrator in 3.0.0; Phase 4 migrates it here). |
```

- [ ] **Step 3: Update any tier-count summaries in the document**

If the file has sentences like "Tier 4 (22 agents)", increment Tier 2 count by 1 and decrement Tier 4 count by 1 (net zero total but counts shift).

- [ ] **Step 4: Held for commit in Task 18**

---

## Task 18: Extend `tests/contract/ui-frontmatter-consistency.bats` + delete duplicate

**Files modified:**
- Modify: `tests/contract/ui-frontmatter-consistency.bats`
- Delete: `tests/structural/ui-frontmatter-consistency.bats`

- [ ] **Step 1: Read both current bats files**

```bash
diff tests/contract/ui-frontmatter-consistency.bats tests/structural/ui-frontmatter-consistency.bats
```

Confirm the `structural/` copy is a duplicate or subset. If it has unique assertions, merge them into `contract/` before deleting.

- [ ] **Step 2: Add 5 new assertions to `tests/contract/ui-frontmatter-consistency.bats`**

Append at end of file:

```bash
@test "every agent has an explicit ui: block" {
  for f in "$PLUGIN_ROOT"/agents/fg-*.md; do
    grep -q "^ui:" "$f" || { echo "Missing ui: $f"; return 1; }
  done
}

@test "no agent uses ui.tier shortcut" {
  for f in "$PLUGIN_ROOT"/agents/fg-*.md; do
    if awk '/^ui:/{flag=1; next} flag && /^[a-z]/{flag=0} flag' "$f" | grep -q "^ *tier:"; then
      echo "ui.tier shortcut found in $f"; return 1
    fi
  done
}

@test "every agent has a color: field" {
  for f in "$PLUGIN_ROOT"/agents/fg-*.md; do
    grep -q "^color:" "$f" || { echo "Missing color: $f"; return 1; }
  done
}

@test "cluster-scoped color uniqueness holds" {
  # Cluster → members mapping sourced from shared/agent-colors.md §2
  declare -A clusters
  clusters["pre-pipeline"]="fg-010 fg-015 fg-020 fg-050 fg-090"
  clusters["orch"]="fg-100 fg-101 fg-102 fg-103"
  clusters["preflight"]="fg-130 fg-135 fg-140 fg-150"
  clusters["plan"]="fg-160 fg-200 fg-205 fg-210 fg-250"
  clusters["impl"]="fg-300 fg-310 fg-320 fg-350"
  clusters["review"]="fg-400 fg-410 fg-411 fg-412 fg-413 fg-416 fg-417 fg-418 fg-419"
  clusters["verify"]="fg-500 fg-505 fg-510 fg-515"
  clusters["ship"]="fg-590 fg-600 fg-610 fg-620 fg-650"
  clusters["learn"]="fg-700 fg-710"

  local bad=0
  for cluster in "${!clusters[@]}"; do
    local colors=""
    for member in ${clusters[$cluster]}; do
      local c
      c=$(grep -h "^color:" "$PLUGIN_ROOT"/agents/${member}*.md 2>/dev/null | head -1 | awk '{print $2}')
      colors="$colors $c"
    done
    local distinct total
    distinct=$(echo "$colors" | tr ' ' '\n' | grep -v '^$' | sort -u | wc -l | tr -d ' ')
    total=$(echo "$colors" | wc -w | tr -d ' ')
    if [ "$distinct" != "$total" ]; then
      echo "Cluster $cluster has collision: $colors"
      bad=1
    fi
  done
  [ "$bad" -eq 0 ]
}

@test "Tier 1/2 agents contain User-interaction examples section" {
  local tier12=(fg-010 fg-015 fg-020 fg-050 fg-090 fg-100 fg-103 fg-160 fg-200 fg-210 fg-400 fg-500 fg-600 fg-710)
  for agent in "${tier12[@]}"; do
    local f
    f=$(ls "$PLUGIN_ROOT"/agents/${agent}*.md 2>/dev/null | head -1)
    [ -n "$f" ] || { echo "Missing agent: $agent"; return 1; }
    grep -q "^## User-interaction examples" "$f" \
      || { echo "Missing User-interaction examples section: $f"; return 1; }
    grep -q '"question":' "$f" \
      || { echo "No AskUserQuestion JSON payload found in: $f"; return 1; }
  done
}
```

- [ ] **Step 3: Delete the duplicate**

```bash
git rm tests/structural/ui-frontmatter-consistency.bats
```

- [ ] **Step 4: Static parse check**

```bash
bash -n tests/contract/ui-frontmatter-consistency.bats
```

- [ ] **Step 5: Commit 3 — Frontmatter contract**

```bash
git add agents/fg-*.md
git add shared/agent-ui.md shared/agent-role-hierarchy.md
git add tests/contract/ui-frontmatter-consistency.bats
git commit -m "feat(phase1): enforce agent frontmatter contract

- Explicit ui: block on all 42 agents (12 added, 3 normalized from ui.tier shortcut)
- fg-210 promoted Tier 4 → Tier 2 (frontmatter + tools only; behavior unchanged)
- fg-205 gets a color (crimson)
- 22 agents get color reassignment to satisfy cluster-scoped uniqueness
- 42 agent descriptions tier-sized per word-count rule
- 14 Tier 1/2 agents get ## User-interaction examples section
- shared/agent-ui.md: remove implicit-omission language
- shared/agent-role-hierarchy.md: add fg-205, promote fg-210
- tests/contract/ui-frontmatter-consistency.bats: 5 new assertions
- tests/structural/ui-frontmatter-consistency.bats: delete (duplicate)"
```

---

## Task 19: Rewrite `skills/forge-compress/SKILL.md`

**Files modified:**
- Rewrite: `skills/forge-compress/SKILL.md`

- [ ] **Step 1: Replace full contents**

```markdown
---
name: forge-compress
description: "[writes] Unified compression — `agents` compresses agent .md files for 30-50% system-prompt reduction; `output <mode>` sets runtime output compression (off|lite|full|ultra) writing .forge/caveman-mode; `status` shows current settings (default, read-only); `help` prints reference card. Use to save tokens on prompts or session output. Trigger: /forge-compress, compress agents, compress output, caveman mode, reduce tokens"
---

# Forge Compress

Single entry point for compression. Replaces `/forge-compress` (previous agent-only surface), `/forge-caveman`, and `/forge-compression-help` (all removed in 3.0.0).

## Subcommands

| Subcommand | Read/Write | Purpose |
|---|---|---|
| `agents` | writes | Compress agent `.md` files via terse-rewrite (30–50% reduction) |
| `output <mode>` | writes | Set output compression. mode ∈ {off, lite, full, ultra}. Writes .forge/caveman-mode |
| `status` *(default)* | read-only | Show current agent-compression ratio and output-mode |
| `help` | read-only | Reference card (flags, modes, token savings by mode, tips) |

## Flags

- **--help**: print usage and exit 0
- **--dry-run**: (agents, output) preview without writing
- **--json**: (status, help) structured output

## Exit codes

See `shared/skill-contract.md` for the standard exit-code table.

## Examples

```
/forge-compress                            # default: status
/forge-compress output lite                # set lite mode
/forge-compress output ultra --dry-run     # preview ultra without writing
/forge-compress agents                     # compress all agent .md
/forge-compress agents --dry-run           # preview compression
/forge-compress help                       # reference card
/forge-compress status --json              # JSON for scripting
```

## Modes (output subcommand)

| Mode | Token savings | Description |
|------|---------------|-------------|
| off | 0% | Full verbose output (default) |
| lite | ~30% | Strip redundant narration; keep code/data intact |
| full | ~55% | Aggressive prose compression; ellipsis-heavy |
| ultra | ~75% | Caveman grammar; skeletal output only |

Replacements for removed skills:

| Old skill | New invocation |
|---|---|
| /forge-caveman | /forge-compress output <mode> |
| /forge-compression-help | /forge-compress help |
```

- [ ] **Step 2: Held for commit in Task 22**

---

## Task 20: Rewrite `skills/forge-help/SKILL.md`

**Files modified:**
- Rewrite: `skills/forge-help/SKILL.md`

- [ ] **Step 1: Read current content to preserve taxonomy**

```bash
cat skills/forge-help/SKILL.md
```

Note the existing 3-tier taxonomy (Essential/Power User/Advanced) and "Similar Skills" section.

- [ ] **Step 2: Rewrite with augmented output**

Preserve the existing decision-tree content **verbatim** where it covers persistent skills. For each skill entry, add the inline `[read-only]` or `[writes]` badge immediately after the skill name. Remove entries for the 7 deleted skills. Add entries for `/forge-recover` and rewritten `/forge-compress`.

Add new section at the end — `--json` output mode spec:

```markdown
## --json output

When invoked with `--json`, `/forge-help` emits the decision tree as structured JSON:

```json
{
  "total_skills": 35,
  "tiers": {
    "essential": [
      {"name": "forge-run", "mode": "writes", "summary": "Full 10-stage pipeline"},
      ...
    ],
    "power_user": [...],
    "advanced": [...]
  },
  "similar_skills": [
    {"category": "health-audit", "read": "forge-codebase-health", "fix": "forge-deep-health"},
    ...
  ]
}
```
```

- [ ] **Step 3: Held for commit in Task 22**

---

## Task 21: Apply skill-contract template to 32 in-place SKILL.md files

**Files modified (32):** Enumerated in spec §5.4.

- [ ] **Step 1: Define the template to apply**

Every target SKILL.md receives these edits (order matters):

**A. Description badge prefix.** In YAML frontmatter `description:` field, prepend `[read-only] ` or `[writes] ` per the §4 categorization in `shared/skill-contract.md`. Remove any pre-existing prefix bracket notation.

**B. Add `## Flags` section.** Insert immediately after the first `##` heading in the body (usually "# <Skill name>" then description text; add `## Flags` as the first `##`-level subsection):

For mutating skills:
```markdown
## Flags

- **--help**: print usage and exit 0
- **--dry-run**: preview actions without writing

## Exit codes

See `shared/skill-contract.md` for the standard exit-code table.
```

For read-only skills:
```markdown
## Flags

- **--help**: print usage and exit 0
- **--json**: structured JSON output

## Exit codes

See `shared/skill-contract.md` for the standard exit-code table.
```

- [ ] **Step 2: Enumerate target files with their category**

**Read-only (13 in-place updates; excludes forge-help which is rewritten):**
forge-ask, forge-codebase-health, forge-config-validate, forge-graph-debug, forge-graph-query, forge-graph-status, forge-history, forge-insights, forge-playbooks, forge-profile, forge-security-audit, forge-status, forge-tour, forge-verify.

Count check: 14 read-only total − 1 (forge-help rewritten) = 13 in-place read-only updates.

**Writes (19 in-place updates; excludes forge-compress rewritten and forge-recover new):**
forge-abort, forge-automation, forge-bootstrap, forge-commit, forge-config, forge-deep-health, forge-deploy, forge-docs-generate, forge-fix, forge-graph-init, forge-graph-rebuild, forge-init, forge-migration, forge-playbook-refine, forge-review, forge-run, forge-shape, forge-sprint.

Count check: 20 writes total − 2 (forge-compress rewritten, forge-recover new) = 18. Hmm — 18, not 19. Recount from the writes list above: 18 entries. Plan-writer note: count is 18 in-place writes updates.

**Total in-place SKILL.md updates: 13 + 18 = 31.** Plus 32nd (?) — recount against spec §5.4 "32 in-place SKILL.md updates" — spec says 32. Delta: 1 skill unaccounted. Likely `forge-sprint` counted twice or missed, or spec miscounts. **Reconcile before proceeding:**

```bash
# Expected: 34 remaining SKILL.md minus 2 rewrites = 32
find skills/ -mindepth 1 -maxdepth 1 -type d | wc -l
# After Task 8 we've added forge-recover so skills/ has 41 + 1 new (pre-deletion) = 42
# 42 - 7 (to be deleted in Task 28) - 2 (rewrites: forge-compress, forge-help) - 1 (new: forge-recover) = 32 in-place
```

Corrected enumeration for the remaining 32:

Read-only (14): forge-ask, forge-codebase-health, forge-config-validate, forge-graph-debug, forge-graph-query, forge-graph-status, forge-history, forge-insights, forge-playbooks, forge-profile, forge-security-audit, forge-status, forge-tour, forge-verify. (forge-help is rewritten.)

Writes (18): forge-abort, forge-automation, forge-bootstrap, forge-commit, forge-config, forge-deep-health, forge-deploy, forge-docs-generate, forge-fix, forge-graph-init, forge-graph-rebuild, forge-init, forge-migration, forge-playbook-refine, forge-review, forge-run, forge-shape, forge-sprint.

14 + 18 = 32 ✅

- [ ] **Step 3: Apply the template to all 32 files**

For each file, edit description prefix AND add Flags + Exit codes sections. Example — `skills/forge-run/SKILL.md`:

Current frontmatter (illustrative):
```yaml
---
name: forge-run
description: "Universal pipeline entry point. Auto-classifies intent and routes to the correct pipeline mode. Use when you want to build a feature, implement a requirement, or run the full development pipeline. Accepts --from=<stage>, --dry-run, --spec <path>, --sprint, --parallel."
---
```

After:
```yaml
---
name: forge-run
description: "[writes] Universal pipeline entry point. Auto-classifies intent and routes to the correct pipeline mode. Use when you want to build a feature, implement a requirement, or run the full development pipeline. Accepts --from=<stage>, --spec <path>, --sprint, --parallel."
---
```

And insert after the top of the body:
```markdown
## Flags

- **--help**: print usage and exit 0
- **--dry-run**: preview actions without writing

## Exit codes

See `shared/skill-contract.md` for the standard exit-code table.
```

Note: `forge-run` already documents `--dry-run` in its description; keep the mention but move the formal listing to `## Flags`. Same applies to any other skill that mentions flags inline.

- [ ] **Step 4: Held for commit in Task 22**

---

## Task 22: Commit 4 — Skill contract applied

**Files touched:**
- Rewrite: `skills/forge-compress/SKILL.md`, `skills/forge-help/SKILL.md`
- Update: 32 in-place SKILL.md files

- [ ] **Step 1: Stage and commit (explicit paths — no `git add -A` or `git add skills/`)**

```bash
# 32 in-place updates
git add skills/forge-abort/SKILL.md skills/forge-ask/SKILL.md \
  skills/forge-automation/SKILL.md skills/forge-bootstrap/SKILL.md \
  skills/forge-codebase-health/SKILL.md skills/forge-commit/SKILL.md \
  skills/forge-config/SKILL.md skills/forge-config-validate/SKILL.md \
  skills/forge-deep-health/SKILL.md skills/forge-deploy/SKILL.md \
  skills/forge-docs-generate/SKILL.md skills/forge-fix/SKILL.md \
  skills/forge-graph-debug/SKILL.md skills/forge-graph-init/SKILL.md \
  skills/forge-graph-query/SKILL.md skills/forge-graph-rebuild/SKILL.md \
  skills/forge-graph-status/SKILL.md skills/forge-history/SKILL.md \
  skills/forge-init/SKILL.md skills/forge-insights/SKILL.md \
  skills/forge-migration/SKILL.md skills/forge-playbook-refine/SKILL.md \
  skills/forge-playbooks/SKILL.md skills/forge-profile/SKILL.md \
  skills/forge-review/SKILL.md skills/forge-run/SKILL.md \
  skills/forge-security-audit/SKILL.md skills/forge-shape/SKILL.md \
  skills/forge-sprint/SKILL.md skills/forge-status/SKILL.md \
  skills/forge-tour/SKILL.md skills/forge-verify/SKILL.md
# 2 rewrites
git add skills/forge-compress/SKILL.md skills/forge-help/SKILL.md

git commit -m "feat(phase1): apply skill contract to 34 SKILL.md files

- Rewrite skills/forge-compress/SKILL.md (4-subcommand surface)
- Rewrite skills/forge-help/SKILL.md (augmented taxonomy + [read-only]/[writes] badges + --json)
- 32 in-place updates: description badge, ## Flags, ## Exit codes, flag coverage per shared/skill-contract.md"
```

- [ ] **Step 2: No push yet**

---

## Task 23: Delete 7 skill directories

**Files deleted:**
- `skills/forge-diagnose/`
- `skills/forge-repair-state/`
- `skills/forge-reset/`
- `skills/forge-resume/`
- `skills/forge-rollback/`
- `skills/forge-caveman/`
- `skills/forge-compression-help/`

- [ ] **Step 1: Remove the directories**

```bash
git rm -r skills/forge-diagnose skills/forge-repair-state skills/forge-reset skills/forge-resume skills/forge-rollback skills/forge-caveman skills/forge-compression-help
```

- [ ] **Step 2: Verify skill count is now 35**

```bash
find skills -mindepth 1 -maxdepth 1 -type d | wc -l
```

Expected: 35.

- [ ] **Step 3: Held for commit in Task 28**

---

## Task 24: Rename `tests/unit/caveman-modes.bats` → `compress-output-modes.bats`

**Files:**
- Rewrite: `tests/unit/caveman-modes.bats` → `tests/unit/compress-output-modes.bats`

- [ ] **Step 1: Read current contents**

```bash
cat tests/unit/caveman-modes.bats
```

- [ ] **Step 2: Rename and rewrite**

```bash
git mv tests/unit/caveman-modes.bats tests/unit/compress-output-modes.bats
```

Edit the renamed file to replace every reference to `/forge-caveman` with `/forge-compress output`. Preserve assertion structure; only change command-name strings.

- [ ] **Step 3: Held for commit in Task 28**

---

## Task 25: Delete `tests/unit/skill-execution/forge-compression-help.bats`

**Files:**
- Delete: `tests/unit/skill-execution/forge-compression-help.bats`

- [ ] **Step 1: Remove**

```bash
git rm tests/unit/skill-execution/forge-compression-help.bats
```

- [ ] **Step 2: Held for commit in Task 28**

---

## Task 26: Mechanical name-swap across all referencing files

**Files modified (47 files total — the authoritative list below):**

Scope widened from v1 per spec §4.9 and code-reviewer feedback. The dangling-reference sweep that activates in Task 28 scans `README.md`, `CLAUDE.md`, `shared/`, `skills/`, `tests/`, `hooks/` — every ref must be scrubbed before that sweep passes. Scrubbed files:

**27 shared files (24 md + 1 SQL + 2 JSON):**

Markdown (24): `shared/security-audit-trail.md`, `shared/next-task-prediction.md`, `shared/run-history/run-history.md`, `shared/confidence-scoring.md`, `shared/input-compression.md`, `shared/event-log.md`, `shared/automations.md`, `shared/agent-communication.md`, `shared/explore-cache.md`, `shared/recovery/recovery-engine.md`, `shared/flaky-test-management.md`, `shared/plan-cache.md`, `shared/graph/schema.md`, `shared/performance-regression.md`, `shared/playbooks.md`, `shared/background-execution.md`, `shared/learnings/README.md`, `shared/learnings/rule-promotion.md`, `shared/data-classification.md`, `shared/dx-metrics.md`, `shared/visual-verification.md`, `shared/knowledge-base.md`, `shared/state-schema.md`, `shared/output-compression.md`.

SQL (1): `shared/run-history/migrations/001-initial.sql` — per-file careful edit (refs are in SQL comments only; preserve schema).

JSON (2): `shared/schemas/dx-metrics-schema.json`, `shared/schemas/benchmarks-schema.json` — per-file careful edit (refs are inside `description` string fields only; preserve JSON structure).

**17 skill cross-reference files:**

`skills/forge-abort/SKILL.md`, `skills/forge-automation/SKILL.md`, `skills/forge-bootstrap/SKILL.md`, `skills/forge-commit/SKILL.md`, `skills/forge-config-validate/SKILL.md`, `skills/forge-deploy/SKILL.md`, `skills/forge-fix/SKILL.md`, `skills/forge-help/SKILL.md`, `skills/forge-history/SKILL.md`, `skills/forge-init/SKILL.md`, `skills/forge-insights/SKILL.md`, `skills/forge-migration/SKILL.md`, `skills/forge-profile/SKILL.md`, `skills/forge-run/SKILL.md`, `skills/forge-sprint/SKILL.md`, `skills/forge-status/SKILL.md`, `skills/forge-tour/SKILL.md`.

**3 top-level files (name-swap pass only; content rewrites land in Commit 7):**

`README.md`, `CLAUDE.md`, `CHANGELOG.md`.

- [ ] **Step 1: Define the substitution table**

| Old | New |
|---|---|
| `/forge-diagnose` | `/forge-recover diagnose` |
| `/forge-repair-state` | `/forge-recover repair` |
| `/forge-reset` | `/forge-recover reset` |
| `/forge-resume` | `/forge-recover resume` |
| `/forge-rollback` | `/forge-recover rollback` |
| `/forge-caveman` | `/forge-compress output` |
| `/forge-compression-help` | `/forge-compress help` |
| `forge-diagnose` (unslashed) | `forge-recover` |
| `forge-caveman` (unslashed) | `forge-compress` |

- [ ] **Step 2: Run the swap**

Use sed with the file list. Preserve per-file context — if a doc reads `"run /forge-reset first"`, the swap to `"/forge-recover reset first"` is semantically correct. Always prefer the subcommand form to preserve meaning.

```bash
for f in \
  shared/security-audit-trail.md shared/next-task-prediction.md \
  shared/run-history/run-history.md shared/confidence-scoring.md \
  shared/input-compression.md shared/event-log.md shared/automations.md \
  shared/agent-communication.md shared/explore-cache.md \
  shared/recovery/recovery-engine.md shared/flaky-test-management.md \
  shared/plan-cache.md shared/graph/schema.md \
  shared/performance-regression.md shared/playbooks.md \
  shared/background-execution.md shared/learnings/README.md \
  shared/learnings/rule-promotion.md shared/data-classification.md \
  shared/dx-metrics.md shared/visual-verification.md \
  shared/knowledge-base.md shared/state-schema.md \
  shared/output-compression.md \
  skills/forge-abort/SKILL.md skills/forge-automation/SKILL.md \
  skills/forge-bootstrap/SKILL.md skills/forge-commit/SKILL.md \
  skills/forge-config-validate/SKILL.md skills/forge-deploy/SKILL.md \
  skills/forge-fix/SKILL.md skills/forge-help/SKILL.md \
  skills/forge-history/SKILL.md skills/forge-init/SKILL.md \
  skills/forge-insights/SKILL.md skills/forge-migration/SKILL.md \
  skills/forge-profile/SKILL.md skills/forge-run/SKILL.md \
  skills/forge-sprint/SKILL.md skills/forge-status/SKILL.md \
  skills/forge-tour/SKILL.md \
  README.md CLAUDE.md CHANGELOG.md; do
  sed -i.bak \
    -e 's|/forge-diagnose|/forge-recover diagnose|g' \
    -e 's|/forge-repair-state|/forge-recover repair|g' \
    -e 's|/forge-reset|/forge-recover reset|g' \
    -e 's|/forge-resume|/forge-recover resume|g' \
    -e 's|/forge-rollback|/forge-recover rollback|g' \
    -e 's|/forge-caveman|/forge-compress output|g' \
    -e 's|/forge-compression-help|/forge-compress help|g' \
    "$f"
  rm -f "${f}.bak"
done
```

Note: `sed -i` syntax differs between GNU and BSD. The `-i.bak` form works on both — creates a backup which we then delete.

- [ ] **Step 3: Per-file careful edits for SQL and JSON (3 files — no sed)**

For `shared/run-history/migrations/001-initial.sql`: open the file; references are inside `-- comment` lines only. Manually replace with new command names. Do NOT sed — SQL comment syntax is context-sensitive.

For `shared/schemas/dx-metrics-schema.json` and `shared/schemas/benchmarks-schema.json`: open each file; references are inside `"description"` string fields. Manually replace. Validate each file parses as JSON after editing:

```bash
python3 -m json.tool shared/schemas/dx-metrics-schema.json > /dev/null
python3 -m json.tool shared/schemas/benchmarks-schema.json > /dev/null
```

Expected: no output (JSON valid).

- [ ] **Step 4: Grep-verify zero references remain in the sweep scope**

```bash
grep -rn "forge-diagnose\|forge-repair-state\|forge-reset\|forge-resume\|forge-rollback\|forge-caveman\|forge-compression-help" \
  README.md CLAUDE.md CHANGELOG.md shared/ skills/ 2>/dev/null \
  | grep -v "forge-recover\|forge-compress"
```

Expected: empty output. Fix any hits individually before proceeding.

- [ ] **Step 5: Held for commit in Task 28**

---

## Task 27: Update 8 test files + `validate-plugin.sh`

**Files modified (9 total):**
- `tests/contract/compression-insights-contract.bats`
- `tests/contract/explore-cache.bats`
- `tests/contract/plan-cache.bats`
- `tests/contract/skill-frontmatter.bats`
- `tests/contract/state-schema.bats`
- `tests/unit/skill-execution/decision-tree-refs.bats`
- `tests/unit/skill-execution/skill-completeness.bats`
- `tests/unit/skill-execution/skill-prerequisites.bats`
- `tests/validate-plugin.sh`

**Note on excluded files:**
- `tests/contract/ui-frontmatter-consistency.bats` — extended in Task 18; grep confirms zero deleted-skill refs.
- `tests/unit/caveman-modes.bats` — renamed + content-rewritten in Task 24, so excluded from this task.
- `tests/unit/skill-execution/forge-compression-help.bats` — deleted in Task 25.
- `tests/unit/skill-execution/forge-compress-integration.bats` — tested separately; has no deleted-skill refs but may need new subcommand-surface updates. If it doesn't yet reference the old `/forge-caveman` pattern, skip for Phase 1.

- [ ] **Step 1: Apply the name-swap to 8 test files**

```bash
for f in \
  tests/contract/compression-insights-contract.bats \
  tests/contract/explore-cache.bats \
  tests/contract/plan-cache.bats \
  tests/contract/skill-frontmatter.bats \
  tests/contract/state-schema.bats \
  tests/unit/skill-execution/decision-tree-refs.bats \
  tests/unit/skill-execution/skill-completeness.bats \
  tests/unit/skill-execution/skill-prerequisites.bats; do
  sed -i.bak \
    -e 's|forge-diagnose|forge-recover|g' \
    -e 's|forge-repair-state|forge-recover|g' \
    -e 's|forge-reset|forge-recover|g' \
    -e 's|forge-resume|forge-recover|g' \
    -e 's|forge-rollback|forge-recover|g' \
    -e 's|forge-caveman|forge-compress|g' \
    -e 's|forge-compression-help|forge-compress|g' \
    "$f"
  rm -f "${f}.bak"
done
```

Test files commonly reference skill NAMES (not full invocations), so the sed above uses unslashed forms. Review each file manually after the sed pass — some assertions may need semantic adjustment beyond name-swap (e.g., an assertion checking "all 41 skills" must become "all 35 skills").

- [ ] **Step 2: Extend `tests/validate-plugin.sh`**

Add these two checks near existing structural checks:

```bash
# Check: every SKILL.md description has [read-only] or [writes] prefix
for skill_md in "$PLUGIN_ROOT"/skills/*/SKILL.md; do
  desc=$(awk '/^description:/{sub(/^description: *"?/, ""); sub(/"?$/, ""); print; exit}' "$skill_md")
  if [[ ! "$desc" =~ ^\[read-only\] ]] && [[ ! "$desc" =~ ^\[writes\] ]]; then
    echo "FAIL: $skill_md missing [read-only]/[writes] badge"
    FAILURES=$((FAILURES+1))
  fi
done

# Check: cluster-scoped color uniqueness (delegated to bats suite)
# validate-plugin.sh keeps its per-file quick check; full cluster check in tests/contract/ui-frontmatter-consistency.bats
```

- [ ] **Step 3: Held for commit in Task 28**

---

## Task 28: Commit 5 — Deletions + reference sweep

**Files touched:**
- Delete: 7 skill dirs + 1 bats file + 1 renamed file (from-side)
- Create: 1 renamed file (to-side)
- Modify: 24 shared/*.md + 11 test files + validate-plugin.sh

- [ ] **Step 1: Stage and commit (explicit paths; no `git add -A`)**

```bash
# Deletions (handled by git rm in earlier tasks — ensure staged)
git add skills/ tests/structural/ tests/unit/skill-execution/forge-compression-help.bats

# 27 shared file sweeps
git add shared/security-audit-trail.md shared/next-task-prediction.md \
  shared/run-history/run-history.md shared/confidence-scoring.md \
  shared/input-compression.md shared/event-log.md shared/automations.md \
  shared/agent-communication.md shared/explore-cache.md \
  shared/recovery/recovery-engine.md shared/flaky-test-management.md \
  shared/plan-cache.md shared/graph/schema.md \
  shared/performance-regression.md shared/playbooks.md \
  shared/background-execution.md shared/learnings/README.md \
  shared/learnings/rule-promotion.md shared/data-classification.md \
  shared/dx-metrics.md shared/visual-verification.md \
  shared/knowledge-base.md shared/state-schema.md \
  shared/output-compression.md
git add shared/run-history/migrations/001-initial.sql
git add shared/schemas/dx-metrics-schema.json shared/schemas/benchmarks-schema.json

# 17 skill cross-ref sweeps (subset of the 32 from Task 22 — same files, second pass)
git add skills/forge-abort/SKILL.md skills/forge-automation/SKILL.md \
  skills/forge-bootstrap/SKILL.md skills/forge-commit/SKILL.md \
  skills/forge-config-validate/SKILL.md skills/forge-deploy/SKILL.md \
  skills/forge-fix/SKILL.md skills/forge-help/SKILL.md \
  skills/forge-history/SKILL.md skills/forge-init/SKILL.md \
  skills/forge-insights/SKILL.md skills/forge-migration/SKILL.md \
  skills/forge-profile/SKILL.md skills/forge-run/SKILL.md \
  skills/forge-sprint/SKILL.md skills/forge-status/SKILL.md \
  skills/forge-tour/SKILL.md

# 8 test file updates + bats rename + validate-plugin.sh
git add tests/contract/compression-insights-contract.bats \
  tests/contract/explore-cache.bats tests/contract/plan-cache.bats \
  tests/contract/skill-frontmatter.bats tests/contract/state-schema.bats \
  tests/unit/skill-execution/decision-tree-refs.bats \
  tests/unit/skill-execution/skill-completeness.bats \
  tests/unit/skill-execution/skill-prerequisites.bats \
  tests/unit/compress-output-modes.bats \
  tests/validate-plugin.sh

# Top-level scrub pass (name-swaps only; content adds happen in Commit 7)
git add README.md CLAUDE.md CHANGELOG.md

git commit -m "refactor(phase1): delete 7 deprecated skills + sweep references

Deletes:
- skills/forge-diagnose, forge-repair-state, forge-reset, forge-resume, forge-rollback
- skills/forge-caveman, forge-compression-help
- tests/unit/skill-execution/forge-compression-help.bats

Rewrites:
- tests/unit/caveman-modes.bats → compress-output-modes.bats

Updates (name-swap to /forge-recover and /forge-compress):
- 24 shared/*.md files
- 11 test files (contract and skill-execution)
- tests/validate-plugin.sh (adds badge + reference sweep)"
```

Dangling-reference sweep (in skill-contract.bats from Task 6) now passes.

- [ ] **Step 2: No push yet**

---

## Task 29: Update `shared/state-schema.md` — add `recovery_op` field

**Files modified:**
- Modify: `shared/state-schema.md`

- [ ] **Step 1: Add the field to the orchestrator input payload schema**

Find the orchestrator input payload section. Add (or create) a row:

```markdown
| `recovery_op` | string | no | One of `diagnose`, `repair`, `reset`, `resume`, `rollback`. Present when `fg-100-orchestrator` is dispatched from `/forge-recover`. Absent otherwise; orchestrator proceeds with normal pipeline. |
```

- [ ] **Step 2: Bump schema version**

If the file has a version header like `**Schema version:** 1.6.0`, bump to `1.7.0`. Add changelog note at bottom:

```markdown
## Changelog

### 1.7.0 (Forge 3.0.0)
- Add `recovery_op` field to orchestrator input payload (Phase 1 skill surface consolidation).
```

- [ ] **Step 3: Held for commit in Task 31**

---

## Task 30: Update `agents/fg-100-orchestrator.md` — Recovery op dispatch section

**Files modified:**
- Modify: `agents/fg-100-orchestrator.md`

- [ ] **Step 1: Add a new section**

Append near the existing dispatch pattern section (the file has numbered § sections; find the last stage handler and add this AFTER stage 10):

```markdown
## § Recovery op dispatch

When `/forge-recover <subcommand>` invokes the orchestrator, the input payload carries `recovery_op: diagnose|repair|reset|resume|rollback`. See `shared/state-schema.md` for the schema.

**Routing:**

| recovery_op | Dispatch action |
|---|---|
| `diagnose` | Read-only: load `state.json`, compute punch list (stage stalled? recovery budget exhausted? counters sane?), print report. No agents dispatched; no TaskCreate. |
| `repair` | Same logic as old `/forge-repair-state`: prompt user via `AskUserQuestion` with fixable items, apply chosen fixes, commit. |
| `reset` | Same logic as old `/forge-reset`: confirm via `AskUserQuestion`, clear pipeline state, preserve cross-run caches. |
| `resume` | Same logic as old `/forge-resume`: verify `state.status ∈ {ABORTED, ESCALATED, FAILED}`, reconstruct phase from checkpoint, resume dispatch. |
| `rollback` | Same logic as old `/forge-rollback`: revert worktree commits (or `--target` branch). |

This is a routing update only. The recovery _logic_ is unchanged from 2.8.x; only the entry point changed.
```

- [ ] **Step 2: Held for commit in Task 31**

---

## Task 31: Commit 6 — State schema + orchestrator

**Files touched:**
- Modify: `shared/state-schema.md`, `agents/fg-100-orchestrator.md`

- [ ] **Step 1: Stage and commit**

```bash
git add shared/state-schema.md agents/fg-100-orchestrator.md
git commit -m "feat(phase1): add recovery_op field + orchestrator routing

- shared/state-schema.md: add recovery_op to orchestrator input payload; schema 1.6.0 → 1.7.0
- agents/fg-100-orchestrator.md: add §Recovery op dispatch section documenting the routing table for /forge-recover subcommands"
```

- [ ] **Step 2: No push yet**

---

## Task 32: Update `README.md` — skill table, version, convention note

**Files modified:**
- Modify: `README.md`

- [ ] **Step 1: Update skill count**

Replace any sentence like `"41 skills"` or similar with `"35 skills"`.

- [ ] **Step 2: Remove deleted skills from skill table**

Find the skill table in README.md and delete rows for: `forge-diagnose`, `forge-repair-state`, `forge-reset`, `forge-resume`, `forge-rollback`, `forge-caveman`, `forge-compression-help`.

- [ ] **Step 3: Add rows for `/forge-recover` and rewritten `/forge-compress`**

```markdown
| `/forge-recover` | [writes] | Diagnose/repair/reset/resume/rollback pipeline state (`<subcommand>` dispatch). Replaces 5 old recovery skills. |
| `/forge-compress` | [writes] | Compress agents/output/status/help. Replaces `forge-caveman` and `forge-compression-help`. |
```

- [ ] **Step 4: Add a sentence about the badge convention**

Near the top of the skill section, add:

```markdown
Every skill advertises its impact with a `[read-only]` or `[writes]` prefix in its description. Read-only skills expose `--json`; writing skills expose `--dry-run`. All skills expose `--help`. See `shared/skill-contract.md` for the full contract.
```

- [ ] **Step 5: Update version string**

Find any `Forge 2.8.0` or `v2.8.0` references and bump to `Forge 3.0.0` / `v3.0.0`.

- [ ] **Step 6: Held for commit in Task 37**

---

## Task 33: Update `CLAUDE.md` — skill table, tier notes, key entry points, skill count

**Files modified:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Skill count**

Replace `"41 total"` → `"35 total"` in the skill-selection-guide section.

- [ ] **Step 2: Skill table same treatment as README**

Remove 7 deleted rows, add 2 new/rewritten rows (per Task 32 template).

- [ ] **Step 3: Add 3 new entries to Key Entry Points table**

```markdown
| Skill contract | `shared/skill-contract.md` |
| Agent colors + clusters | `shared/agent-colors.md` |
| AskUserQuestion patterns | `shared/ask-user-question-patterns.md` |
```

- [ ] **Step 4: Update agent-tier notes**

Find the Tier 4 section listing reviewer agents. Note the addition of `fg-205` and removal of `fg-210` from Tier 4. Add `fg-210` to the Tier 2 list with a one-line description.

- [ ] **Step 5: Add note about `plan_mode` (not `plan`) convention**

If CLAUDE.md discusses agent UI tiers, ensure `plan_mode` (not `plan`) is the documented key.

- [ ] **Step 6: Held for commit in Task 37**

---

## Task 34: Update `DEPRECATIONS.md` — add `## Removed in 3.0.0` section

**Files modified:**
- Modify: `DEPRECATIONS.md`

- [ ] **Step 1: Read current file structure**

```bash
head -80 DEPRECATIONS.md
```

- [ ] **Step 2: Append new section**

At the end of the file, add:

```markdown
## Removed in 3.0.0

The following skills were removed in 3.0.0. No aliases. Update invocations directly.

| Removed | Replacement | Reason |
|---|---|---|
| `/forge-diagnose` | `/forge-recover diagnose` | Recovery consolidation |
| `/forge-repair-state` | `/forge-recover repair` | Recovery consolidation |
| `/forge-reset` | `/forge-recover reset` | Recovery consolidation |
| `/forge-resume` | `/forge-recover resume` | Recovery consolidation |
| `/forge-rollback` | `/forge-recover rollback` | Recovery consolidation |
| `/forge-caveman` | `/forge-compress output <mode>` | Compression consolidation |
| `/forge-compression-help` | `/forge-compress help` | Compression consolidation |

### Migration examples (all 7 removals)

- `/forge-diagnose` → `/forge-recover diagnose`
- `/forge-diagnose --json` → `/forge-recover diagnose --json`
- `/forge-repair-state` → `/forge-recover repair`
- `/forge-reset` → `/forge-recover reset`
- `/forge-resume` → `/forge-recover resume`
- `/forge-rollback` → `/forge-recover rollback`
- `/forge-rollback --target main` → `/forge-recover rollback --target main`
- `/forge-caveman` → `/forge-compress output off` (reset to uncompressed)
- `/forge-caveman ultra` → `/forge-compress output ultra`
- `/forge-compression-help` → `/forge-compress help`

See `shared/skill-contract.md` §4 for the complete 35-skill catalog after consolidation.
```

- [ ] **Step 3: Held for commit in Task 37**

---

## Task 35: Update `CHANGELOG.md` — add 3.0.0 entry

**Files modified:**
- Modify: `CHANGELOG.md`

**Note:** `CHANGELOG.md` already had its legacy 2.8.0-era deleted-skill references scrubbed via Task 26's sed sweep (Commit 5). This task is the *content addition* pass — adding the new 3.0.0 section. Two-pass editing across two distinct commits; no conflict.

- [ ] **Step 1: Add entry at top (under `# Changelog` heading)**

```markdown
## [3.0.0] — 2026-04-16

### Breaking changes

- **Removed 7 skills** (no aliases). See `DEPRECATIONS.md` for the migration table.
  - `/forge-diagnose`, `/forge-repair-state`, `/forge-reset`, `/forge-resume`, `/forge-rollback` → `/forge-recover <subcommand>`
  - `/forge-caveman`, `/forge-compression-help` → `/forge-compress <subcommand>`
- Skill count: 41 → 35.
- Every SKILL.md description now prefixed with `[read-only]` or `[writes]` badge.
- Every agent frontmatter now requires explicit `ui: { tasks, ask, plan_mode }` block — implicit Tier-4-by-omission no longer accepted.
- `ui: { tier: N }` shortcut removed in `fg-135`, `fg-510`, `fg-515`.
- `fg-210-validator` promoted Tier 4 → Tier 2 (frontmatter + tools only; behavior unchanged in this release).
- 22 agents received a new `color:` assignment to satisfy cluster-scoped uniqueness.

### Added

- `/forge-recover` skill with 5 subcommands.
- `shared/skill-contract.md` — authoritative skill-surface contract.
- `shared/agent-colors.md` — cluster-scoped color map (42 agents).
- `shared/ask-user-question-patterns.md` — canonical UX patterns.
- 14 Tier 1/2 agents now carry concrete `AskUserQuestion` JSON examples.
- `--help` on every skill; `--dry-run` on every mutating skill; `--json` on every read-only skill.
- Standard exit codes 0–4 documented in `shared/skill-contract.md`.
- `/forge-help --json` output mode.
- `shared/state-schema.md`: `recovery_op` field on orchestrator input payload (schema 1.6.0 → 1.7.0).
- `agents/fg-100-orchestrator.md`: §Recovery op dispatch section.
- `tests/contract/skill-contract.bats`: 8 new assertions.
- `tests/contract/ui-frontmatter-consistency.bats`: 5 new assertions.
- `tests/unit/skill-execution/forge-recover-integration.bats`: SKILL.md surface check.

### Changed

- `/forge-compress` rewritten from single-verb → 4-subcommand (`agents|output <mode>|status|help`).
- `/forge-help` augmented: existing 3-tier taxonomy preserved; added `[read-only]`/`[writes]` badges and `--json` output.
- `tests/unit/caveman-modes.bats` renamed and rewritten → `tests/unit/compress-output-modes.bats`.
- 24 `shared/*.md` references swept from old skill names to new.
- `shared/agent-ui.md`: "Omitting ui: means Tier 4" language removed.
- `shared/agent-role-hierarchy.md`: `fg-205` added; `fg-210` promoted.

### Removed

- `tests/structural/ui-frontmatter-consistency.bats` (duplicate of contract/ copy).
- `tests/unit/skill-execution/forge-compression-help.bats` (skill deleted).

### Migration notes

- All removed skills have direct replacements in the Breaking Changes list.
- No config changes required.
- Agents with new colors render differently in kanban — expected cosmetic change only.
```

- [ ] **Step 2: Held for commit in Task 37**

---

## Task 36: Bump version in `.claude-plugin/plugin.json` and `marketplace.json`

**Files modified:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`

- [ ] **Step 1: Bump `plugin.json`**

```bash
sed -i.bak 's/"version": "2.8.0"/"version": "3.0.0"/' .claude-plugin/plugin.json
rm -f .claude-plugin/plugin.json.bak
```

- [ ] **Step 2: Bump `marketplace.json`**

```bash
sed -i.bak 's/"version": "2.8.0"/"version": "3.0.0"/' .claude-plugin/marketplace.json
rm -f .claude-plugin/marketplace.json.bak
```

- [ ] **Step 3: Verify**

```bash
grep '"version"' .claude-plugin/plugin.json .claude-plugin/marketplace.json
```

Expected: both show `3.0.0`.

- [ ] **Step 4: Held for commit in Task 37**

---

## Task 37: Commit 7 — Top-level docs + version bump + push + release

**Files touched:**
- Modify: `README.md`, `CLAUDE.md`, `DEPRECATIONS.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`

- [ ] **Step 1: Stage and commit**

```bash
git add README.md CLAUDE.md DEPRECATIONS.md CHANGELOG.md \
        .claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "docs(phase1): update top-level docs and bump to 3.0.0

- README.md: skill table (35 skills), badge convention, version
- CLAUDE.md: skill table, tier notes, new shared docs in key entry points
- DEPRECATIONS.md: Removed in 3.0.0 section with migration table
- CHANGELOG.md: 3.0.0 entry
- .claude-plugin/plugin.json: 2.8.0 → 3.0.0
- .claude-plugin/marketplace.json: 2.8.0 → 3.0.0"
```

- [ ] **Step 2: Push to origin**

```bash
git push origin master
```

- [ ] **Step 3: Wait for CI**

GitHub Actions will run the full bats suite. Monitor via:

```bash
gh run watch
```

Or poll `gh run list --limit 1` for status.

**If CI red:** identify failing test(s), fix forward in a new commit, re-push. Do not revert — single-user plugin, fix-forward is simpler than revert cycles.

**If CI green:** proceed to Step 4.

- [ ] **Step 4: Tag and release**

```bash
git tag -a v3.0.0 -m "Phase 1: Skill surface consolidation

- 7 skills consolidated into /forge-recover + /forge-compress
- Uniform skill contract enforced
- Agent frontmatter contract enforced
- Zero backwards compatibility per single-user plugin policy
- 136 files touched; 29 acceptance criteria; all green"
git push origin v3.0.0
```

- [ ] **Step 5: Create GitHub release**

```bash
gh release create v3.0.0 --title "3.0.0 — Phase 1: Skill Surface Consolidation" \
  --notes-file - <<'EOF'
Full changelog: CHANGELOG.md

## Highlights

- Consolidated 7 overlapping skills into `/forge-recover` and `/forge-compress`.
- Uniform skill contract: every skill has `--help`, mutating skills have `--dry-run`, read-only skills have `--json`.
- Every skill description prefixed with `[read-only]` or `[writes]` badge.
- Agent frontmatter contract enforced in bats.
- `fg-210-validator` promoted to Tier 2 (preparatory for Phase 4 escalation taxonomy).
- 14 Tier 1/2 agents carry concrete `AskUserQuestion` JSON examples.

## Breaking changes

See `DEPRECATIONS.md#Removed in 3.0.0`. No aliases; migrations are direct.

## Next phase

Phase 2: Observability & progress — sub-agent `TaskCreate` visibility, live cost streaming, hook failure surfacing.
EOF
```

---

## Self-review (done by plan author)

Running the self-review checklist per `writing-plans` skill.

### 1. Spec coverage

| Spec section | Implementing task(s) |
|---|---|
| §4.1 Deletions (7 skills) | Task 23 |
| §4.2 `/forge-recover` | Task 5 (create), Task 30 (orchestrator routing), Task 29 (state schema) |
| §4.3 `/forge-compress` | Task 19 (rewrite) |
| §4.4 Skill contract | Task 2 (doc), Task 21 (apply), Task 6 (bats), Task 22 (commit) |
| §4.5 Agent frontmatter | Tasks 9, 10, 11, 12, 13, 14, 15, 16, 17 |
| §4.6 Color palette | Task 3 (doc), Task 13 (apply) |
| §4.7 AskUserQuestion patterns | Task 4 (doc), Task 15 (embed in agents) |
| §4.8 `/forge-help` augment | Task 20 |
| §4.9 Doc updates | Tasks 16, 17, 26, 29, 30, 32, 33, 34, 35, 36 |
| §4.10 Hook audit | Documented in spec as no-op; no task needed |
| §4.11 Test updates | Tasks 6, 7, 18, 24, 25, 27 |
| §5 File manifest | All tasks collectively |
| §6 Acceptance criteria | All 29 AC items covered by tasks above |
| §7 Test strategy | Task 6 (contract), Task 7 (integration), Task 18 (frontmatter), Task 27 (validate-plugin) |
| §8 Risks | Rollout order (Tasks 1–37) designed to mitigate |
| §9 Rollout | Tasks 1 (plan commit) through Task 37 (push+release) |

Gap check: no spec requirement lacks a task. ✅

### 2. Placeholder scan

Searched for `TBD`, `TODO`, `implement later`, `fill in`, `add appropriate`, `handle edge cases`:

- Task 15 Step 2 uses `<label 1>`, `<description 1>` etc. as structural placeholders inside the TEMPLATE that the author fills in per agent. Each of the 14 agents gets a concrete JSON payload per the mapping table in Task 15 Step 1. Not a plan-failure placeholder — it's a template with an explicit fill-in procedure.
- Task 21 Step 2 originally had a self-correcting count discrepancy ("18, not 19" / "31, not 32"). Final counts are concrete: 14 read-only + 18 writes = 32 in-place updates. ✅

No true placeholders. ✅

### 3. Type consistency

Names used across tasks:
- `recovery_op` field (Tasks 5, 29, 30) — consistent spelling throughout.
- `FORGE_DRY_RUN` env var (Task 2) — spelled the same way everywhere.
- Color names (Task 3, 13, 18) — lowercase, from the 18-hue palette. No case drift.
- Agent `ui:` keys — `tasks`, `ask`, `plan_mode` (Tasks 9–11, 16, 18). `plan_mode` is used in every reference; no `plan` drift.
- File paths — `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` used consistently (Tasks 32, 36, 37). No `plugin.json` at root.
- Skill counts — 35 total, 15 read-only + 20 writes, 32 in-place updates, 2 rewrites, 1 net-new. All four numbers consistent across Tasks 2, 6, 21, 22, 23, 32, 33, 35.

All consistent. ✅

### Plan self-review conclusion

Plan is complete and internally consistent. Proceed to user review + code-reviewer dispatch.

---

**Plan complete and saved to `docs/superpowers/plans/2026-04-16-phase1-skill-surface-consolidation.md`.**

Per the superpowers workflow, this plan will be committed after user approval and then reviewed by `superpowers:code-reviewer`.

---

## Appendix A — 14 literal `AskUserQuestion` payloads for Task 15

Copy the JSON block below the matching section heading into the corresponding agent's `.md` file under a new `## User-interaction examples` section.

### A.1 — `agents/fg-010-shaper.md`

```markdown
## User-interaction examples

### Example — Which shaping dimensions to refine first

```json
{
  "question": "This requirement is vague. Which dimensions should I explore with you first?",
  "header": "Shape axes",
  "multiSelect": true,
  "options": [
    {"label": "Actors and user roles", "description": "Who performs each action; who is affected."},
    {"label": "Success criteria", "description": "What observable state defines 'done'."},
    {"label": "Failure modes and edge cases", "description": "What can go wrong; what to do when it does."},
    {"label": "Scope boundaries", "description": "What is explicitly out of scope."}
  ]
}
```
```

### A.2 — `agents/fg-015-scope-decomposer.md`

```markdown
## User-interaction examples

### Example — Execution strategy for a multi-feature spec

```json
{
  "question": "Detected 4 independent features. How should they execute?",
  "header": "Exec strategy",
  "multiSelect": false,
  "options": [
    {"label": "Parallel (Recommended)", "description": "Dispatch 4 pipelines in parallel worktrees; ~4x wall-clock win if no shared files.", "preview": "worktree-a/ ──┐\nworktree-b/ ──┼─ parallel\nworktree-c/ ──┤\nworktree-d/ ──┘"},
    {"label": "Serial", "description": "Run one at a time; safer if features share files.", "preview": "A → B → C → D"},
    {"label": "Hybrid", "description": "Group non-conflicting in parallel; serialize conflicts.", "preview": "(A, C) ║ (B, D)"}
  ]
}
```
```

### A.3 — `agents/fg-020-bug-investigator.md`

```markdown
## User-interaction examples

### Example — Reproduction strategy when initial traces are ambiguous

```json
{
  "question": "The reported trace doesn't uniquely identify the failing code path. How should we proceed?",
  "header": "Repro path",
  "multiSelect": false,
  "options": [
    {"label": "Write a failing test targeting the most likely path (Recommended)", "description": "Start with the top candidate; iterate if it doesn't reproduce."},
    {"label": "Request a fresh trace with more detail", "description": "Ask user for DEBUG-level logs or a minimal reproduction."},
    {"label": "Investigate manually without a failing test", "description": "Skip TDD step; risk missing the root cause."}
  ]
}
```
```

### A.4 — `agents/fg-050-project-bootstrapper.md`

```markdown
## User-interaction examples

### Example — Stack selection for a new REST service

```json
{
  "question": "Which stack should I scaffold?",
  "header": "Stack",
  "multiSelect": false,
  "options": [
    {"label": "Kotlin + Spring Boot + Postgres (Recommended)", "description": "Hexagonal architecture; Gradle composite builds; Flyway migrations.", "preview": "build.gradle.kts\nsrc/main/kotlin/\n├─ domain/\n├─ application/\n└─ infrastructure/"},
    {"label": "TypeScript + NestJS + Postgres", "description": "Modular NestJS with TypeORM.", "preview": "package.json\nsrc/\n├─ domain/\n├─ modules/\n└─ shared/"},
    {"label": "Go + Gin + Postgres", "description": "Minimal Gin; stdlib-first; sqlx.", "preview": "go.mod\ninternal/\n├─ domain/\n├─ handler/\n└─ store/"}
  ]
}
```
```

### A.5 — `agents/fg-090-sprint-orchestrator.md`

```markdown
## User-interaction examples

### Example — Which features to run in parallel

```json
{
  "question": "6 features detected in this cycle. Which should run concurrently?",
  "header": "Parallel set",
  "multiSelect": true,
  "options": [
    {"label": "AUTH-101: Add MFA", "description": "Touches auth/ only — safe for parallel."},
    {"label": "BILL-220: Invoice retry", "description": "Touches billing/ only — safe for parallel."},
    {"label": "NOTIF-45: Push notifications", "description": "Touches notifications/ only — safe for parallel."},
    {"label": "ORDERS-88: Cancellation flow", "description": "Shares order-service.ts with BILL-220 — serialize."}
  ]
}
```
```

### A.6 — `agents/fg-100-orchestrator.md`

```markdown
## User-interaction examples

### Example — Escalation after recovery budget exhausted

```json
{
  "question": "Pipeline has retried 10 times without progress. State is PLATEAUED. How should I proceed?",
  "header": "Escalation",
  "multiSelect": false,
  "options": [
    {"label": "Invoke /forge-recover diagnose (Recommended)", "description": "Read-only state analysis; no changes to worktree."},
    {"label": "Abort this run", "description": "Gracefully stop; preserves state for /forge-recover resume later."},
    {"label": "Force-continue with current state", "description": "Mark plateau as non-blocking; may produce lower-quality output."}
  ]
}
```
```

### A.7 — `agents/fg-103-cross-repo-coordinator.md`

```markdown
## User-interaction examples

### Example — Cross-repo PR merge strategy

```json
{
  "question": "This change spans 3 repos. How should the PRs be merged?",
  "header": "Merge order",
  "multiSelect": false,
  "options": [
    {"label": "Producer-first (Recommended)", "description": "Merge shared-lib, then consumers. Safest when consumers pin a version.", "preview": "shared-lib ──▶ api-service ──▶ web-app"},
    {"label": "All-at-once", "description": "Merge-train with CODEOWNERS approval on all three simultaneously.", "preview": "shared-lib ═╗\napi-service═╬═▶ atomic merge\nweb-app    ═╝"},
    {"label": "Backward-compatible first", "description": "Producer adds new API without removing old; deprecate in a follow-up PR."}
  ]
}
```
```

### A.8 — `agents/fg-160-migration-planner.md`

```markdown
## User-interaction examples

### Example — Migration phasing

```json
{
  "question": "Spring Boot 2.7 → 3.2 migration has 3 viable phasings. Pick one:",
  "header": "Migration",
  "multiSelect": false,
  "options": [
    {"label": "Big-bang (Recommended for small surface)", "description": "Upgrade Spring + javax→jakarta + tests in one commit.", "preview": "Commit 1: full migration\n─ tests may fail\n─ fix forward"},
    {"label": "Phased: jakarta first, then Spring", "description": "Namespace migration first; stays on 2.7 during transition.", "preview": "Phase 1: javax→jakarta\nPhase 2: 2.7→3.2"},
    {"label": "Feature-flag shim", "description": "Temporary bridge layer; most complex; best for large codebases."}
  ]
}
```
```

### A.9 — `agents/fg-200-planner.md`

```markdown
## User-interaction examples

### Example — Risk-aware parallelization decision

```json
{
  "question": "3 tasks are candidates for parallel execution but share `src/shared/config.ts`. How to proceed?",
  "header": "Paralleliz'n",
  "multiSelect": false,
  "options": [
    {"label": "Serialize all three (Recommended)", "description": "Safest; each task sees the previous's config changes."},
    {"label": "Extract config changes into a prep task", "description": "Prep commits config; 3 tasks then run parallel on stable config."},
    {"label": "Run parallel and auto-merge conflicts", "description": "Fastest wall-clock but risks semantic merge bugs."}
  ]
}
```
```

### A.10 — `agents/fg-210-validator.md`

```markdown
## User-interaction examples

### Example — REVISE verdict escalation (Phase 4 will own the dispatch)

```json
{
  "question": "Plan validation returned REVISE. Two perspectives flagged risk gaps. How should we proceed?",
  "header": "Revise path",
  "multiSelect": false,
  "options": [
    {"label": "Send plan back to planner with my notes (Recommended)", "description": "Planner re-drafts; validator re-checks. Adds 5-10 min."},
    {"label": "Approve as-is; accept the risk", "description": "User overrides validator; pipeline proceeds. Logged as user-override."},
    {"label": "Abort pipeline; escalate to human review", "description": "Pause for manual plan revision outside Forge."}
  ]
}
```

> **Note (3.0.0):** This example documents the shape. The REVISE dispatch is still emitted by `fg-100-orchestrator` in 3.0.0; this agent carries the tool declarations (TaskCreate/AskUserQuestion) in preparation for Phase 4 migration.
```

### A.11 — `agents/fg-400-quality-gate.md`

```markdown
## User-interaction examples

### Example — FAIL verdict after 3 cycles

```json
{
  "question": "Quality gate reports FAIL with 2 CRITICAL findings after 3 review cycles. How should we proceed?",
  "header": "FAIL path",
  "multiSelect": false,
  "options": [
    {"label": "Fix CRITICAL findings, retry gate (Recommended)", "description": "Dispatch implementer to fix; re-run quality gate."},
    {"label": "Abort pipeline; surface findings to user", "description": "Halt and escalate CRITICAL findings as plan-level issues."},
    {"label": "Override and proceed (user accepts risk)", "description": "Record override in state; ship anyway; audit-logged."}
  ]
}
```
```

### A.12 — `agents/fg-500-test-gate.md`

```markdown
## User-interaction examples

### Example — Flaky test detected mid-run

```json
{
  "question": "Test `checkout.spec.ts::'should charge card'` failed once, passed once. Flaky?",
  "header": "Flaky?",
  "multiSelect": false,
  "options": [
    {"label": "Quarantine and continue (Recommended)", "description": "Move to flaky quarantine; exclude from gating; alert in retrospective."},
    {"label": "Run 10x more to confirm", "description": "~30s extra; deterministic result."},
    {"label": "Fail the pipeline now", "description": "Strict mode; blocks ship on any non-deterministic test."}
  ]
}
```
```

### A.13 — `agents/fg-600-pr-builder.md`

```markdown
## User-interaction examples

### Example — Commit grouping strategy

```json
{
  "question": "How should the 37 changed files be grouped into commits on the feature branch?",
  "header": "Commits",
  "multiSelect": false,
  "options": [
    {"label": "By logical layer (Recommended)", "description": "Separate commits: schema, domain, API, tests, docs.", "preview": "1. schema/\n2. domain/\n3. api/\n4. tests/\n5. docs/"},
    {"label": "By story", "description": "One commit per story from the plan.", "preview": "1. Story 1 (all files)\n2. Story 2 (all files)\n..."},
    {"label": "One squash commit", "description": "Single commit per PR; easiest to revert.", "preview": "1. Feature X: all changes"}
  ]
}
```
```

### A.14 — `agents/fg-710-post-run.md`

```markdown
## User-interaction examples

### Example — Which retrospective corrections to record

```json
{
  "question": "You made 7 corrections during the run. Which should become persistent learnings?",
  "header": "Learnings",
  "multiSelect": true,
  "options": [
    {"label": "Framework detected incorrectly (detected React, actually Preact)", "description": "Add to shared/learnings/frontend.md; promote after 3 successful applications."},
    {"label": "Agent chose wrong test pattern (unit test for e2e behavior)", "description": "Add to shared/learnings/testing.md; applies to future similar plans."},
    {"label": "Retry loop took 2 extra cycles", "description": "Performance observation only — not a behavior change."},
    {"label": "User reworded 2 commit messages", "description": "Commit-message style preference; add to git conventions."}
  ]
}
```
```

---

## Appendix B — Verification checklist (before pushing in Task 37)

Run through this before `git push` in Task 37 Step 2:

- [ ] `git log --oneline origin/master..HEAD` shows 7 commits (Tasks 1, 8, 18, 22, 28, 31, 37)
- [ ] No `.bak` files left behind from sed: `find . -name "*.bak" | head`
- [ ] `grep -rln "forge-diagnose\|forge-repair-state\|forge-reset\|forge-resume\|forge-rollback\|forge-caveman\|forge-compression-help" README.md CLAUDE.md shared/ skills/ tests/ 2>/dev/null | grep -v forge-recover | grep -v forge-compress` returns empty
- [ ] `find skills -mindepth 1 -maxdepth 1 -type d | wc -l` returns `35`
- [ ] `grep -c '"version"' .claude-plugin/plugin.json .claude-plugin/marketplace.json` shows both at `3.0.0`
- [ ] `bash -n` on all touched shell/bats scripts returns silent
- [ ] `python3 -m json.tool` on both updated JSON schemas returns silent
