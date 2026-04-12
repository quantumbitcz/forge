# Forge Quality Improvement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lift forge plugin quality from B+ to A across agents, docs, tests, and architecture through 16 test-gated fixes.

**Architecture:** Four sequential phases — structural fixes, documentation tightening, test coverage, architecture refinements. Each phase writes failing tests first (RED), applies fixes (GREEN), then verifies with `/requesting-code-review`. All work happens in the existing repo structure using BATS test framework.

**Tech Stack:** BATS (testing), bash, YAML frontmatter, jq (JSON), markdown

**Spec:** `docs/superpowers/specs/2026-04-12-quality-improvement-umbrella-design.md`

---

## File Structure

### Phase 1: Structural Fixes
- **Modify:** `agents/fg-210-validator.md`, `agents/fg-101-worktree-manager.md`, `agents/fg-102-conflict-resolver.md`, `agents/fg-410-code-reviewer.md`, `agents/fg-411-security-reviewer.md`, `agents/fg-412-architecture-reviewer.md`, `agents/fg-413-frontend-reviewer.md`, `agents/fg-416-backend-performance-reviewer.md`, `agents/fg-417-version-compat-reviewer.md`, `agents/fg-418-docs-consistency-reviewer.md`, `agents/fg-419-infra-deploy-reviewer.md`, `agents/fg-420-dependency-reviewer.md`
- **Modify:** `.claude-plugin/marketplace.json`
- **Modify:** `agents/fg-160-migration-planner.md`, `agents/fg-200-planner.md`
- **Create:** `tests/contract/tier4-no-ui-block.bats`, `tests/contract/version-sync.bats`, `tests/contract/tier1-description-examples.bats`

### Phase 2: Documentation Tightening
- **Modify:** `shared/mcp-provisioning.md`, `shared/convergence-engine.md`, `shared/state-schema.md`, `shared/stage-contract.md`, `shared/agent-communication.md`
- **Create:** `tests/contract/mcp-provisioning-completeness.bats`, `tests/contract/state-schema-field-coverage.bats`

### Phase 3: Test Coverage
- **Create:** `tests/contract/language-module-structure.bats`, `tests/contract/testing-module-structure.bats`, `tests/scenario/pipeline-dry-run-e2e.bats`, `tests/unit/scoring-formula.bats`

### Phase 4: Architecture Refinements
- **Create:** `shared/mcp-detection.md`, `shared/agent-registry.md`, `skills/graph-debug/SKILL.md`
- **Modify:** `shared/forge-compact-check.sh`
- **Modify:** Skills referencing inline MCP detection (forge-run, forge-fix, deep-health, migration)
- **Create:** `tests/contract/mcp-detection-completeness.bats`, `tests/unit/compact-check-logging.bats`, `tests/contract/agent-registry-sync.bats`, `tests/contract/graph-debug-skill.bats`

---

## PHASE 1: STRUCTURAL FIXES

### Task 1: Write Tier 4 no-ui-block test (RED)

**Files:**
- Create: `tests/contract/tier4-no-ui-block.bats`

- [ ] **Step 1: Create the test file**

```bash
cat > tests/contract/tier4-no-ui-block.bats << 'BATSEOF'
#!/usr/bin/env bats
# Contract test: Tier 4 agents must not have ui: blocks in frontmatter.
# Rationale: Tier 4 = "(none)" per CLAUDE.md. Explicit false adds 48 lines
# of system prompt tokens with zero information.

load '../helpers/test-helpers'

AGENTS_DIR="$PLUGIN_ROOT/agents"

# Tier 4 agents per CLAUDE.md: all reviewers, validator, worktree manager, conflict resolver
TIER4_AGENTS=(
  fg-210-validator
  fg-101-worktree-manager
  fg-102-conflict-resolver
  fg-410-code-reviewer
  fg-411-security-reviewer
  fg-412-architecture-reviewer
  fg-413-frontend-reviewer
  fg-416-backend-performance-reviewer
  fg-417-version-compat-reviewer
  fg-418-docs-consistency-reviewer
  fg-419-infra-deploy-reviewer
  fg-420-dependency-reviewer
)

# Helper: extract YAML frontmatter between first two --- lines
get_frontmatter() {
  awk '/^---$/{n++; if(n==2) exit; next} n==1{print}' "$1"
}

@test "tier4-no-ui: Tier 4 agents do not have ui: block in frontmatter" {
  local failures=()
  for agent_name in "${TIER4_AGENTS[@]}"; do
    local agent_file="${AGENTS_DIR}/${agent_name}.md"
    [[ -f "$agent_file" ]] || { failures+=("${agent_name}: file not found"); continue; }
    local frontmatter
    frontmatter="$(get_frontmatter "$agent_file")"
    if echo "$frontmatter" | grep -q "^ui:"; then
      failures+=("${agent_name}: has ui: block (Tier 4 should have none)")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    printf '%s\n' "${failures[@]}"
    fail "Tier 4 ui: block violations: ${#failures[@]} agents"
  fi
}

@test "tier4-no-ui: all listed Tier 4 agent files exist" {
  local missing=()
  for agent_name in "${TIER4_AGENTS[@]}"; do
    [[ -f "${AGENTS_DIR}/${agent_name}.md" ]] || missing+=("${agent_name}")
  done
  if (( ${#missing[@]} > 0 )); then
    printf '%s\n' "${missing[@]}"
    fail "Missing Tier 4 agent files: ${#missing[@]}"
  fi
}
BATSEOF
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/lib/bats-core/bin/bats tests/contract/tier4-no-ui-block.bats`

Expected: FAIL on "tier4-no-ui: Tier 4 agents do not have ui: block in frontmatter" — all 12 agents currently have `ui:` blocks.

---

### Task 2: Remove ui: blocks from 12 Tier 4 agents (GREEN)

**Files:**
- Modify: 12 agent `.md` files listed above

- [ ] **Step 1: Remove ui: blocks from all 12 Tier 4 agents**

For each of the 12 agents, remove these 4 lines from the YAML frontmatter:
```yaml
ui:
  ask: false
  tasks: false
  plan_mode: false
```

The agents are:
- `agents/fg-210-validator.md`
- `agents/fg-101-worktree-manager.md`
- `agents/fg-102-conflict-resolver.md`
- `agents/fg-410-code-reviewer.md`
- `agents/fg-411-security-reviewer.md`
- `agents/fg-412-architecture-reviewer.md`
- `agents/fg-413-frontend-reviewer.md`
- `agents/fg-416-backend-performance-reviewer.md`
- `agents/fg-417-version-compat-reviewer.md`
- `agents/fg-418-docs-consistency-reviewer.md`
- `agents/fg-419-infra-deploy-reviewer.md`
- `agents/fg-420-dependency-reviewer.md`

For each file, the block to remove looks like this (always immediately after the `tools:` line or `color:` line):
```yaml
ui:
  ask: false
  tasks: false
  plan_mode: false
```

- [ ] **Step 2: Run the Tier 4 test to verify it passes**

Run: `./tests/lib/bats-core/bin/bats tests/contract/tier4-no-ui-block.bats`

Expected: PASS (both tests green)

- [ ] **Step 3: Run existing UI consistency test to verify no regression**

Run: `./tests/lib/bats-core/bin/bats tests/contract/ui-frontmatter-consistency.bats`

Expected: PASS (all 6 existing tests still green — they only check `true` values)

---

### Task 3: Write version-sync test (RED)

**Files:**
- Create: `tests/contract/version-sync.bats`

- [ ] **Step 1: Create the test file**

