# Forge Kanban & Git Workflow (v1.1.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add file-based kanban tracking, ticket-linked branch naming, commit conventions with project hook detection, sub-agent progress visibility, and worktree enforcement to the forge plugin.

**Architecture:** Four interconnected features that form the "git workflow" layer of forge. The kanban tracking system provides ticket IDs consumed by branch naming. Branch naming and commit conventions are read from `forge.local.md` by the orchestrator and PR builder. Sub-agent visibility wraps every Agent dispatch in the orchestrator with TaskCreate/TaskUpdate. Worktree creation moves from Stage 4 to Stage 0 (PREFLIGHT) and uses ticket-based branch names.

**Tech Stack:** Markdown (agent/skill docs), bash (helper scripts), JSON (counter, board), bats (tests)

**Spec:** `docs/superpowers/specs/2026-04-02-forge-redesign-design.md` — Sections 4, 5, 6, 7

---

## File Structure

### New files to create

```
shared/tracking/                           # Kanban tracking system
├── tracking-ops.sh                       # Shell functions: create_ticket, move_ticket, next_id, generate_board
└── tracking-schema.md                    # Documents the ticket format and kanban structure

shared/git-conventions.md                  # Documents branch naming, commit format, hook detection rules

tests/unit/tracking.bats                   # Unit tests for tracking-ops.sh
tests/contract/tracking-contract.bats      # Contract tests for kanban integration with stages
tests/contract/git-conventions.bats        # Contract tests for branch naming and commit conventions
tests/scenario/kanban-lifecycle.bats       # Scenario tests for ticket lifecycle
```

### Files to modify

```
agents/fg-100-orchestrator.md              # Worktree at Stage 0, sub-agent visibility, kanban integration, git config reading
agents/fg-010-shaper.md                    # Create ticket when saving spec
agents/fg-600-pr-builder.md               # Read git conventions from config, ticket-based branch names
skills/forge-init/SKILL.md                 # Hook detection phase, git: section in forge.local.md
skills/forge-run/SKILL.md                  # Pass ticket ID to orchestrator
shared/stage-contract.md                   # Worktree at PREFLIGHT, kanban status transitions
shared/state-schema.md                     # Add tracking section to schema
modules/frameworks/*/local-template.md     # Add git: and tracking: sections (21 files)
CLAUDE.md                                  # Document new features
CONTRIBUTING.md                            # Update for new conventions
tests/helpers/test-helpers.bash            # Add tracking helper functions
```

---

## Task 1: Create Kanban Tracking Shell Library

**Files:**
- Create: `shared/tracking/tracking-ops.sh`
- Create: `shared/tracking/tracking-schema.md`
- Test: `tests/unit/tracking.bats`

This is the core utility used by all agents. It provides shell functions for creating tickets, moving between statuses, generating the board, and reading/incrementing the counter.

- [ ] **Step 1: Write the tracking schema documentation**

Create `shared/tracking/tracking-schema.md`:

```markdown
# Kanban Tracking Schema

## Directory Structure

```
.forge/tracking/
├── counter.json        # { "next": N, "prefix": "FG" }
├── board.md            # Auto-generated summary (regenerated on every status change)
├── backlog/            # Tickets not yet started
├── in-progress/        # Tickets being worked on
├── review/             # Tickets in review/ship stages
└── done/               # Completed tickets
```

## Ticket File Format

YAML frontmatter + markdown body. Filename: `{ID}-{slug}.md`

### Required Frontmatter Fields

| Field | Type | Values |
|-------|------|--------|
| `id` | string | `{PREFIX}-{NNN}` (e.g., `FG-001`) |
| `title` | string | Human-readable ticket title |
| `type` | enum | `feature`, `bugfix`, `refactor`, `chore` |
| `status` | enum | `backlog`, `in-progress`, `review`, `done` |
| `priority` | enum | `low`, `medium`, `high`, `critical` |
| `branch` | string or null | Branch name (set when work begins) |
| `created` | ISO 8601 | Creation timestamp |
| `updated` | ISO 8601 | Last modification timestamp |
| `linear_id` | string or null | Linear issue ID if synced |
| `spec` | string or null | Path to spec file |
| `pr` | string or null | PR URL when created |

### Body Sections

- `## Description` — What this ticket is about
- `## Acceptance Criteria` — Checkboxes for verification
- `## Stories` — Story breakdown (from spec if available)
- `## Activity Log` — Timestamped status changes

## Counter

`counter.json`: `{ "next": 1, "prefix": "FG" }`

- `next` only increments, never decrements
- `prefix` configurable via `tracking.prefix` in `forge.local.md`
- Default prefix: `FG`

## Board

`board.md` is regenerated from ticket frontmatter on every status change. It is a read-only view — never edit it directly.

## Status Transitions

```
backlog → in-progress → review → done
                ↑          |
                └──────────┘  (PR rejected)
in-progress → backlog        (abort/failure)
```
```

- [ ] **Step 2: Write failing tests for tracking-ops.sh**

Create `tests/unit/tracking.bats`:

```bash
#!/usr/bin/env bash
# Tests for shared/tracking/tracking-ops.sh

setup() {
  load '../lib/bats-support/load'
  load '../lib/bats-assert/load'
  PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  source "$PLUGIN_ROOT/shared/tracking/tracking-ops.sh"
  TEST_TEMP="$(mktemp -d)"
  export FORGE_DIR="$TEST_TEMP/.forge"
  mkdir -p "$FORGE_DIR/tracking/backlog" "$FORGE_DIR/tracking/in-progress" "$FORGE_DIR/tracking/review" "$FORGE_DIR/tracking/done"
}

teardown() {
  rm -rf "$TEST_TEMP"
}

# --- Counter ---

@test "tracking: init_counter creates counter.json with defaults" {
  init_counter "$FORGE_DIR/tracking"
  run jq -r '.next' "$FORGE_DIR/tracking/counter.json"
  assert_output "1"
  run jq -r '.prefix' "$FORGE_DIR/tracking/counter.json"
  assert_output "FG"
}

@test "tracking: init_counter respects custom prefix" {
  init_counter "$FORGE_DIR/tracking" "WP"
  run jq -r '.prefix' "$FORGE_DIR/tracking/counter.json"
  assert_output "WP"
}

@test "tracking: next_id increments counter and returns formatted ID" {
  init_counter "$FORGE_DIR/tracking"
  run next_id "$FORGE_DIR/tracking"
  assert_output "FG-001"
  run jq -r '.next' "$FORGE_DIR/tracking/counter.json"
  assert_output "2"
}

@test "tracking: next_id pads to 3 digits" {
  echo '{"next": 42, "prefix": "FG"}' > "$FORGE_DIR/tracking/counter.json"
  run next_id "$FORGE_DIR/tracking"
  assert_output "FG-042"
}