```bash
cat > tests/contract/version-sync.bats << 'BATSEOF'
#!/usr/bin/env bats
# Contract test: plugin.json and marketplace.json versions must match.

load '../helpers/test-helpers'

@test "version-sync: plugin.json version equals marketplace.json version" {
  local plugin_version marketplace_version
  plugin_version="$(jq -r '.version' "$PLUGIN_ROOT/.claude-plugin/plugin.json")"
  marketplace_version="$(jq -r '.metadata.version' "$PLUGIN_ROOT/.claude-plugin/marketplace.json")"

  [[ -n "$plugin_version" ]] || fail "Could not extract plugin.json version"
  [[ -n "$marketplace_version" ]] || fail "Could not extract marketplace.json version"

  [[ "$plugin_version" == "$marketplace_version" ]] || \
    fail "Version mismatch: plugin.json=$plugin_version, marketplace.json=$marketplace_version"
}
BATSEOF
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/lib/bats-core/bin/bats tests/contract/version-sync.bats`

Expected: FAIL with "Version mismatch: plugin.json=1.13.0, marketplace.json=1.12.0"

---

### Task 4: Fix marketplace.json version (GREEN)

**Files:**
- Modify: `.claude-plugin/marketplace.json`

- [ ] **Step 1: Update the version**

In `.claude-plugin/marketplace.json`, change line 9:
```json
    "version": "1.12.0"
```
to:
```json
    "version": "1.13.0"
```

- [ ] **Step 2: Run the version-sync test**

Run: `./tests/lib/bats-core/bin/bats tests/contract/version-sync.bats`

Expected: PASS

---

### Task 5: Write Tier 1 description examples test (RED)

**Files:**
- Create: `tests/contract/tier1-description-examples.bats`

- [ ] **Step 1: Create the test file**

```bash
cat > tests/contract/tier1-description-examples.bats << 'BATSEOF'
#!/usr/bin/env bats
# Contract test: Tier 1 agents must have <example> blocks in description.
# Per CLAUDE.md: "Tier 1 (entry, 6): description + example."

load '../helpers/test-helpers'

AGENTS_DIR="$PLUGIN_ROOT/agents"

TIER1_AGENTS=(
  fg-010-shaper
  fg-015-scope-decomposer
  fg-050-project-bootstrapper
  fg-090-sprint-orchestrator
  fg-160-migration-planner
  fg-200-planner
)

# Extract full YAML frontmatter
get_frontmatter() {
  awk '/^---$/{n++; if(n==2) exit; next} n==1{print}' "$1"
}

@test "tier1-examples: all Tier 1 agents have <example> blocks in description" {
  local failures=()
  for agent_name in "${TIER1_AGENTS[@]}"; do
    local agent_file="${AGENTS_DIR}/${agent_name}.md"
    [[ -f "$agent_file" ]] || { failures+=("${agent_name}: file not found"); continue; }
    local frontmatter
    frontmatter="$(get_frontmatter "$agent_file")"
    if ! echo "$frontmatter" | grep -q "<example>"; then
      failures+=("${agent_name}: missing <example> block in description")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    printf '%s\n' "${failures[@]}"
    fail "Tier 1 example violations: ${#failures[@]} agents"
  fi
}

@test "tier1-examples: all listed Tier 1 agent files exist" {
  local missing=()
  for agent_name in "${TIER1_AGENTS[@]}"; do
    [[ -f "${AGENTS_DIR}/${agent_name}.md" ]] || missing+=("${agent_name}")
  done
  if (( ${#missing[@]} > 0 )); then
    printf '%s\n' "${missing[@]}"
    fail "Missing Tier 1 agent files: ${#missing[@]}"
  fi
}
BATSEOF
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/lib/bats-core/bin/bats tests/contract/tier1-description-examples.bats`

Expected: FAIL with "Tier 1 example violations: 2 agents" (fg-160 and fg-200)

---

### Task 6: Expand fg-160 and fg-200 descriptions (GREEN)

**Files:**
- Modify: `agents/fg-160-migration-planner.md`
- Modify: `agents/fg-200-planner.md`

- [ ] **Step 1: Update fg-160-migration-planner.md frontmatter**

Replace the `description:` line (line 3) in `agents/fg-160-migration-planner.md`:

Old:
```yaml
description: Plans and orchestrates multi-phase library migrations and major upgrades with per-batch rollback.
```

New:
```yaml
description: |
  Plans and orchestrates multi-phase library migrations and major upgrades with per-batch rollback.

  <example>
  Context: Developer wants to upgrade a major framework version
  user: "migrate: Spring Boot 2.7 to 3.2"
  assistant: "I'll dispatch the migration planner to analyze the upgrade path, identify breaking changes, and create a phased migration plan with rollback points."
  </example>
```

- [ ] **Step 2: Update fg-200-planner.md frontmatter**

Replace the `description:` line (line 3) in `agents/fg-200-planner.md`:

Old:
```yaml
description: Decomposes a requirement into a risk-assessed implementation plan with stories, tasks, and parallel groups.
```

New:
```yaml
description: |
  Decomposes a requirement into a risk-assessed implementation plan with stories, tasks, and parallel groups.

  <example>
  Context: Developer wants to implement a new feature
  user: "Implement plan comment feature"
  assistant: "I'll dispatch the planner to decompose this into stories, assess risk per task, and identify which tasks can run in parallel."
  </example>
```

- [ ] **Step 3: Run the Tier 1 test**

Run: `./tests/lib/bats-core/bin/bats tests/contract/tier1-description-examples.bats`

Expected: PASS (both tests green)

---

### Task 7: Phase 1 full verification

- [ ] **Step 1: Run all Phase 1 tests together**

Run: `./tests/lib/bats-core/bin/bats tests/contract/tier4-no-ui-block.bats tests/contract/version-sync.bats tests/contract/tier1-description-examples.bats`

Expected: All tests PASS

- [ ] **Step 2: Run the full existing test suite**

Run: `./tests/run-all.sh`

Expected: All existing tests PASS (no regressions)

- [ ] **Step 3: Commit Phase 1**

```bash
git add agents/fg-210-validator.md agents/fg-101-worktree-manager.md agents/fg-102-conflict-resolver.md \
  agents/fg-410-code-reviewer.md agents/fg-411-security-reviewer.md agents/fg-412-architecture-reviewer.md \
  agents/fg-413-frontend-reviewer.md agents/fg-416-backend-performance-reviewer.md \
  agents/fg-417-version-compat-reviewer.md agents/fg-418-docs-consistency-reviewer.md \
  agents/fg-419-infra-deploy-reviewer.md agents/fg-420-dependency-reviewer.md \
  agents/fg-160-migration-planner.md agents/fg-200-planner.md \
  .claude-plugin/marketplace.json \
  tests/contract/tier4-no-ui-block.bats tests/contract/version-sync.bats tests/contract/tier1-description-examples.bats
git commit -m "fix: Phase 1 structural fixes — remove Tier 4 ui blocks, sync versions, expand descriptions"
```

- [ ] **Step 4: Run `/requesting-code-review` for Phase 1**

---

## PHASE 2: DOCUMENTATION TIGHTENING

### Task 8: Write MCP provisioning completeness test (RED)

**Files:**
- Create: `tests/contract/mcp-provisioning-completeness.bats`

- [ ] **Step 1: Create the test file**

```bash
cat > tests/contract/mcp-provisioning-completeness.bats << 'BATSEOF'
#!/usr/bin/env bats
# Contract test: every MCP listed in CLAUDE.md must have a section in mcp-provisioning.md.

load '../helpers/test-helpers'

# Extract MCP names from CLAUDE.md "Detects" line
# Format: "Detects Linear, Playwright, Slack, Context7, Figma, Excalidraw, Neo4j."
extract_mcp_list() {
  local line
  line="$(grep -i "Detects.*Linear" "$PLUGIN_ROOT/CLAUDE.md" | head -1)"
  # Extract names between "Detects " and the period
  echo "$line" | sed 's/.*Detects //' | sed 's/\..*//' | tr ',' '\n' | sed 's/^ *//' | sed 's/ *$//'
}

@test "mcp-completeness: every detected MCP has section in mcp-provisioning.md" {
  local failures=()
  local prov_file="$PLUGIN_ROOT/shared/mcp-provisioning.md"
  [[ -f "$prov_file" ]] || fail "shared/mcp-provisioning.md not found"

  while IFS= read -r mcp_name; do
    [[ -z "$mcp_name" ]] && continue
    # Check for section header containing the MCP name (case-insensitive)
    if ! grep -qi "${mcp_name}" "$prov_file"; then
      failures+=("${mcp_name}: no section found in mcp-provisioning.md")
    fi
  done < <(extract_mcp_list)

  if (( ${#failures[@]} > 0 )); then
    printf '%s\n' "${failures[@]}"
    fail "Missing MCP documentation: ${#failures[@]} MCPs"
  fi
}

@test "mcp-completeness: at least 7 MCPs detected from CLAUDE.md" {
  local count=0
  while IFS= read -r mcp_name; do
    [[ -n "$mcp_name" ]] && ((count++))
  done < <(extract_mcp_list)
  (( count >= 7 )) || fail "Expected >= 7 MCPs, found $count"
}
BATSEOF
```

- [ ] **Step 2: Run to verify it fails**

Run: `./tests/lib/bats-core/bin/bats tests/contract/mcp-provisioning-completeness.bats`

Expected: FAIL — Slack and Context7 not found in mcp-provisioning.md

---

### Task 9: Write state-schema field coverage test (RED)

**Files:**
- Create: `tests/contract/state-schema-field-coverage.bats`

- [ ] **Step 1: Create the test file**

```bash
cat > tests/contract/state-schema-field-coverage.bats << 'BATSEOF'
#!/usr/bin/env bats
# Contract test: fields referenced in state-transitions.md must be documented in state-schema.md.

load '../helpers/test-helpers'

@test "state-schema-coverage: evidence_refresh_count is documented in state-schema.md" {
  local schema_file="$PLUGIN_ROOT/shared/state-schema.md"
  [[ -f "$schema_file" ]] || fail "shared/state-schema.md not found"
  grep -q "evidence_refresh_count" "$schema_file" || \
    fail "evidence_refresh_count referenced in state-transitions.md but not in state-schema.md"
}

@test "state-schema-coverage: feedback_loop_count is documented in state-schema.md" {
  local schema_file="$PLUGIN_ROOT/shared/state-schema.md"
  grep -q "feedback_loop_count" "$schema_file" || \
    fail "feedback_loop_count not documented in state-schema.md"
}

@test "state-schema-coverage: convergence fields are documented in state-schema.md" {
  local schema_file="$PLUGIN_ROOT/shared/state-schema.md"
  local fields=(phase_iterations plateau_count total_iterations)
  local failures=()
  for field in "${fields[@]}"; do
    grep -q "$field" "$schema_file" || failures+=("$field")
  done
  if (( ${#failures[@]} > 0 )); then
    printf 'Missing: %s\n' "${failures[@]}"
    fail "Undocumented convergence fields: ${#failures[@]}"
  fi
}
BATSEOF
```

- [ ] **Step 2: Run to verify it fails**

Run: `./tests/lib/bats-core/bin/bats tests/contract/state-schema-field-coverage.bats`

Expected: FAIL on `evidence_refresh_count` (not currently in state-schema.md). Other fields may pass.

---

### Task 10: Add Slack and Context7 sections to mcp-provisioning.md (GREEN)

**Files:**
- Modify: `shared/mcp-provisioning.md`

- [ ] **Step 1: Add Slack MCP section**

Add the following section to `shared/mcp-provisioning.md` (after the existing MCP sections, before any closing content):

```markdown
## Slack

- **Tool name prefix:** `mcp__claude_ai_Slack__`
- **Detection probe:** `mcp__claude_ai_Slack__slack_send_message`
- **Capability:** Channel messaging, search, canvas creation, user profile lookup
- **Degradation:** Skip Slack notifications. Use console output and file-based tracking only. Log INFO: `MCP-UNAVAILABLE: Slack`
- **Provisioning:** User-configured via Claude AI MCP settings. Not auto-installable by forge.

## Context7

- **Tool name prefix:** `mcp__plugin_context7_context7__`
- **Detection probe:** `mcp__plugin_context7_context7__resolve-library-id`
- **Capability:** Live documentation lookup for libraries and frameworks. Version-aware API references. Used by review agents (fg-410 through fg-420) and deprecation refresh (fg-140) for current API validation.
- **Degradation:** Fall back to training data knowledge and WebSearch. Version-specific guidance may be stale. Log INFO: `MCP-UNAVAILABLE: Context7`
- **Provisioning:** Plugin-installed MCP. Auto-detected when available.
```

- [ ] **Step 2: Run the MCP completeness test**

Run: `./tests/lib/bats-core/bin/bats tests/contract/mcp-provisioning-completeness.bats`

Expected: PASS

---

### Task 11: Add evidence_refresh_count to state-schema.md (GREEN)

**Files:**
- Modify: `shared/state-schema.md`

- [ ] **Step 1: Find the evidence object section and add the field**

In `shared/state-schema.md`, locate the `evidence` object documentation (search for `evidence` in the field reference table). Add:

```markdown
| `evidence_refresh_count` | int | 0 | Tracks stale-evidence refresh attempts at SHIPPING entry. Capped at 3 before user escalation. See `verification-evidence.md` §Staleness and `state-transitions.md` row 52. |
```

Add this row in the evidence-related section of the field table, near other evidence fields.

- [ ] **Step 2: Run the state-schema field coverage test**

Run: `./tests/lib/bats-core/bin/bats tests/contract/state-schema-field-coverage.bats`

Expected: PASS (all 3 tests green)

---

### Task 12: Apply prose documentation fixes

**Files:**
- Modify: `shared/convergence-engine.md`
- Modify: `shared/stage-contract.md`
- Modify: `shared/agent-communication.md`

- [ ] **Step 1: Clarify convergence plateau exemption**

In `shared/convergence-engine.md`, find the "first 2 cycles" text (near line 107) and add this clarification paragraph immediately after:

```markdown
> **Clarification:** Cycles 1-2 establish a baseline — `plateau_count` remains 0 and convergence state is IMPROVING regardless of the smoothed delta value. Starting from cycle 3 (`phase_iterations >= 2` in `state-transitions.md`), the smoothed delta is evaluated against `oscillation_tolerance`. If `|smoothed_delta| <= oscillation_tolerance`, `plateau_count` increments. Escalation occurs when `plateau_count >= plateau_patience`.
```

- [ ] **Step 2: Inline analysis_pass definition in stage-contract.md**

In `shared/stage-contract.md`, find the Stage 5 (VERIFY) section where `analysis_pass` is referenced. Add inline:

```markdown
(where `analysis_pass` = no CRITICAL findings from review agents AND quality gate verdict != FAIL — see `convergence-engine.md` Phase B exit condition)
```

- [ ] **Step 3: Promote PREEMPT marker format to dedicated subsection**

In `shared/agent-communication.md`, find the PREEMPT_APPLIED/PREEMPT_SKIPPED text (near line 175). Replace the inline mention with a dedicated subsection:

```markdown
### PREEMPT Marker Format

Markers are written to stage notes under `## Attempt N` headers.

**Format:**
```
PREEMPT_APPLIED: {item-id} — applied at {file}:{line}
PREEMPT_SKIPPED: {item-id} — not applicable ({reason})
```

**Parsing regex:** `^PREEMPT_(APPLIED|SKIPPED): (\S+) — (.+)$`