@test "tracking: next_id handles 4+ digits" {
  echo '{"next": 1000, "prefix": "FG"}' > "$FORGE_DIR/tracking/counter.json"
  run next_id "$FORGE_DIR/tracking"
  assert_output "FG-1000"
}

# --- Create ticket ---

@test "tracking: create_ticket creates file in backlog" {
  init_counter "$FORGE_DIR/tracking"
  run create_ticket "$FORGE_DIR/tracking" "Add user notifications" "feature" "medium"
  assert_success
  assert_output --partial "FG-001"
  [ -f "$FORGE_DIR/tracking/backlog/FG-001-add-user-notifications.md" ]
}

@test "tracking: create_ticket frontmatter has correct fields" {
  init_counter "$FORGE_DIR/tracking"
  create_ticket "$FORGE_DIR/tracking" "Fix booking overlap" "bugfix" "high"
  local ticket="$FORGE_DIR/tracking/backlog/FG-001-fix-booking-overlap.md"
  grep -q "^id: FG-001$" "$ticket"
  grep -q "^title: Fix booking overlap$" "$ticket"
  grep -q "^type: bugfix$" "$ticket"
  grep -q "^status: backlog$" "$ticket"
  grep -q "^priority: high$" "$ticket"
  grep -q "^branch: null$" "$ticket"
}

@test "tracking: create_ticket with target_status=in-progress creates in in-progress/" {
  init_counter "$FORGE_DIR/tracking"
  run create_ticket "$FORGE_DIR/tracking" "Quick fix" "bugfix" "critical" "in-progress"
  assert_success
  [ -f "$FORGE_DIR/tracking/in-progress/FG-001-quick-fix.md" ]
}

# --- Move ticket ---

@test "tracking: move_ticket moves file between status directories" {
  init_counter "$FORGE_DIR/tracking"
  create_ticket "$FORGE_DIR/tracking" "Test ticket" "feature" "low"
  move_ticket "$FORGE_DIR/tracking" "FG-001" "in-progress"
  [ -f "$FORGE_DIR/tracking/in-progress/FG-001-test-ticket.md" ]
  [ ! -f "$FORGE_DIR/tracking/backlog/FG-001-test-ticket.md" ]
}

@test "tracking: move_ticket updates status in frontmatter" {
  init_counter "$FORGE_DIR/tracking"
  create_ticket "$FORGE_DIR/tracking" "Test ticket" "feature" "low"
  move_ticket "$FORGE_DIR/tracking" "FG-001" "in-progress"
  grep -q "^status: in-progress$" "$FORGE_DIR/tracking/in-progress/FG-001-test-ticket.md"
}

@test "tracking: move_ticket updates the updated timestamp" {
  init_counter "$FORGE_DIR/tracking"
  create_ticket "$FORGE_DIR/tracking" "Test ticket" "feature" "low"
  sleep 1
  move_ticket "$FORGE_DIR/tracking" "FG-001" "in-progress"
  local created updated
  created=$(grep "^created:" "$FORGE_DIR/tracking/in-progress/FG-001-test-ticket.md" | sed 's/^created: *//')
  updated=$(grep "^updated:" "$FORGE_DIR/tracking/in-progress/FG-001-test-ticket.md" | sed 's/^updated: *//')
  [ "$created" != "$updated" ]
}

@test "tracking: move_ticket appends to Activity Log" {
  init_counter "$FORGE_DIR/tracking"
  create_ticket "$FORGE_DIR/tracking" "Test ticket" "feature" "low"
  move_ticket "$FORGE_DIR/tracking" "FG-001" "in-progress"
  grep -q "Moved to in-progress" "$FORGE_DIR/tracking/in-progress/FG-001-test-ticket.md"
}

@test "tracking: move_ticket returns error for unknown ticket" {
  run move_ticket "$FORGE_DIR/tracking" "FG-999" "in-progress"
  assert_failure
}

# --- Update field ---

@test "tracking: update_ticket_field updates pr field" {
  init_counter "$FORGE_DIR/tracking"
  create_ticket "$FORGE_DIR/tracking" "Test ticket" "feature" "low"
  update_ticket_field "$FORGE_DIR/tracking" "FG-001" "pr" "https://github.com/org/repo/pull/42"
  grep -q "^pr: https://github.com/org/repo/pull/42$" "$FORGE_DIR/tracking/backlog/FG-001-test-ticket.md"
}

@test "tracking: update_ticket_field updates branch field" {
  init_counter "$FORGE_DIR/tracking"
  create_ticket "$FORGE_DIR/tracking" "Test ticket" "feature" "low"
  update_ticket_field "$FORGE_DIR/tracking" "FG-001" "branch" "feat/FG-001-test-ticket"
  grep -q "^branch: feat/FG-001-test-ticket$" "$FORGE_DIR/tracking/backlog/FG-001-test-ticket.md"
}

# --- Board generation ---

@test "tracking: generate_board creates board.md with table" {
  init_counter "$FORGE_DIR/tracking"
  create_ticket "$FORGE_DIR/tracking" "Feature A" "feature" "medium"
  create_ticket "$FORGE_DIR/tracking" "Bug B" "bugfix" "high"
  generate_board "$FORGE_DIR/tracking"
  [ -f "$FORGE_DIR/tracking/board.md" ]
  grep -q "# Forge Board" "$FORGE_DIR/tracking/board.md"
  grep -q "FG-001" "$FORGE_DIR/tracking/board.md"
  grep -q "FG-002" "$FORGE_DIR/tracking/board.md"
}

@test "tracking: generate_board shows status column" {
  init_counter "$FORGE_DIR/tracking"
  create_ticket "$FORGE_DIR/tracking" "Feature A" "feature" "medium"
  move_ticket "$FORGE_DIR/tracking" "FG-001" "in-progress"
  generate_board "$FORGE_DIR/tracking"
  grep -q "In Progress" "$FORGE_DIR/tracking/board.md"
}

# --- Slug generation ---

@test "tracking: slugify converts title to kebab-case" {
  run slugify "Add User Notifications"
  assert_output "add-user-notifications"
}

@test "tracking: slugify strips special characters" {
  run slugify "Fix the 404 error (critical!)"
  assert_output "fix-the-404-error-critical"
}