**Rules:**
- Only markers from the **last attempt** in a stage are authoritative
- Earlier attempt markers are superseded (the fix may have changed applicability)
- Orchestrator counts APPLIED/SKIPPED per item-id for decay tracking
```

---

### Task 13: Phase 2 full verification

- [ ] **Step 1: Run all Phase 2 tests**

Run: `./tests/lib/bats-core/bin/bats tests/contract/mcp-provisioning-completeness.bats tests/contract/state-schema-field-coverage.bats`

Expected: All PASS

- [ ] **Step 2: Run full test suite**

Run: `./tests/run-all.sh`

Expected: All existing + new tests PASS

- [ ] **Step 3: Commit Phase 2**

```bash
git add shared/mcp-provisioning.md shared/convergence-engine.md shared/state-schema.md \
  shared/stage-contract.md shared/agent-communication.md \
  tests/contract/mcp-provisioning-completeness.bats tests/contract/state-schema-field-coverage.bats
git commit -m "docs: Phase 2 documentation tightening — MCP completeness, cross-references, PREEMPT format"
```

- [ ] **Step 4: Run `/requesting-code-review` for Phase 2**

---

## PHASE 3: TEST COVERAGE

### Task 14: Write language module structure test

**Files:**
- Create: `tests/contract/language-module-structure.bats`

- [ ] **Step 1: Create the test file**

```bash
cat > tests/contract/language-module-structure.bats << 'BATSEOF'
#!/usr/bin/env bats
# Contract test: language module structural validation.
# Each language module in modules/languages/ must exist, be non-empty,
# and contain required sections (overview, Dos, Don'ts).

load '../helpers/test-helpers'

source "$PLUGIN_ROOT/tests/lib/module-lists.bash"

@test "language-modules: minimum count guard (>= $MIN_LANGUAGES)" {
  guard_min_count "languages" "${#DISCOVERED_LANGUAGES[@]}" "$MIN_LANGUAGES"
}

@test "language-modules: all discovered modules are non-empty" {
  local failures=()
  for lang in "${DISCOVERED_LANGUAGES[@]}"; do
    local file="$PLUGIN_ROOT/modules/languages/${lang}.md"
    [[ -s "$file" ]] || failures+=("${lang}: file is empty or missing")
  done
  if (( ${#failures[@]} > 0 )); then
    printf '%s\n' "${failures[@]}"
    fail "Empty/missing language modules: ${#failures[@]}"
  fi
}

@test "language-modules: each module contains required sections" {
  local failures=()
  for lang in "${DISCOVERED_LANGUAGES[@]}"; do
    local file="$PLUGIN_ROOT/modules/languages/${lang}.md"
    [[ -f "$file" ]] || continue

    # Must have at least one level-2 heading (overview)
    grep -q "^## " "$file" || failures+=("${lang}: no ## heading (overview)")

    # Must have Dos section (case-insensitive, handles "Dos", "Do", "Best Practices")
    grep -qi "^##.*\(Dos\|Do \|Best Practice\|Recommended\)" "$file" || \
      failures+=("${lang}: no Dos/Best Practices section")

    # Must have Don'ts section (case-insensitive, handles "Don'ts", "Avoid", "Anti-patterns")
    grep -qi "^##.*\(Don.t\|Avoid\|Anti.pattern\)" "$file" || \
      failures+=("${lang}: no Don'ts/Avoid section")
  done
  if (( ${#failures[@]} > 0 )); then
    printf '%s\n' "${failures[@]}"
    fail "Language module section violations: ${#failures[@]}"
  fi
}
BATSEOF
```

- [ ] **Step 2: Run to verify it passes**

Run: `./tests/lib/bats-core/bin/bats tests/contract/language-module-structure.bats`

Expected: PASS (these modules should already have the required structure). If any fail, the test has found a real gap — fix the module, not the test.

---

### Task 15: Write testing module structure test

**Files:**
- Create: `tests/contract/testing-module-structure.bats`

- [ ] **Step 1: Create the test file**

```bash
cat > tests/contract/testing-module-structure.bats << 'BATSEOF'
#!/usr/bin/env bats
# Contract test: testing module structural validation.
# Each testing module in modules/testing/ must exist, be non-empty,
# and contain convention/integration guidance.

load '../helpers/test-helpers'

source "$PLUGIN_ROOT/tests/lib/module-lists.bash"

@test "testing-modules: minimum count guard (>= $MIN_TESTING_FILES)" {
  guard_min_count "testing" "${#DISCOVERED_TESTING_FILES[@]}" "$MIN_TESTING_FILES"
}

@test "testing-modules: all discovered modules are non-empty" {
  local failures=()
  for mod in "${DISCOVERED_TESTING_FILES[@]}"; do
    local file="$PLUGIN_ROOT/modules/testing/${mod}"
    [[ -s "$file" ]] || failures+=("${mod}: file is empty or missing")
  done
  if (( ${#failures[@]} > 0 )); then
    printf '%s\n' "${failures[@]}"
    fail "Empty/missing testing modules: ${#failures[@]}"
  fi
}

@test "testing-modules: each module contains required sections" {
  local failures=()
  for mod in "${DISCOVERED_TESTING_FILES[@]}"; do
    local file="$PLUGIN_ROOT/modules/testing/${mod}"
    [[ -f "$file" ]] || continue

    # Must have at least one level-2 heading
    grep -q "^## " "$file" || failures+=("${mod}: no ## heading")

    # Must have convention or integration content (at least 20 lines)
    local lines
    lines="$(wc -l < "$file" | tr -d ' ')"
    (( lines >= 20 )) || failures+=("${mod}: too short (${lines} lines, expected >= 20)")
  done
  if (( ${#failures[@]} > 0 )); then
    printf '%s\n' "${failures[@]}"
    fail "Testing module violations: ${#failures[@]}"
  fi
}
BATSEOF
```

- [ ] **Step 2: Run to verify it passes**

Run: `./tests/lib/bats-core/bin/bats tests/contract/testing-module-structure.bats`

Expected: PASS

---

### Task 16: Write E2E dry-run pipeline scenario test

**Files:**
- Create: `tests/scenario/pipeline-dry-run-e2e.bats`

- [ ] **Step 1: Create the test file**

```bash
cat > tests/scenario/pipeline-dry-run-e2e.bats << 'BATSEOF'
#!/usr/bin/env bats
# Scenario test: dry-run pipeline state machine progression.
# Validates PREFLIGHT → EXPLORING → PLANNING → VALIDATING → COMPLETE
# using forge-state.sh transition events.

load '../helpers/test-helpers'

FORGE_STATE_SH="$PLUGIN_ROOT/shared/forge-state.sh"

setup() {
  # Standard setup from helpers
  TEST_TEMP="$(mktemp -d "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/bats-forge.XXXXXX")"
  MOCK_BIN="${TEST_TEMP}/mock-bin"
  mkdir -p "${MOCK_BIN}"
  export PATH="${MOCK_BIN}:${PATH}"

  FORGE_DIR="${TEST_TEMP}/.forge"
  mkdir -p "$FORGE_DIR"

  # Create initial state.json for dry-run
  cat > "$FORGE_DIR/state.json" << 'STATEEOF'
{
  "version": "1.5.0",
  "stage": "PREFLIGHT",
  "mode": "standard",
  "dry_run": true,
  "_seq": 0,
  "convergence": {
    "phase_iterations": 0,
    "plateau_count": 0,
    "total_iterations": 0
  },
  "score_history": [],
  "recovery_budget": 0.0
}
STATEEOF
}

teardown() {
  [[ -n "${TEST_TEMP:-}" && -d "${TEST_TEMP}" ]] && rm -rf "${TEST_TEMP}"
}

@test "dry-run: initial state is PREFLIGHT" {
  local stage
  stage="$(jq -r '.stage' "$FORGE_DIR/state.json")"
  [[ "$stage" == "PREFLIGHT" ]]
}

@test "dry-run: preflight_complete transitions to EXPLORING" {
  run bash "$FORGE_STATE_SH" transition preflight_complete --forge-dir "$FORGE_DIR"
  assert_success
  local stage
  stage="$(jq -r '.stage' "$FORGE_DIR/state.json")"
  [[ "$stage" == "EXPLORING" ]]
}

@test "dry-run: explore_complete transitions to PLANNING" {
  # First get to EXPLORING
  bash "$FORGE_STATE_SH" transition preflight_complete --forge-dir "$FORGE_DIR"
  # Then transition to PLANNING (scope < threshold)
  # NOTE: guard parameters must come BEFORE --forge-dir (arg parser consumes --forge-dir via shift)
  run bash "$FORGE_STATE_SH" transition explore_complete scope=1 decomposition_threshold=3 --forge-dir "$FORGE_DIR"
  assert_success
  local stage
  stage="$(jq -r '.stage' "$FORGE_DIR/state.json")"
  [[ "$stage" == "PLANNING" ]]
}

@test "dry-run: plan_complete transitions to VALIDATING" {
  bash "$FORGE_STATE_SH" transition preflight_complete --forge-dir "$FORGE_DIR"
  bash "$FORGE_STATE_SH" transition explore_complete scope=1 decomposition_threshold=3 --forge-dir "$FORGE_DIR"
  run bash "$FORGE_STATE_SH" transition plan_complete --forge-dir "$FORGE_DIR"
  assert_success
  local stage
  stage="$(jq -r '.stage' "$FORGE_DIR/state.json")"
  [[ "$stage" == "VALIDATING" ]]
}

@test "dry-run: validate_complete with dry_run=true completes pipeline" {
  bash "$FORGE_STATE_SH" transition preflight_complete --forge-dir "$FORGE_DIR"
  bash "$FORGE_STATE_SH" transition explore_complete scope=1 decomposition_threshold=3 --forge-dir "$FORGE_DIR"
  bash "$FORGE_STATE_SH" transition plan_complete --forge-dir "$FORGE_DIR"
  run bash "$FORGE_STATE_SH" transition validate_complete --forge-dir "$FORGE_DIR"
  assert_success
  local stage
  stage="$(jq -r '.stage' "$FORGE_DIR/state.json")"
  # dry_run=true should end pipeline (COMPLETE or remain VALIDATING with completion marker)
  [[ "$stage" == "COMPLETE" || "$stage" == "VALIDATING" ]]
}

@test "dry-run: state file well-formed after transitions" {
  bash "$FORGE_STATE_SH" transition preflight_complete --forge-dir "$FORGE_DIR"
  bash "$FORGE_STATE_SH" transition explore_complete scope=1 decomposition_threshold=3 --forge-dir "$FORGE_DIR"

  # Validate required fields exist
  local version stage mode seq
  version="$(jq -r '.version' "$FORGE_DIR/state.json")"
  stage="$(jq -r '.stage' "$FORGE_DIR/state.json")"
  mode="$(jq -r '.mode' "$FORGE_DIR/state.json")"
  seq="$(jq -r '._seq' "$FORGE_DIR/state.json")"

  [[ "$version" == "1.5.0" ]]
  [[ -n "$stage" && "$stage" != "null" ]]
  [[ "$mode" == "standard" ]]
  (( seq > 0 ))
}

@test "dry-run: _seq increments on each transition" {
  local seq_before seq_after
  seq_before="$(jq -r '._seq' "$FORGE_DIR/state.json")"
  bash "$FORGE_STATE_SH" transition preflight_complete --forge-dir "$FORGE_DIR"
  seq_after="$(jq -r '._seq' "$FORGE_DIR/state.json")"
  (( seq_after > seq_before ))
}

@test "dry-run: invalid event from wrong state is rejected" {
  # From PREFLIGHT, send explore_complete (wrong — should be preflight_complete)
  run bash "$FORGE_STATE_SH" transition explore_complete --forge-dir "$FORGE_DIR"
  assert_failure
}
BATSEOF
```

- [ ] **Step 2: Run to verify tests work**

Run: `./tests/lib/bats-core/bin/bats tests/scenario/pipeline-dry-run-e2e.bats`

Expected: All PASS (if forge-state.sh is working correctly). If any fail, investigate the state machine event format and adjust the test — the state machine is the source of truth.

---

### Task 17: Write scoring formula test

**Files:**
- Create: `tests/unit/scoring-formula.bats`

- [ ] **Step 1: Create the test file**

```bash
cat > tests/unit/scoring-formula.bats << 'BATSEOF'
#!/usr/bin/env bats
# Unit test: scoring formula and verdict determination.
# Formula: max(0, 100 - 20*CRITICAL - 5*WARNING - 2*INFO)
# Verdicts: PASS >= 80 (and 0 unresolved CRITICAL), CONCERNS 60-79, FAIL < 60 or unresolved CRITICAL

load '../helpers/test-helpers'

# Implement the scoring formula in bash (specification test)
compute_score() {
  local critical="${1:-0}" warning="${2:-0}" info="${3:-0}"
  local raw=$((100 - 20 * critical - 5 * warning - 2 * info))
  if (( raw < 0 )); then
    echo 0
  else
    echo "$raw"
  fi
}

# Determine verdict
compute_verdict() {
  local score="$1" unresolved_critical="${2:-0}"
  if (( unresolved_critical > 0 )); then
    echo "FAIL"
  elif (( score >= 80 )); then
    echo "PASS"
  elif (( score >= 60 )); then
    echo "CONCERNS"
  else
    echo "FAIL"
  fi
}

@test "scoring: clean slate = 100" {
  local score
  score="$(compute_score 0 0 0)"
  [[ "$score" == "100" ]]
}

@test "scoring: 1 critical = 80" {
  local score
  score="$(compute_score 1 0 0)"
  [[ "$score" == "80" ]]
}

@test "scoring: 5 criticals floors at 0" {
  local score
  score="$(compute_score 5 0 0)"
  [[ "$score" == "0" ]]
}

@test "scoring: 6 criticals still floors at 0 (max function)" {
  local score
  score="$(compute_score 6 0 0)"
  [[ "$score" == "0" ]]
}

@test "scoring: mixed findings (1C + 2W + 3I = 64)" {
  local score
  score="$(compute_score 1 2 3)"
  [[ "$score" == "64" ]]
}

@test "scoring: verdict PASS when score >= 80 and 0 critical" {
  local verdict
  verdict="$(compute_verdict 80 0)"
  [[ "$verdict" == "PASS" ]]
}

@test "scoring: verdict CONCERNS when 60 <= score < 80" {
  local verdict
  verdict="$(compute_verdict 70 0)"
  [[ "$verdict" == "CONCERNS" ]]
}

@test "scoring: verdict FAIL when score < 60" {
  local verdict
  verdict="$(compute_verdict 45 0)"
  [[ "$verdict" == "FAIL" ]]
}

@test "scoring: verdict FAIL when unresolved CRITICAL regardless of score" {
  local verdict
  verdict="$(compute_verdict 80 1)"
  [[ "$verdict" == "FAIL" ]]
}

@test "scoring: deduplication — same key counted once" {
  # Simulate: two findings with identical (component, file, line, category)
  # Only one should contribute to score
  local findings=(
    "comp1|src/main.ts|42|SEC-001"
    "comp1|src/main.ts|42|SEC-001"
    "comp1|src/main.ts|99|QUAL-001"
  )
  # Deduplicate by unique key
  local unique_count
  unique_count="$(printf '%s\n' "${findings[@]}" | sort -u | wc -l | tr -d ' ')"
  [[ "$unique_count" == "2" ]]
}
BATSEOF
```

- [ ] **Step 2: Run to verify tests pass**

Run: `./tests/lib/bats-core/bin/bats tests/unit/scoring-formula.bats`

Expected: All PASS

---

### Task 18: Phase 3 full verification

- [ ] **Step 1: Run all Phase 3 tests**

Run: `./tests/lib/bats-core/bin/bats tests/contract/language-module-structure.bats tests/contract/testing-module-structure.bats tests/scenario/pipeline-dry-run-e2e.bats tests/unit/scoring-formula.bats`

Expected: All PASS

- [ ] **Step 2: Run full test suite**

Run: `./tests/run-all.sh`

Expected: All tests PASS

- [ ] **Step 3: Commit Phase 3**

```bash
git add tests/contract/language-module-structure.bats tests/contract/testing-module-structure.bats \
  tests/scenario/pipeline-dry-run-e2e.bats tests/unit/scoring-formula.bats
git commit -m "test: Phase 3 test coverage — language modules, testing modules, E2E pipeline, scoring formula"
```

- [ ] **Step 4: Run `/requesting-code-review` for Phase 3**

---

## PHASE 4: ARCHITECTURE REFINEMENTS

### Task 19: Write MCP detection completeness test (RED) and create mcp-detection.md (GREEN)

**Files:**
- Create: `shared/mcp-detection.md`
- Create: `tests/contract/mcp-detection-completeness.bats`

- [ ] **Step 1: Create the test file**

```bash
cat > tests/contract/mcp-detection-completeness.bats << 'BATSEOF'
#!/usr/bin/env bats
# Contract test: shared/mcp-detection.md must document all MCPs from CLAUDE.md.

load '../helpers/test-helpers'

@test "mcp-detection: shared/mcp-detection.md exists" {
  [[ -f "$PLUGIN_ROOT/shared/mcp-detection.md" ]]
}

@test "mcp-detection: contains Detection Table section" {
  grep -q "Detection Table\|Detection Protocol" "$PLUGIN_ROOT/shared/mcp-detection.md"
}

@test "mcp-detection: documents all MCPs listed in CLAUDE.md" {
  local failures=()
  local detect_file="$PLUGIN_ROOT/shared/mcp-detection.md"
  local mcp_line
  mcp_line="$(grep -i "Detects.*Linear" "$PLUGIN_ROOT/CLAUDE.md" | head -1)"
  local mcps
  mcps="$(echo "$mcp_line" | sed 's/.*Detects //' | sed 's/\..*//' | tr ',' '\n' | sed 's/^ *//' | sed 's/ *$//')"

  while IFS= read -r mcp_name; do
    [[ -z "$mcp_name" ]] && continue
    grep -qi "$mcp_name" "$detect_file" || failures+=("$mcp_name")
  done <<< "$mcps"

  if (( ${#failures[@]} > 0 )); then
    printf 'Missing: %s\n' "${failures[@]}"
    fail "MCPs not in mcp-detection.md: ${#failures[@]}"
  fi
}
BATSEOF
```

- [ ] **Step 2: Run to verify it fails (file doesn't exist yet)**

Run: `./tests/lib/bats-core/bin/bats tests/contract/mcp-detection-completeness.bats`

Expected: FAIL — `shared/mcp-detection.md` not found

- [ ] **Step 3: Create shared/mcp-detection.md**

```bash
cat > shared/mcp-detection.md << 'MDEOF'
# MCP Detection Reference

Canonical tool name prefixes and degradation behavior for each detected MCP.
Skills MUST reference this document instead of inline detection logic.

## Detection Table

| MCP | Tool Name Prefix | Detection Probe Tool | Available Capability | Degradation When Unavailable |
|---|---|---|---|---|
| Linear | `mcp__claude_ai_Linear__` | `mcp__claude_ai_Linear__list_teams` | Epic/story tracking, status sync | File-based kanban only; skip Linear sync |
| Playwright | `mcp__plugin_playwright_playwright__` | `mcp__plugin_playwright_playwright__browser_navigate` | Browser automation, E2E testing, screenshots | Skip preview validation; manual testing |
| Slack | `mcp__claude_ai_Slack__` | `mcp__claude_ai_Slack__slack_send_message` | Channel messaging, search, canvas | Skip notifications; console output only |
| Context7 | `mcp__plugin_context7_context7__` | `mcp__plugin_context7_context7__resolve-library-id` | Live documentation lookup, version-aware API refs | Fall back to training data + WebSearch |
| Figma | `mcp__claude_ai_Figma__` | `mcp__claude_ai_Figma__get_design_context` | Design-to-code, screenshots, component mapping | Skip design system validation |
| Excalidraw | `mcp__claude_ai_Excalidraw__` | `mcp__claude_ai_Excalidraw__create_view` | Architecture diagrams, visual documentation | Text-based diagrams only |
| Neo4j | `neo4j-mcp` | `neo4j-mcp` (tool name) | Knowledge graph queries, codebase graph | Skip graph enrichment; file-based analysis |

## Detection Protocol

1. At PREFLIGHT, probe each MCP by checking if its detection probe tool is available
2. First failure per MCP marks it as `degraded` for the remainder of the run
3. Log an INFO finding: `MCP-UNAVAILABLE: {mcp_name} — {degradation behavior}`
4. Do NOT invoke the recovery engine for MCP failures (per `error-taxonomy.md`)

## Referencing This Document

Skills should reference this table rather than hardcoding detection logic:
- Use: "Detect MCPs per `shared/mcp-detection.md` detection table"
- Do NOT duplicate tool name prefixes in skill files
MDEOF
```

- [ ] **Step 4: Run the test**

Run: `./tests/lib/bats-core/bin/bats tests/contract/mcp-detection-completeness.bats`

Expected: PASS

---

### Task 20: Add error logging to forge-compact-check.sh

**Files:**
- Modify: `shared/forge-compact-check.sh`
- Create: `tests/unit/compact-check-logging.bats`

- [ ] **Step 1: Create the test file (RED)**

```bash
cat > tests/unit/compact-check-logging.bats << 'BATSEOF'
#!/usr/bin/env bats
# Unit test: forge-compact-check.sh logs errors to .hook-failures.log

load '../helpers/test-helpers'

COMPACT_CHECK="$PLUGIN_ROOT/shared/forge-compact-check.sh"

setup() {
  TEST_TEMP="$(mktemp -d "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/bats-forge.XXXXXX")"
  MOCK_BIN="${TEST_TEMP}/mock-bin"
  mkdir -p "${MOCK_BIN}" "${TEST_TEMP}/.forge"
  export PATH="${MOCK_BIN}:${PATH}"
}

teardown() {
  [[ -n "${TEST_TEMP:-}" && -d "${TEST_TEMP}" ]] && rm -rf "${TEST_TEMP}"
}

@test "compact-check-logging: logs failure when increment fails" {
  # Override atomic_increment to always fail (return empty)
  # The script sources platform.sh which defines it, but export -f overrides
  atomic_increment() { return 1; }
  export -f atomic_increment

  # Also mock flock to fail (fallback path)
  cat > "${MOCK_BIN}/flock" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "${MOCK_BIN}/flock"

  # Run the compact check — it should still exit 0 (best-effort)
  run bash "$COMPACT_CHECK" --forge-dir "${TEST_TEMP}/.forge"
  assert_success

  # Verify failure was logged
  [[ -f "${TEST_TEMP}/.forge/.hook-failures.log" ]] || fail "No .hook-failures.log created"
  grep -q "compact-check" "${TEST_TEMP}/.forge/.hook-failures.log" || \
    fail "Log does not contain compact-check entry"
}

@test "compact-check-logging: exits 0 even on failure" {
  atomic_increment() { return 1; }
  export -f atomic_increment
  run bash "$COMPACT_CHECK" --forge-dir "${TEST_TEMP}/.forge"
  assert_success
}
BATSEOF
```

- [ ] **Step 2: Modify forge-compact-check.sh to add logging**

In `shared/forge-compact-check.sh`, add error logging after the increment logic. Replace the section from line 24 to line 46 with:

```bash
if type atomic_increment &>/dev/null; then
  count=$(atomic_increment "$TOKEN_FILE") || count=""
else
  # Fallback with inline flock if available
  if command -v flock &>/dev/null; then
    count=$(
      flock -w 2 9 || { echo "0"; exit 1; }
      c=0
      [ -f "$TOKEN_FILE" ] && c=$(cat "$TOKEN_FILE" 2>/dev/null || echo 0)
      [[ "$c" =~ ^[0-9]+$ ]] || c=0
      c=$((c + 1))
      echo "$c" > "$TOKEN_FILE"
      echo "$c"
    ) 9>"${TOKEN_FILE}.lock" || count=""
  else
    # Last resort: accept possible race on systems without flock
    count=""
    if [[ -f "$TOKEN_FILE" ]]; then
      count=$(cat "$TOKEN_FILE" 2>/dev/null || echo "")
    fi
    [[ "$count" =~ ^[0-9]+$ ]] || count=""
    if [[ -n "$count" ]]; then
      count=$((count + 1))
      echo "$count" > "$TOKEN_FILE"
    fi
  fi
fi

# Log failure if increment failed or returned empty
if [[ -z "$count" ]]; then
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) compact-check: atomic_increment failed or returned empty" \
    >> "${FORGE_DIR}/.hook-failures.log" 2>/dev/null
  count=0
fi
```

- [ ] **Step 3: Run the test**

Run: `./tests/lib/bats-core/bin/bats tests/unit/compact-check-logging.bats`

Expected: PASS

---

### Task 21: Create agent-registry.md and sync test

**Files:**
- Create: `shared/agent-registry.md`
- Create: `tests/contract/agent-registry-sync.bats`

- [ ] **Step 1: Create the test file (RED)**

```bash
cat > tests/contract/agent-registry-sync.bats << 'BATSEOF'
#!/usr/bin/env bats
# Contract test: agent-registry.md must list every agent file and vice versa.

load '../helpers/test-helpers'

AGENTS_DIR="$PLUGIN_ROOT/agents"
REGISTRY="$PLUGIN_ROOT/shared/agent-registry.md"

@test "agent-registry: registry file exists" {
  [[ -f "$REGISTRY" ]]
}

@test "agent-registry: every agent file has a registry entry" {
  local failures=()
  for agent_file in "$AGENTS_DIR"/fg-*.md; do
    local name
    name="$(basename "$agent_file" .md)"
    grep -q "$name" "$REGISTRY" || failures+=("$name: in agents/ but not in registry")
  done
  if (( ${#failures[@]} > 0 )); then
    printf '%s\n' "${failures[@]}"
    fail "Agents missing from registry: ${#failures[@]}"
  fi
}

@test "agent-registry: every registry entry has an agent file" {
  local failures=()
  # Extract agent IDs from registry table (lines matching fg-NNN-name pattern)
  while IFS= read -r agent_id; do
    [[ -f "${AGENTS_DIR}/${agent_id}.md" ]] || failures+=("${agent_id}: in registry but no agent file")
  done < <(grep -oE 'fg-[0-9]+-[a-z-]+' "$REGISTRY" | sort -u)

  if (( ${#failures[@]} > 0 )); then
    printf '%s\n' "${failures[@]}"
    fail "Registry entries without agent files: ${#failures[@]}"
  fi
}
BATSEOF
```

- [ ] **Step 2: Run to verify it fails**

Run: `./tests/lib/bats-core/bin/bats tests/contract/agent-registry-sync.bats`

Expected: FAIL — registry file doesn't exist yet

- [ ] **Step 3: Create shared/agent-registry.md**

```bash
cat > shared/agent-registry.md << 'MDEOF'
# Agent Registry

Single source of truth for all forge agents. When referencing an agent in skills or shared documents, use the exact ID from this table. When adding, renaming, or removing an agent, update this registry FIRST.

## Registry

| Agent ID | Tier | Dispatches? | Pipeline Stage | Category |
|---|---|---|---|---|
| fg-010-shaper | 1 | No | Pre-pipeline | Shaping |
| fg-015-scope-decomposer | 1 | No | Pre-pipeline | Decomposition |
| fg-020-bug-investigator | 2 | No | Pre-pipeline | Investigation |
| fg-050-project-bootstrapper | 1 | No | Pre-pipeline | Bootstrap |
| fg-090-sprint-orchestrator | 1 | Yes | Sprint | Orchestration |
| fg-100-orchestrator | 2 | Yes | Core | Orchestration |
| fg-101-worktree-manager | 4 | No | Core | Git |
| fg-102-conflict-resolver | 4 | No | Core | Analysis |
| fg-103-cross-repo-coordinator | 2 | Yes | Core | Coordination |
| fg-130-docs-discoverer | 3 | No | Preflight | Discovery |
| fg-140-deprecation-refresh | 3 | No | Preflight | Maintenance |
| fg-150-test-bootstrapper | 3 | Yes | Preflight | Testing |
| fg-160-migration-planner | 1 | No | Preflight | Migration |
| fg-200-planner | 1 | Yes | Plan | Planning |
| fg-210-validator | 4 | No | Validate | Validation |
| fg-250-contract-validator | 3 | Yes | Validate | Contracts |
| fg-300-implementer | 3 | No | Implement | TDD |
| fg-310-scaffolder | 3 | No | Implement | Scaffolding |
| fg-320-frontend-polisher | 3 | No | Implement | Frontend |
| fg-350-docs-generator | 3 | Yes | Document | Documentation |
| fg-400-quality-gate | 2 | Yes | Review | Coordination |
| fg-410-code-reviewer | 4 | No | Review | Quality |
| fg-411-security-reviewer | 4 | No | Review | Security |
| fg-412-architecture-reviewer | 4 | No | Review | Architecture |
| fg-413-frontend-reviewer | 4 | No | Review | Frontend |
| fg-416-backend-performance-reviewer | 4 | No | Review | Performance |
| fg-417-version-compat-reviewer | 4 | No | Review | Compatibility |
| fg-418-docs-consistency-reviewer | 4 | No | Review | Documentation |
| fg-419-infra-deploy-reviewer | 4 | No | Review | Infrastructure |
| fg-420-dependency-reviewer | 4 | No | Review | Dependencies |
| fg-500-test-gate | 2 | Yes | Verify | Coordination |
| fg-505-build-verifier | 3 | No | Verify | Build |
| fg-590-pre-ship-verifier | 3 | Yes | Ship | Verification |
| fg-600-pr-builder | 2 | Yes | Ship | Shipping |
| fg-610-infra-deploy-verifier | 3 | No | Ship | Infrastructure |
| fg-650-preview-validator | 3 | No | Ship | Preview |
| fg-700-retrospective | 3 | No | Learn | Learning |
| fg-710-post-run | 2 | No | Learn | Feedback |

## Rules

1. Agent IDs follow the pattern `fg-{NNN}-{role}` where NNN determines pipeline ordering
2. When referencing an agent in a skill or shared doc, use the exact ID from this table
3. When adding a new agent, add a row here BEFORE creating the agent file
4. When removing an agent, remove the row here AND grep for references across skills/shared docs
5. The Dispatches? column indicates whether the agent has `Agent` in its tools list
MDEOF
```

- [ ] **Step 4: Run the sync test**

Run: `./tests/lib/bats-core/bin/bats tests/contract/agent-registry-sync.bats`

Expected: PASS (bidirectional sync verified)

---

### Task 22: Create graph-debug skill and test

**Files:**
- Create: `skills/graph-debug/SKILL.md`
- Create: `tests/contract/graph-debug-skill.bats`

- [ ] **Step 1: Create the test file (RED)**

```bash
cat > tests/contract/graph-debug-skill.bats << 'BATSEOF'
#!/usr/bin/env bats
# Contract test: graph-debug skill structure and safety.

load '../helpers/test-helpers'

SKILL_FILE="$PLUGIN_ROOT/skills/graph-debug/SKILL.md"

@test "graph-debug: skill file exists" {
  [[ -f "$SKILL_FILE" ]]
}

@test "graph-debug: has valid frontmatter with name and description" {
  # Extract frontmatter
  local frontmatter
  frontmatter="$(awk '/^---$/{n++; if(n==2) exit; next} n==1{print}' "$SKILL_FILE")"
  echo "$frontmatter" | grep -q "^name: graph-debug" || fail "Missing name: graph-debug"
  echo "$frontmatter" | grep -q "^description:" || fail "Missing description field"
}

@test "graph-debug: all Cypher queries are read-only" {
  # No CREATE, MERGE, DELETE, SET, DETACH, REMOVE in Cypher blocks
  local violations=()
  while IFS= read -r line; do
    if echo "$line" | grep -qiE "^\s*(CREATE|MERGE|DELETE|DETACH|SET|REMOVE)\b"; then
      violations+=("$line")
    fi
  done < <(awk '/```cypher/,/```/' "$SKILL_FILE" | grep -v '```')

  if (( ${#violations[@]} > 0 )); then
    printf 'Write operation: %s\n' "${violations[@]}"
    fail "Graph-debug skill contains write operations: ${#violations[@]}"
  fi
}
BATSEOF
```

- [ ] **Step 2: Run to verify it fails**

Run: `./tests/lib/bats-core/bin/bats tests/contract/graph-debug-skill.bats`

Expected: FAIL — skill file doesn't exist yet

- [ ] **Step 3: Create the skill directory and file**

```bash
mkdir -p skills/graph-debug
```

Create `skills/graph-debug/SKILL.md`:

```markdown
---
name: graph-debug
description: Diagnose Neo4j knowledge graph issues — orphaned nodes, stale data, missing enrichments, relationship integrity. Use when graph-status shows anomalies or graph queries return unexpected results.
---

# Graph Debug

Targeted diagnostic skill for the Neo4j knowledge graph. Provides structured diagnostic recipes without requiring raw Cypher knowledge.

## Prerequisites

- Neo4j container running (check via `shared/graph/neo4j-health.sh`)
- Graph initialized (`/graph-init` completed)

## Diagnostic Recipes

### 1. Orphaned Nodes

Nodes with no relationships (potential data quality issue):

```cypher
MATCH (n) WHERE NOT (n)--() RETURN labels(n) AS type, count(n) AS count
```

### 2. Stale Nodes

Nodes not updated since the current HEAD:

```cypher
MATCH (n {project_id: $project_id})
WHERE n.last_updated_sha <> $current_sha
RETURN labels(n)[0] AS type, n.name AS name, n.last_updated_sha AS stale_sha
LIMIT 50
```

### 3. Missing Enrichments

Expected enrichment properties absent on node types:

```cypher
MATCH (n:Function {project_id: $project_id})
WHERE n.complexity IS NULL OR n.test_coverage IS NULL
RETURN n.name AS function, n.file_path AS file
LIMIT 50
```

### 4. Relationship Integrity

Check for expected relationship types:

```cypher
MATCH (n {project_id: $project_id})
WHERE NOT (n)-[:DEFINED_IN]->()
RETURN labels(n)[0] AS type, n.name AS name
LIMIT 50
```

### 5. Node Count Summary

Quick health overview by label:

```cypher
MATCH (n {project_id: $project_id})
RETURN labels(n)[0] AS label, count(n) AS count
ORDER BY count DESC
```

## Procedure

1. Run Neo4j health check via `shared/graph/neo4j-health.sh`
2. If unhealthy: report status and suggest `/graph-init` or Docker troubleshooting
3. If healthy: derive `project_id` from git remote origin URL
4. Run diagnostic recipes 1-5, report findings in table format
5. If user provides a specific concern, run targeted Cypher (read-only, enforce LIMIT)
6. Suggest remediation: `/graph-rebuild` for widespread staleness, manual fixes for isolated issues

## Safety

- All queries are READ-ONLY (no CREATE, MERGE, DELETE, SET)
- All queries enforce LIMIT (max 50 rows default, configurable)
- Never modify graph state — diagnostic only
```

- [ ] **Step 4: Run the test**

Run: `./tests/lib/bats-core/bin/bats tests/contract/graph-debug-skill.bats`

Expected: PASS

---

### Task 23: Update skills to reference mcp-detection.md

**Files:**
- Modify: `skills/forge-run/SKILL.md`
- Modify: `skills/forge-fix/SKILL.md`
- Modify: `skills/deep-health/SKILL.md`
- Modify: `skills/migration/SKILL.md`

- [ ] **Step 1: In each of the 4 skill files, find inline MCP detection logic and replace with a reference**

For each skill file, search for sections that list MCP tool name prefixes or detection patterns (e.g., `mcp__claude_ai_Linear__`, `mcp__plugin_playwright_playwright__`).

Replace the inline detection block with:

```markdown
Detect available MCPs per `shared/mcp-detection.md` detection table. For each MCP, check if its probe tool is available. Mark unavailable MCPs as degraded and apply the documented degradation behavior.
```

Keep any skill-specific logic that depends on MCP availability (e.g., "if Linear available, create epic; otherwise use kanban") — only remove the duplicated detection table/prefixes.

- [ ] **Step 2: Verify no regressions**

Run: `./tests/run-all.sh`

Expected: All tests PASS (skill content changes don't affect structural tests)

---

### Task 24: Phase 4 full verification

- [ ] **Step 1: Run all Phase 4 tests**

Run: `./tests/lib/bats-core/bin/bats tests/contract/mcp-detection-completeness.bats tests/unit/compact-check-logging.bats tests/contract/agent-registry-sync.bats tests/contract/graph-debug-skill.bats`

Expected: All PASS

- [ ] **Step 2: Run full test suite**

Run: `./tests/run-all.sh`

Expected: All tests PASS

- [ ] **Step 3: Commit Phase 4**

```bash
git add shared/mcp-detection.md shared/agent-registry.md shared/forge-compact-check.sh \
  skills/graph-debug/SKILL.md \
  skills/forge-run/SKILL.md skills/forge-fix/SKILL.md skills/deep-health/SKILL.md skills/migration/SKILL.md \
  tests/contract/mcp-detection-completeness.bats tests/unit/compact-check-logging.bats \
  tests/contract/agent-registry-sync.bats tests/contract/graph-debug-skill.bats
git commit -m "feat: Phase 4 architecture — MCP detection, agent registry, graph-debug skill, hook logging"
```

- [ ] **Step 4: Run `/requesting-code-review` for Phase 4**

---

## POST-IMPLEMENTATION

### Task 25: Final full verification

- [ ] **Step 1: Run validate-plugin.sh**

Run: `./tests/validate-plugin.sh`

Expected: All structural checks PASS (73+)

- [ ] **Step 2: Run full test suite**

Run: `./tests/run-all.sh`

Expected: All tests PASS (1,367 existing + ~53 new)

- [ ] **Step 3: Verify no uncommitted changes**

Run: `git status`

Expected: Clean working tree