@test "tracking: slugify truncates at max length" {
  run slugify "This is a very long title that should be truncated to a reasonable length for branch names" 40
  [ ${#output} -le 40 ]
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `tests/lib/bats-core/bin/bats tests/unit/tracking.bats`
Expected: All tests FAIL (tracking-ops.sh doesn't exist yet)

- [ ] **Step 4: Implement tracking-ops.sh**

Create `shared/tracking/tracking-ops.sh`:

```bash
#!/usr/bin/env bash
# Forge kanban tracking operations.
# Source this file to use: create_ticket, move_ticket, next_id, generate_board, etc.
# All functions take $tracking_dir as first arg (typically ".forge/tracking").

set -euo pipefail

# --- Utility ---

slugify() {
  local title="$1"
  local max_len="${2:-40}"
  local slug
  slug=$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9 -]//g' | tr ' ' '-' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
  printf '%s' "${slug:0:$max_len}" | sed 's/-$//'
}

iso_now() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

# --- Counter ---

init_counter() {
  local tracking_dir="$1"
  local prefix="${2:-FG}"
  printf '{"next": 1, "prefix": "%s"}\n' "$prefix" > "$tracking_dir/counter.json"
}

next_id() {
  local tracking_dir="$1"
  local counter_file="$tracking_dir/counter.json"
  local next prefix id
  next=$(jq -r '.next' "$counter_file")
  prefix=$(jq -r '.prefix' "$counter_file")
  id=$(printf '%s-%03d' "$prefix" "$next")
  # Handle 4+ digit IDs (no leading zeros beyond 3)
  if [ "$next" -ge 1000 ]; then
    id=$(printf '%s-%d' "$prefix" "$next")
  fi
  jq ".next = $(( next + 1 ))" "$counter_file" > "$counter_file.tmp" && mv "$counter_file.tmp" "$counter_file"
  printf '%s' "$id"
}

# --- Ticket CRUD ---

create_ticket() {
  local tracking_dir="$1"
  local title="$2"
  local type="$3"
  local priority="$4"
  local target_status="${5:-backlog}"
  local id slug filename now ticket_path

  id=$(next_id "$tracking_dir")
  slug=$(slugify "$title")
  filename="${id}-${slug}.md"
  now=$(iso_now)
  ticket_path="$tracking_dir/$target_status/$filename"

  cat > "$ticket_path" <<TICKET
---
id: $id
title: $title
type: $type
status: $target_status
priority: $priority
branch: null
created: $now
updated: $now
linear_id: null
spec: null
pr: null
---

## Description
$title

## Acceptance Criteria
- [ ] (to be defined)

## Stories
(none yet)

## Activity Log
- $now — Created
TICKET

  printf '%s' "$id"
}

# --- Find ticket ---

find_ticket() {
  local tracking_dir="$1"
  local ticket_id="$2"
  local dir
  for dir in backlog in-progress review done; do
    local match
    match=$(find "$tracking_dir/$dir" -maxdepth 1 -name "${ticket_id}-*" -type f 2>/dev/null | head -1)
    if [ -n "$match" ]; then
      printf '%s' "$match"
      return 0
    fi
  done
  return 1
}

# --- Move ticket ---

move_ticket() {
  local tracking_dir="$1"
  local ticket_id="$2"
  local new_status="$3"
  local source_path new_path filename now

  source_path=$(find_ticket "$tracking_dir" "$ticket_id") || { echo "Ticket $ticket_id not found" >&2; return 1; }
  filename=$(basename "$source_path")
  new_path="$tracking_dir/$new_status/$filename"
  now=$(iso_now)

  # Update status and updated timestamp in frontmatter
  sed -i '' "s/^status: .*/status: $new_status/" "$source_path"
  sed -i '' "s/^updated: .*/updated: $now/" "$source_path"

  # Append to activity log
  printf '\n- %s — Moved to %s\n' "$now" "$new_status" >> "$source_path"

  # Move file
  mv "$source_path" "$new_path"
}

# --- Update field ---

update_ticket_field() {
  local tracking_dir="$1"
  local ticket_id="$2"
  local field="$3"
  local value="$4"
  local ticket_path now

  ticket_path=$(find_ticket "$tracking_dir" "$ticket_id") || { echo "Ticket $ticket_id not found" >&2; return 1; }
  now=$(iso_now)

  sed -i '' "s|^${field}: .*|${field}: ${value}|" "$ticket_path"
  sed -i '' "s/^updated: .*/updated: $now/" "$ticket_path"
}

# --- Board generation ---

generate_board() {
  local tracking_dir="$1"
  local board_file="$tracking_dir/board.md"
  local now
  now=$(iso_now)

  cat > "$board_file" <<HEADER
# Forge Board

> Last updated: $now

| Status | ID | Title | Type | Priority | Branch |
|--------|----|-------|------|----------|--------|
HEADER

  local status_order=("in-progress" "review" "backlog" "done")
  local status_labels=("In Progress" "Review" "Backlog" "Done")

  for i in "${!status_order[@]}"; do
    local status="${status_order[$i]}"
    local label="${status_labels[$i]}"
    local dir="$tracking_dir/$status"
    [ -d "$dir" ] || continue
    for ticket_file in "$dir"/*.md; do
      [ -f "$ticket_file" ] || continue
      [ "$(basename "$ticket_file")" = "board.md" ] && continue
      local id title type priority branch
      id=$(grep "^id:" "$ticket_file" | sed 's/^id: *//')
      title=$(grep "^title:" "$ticket_file" | sed 's/^title: *//')
      type=$(grep "^type:" "$ticket_file" | sed 's/^type: *//')
      priority=$(grep "^priority:" "$ticket_file" | sed 's/^priority: *//')
      branch=$(grep "^branch:" "$ticket_file" | sed 's/^branch: *//')
      [ "$branch" = "null" ] && branch="—"
      printf '| **%s** | %s | %s | %s | %s | %s |\n' "$label" "$id" "$title" "$type" "$priority" "\`$branch\`" >> "$board_file"
    done
  done
}
```

- [ ] **Step 5: Make tracking-ops.sh executable**

```bash
chmod +x shared/tracking/tracking-ops.sh
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `tests/lib/bats-core/bin/bats tests/unit/tracking.bats`
Expected: All tests PASS

- [ ] **Step 7: Fix any platform issues**

The `sed -i ''` is macOS-specific. Use the portable pattern from `shared/platform.sh`:

```bash
# At top of tracking-ops.sh, add:
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/platform.sh" 2>/dev/null || true

# Replace all sed -i '' with:
portable_sed_i() {
  if [[ "$FORGE_OS" == "darwin" ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}
```

Then replace all `sed -i ''` calls with `portable_sed_i`.

- [ ] **Step 8: Re-run tests after platform fix**

Run: `tests/lib/bats-core/bin/bats tests/unit/tracking.bats`
Expected: All tests PASS

- [ ] **Step 9: Commit**

```bash
git add shared/tracking/ tests/unit/tracking.bats
git commit -m "feat(tracking): add kanban tracking shell library with tests"
```

---

## Task 2: Create Git Conventions Document

**Files:**
- Create: `shared/git-conventions.md`
- Test: `tests/contract/git-conventions.bats`

This shared document defines branch naming, commit format, and hook detection rules. Referenced by the orchestrator, PR builder, and init skill.

- [ ] **Step 1: Write the git conventions document**

Create `shared/git-conventions.md`:

```markdown
# Git Conventions

Shared git workflow rules for forge. Referenced by `fg-100-orchestrator`, `fg-600-pr-builder`, and `/forge-init`.

## Branch Naming

### Default Template

```
{type}/{ticket}-{slug}
```

### Configuration

Read from `forge.local.md` `git:` section:

```yaml
git:
  branch_template: "{type}/{ticket}-{slug}"
  branch_types: [feat, fix, refactor, chore]
  slug_max_length: 40
  ticket_source: auto
```

### Resolution

`ticket_source: auto` resolves in order:
1. Linear issue ID (if Linear MCP available and issue synced)
2. Kanban ticket ID (from `.forge/tracking/`)
3. No ticket prefix (fallback)

### Type Mapping

| Requirement mode | Branch type |
|-----------------|-------------|
| Standard (feature) | `feat` |
| Bugfix | `fix` |
| Migration | `migrate` |
| Bootstrap | `chore` |
| Refactor | `refactor` |

## Commit Format

### Default: Conventional Commits

```
{type}({scope}): {description}

{optional body}
```

### Configuration

Read from `forge.local.md` `git:` section:

```yaml
git:
  commit_format: conventional
  commit_types: [feat, fix, test, refactor, docs, chore, perf, ci]
  commit_scopes: auto
  max_subject_length: 72
  require_scope: false
  sign_commits: false
```

### Enforcement Rules

- Type must be one of configured `commit_types`
- Description: imperative mood, lowercase start, no period, max `max_subject_length` chars
- **NEVER**: `Co-Authored-By`, `Generated by`, any AI attribution
- **NEVER**: `--no-verify`, `--force`, skip hooks
- Each commit independently valid (compiles, tests pass for its scope)

### Small Commit Strategy

Group changes into logical units by architectural layer:
1. Domain model + ports
2. Use case implementation
3. Persistence + migration
4. API endpoint + tests
5. Frontend component

## Hook Detection

During `/forge-init`, detect existing project conventions:

### Scanned Paths

| Path | Tool |
|------|------|
| `.husky/` | Husky |
| `.git/hooks/commit-msg` | Native git hook |
| `.pre-commit-config.yaml` | pre-commit framework |
| `lefthook.yml` | Lefthook |
| `commitlint.config.*` | commitlint |
| `.czrc`, `.cz.json` | Commitizen |

### Detection Algorithm

1. Scan for existing hooks (any of the above)
2. If commitlint found → parse `rules` for allowed types/scopes → write to `forge.local.md` `git:` section
3. If branch naming hook found → parse pattern → write to `forge.local.md`
4. If any convention tool found → set `git.commit_enforcement: external`
5. If nothing found → ask user: "No commit conventions detected. Create conventional commits enforcement?"

### Respect Rule

**Never override existing project hooks.** If the project has conventions, adopt them. Only create new hooks when the project has none and the user agrees.
```

- [ ] **Step 2: Write contract tests**

Create `tests/contract/git-conventions.bats`:

```bash
#!/usr/bin/env bash

setup() {
  load '../lib/bats-support/load'
  load '../lib/bats-assert/load'
  PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  GIT_CONV="$PLUGIN_ROOT/shared/git-conventions.md"
}

@test "git-conventions: document exists" {
  [ -f "$GIT_CONV" ]
}

@test "git-conventions: branch naming template documented" {
  grep -q '{type}/{ticket}-{slug}' "$GIT_CONV"
}

@test "git-conventions: all 4 branch types documented" {
  grep -q 'feat' "$GIT_CONV"
  grep -q 'fix' "$GIT_CONV"
  grep -q 'refactor' "$GIT_CONV"
  grep -q 'chore' "$GIT_CONV"
}

@test "git-conventions: ticket_source auto resolution documented" {
  grep -q 'ticket_source: auto' "$GIT_CONV"
  grep -q 'Linear issue ID' "$GIT_CONV"
  grep -q 'Kanban ticket ID' "$GIT_CONV"
}

@test "git-conventions: conventional commits format documented" {
  grep -q '{type}({scope}): {description}' "$GIT_CONV"
}

@test "git-conventions: no AI attribution rule documented" {
  grep -q 'Co-Authored-By' "$GIT_CONV"
  grep -q 'NEVER' "$GIT_CONV"
}

@test "git-conventions: commit_types list includes all 8 types" {
  grep -q 'feat, fix, test, refactor, docs, chore, perf, ci' "$GIT_CONV"
}

@test "git-conventions: hook detection section exists" {
  grep -q 'Hook Detection' "$GIT_CONV"
}

@test "git-conventions: all 6 hook tools documented" {
  grep -q 'Husky' "$GIT_CONV"
  grep -q 'pre-commit' "$GIT_CONV"
  grep -q 'Lefthook' "$GIT_CONV"
  grep -q 'commitlint' "$GIT_CONV"
  grep -q 'Commitizen' "$GIT_CONV"
  grep -q 'Native git hook' "$GIT_CONV"
}

@test "git-conventions: respect rule documented" {
  grep -q 'Never override existing project hooks' "$GIT_CONV"
}

@test "git-conventions: small commit strategy documented" {
  grep -q 'Small Commit Strategy' "$GIT_CONV"
}

@test "git-conventions: forge.local.md git section documented" {
  grep -q 'forge.local.md' "$GIT_CONV"
  grep -q 'branch_template' "$GIT_CONV"
  grep -q 'commit_format' "$GIT_CONV"
}
```

- [ ] **Step 3: Run tests**

Run: `tests/lib/bats-core/bin/bats tests/contract/git-conventions.bats`
Expected: All PASS

- [ ] **Step 4: Commit**

```bash
git add shared/git-conventions.md tests/contract/git-conventions.bats
git commit -m "docs(git): add git conventions shared document with contract tests"
```

---

## Task 3: Update Orchestrator — Worktree at PREFLIGHT + Sub-Agent Visibility

**Files:**
- Modify: `agents/fg-100-orchestrator.md`
- Modify: `shared/stage-contract.md`
- Test: `tests/contract/tracking-contract.bats`

This is the largest and most complex task. It modifies the orchestrator to:
1. Create worktree at PREFLIGHT (Stage 0) instead of IMPLEMENT (Stage 4)
2. Use ticket-based branch naming
3. Wrap every Agent dispatch with TaskCreate/TaskUpdate for sub-agent visibility
4. Integrate kanban status transitions at stage boundaries

- [ ] **Step 1: Read the orchestrator's current worktree section**

Read `agents/fg-100-orchestrator.md` lines 935-960 (Stage 4 worktree creation) and lines 650-680 (TaskCreate setup). Understand the current patterns before modifying.

- [ ] **Step 2: Move worktree creation from Stage 4 to Stage 0**

In `agents/fg-100-orchestrator.md`, find the Stage 4 entry section (around line 940) that creates the worktree. Move this logic to the end of Stage 0 (PREFLIGHT), after state initialization but before the task tracker creation. The new location should be approximately after the "Initialize State" section and before "Create Task Tracker".

The worktree section in Stage 0 should read:

```markdown
### 3.8 Create Worktree (Stage 0)

Skip if `--dry-run` (no worktree needed for read-only analysis).

1. Read `git:` section from `forge.local.md` for branch naming config.
2. Determine branch type from mode:
   - Standard → `feat`
   - Migration → `migrate`
   - Bootstrap → `chore`
3. Determine ticket ID:
   - If `--spec` provided and spec has a tracking ticket → use that ID
   - If requirement matches existing ticket in `.forge/tracking/` → use that ID
   - Otherwise → create new ticket via `tracking-ops.sh create_ticket` → use new ID
4. Build branch name: `{type}/{ticket}-{slug}` (using `git:` config template)
5. Check for stale worktree: if `.forge/worktree` exists, remove it (`git worktree remove .forge/worktree --force` after user confirmation)
6. Create worktree: `git worktree add .forge/worktree -b {branch_name}`
7. Update ticket: set `branch` field to the branch name
8. Move ticket to `in-progress/` if in `backlog/`
9. Store `branch_name` and `ticket_id` in `state.json`
```

Remove the old worktree creation from Stage 4 entry. Replace it with a check:
```markdown
### Stage 4 Entry

Verify worktree exists at `.forge/worktree`. If not (edge case — should not happen after PREFLIGHT), abort with error.
```

- [ ] **Step 3: Add sub-agent visibility pattern**

In `agents/fg-100-orchestrator.md`, find the task tracker creation section (around line 654). After creating the 10 stage tasks, add this pattern documentation:

```markdown
### 3.10 Sub-Agent Dispatch Pattern

Every `Agent` dispatch in the orchestrator MUST be wrapped with TaskCreate/TaskUpdate:

```
sub_task = TaskCreate(subject="Dispatching fg-NNN-name", activeForm="Running fg-NNN-name")
result = Agent(name="fg-NNN-name", prompt=...)
TaskUpdate(taskId=sub_task, status="completed")   # or note failure
```

For inline orchestrator work (not an Agent dispatch), use descriptive subjects:
- `Loading project config`
- `Acquiring run lock`
- `Resolving convention stack for {component}`

For review batches:
- `Review batch 1: architecture-reviewer, security-reviewer`
- Individual sub-task per reviewer within the batch

For convergence iterations:
- `Convergence iteration {N}/{max} (score: {prev} → {current})`

Stage tasks use `addBlockedBy` to express the parent→child relationship:
- Each sub-task is `addBlockedBy: [stage_task_id]`
```

Then go through EVERY Agent dispatch in the orchestrator (there are ~20+ dispatch points) and add the TaskCreate/TaskUpdate wrapper pattern. The key dispatch points are:

**Stage 0:** fg-130-docs-discoverer, fg-140-deprecation-refresh, fg-150-test-bootstrapper
**Stage 1:** Explorer agent(s)
**Stage 2:** fg-200-planner (or fg-160-migration-planner)
**Stage 3:** fg-210-validator
**Stage 4:** fg-310-scaffolder, fg-300-implementer, fg-320-frontend-polisher
**Stage 5:** fg-500-test-gate
**Stage 6:** fg-400-quality-gate, then batch review agents
**Stage 7:** fg-350-docs-generator
**Stage 8:** fg-600-pr-builder, fg-650-preview-validator
**Stage 9:** fg-700-retrospective, fg-720-recap

For each, add the TaskCreate before and TaskUpdate after.

- [ ] **Step 4: Add kanban transitions at stage boundaries**

In the orchestrator, at each stage transition point, add kanban status updates:

```markdown
### Kanban Status Transitions

| Orchestrator event | Kanban action |
|-------------------|---------------|
| PREFLIGHT complete, worktree created | Move ticket to `in-progress/` (if not already) |
| REVIEW stage entry | Move ticket to `review/` |
| SHIP — PR created | Update ticket `pr:` field |
| SHIP — PR merged | Move ticket to `done/` |
| PR rejected → re-enter IMPLEMENT | Move ticket back to `in-progress/` |
| Abort/failure | Move ticket to `backlog/`, add Activity Log entry |

Use `tracking-ops.sh` functions. If `.forge/tracking/` does not exist (kanban not initialized), skip silently.
```

- [ ] **Step 5: Update stage-contract.md**

In `shared/stage-contract.md`, update:

1. **Stage 0 (PREFLIGHT) exit conditions** — add: "Worktree created at `.forge/worktree` (unless `--dry-run`). Ticket created/resolved in `.forge/tracking/`."

2. **Stage 4 (IMPLEMENT) entry conditions** — change from "Creates worktree..." to "Verifies worktree exists at `.forge/worktree`."

3. Add a **Cross-Cutting Constraints** section (if not already present):

```markdown
## Cross-Cutting Constraints

### Worktree Isolation

All forge workflows (feature, bugfix, migration, bootstrap) run in `.forge/worktree`. No exceptions except:
- `--dry-run` (read-only, no worktree)
- `/forge-init` (writes to `.claude/` config, not source files)

User's working tree is NEVER modified during any forge workflow.

### Kanban Tracking

If `.forge/tracking/` exists, ticket status is updated at stage boundaries. If tracking is not initialized, all kanban operations are silently skipped (graceful degradation).
```

- [ ] **Step 6: Write contract tests for tracking integration**

Create `tests/contract/tracking-contract.bats`:

```bash
#!/usr/bin/env bash

setup() {
  load '../lib/bats-support/load'
  load '../lib/bats-assert/load'
  PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  ORCHESTRATOR="$PLUGIN_ROOT/agents/fg-100-orchestrator.md"
  STAGE_CONTRACT="$PLUGIN_ROOT/shared/stage-contract.md"
}

@test "tracking-contract: orchestrator references tracking-ops.sh" {
  grep -q "tracking-ops.sh" "$ORCHESTRATOR"
}

@test "tracking-contract: orchestrator creates worktree at PREFLIGHT not IMPLEMENT" {
  # Worktree creation should be in Stage 0 section
  grep -A5 "Create Worktree" "$ORCHESTRATOR" | grep -q "Stage 0\|PREFLIGHT"
}

@test "tracking-contract: orchestrator has sub-agent dispatch pattern documented" {
  grep -q "Sub-Agent Dispatch Pattern" "$ORCHESTRATOR"
}

@test "tracking-contract: orchestrator wraps Agent dispatch with TaskCreate" {
  grep -q "TaskCreate.*Dispatching" "$ORCHESTRATOR"
}

@test "tracking-contract: orchestrator has kanban transitions table" {
  grep -q "Kanban Status Transitions" "$ORCHESTRATOR"
}

@test "tracking-contract: stage-contract has worktree at PREFLIGHT" {
  grep -q "Worktree.*PREFLIGHT\|worktree.*Stage 0" "$STAGE_CONTRACT"
}

@test "tracking-contract: stage-contract has cross-cutting constraints" {
  grep -q "Cross-Cutting Constraints\|Worktree Isolation" "$STAGE_CONTRACT"
}

@test "tracking-contract: orchestrator stores ticket_id in state.json" {
  grep -q "ticket_id" "$ORCHESTRATOR"
}

@test "tracking-contract: orchestrator stores branch_name in state.json" {
  grep -q "branch_name" "$ORCHESTRATOR"
}

@test "tracking-contract: stage-contract documents kanban graceful degradation" {
  grep -q "graceful degradation\|silently skipped" "$STAGE_CONTRACT"
}
```

- [ ] **Step 7: Run contract tests**

Run: `tests/lib/bats-core/bin/bats tests/contract/tracking-contract.bats`
Expected: All PASS

- [ ] **Step 8: Commit**

```bash
git add agents/fg-100-orchestrator.md shared/stage-contract.md tests/contract/tracking-contract.bats
git commit -m "feat(orchestrator): worktree at PREFLIGHT, sub-agent visibility, kanban integration"
```

---

## Task 4: Update PR Builder — Ticket-Based Branches + Git Config

**Files:**
- Modify: `agents/fg-600-pr-builder.md`

- [ ] **Step 1: Read current PR builder branch/commit sections**

Read `agents/fg-600-pr-builder.md` lines 73-155 (branch naming + commit conventions).

- [ ] **Step 2: Update branch naming to read from config**

Replace the current hardcoded branch naming section with:

```markdown
### Branch Naming

Read branch naming configuration from `forge.local.md` `git:` section (passed via stage notes or state.json). If not present, use defaults from `shared/git-conventions.md`.

The orchestrator has already created the worktree branch at PREFLIGHT using ticket-based naming. The PR builder uses the SAME branch (no new branch creation needed). Read the branch name from `state.json.branch_name`.

If the worktree branch follows the `pipeline/{story-id}` legacy pattern (shouldn't happen in forge v1.1.0+), fall back to:
```
{type}/{ticket}-{slug}
```
Where `{ticket}` comes from `state.json.ticket_id` and `{type}` is determined by mode (feat/fix/refactor/chore).
```

- [ ] **Step 3: Update commit conventions to read from config**

Replace the current hardcoded commit format section with:

```markdown
### Commit Format

Read commit configuration from `forge.local.md` `git:` section. If `git.commit_format` is `project` (detected existing conventions), follow the project's format. If `conventional` (default), use:

```
{type}({scope}): {description}
```

Rules from `shared/git-conventions.md`:
- Type from `git.commit_types` (default: `[feat, fix, test, refactor, docs, chore, perf, ci]`)
- Scope: auto-derived from changed files' module/component, or omitted if `git.require_scope` is false
- Description: imperative mood, lowercase, no period, max `git.max_subject_length` chars (default 72)
- Sign commits if `git.sign_commits` is true

**CRITICAL — ALWAYS ENFORCED regardless of config:**
- NEVER include `Co-Authored-By` lines
- NEVER include `Generated by` or any AI attribution
- NEVER use `--no-verify` or `--force`
```

- [ ] **Step 4: Add ticket field updates to PR creation**

Add to the PR creation section:

```markdown
### Kanban Updates at SHIP

After PR is created:
1. Update ticket: `update_ticket_field tracking_dir ticket_id "pr" "$PR_URL"`
2. Board regeneration: `generate_board tracking_dir`

If tracking not initialized, skip silently.
```

- [ ] **Step 5: Commit**

```bash
git add agents/fg-600-pr-builder.md
git commit -m "feat(pr-builder): ticket-based branches and configurable commit format"
```

---

## Task 5: Update Shaper — Create Ticket When Saving Spec

**Files:**
- Modify: `agents/fg-010-shaper.md`

- [ ] **Step 1: Read current shaper output section**

Read `agents/fg-010-shaper.md` lines 106-210 (output format and integration).

- [ ] **Step 2: Add ticket creation after spec save**

In the "Integration" section (Section 5), after "Save the Spec", add:

```markdown
### Create Tracking Ticket

After saving the spec, create a kanban ticket:

1. Check if `.forge/tracking/counter.json` exists (kanban initialized)
2. If yes:
   - `id = next_id(tracking_dir)` via `shared/tracking/tracking-ops.sh`
   - Create ticket in `backlog/` with:
     - `title`: feature title from spec
     - `type`: `feature` (shaper always produces features, bugfix uses `/forge-fix`)
     - `priority`: `medium` (default, user can change)
     - `spec`: path to saved spec file
   - Generate board
   - Tell user: "Ticket {id} created. Run `/forge-run --spec .forge/specs/{name}.md` to start."
3. If no (kanban not initialized):
   - Skip ticket creation
   - Tell user: "Spec saved. Run `/forge-run --spec .forge/specs/{name}.md` to start."
   - Optionally suggest: "Run `/forge-init` to set up kanban tracking."

### Linear Integration (optional)

If the Linear MCP is available, offer to create an Epic with stories. If user confirms:
1. Create Epic
2. Create one Issue per story
3. Store Epic ID in the spec under `## Linear` section
4. Store Epic ID as `linear_id` in the tracking ticket (if kanban initialized)
```

- [ ] **Step 3: Commit**

```bash
git add agents/fg-010-shaper.md
git commit -m "feat(shaper): create kanban ticket when saving spec"
```

---

## Task 6: Update forge-init — Hook Detection + Git Config

**Files:**
- Modify: `skills/forge-init/SKILL.md`
- Modify: 21 `modules/frameworks/*/local-template.md` (add `git:` and `tracking:` sections)

- [ ] **Step 1: Read current forge-init CONFIGURE phase**

Read `skills/forge-init/SKILL.md` lines 200-220 (the CONFIGURE phase).

- [ ] **Step 2: Add hook detection phase after CONFIGURE**

Insert a new phase between CONFIGURE and VALIDATE (or at the end of CONFIGURE):

```markdown
### Phase 2a — Git Conventions Detection

1. **Scan for existing hooks:**
   Check these paths in the project:
   - `.husky/` → Husky detected
   - `.git/hooks/commit-msg` (with content, not sample) → Native git hook
   - `.pre-commit-config.yaml` → pre-commit framework
   - `lefthook.yml` → Lefthook
   - `commitlint.config.*` (js, json, yaml, yml, ts, cjs, mjs) → commitlint
   - `.czrc` or `.cz.json` → Commitizen

2. **If any convention tool detected:**
   - Parse commitlint rules if available (extract types, scopes)
   - Write to `forge.local.md` `git:` section with `commit_format: project` and detected rules
   - Set `git.commit_enforcement: external`
   - Tell user: "Detected {tool}. Adopting your project's commit conventions."

3. **If NO convention tool detected:**
   - Ask user via AskUserQuestion:
     ```
     Header: "Git Conventions"
     Question: "No commit conventions detected. Would you like to set up Conventional Commits?"
     Options:
       A) Yes, set up Conventional Commits (recommended)
       B) No, I'll configure my own later
     ```
   - If (A): Write defaults to `forge.local.md` `git:` section with `commit_format: conventional`
   - If (B): Write `git:` section with `commit_format: none` (no enforcement)

4. **Branch naming:**
   - Write `git.branch_template: "{type}/{ticket}-{slug}"` to `forge.local.md`
   - If custom branch hook detected, parse pattern and use it instead
```

- [ ] **Step 3: Add tracking initialization phase**

Insert after git conventions:

```markdown
### Phase 2b — Kanban Tracking Setup

1. Check if `.forge/tracking/counter.json` already exists
2. If not:
   - Ask user via AskUserQuestion:
     ```
     Header: "Kanban Tracking"
     Question: "Set up file-based kanban tracking for this project?"
     Options:
       A) Yes, with default prefix "FG"
       B) Yes, with custom prefix
       C) No, skip tracking
     ```
   - If (A): Initialize tracking with `init_counter` and default prefix
   - If (B): Ask for prefix, initialize with custom prefix
   - If (C): Skip
3. Create directory structure: `backlog/`, `in-progress/`, `review/`, `done/`
4. Create empty `board.md`
```

- [ ] **Step 4: Add `git:` and `tracking:` sections to all 21 local-template.md files**

For each `modules/frameworks/*/local-template.md`, add at the end (before any closing sections):

```yaml
# Git conventions (auto-detected or configured by /forge-init)
git:
  branch_template: "{type}/{ticket}-{slug}"
  branch_types: [feat, fix, refactor, chore]
  slug_max_length: 40
  ticket_source: auto
  commit_format: conventional
  commit_types: [feat, fix, test, refactor, docs, chore, perf, ci]
  commit_scopes: auto
  max_subject_length: 72
  require_scope: false
  sign_commits: false
  # commit_enforcement: external  # Uncomment if project has its own hooks

# Kanban tracking
tracking:
  prefix: FG
  # enabled: true  # Set to false to disable tracking
```

- [ ] **Step 5: Commit**

```bash
git add skills/forge-init/SKILL.md modules/frameworks/*/local-template.md
git commit -m "feat(init): add git hook detection and kanban tracking setup"
```

---

## Task 7: Update State Schema + forge-run

**Files:**
- Modify: `shared/state-schema.md`
- Modify: `skills/forge-run/SKILL.md`

- [ ] **Step 1: Add tracking fields to state-schema.md**

Add to the state.json schema documentation:

```markdown
### Tracking Fields (v1.1.0)

| Field | Type | Description |
|-------|------|-------------|
| `ticket_id` | string or null | Kanban ticket ID (e.g., `FG-001`). Null if tracking not initialized. |
| `branch_name` | string | Full branch name (e.g., `feat/FG-001-user-notifications`). Set at PREFLIGHT. |
| `tracking_dir` | string | Path to tracking directory (e.g., `.forge/tracking`). |

These fields are set during PREFLIGHT (Stage 0) when the worktree is created. They remain constant for the duration of the run.
```

Also update the state.json example to include these fields.

- [ ] **Step 2: Update forge-run to pass ticket ID**

In `skills/forge-run/SKILL.md`, update the argument parsing to accept an optional ticket ID:

```markdown
### Input Parsing

Parse the user's input. Supported forms:
- `/forge-run <requirement description>` — standard feature mode
- `/forge-run --spec <path>` — use shaped spec (may have ticket ID)
- `/forge-run --from=<stage>` — resume from stage
- `/forge-run --dry-run <requirement>` — analysis only
- `/forge-run --ticket FG-001 <requirement>` — link to existing ticket
- `/forge-run FG-001` — shorthand: look up ticket, use its description as requirement

If a ticket ID is provided (either via `--ticket` or as sole argument matching `{PREFIX}-{NNN}` pattern):
1. Read the ticket file from `.forge/tracking/`
2. Use ticket's `title` and `## Description` as the requirement
3. Pass `ticket_id` to the orchestrator
```

- [ ] **Step 3: Commit**

```bash
git add shared/state-schema.md skills/forge-run/SKILL.md
git commit -m "feat(schema): add tracking fields and ticket-aware forge-run"
```

---

## Task 8: Update Documentation (CLAUDE.md, CONTRIBUTING.md)

**Files:**
- Modify: `CLAUDE.md`
- Modify: `CONTRIBUTING.md`

- [ ] **Step 1: Update CLAUDE.md**

Add to the appropriate sections:

1. In "Key conventions" → add a new subsection after "Hooks":

```markdown
### Kanban Tracking (`.forge/tracking/`)

File-based kanban board. Tickets in `backlog/`, `in-progress/`, `review/`, `done/` with YAML frontmatter. Counter in `counter.json`. Board summary in `board.md` (auto-generated). Ticket IDs used in branch names. See `shared/tracking/tracking-schema.md`.

Configurable prefix in `forge.local.md`: `tracking.prefix: "WP"`. Default: `FG`.

Graceful degradation: all kanban operations silently skip if tracking not initialized.
```

2. In "Key conventions" → add after Kanban:

```markdown
### Git Conventions (`shared/git-conventions.md`)

Branch naming: `{type}/{ticket}-{slug}` (configurable via `git:` in `forge.local.md`). Commit format: Conventional Commits by default, or `project` if existing hooks detected. `/forge-init` scans for Husky, commitlint, Lefthook, pre-commit, Commitizen — adopts existing conventions, never overrides.

**Never in commits:** `Co-Authored-By`, AI attribution, `--no-verify`.
```

3. In "Gotchas" → update the worktree section:

```markdown
### Worktree enforcement

Worktree created at PREFLIGHT (Stage 0), not IMPLEMENT (Stage 4). All forge workflows use `.forge/worktree`. Only exceptions: `--dry-run` and `/forge-init`. Branch name uses ticket ID from kanban tracking.
```

4. In the agents listing, note that the orchestrator now provides sub-agent visibility via TaskCreate.

- [ ] **Step 2: Update CONTRIBUTING.md**

Add a section about the tracking system and git conventions for contributors.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md CONTRIBUTING.md
git commit -m "docs: document kanban tracking, git conventions, worktree enforcement"
```

---

## Task 9: Scenario Tests + Full Verification

**Files:**
- Create: `tests/scenario/kanban-lifecycle.bats`
- Modify: `tests/helpers/test-helpers.bash`

- [ ] **Step 1: Add tracking helper functions to test-helpers.bash**

```bash
# --- Tracking helpers ---

setup_tracking() {
  local forge_dir="$1"
  mkdir -p "$forge_dir/tracking/backlog" "$forge_dir/tracking/in-progress" "$forge_dir/tracking/review" "$forge_dir/tracking/done"
  echo '{"next": 1, "prefix": "FG"}' > "$forge_dir/tracking/counter.json"
}
```

- [ ] **Step 2: Write kanban lifecycle scenario tests**

Create `tests/scenario/kanban-lifecycle.bats`:

```bash
#!/usr/bin/env bash

setup() {
  load '../lib/bats-support/load'
  load '../lib/bats-assert/load'
  PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  source "$PLUGIN_ROOT/shared/tracking/tracking-ops.sh"
  TEST_TEMP="$(mktemp -d)"
  export FORGE_DIR="$TEST_TEMP/.forge"
  mkdir -p "$FORGE_DIR/tracking/backlog" "$FORGE_DIR/tracking/in-progress" "$FORGE_DIR/tracking/review" "$FORGE_DIR/tracking/done"
  init_counter "$FORGE_DIR/tracking"
}

teardown() {
  rm -rf "$TEST_TEMP"
}

@test "lifecycle: create → in-progress → review → done" {
  create_ticket "$FORGE_DIR/tracking" "Feature A" "feature" "medium"
  [ -f "$FORGE_DIR/tracking/backlog/FG-001-feature-a.md" ]

  move_ticket "$FORGE_DIR/tracking" "FG-001" "in-progress"
  [ -f "$FORGE_DIR/tracking/in-progress/FG-001-feature-a.md" ]
  [ ! -f "$FORGE_DIR/tracking/backlog/FG-001-feature-a.md" ]

  move_ticket "$FORGE_DIR/tracking" "FG-001" "review"
  [ -f "$FORGE_DIR/tracking/review/FG-001-feature-a.md" ]

  move_ticket "$FORGE_DIR/tracking" "FG-001" "done"
  [ -f "$FORGE_DIR/tracking/done/FG-001-feature-a.md" ]
}

@test "lifecycle: PR rejection moves review → in-progress" {
  create_ticket "$FORGE_DIR/tracking" "Feature B" "feature" "high"
  move_ticket "$FORGE_DIR/tracking" "FG-001" "in-progress"
  move_ticket "$FORGE_DIR/tracking" "FG-001" "review"
  move_ticket "$FORGE_DIR/tracking" "FG-001" "in-progress"
  [ -f "$FORGE_DIR/tracking/in-progress/FG-001-feature-b.md" ]
  # Activity log should have 4 entries (created + 3 moves)
  local count
  count=$(grep -c "Moved to\|Created" "$FORGE_DIR/tracking/in-progress/FG-001-feature-b.md")
  [ "$count" -ge 4 ]
}

@test "lifecycle: abort moves in-progress → backlog" {
  create_ticket "$FORGE_DIR/tracking" "Feature C" "feature" "low"
  move_ticket "$FORGE_DIR/tracking" "FG-001" "in-progress"
  move_ticket "$FORGE_DIR/tracking" "FG-001" "backlog"
  [ -f "$FORGE_DIR/tracking/backlog/FG-001-feature-c.md" ]
}

@test "lifecycle: multiple tickets tracked independently" {
  create_ticket "$FORGE_DIR/tracking" "Feature A" "feature" "medium"
  create_ticket "$FORGE_DIR/tracking" "Bug B" "bugfix" "critical"
  move_ticket "$FORGE_DIR/tracking" "FG-001" "in-progress"
  [ -f "$FORGE_DIR/tracking/in-progress/FG-001-feature-a.md" ]
  [ -f "$FORGE_DIR/tracking/backlog/FG-002-bug-b.md" ]
}

@test "lifecycle: board reflects current state" {
  create_ticket "$FORGE_DIR/tracking" "Feature A" "feature" "medium"
  create_ticket "$FORGE_DIR/tracking" "Bug B" "bugfix" "high"
  move_ticket "$FORGE_DIR/tracking" "FG-001" "in-progress"
  generate_board "$FORGE_DIR/tracking"
  grep -q "In Progress.*FG-001" "$FORGE_DIR/tracking/board.md"
  grep -q "Backlog.*FG-002" "$FORGE_DIR/tracking/board.md"
}

@test "lifecycle: update_ticket_field sets PR URL" {
  create_ticket "$FORGE_DIR/tracking" "Feature A" "feature" "medium"
  update_ticket_field "$FORGE_DIR/tracking" "FG-001" "pr" "https://github.com/org/repo/pull/1"
  grep -q "^pr: https://github.com/org/repo/pull/1$" "$FORGE_DIR/tracking/backlog/FG-001-feature-a.md"
}

@test "lifecycle: create with custom prefix" {
  echo '{"next": 1, "prefix": "WP"}' > "$FORGE_DIR/tracking/counter.json"
  run create_ticket "$FORGE_DIR/tracking" "Custom prefix" "feature" "low"
  assert_output "WP-001"
  [ -f "$FORGE_DIR/tracking/backlog/WP-001-custom-prefix.md" ]
}
```

- [ ] **Step 3: Run all new tests**

```bash
tests/lib/bats-core/bin/bats tests/unit/tracking.bats tests/contract/git-conventions.bats tests/contract/tracking-contract.bats tests/scenario/kanban-lifecycle.bats
```
Expected: All PASS

- [ ] **Step 4: Run full test suite**

```bash
./tests/run-all.sh
```
Expected: All tests PASS (existing + new)

- [ ] **Step 5: Commit**

```bash
git add tests/scenario/kanban-lifecycle.bats tests/helpers/test-helpers.bash
git commit -m "test: add kanban lifecycle scenarios and tracking test helpers"
```

---

## Task 10: Final Verification + Update validate-plugin.sh

**Files:**
- Modify: `tests/validate-plugin.sh`

- [ ] **Step 1: Add structural checks for new files**

Add to `tests/validate-plugin.sh`:

```bash
# --- TRACKING ---
echo ""
echo "--- TRACKING ---"

check_pass_fail "tracking-ops.sh exists and is executable" \
  "[ -x '$PLUGIN_ROOT/shared/tracking/tracking-ops.sh' ]"

check_pass_fail "tracking-schema.md exists" \
  "[ -f '$PLUGIN_ROOT/shared/tracking/tracking-schema.md' ]"

check_pass_fail "git-conventions.md exists" \
  "[ -f '$PLUGIN_ROOT/shared/git-conventions.md' ]"
```

- [ ] **Step 2: Run structural validation**

```bash
./tests/validate-plugin.sh
```
Expected: All checks pass (39 original + 3 new = 42)

- [ ] **Step 3: Run full test suite**

```bash
./tests/run-all.sh
```
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add tests/validate-plugin.sh
git commit -m "test: add structural checks for tracking and git conventions"
```
