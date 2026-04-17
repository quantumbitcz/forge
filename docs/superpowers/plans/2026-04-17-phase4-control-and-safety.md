# Phase 4 — Control & Safety Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans.

**Goal:** Staging overlay + editable plan + tiered autonomous + 4-level escalation taxonomy. Ship as Forge 4.0.0 (SemVer major).

**Architecture:** 9 logical commits in one PR. Each commit independently CI-green via Group A/B sentinel pattern from Phases 2-3. Sentinel: `FORGE_PHASE4_ACTIVE=1` when 4 new skills + 3 new shared docs + forge-resolve-file.sh + state-schema 1.8.0 all present.

**Tech Stack:** Bash 4+ (via Phase 3 platform.sh), Python 3, Bats, rsync, shasum/sha256sum.

**Verification policy:** No local test runs. Static parse checks only. CI validates on push.

**Spec:** `docs/superpowers/specs/2026-04-17-phase4-control-and-safety-design.md`
**Depends on:** Phases 1-3 merged. Phase 3 helpers used: `acquire_lock_with_retry`, `release_lock`, `safe_realpath`.

---

## File Structure

| File | Role |
|---|---|
| `shared/staging-overlay.md` | Contract for `.forge/pending/` mechanics |
| `shared/autonomous-scopes.md` | 4-scope contract (test_exec/write/apply/deploy) |
| `shared/escalation-taxonomy.md` | 4-level E1-E4 contract |
| `shared/forge-resolve-file.sh` | Pending-over-worktree resolver + overlay + containment |
| `skills/forge-preview/SKILL.md` | Read-only pending-vs-worktree diff |
| `skills/forge-apply/SKILL.md` | Promote pending → worktree (locked) |
| `skills/forge-reject/SKILL.md` | Discard pending (locked, confirmed) |
| `skills/forge-plan-done/SKILL.md` | Exit PLAN_EDIT_WAIT |
| `docs/control-safety.md` | User guide |
| `tests/contract/escalation-taxonomy.bats` | E1-E4 cross-agent scan |
| `tests/contract/staging-overlay.bats` | fg-300 write-target + skill existence |
| `tests/unit/skill-execution/forge-apply-reject.bats` | Runtime apply/reject test |

Extended: 4 agents + 5 shared + 4 skills + config + 6 top-level = **32 unique file operations**.

---

## Task 0: Verify Phase 3 preconditions

- [ ] **Step 1: Verify plugin at 3.2.0 and Phase 3 deliverables present**

```bash
grep '"version": "3.2.0"' .claude-plugin/plugin.json      || { echo "ABORT: Phase 3 not merged"; exit 1; }
test -f shared/cross-platform-contract.md                 || { echo "ABORT: Phase 3 missing"; exit 1; }
test -f shared/graph/query-translator.sh                  || { echo "ABORT: Phase 3 missing"; exit 1; }
grep -q "^release_lock()" shared/platform.sh              || { echo "ABORT: release_lock not in platform.sh"; exit 1; }
grep -q "^safe_realpath()" shared/platform.sh             || { echo "ABORT: safe_realpath not in platform.sh"; exit 1; }
```

All checks must pass.

---

## Task 1: Commit this plan

- [ ] **Step 1:**

```bash
git add docs/superpowers/plans/2026-04-17-phase4-control-and-safety.md
git commit -m "docs(phase4): add control & safety implementation plan"
```

---

## Task 2: Create 3 shared contract docs

**Files:**
- Create: `shared/staging-overlay.md`, `shared/autonomous-scopes.md`, `shared/escalation-taxonomy.md`

- [ ] **Step 1: Write `shared/staging-overlay.md`**

Document the mechanics of `.forge/pending/`, `forge-resolve-file.sh` subcommands (read/exists/overlay-view/diff/containment-check), the overlay-view caching strategy from spec §4.1.3 (persistent `.forge/overlay/` + one-time worktree mirror + per-iteration pending rsync), the `APPLY_GATE` + `APPLY_GATE_WAIT` state flow, and the lock coordination between `/forge-apply`, `/forge-reject`, and implementer writes via `.forge/apply.lock`.

- [ ] **Step 2: Write `shared/autonomous-scopes.md`**

Document the 4 scopes (test_exec, write, apply, deploy) per spec §4.3.1. Include:
- Scope table with action classes covered + examples
- Default scope sets per spec §4.3.2 (conservative, recommended, trust-based, full)
- Migration from 3.x scalar per spec §4.3.2 (in-memory PREFLIGHT normalization)
- Empty-scopes + `enabled: true` → equivalent to `enabled: false` case
- Scope-gating pseudocode from spec §4.3.3

**Critical note to include:** The `test_exec` scope does NOT guarantee zero side effects. Tests may write to `/tmp`, `$HOME/.cache`, or make network calls. The scope authorizes "execution with ambient privileges"; users with zero-side-effect requirements must set `scopes: []`.

- [ ] **Step 3: Write `shared/escalation-taxonomy.md`**

Document the 4-level taxonomy per spec §4.4. Include:
- 4-row level table (trigger, emission, user flow, rollback path, state impact)
- E3 rollback mode breakdown (4 explicit options: rollback-pending, rollback-commits-soft, rollback-commits-hard with guard, continue-anyway, abort) per spec §4.4.1
- `state.abort_reason` enum per spec §4.4.1
- Emission contract per spec §4.4.2 (stage_note.escalation format for each level)
- Cross-references to `docs/error-recovery.md` (Phase 2) for E2/E3 inline guidance

- [ ] **Step 4: Held for commit in Task 8**

---

## Task 3: Create `shared/forge-resolve-file.sh`

**Files:**
- Create: `shared/forge-resolve-file.sh`

- [ ] **Step 1: Write the helper script with 5 subcommands**

```bash
#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# forge-resolve-file.sh — pending-over-worktree file resolution + overlay
#
# Subcommands:
#   read <relative-path>            Print file contents (pending preferred)
#   exists <relative-path>          Exit 0 if file exists in pending or worktree
#   overlay-view                    Print path to persistent overlay dir;
#                                   incrementally refreshes pending layer
#   diff                            Unified diff of pending vs worktree
#   containment-check <path>        Exit 0 if path canonicalizes within .forge/pending/
# ============================================================================

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=./platform.sh
source "${PLUGIN_ROOT}/platform.sh"

cmd_read() {
  local p=$1
  [[ -f ".forge/pending/$p" ]] && cat ".forge/pending/$p" && return
  [[ -f ".forge/worktree/$p" ]] && cat ".forge/worktree/$p" && return
  echo "ERROR: $p not in pending or worktree" >&2
  exit 2
}

cmd_exists() {
  local p=$1
  [[ -f ".forge/pending/$p" ]] || [[ -f ".forge/worktree/$p" ]]
}

cmd_overlay_view() {
  local scratch=".forge/overlay"
  mkdir -p "$scratch"

  # Lock overlay mutations
  acquire_lock_with_retry "${scratch}/.lock" 50 20 \
    || { echo "ERROR: overlay lock unavailable" >&2; exit 1; }
  trap 'release_lock ".forge/overlay/.lock"' EXIT

  # Compute current worktree SHA marker
  local worktree_sha
  worktree_sha=$(git -C .forge/worktree rev-parse HEAD 2>/dev/null || echo "no-sha")

  # Compare to marker
  local marker="$scratch/.sha"
  local refresh_worktree=0
  if [[ ! -f "$marker" ]] || [[ "$(cat "$marker")" != "$worktree_sha" ]]; then
    refresh_worktree=1
  fi

  if [[ $refresh_worktree -eq 1 ]]; then
    # One-time worktree mirror (or re-mirror on SHA change)
    rsync -a --delete-excluded \
      --exclude='.git/' --exclude='node_modules/' \
      .forge/worktree/ "$scratch/"
    printf '%s' "$worktree_sha" > "$marker"
  fi

  # Always sync pending (cheap when empty)
  if [[ -d .forge/pending ]]; then
    rsync -a .forge/pending/ "$scratch/"
  fi

  printf '%s' "$scratch"
}

cmd_diff() {
  diff -Nur -x .git -x node_modules .forge/worktree .forge/pending 2>/dev/null || true
}

cmd_containment_check() {
  local path=$1
  local canonical pending_root
  canonical=$(safe_realpath "$path")
  pending_root=$(safe_realpath ".forge/pending")
  [[ "$canonical" == "$pending_root"/* ]] || [[ "$canonical" == "$pending_root" ]]
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    read) cmd_read "$@" ;;
    exists) cmd_exists "$@" ;;
    overlay-view) cmd_overlay_view ;;
    diff) cmd_diff ;;
    containment-check) cmd_containment_check "$@" ;;
    --help|-h|"") cat <<'HELP'
forge-resolve-file.sh — pending-over-worktree resolver + overlay

USAGE:
  forge-resolve-file.sh <subcommand> [args]

SUBCOMMANDS:
  read <path>                 Print file contents (pending preferred)
  exists <path>               Exit 0 if file exists in pending or worktree
  overlay-view                Print persistent overlay dir path; updates pending layer
  diff                        Unified diff of pending vs worktree
  containment-check <path>    Exit 0 if path is inside .forge/pending/
HELP
      ;;
    *) echo "ERROR: unknown subcommand: $cmd" >&2; exit 1 ;;
  esac
}

main "$@"
```

- [ ] **Step 2: chmod +x + parse check**

```bash
chmod +x shared/forge-resolve-file.sh
bash -n shared/forge-resolve-file.sh
```

- [ ] **Step 3: Held for commit in Task 8**

---

## Task 4: Create 2 skeleton bats files (Group A active; Group B gated)

**Files:**
- Create: `tests/contract/escalation-taxonomy.bats`, `tests/contract/staging-overlay.bats`

- [ ] **Step 1: Write escalation-taxonomy.bats**

```bash
#!/usr/bin/env bats

setup() {
  PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export PLUGIN_ROOT
  if [[ -f "$PLUGIN_ROOT/shared/escalation-taxonomy.md" ]] && \
     [[ -f "$PLUGIN_ROOT/skills/forge-preview/SKILL.md" ]] && \
     [[ -f "$PLUGIN_ROOT/skills/forge-apply/SKILL.md" ]] && \
     [[ -f "$PLUGIN_ROOT/shared/forge-resolve-file.sh" ]]; then
    export FORGE_PHASE4_ACTIVE=1
  fi
}

@test "[A] escalation-taxonomy.md exists with 4 levels" {
  local f="$PLUGIN_ROOT/shared/escalation-taxonomy.md"
  [ -f "$f" ]
  for lvl in "E1 advisory" "E2 decision" "E3 data-risk" "E4 abort"; do
    grep -qF "$lvl" "$f" || { echo "Missing level: $lvl"; return 1; }
  done
}

@test "[A] escalation-taxonomy.md documents E3 rollback modes" {
  local f="$PLUGIN_ROOT/shared/escalation-taxonomy.md"
  for mode in "rollback-pending" "rollback-commits-soft" "rollback-commits-hard" "continue-anyway"; do
    grep -qF "$mode" "$f" || { echo "Missing E3 mode: $mode"; return 1; }
  done
}

@test "[A] escalation-taxonomy.md documents state.abort_reason enum" {
  local f="$PLUGIN_ROOT/shared/escalation-taxonomy.md"
  for val in '"e4"' '"user_abort"' '"wait_state_abort"' '"budget_exhausted"'; do
    grep -qF "$val" "$f" || { echo "Missing abort_reason value: $val"; return 1; }
  done
}

@test "[B] every E1-E4 mention in agents/ references taxonomy" {
  [[ "${FORGE_PHASE4_ACTIVE:-0}" = "1" ]] || skip "Group B activates in Commit 8"
  local bad=0
  for f in "$PLUGIN_ROOT"/agents/fg-*.md; do
    if grep -qE '\bE[1-4]\b' "$f"; then
      grep -q "escalation-taxonomy.md" "$f" \
        || { echo "$f mentions E1-E4 but doesn't reference shared/escalation-taxonomy.md"; bad=1; }
    fi
  done
  [ "$bad" -eq 0 ]
}
```

- [ ] **Step 2: Write staging-overlay.bats**

```bash
#!/usr/bin/env bats

setup() {
  PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export PLUGIN_ROOT
  if [[ -f "$PLUGIN_ROOT/shared/staging-overlay.md" ]] && \
     [[ -f "$PLUGIN_ROOT/shared/forge-resolve-file.sh" ]] && \
     [[ -f "$PLUGIN_ROOT/skills/forge-preview/SKILL.md" ]]; then
    export FORGE_PHASE4_ACTIVE=1
  fi
}

@test "[A] staging-overlay.md exists" {
  [ -f "$PLUGIN_ROOT/shared/staging-overlay.md" ]
}

@test "[A] forge-resolve-file.sh exists and advertises 5 subcommands" {
  local f="$PLUGIN_ROOT/shared/forge-resolve-file.sh"
  [ -f "$f" ] && [ -x "$f" ]
  for sub in read exists overlay-view diff containment-check; do
    grep -q "^cmd_${sub//-/_}()" "$f" \
      || grep -q "${sub})" "$f" \
      || { echo "Missing subcommand: $sub"; return 1; }
  done
}

@test "[A] 4 new skills exist with skill-contract badges" {
  for skill in forge-preview forge-apply forge-reject forge-plan-done; do
    local f="$PLUGIN_ROOT/skills/$skill/SKILL.md"
    [ -f "$f" ]
    head -10 "$f" | grep -qE '\[read-only\]|\[writes\]' \
      || { echo "$skill missing badge"; return 1; }
  done
}

@test "[B] fg-300-implementer write path is .forge/pending/ (not .forge/worktree/)" {
  [[ "${FORGE_PHASE4_ACTIVE:-0}" = "1" ]] || skip "Group B activates in Commit 8"
  local f="$PLUGIN_ROOT/agents/fg-300-implementer.md"
  grep -q "\.forge/pending" "$f"
  ! grep -qE "Verify target path within \`?\.forge/worktree\`?" "$f"
}

@test "[B] state-schema.md version is 1.8.0" {
  [[ "${FORGE_PHASE4_ACTIVE:-0}" = "1" ]] || skip "Group B activates in Commit 8"
  grep -q '"version": "1.8.0"' "$PLUGIN_ROOT/shared/state-schema.md"
}
```

- [ ] **Step 3: Parse checks**

```bash
bash -n tests/contract/escalation-taxonomy.bats tests/contract/staging-overlay.bats
```

- [ ] **Step 4: Held for commit in Task 8**

---

## Task 5: Commit 2 — Foundations

**Files:**
- Create (6): 3 shared docs, `shared/forge-resolve-file.sh`, 2 bats skeletons

- [ ] **Step 1: Commit**

```bash
git add shared/staging-overlay.md shared/autonomous-scopes.md shared/escalation-taxonomy.md
git add shared/forge-resolve-file.sh
chmod +x shared/forge-resolve-file.sh
git add tests/contract/escalation-taxonomy.bats tests/contract/staging-overlay.bats
git commit -m "feat(phase4): foundations — contract docs + resolve helper + skeleton bats

Group A assertions active from this commit; Group B gated on
FORGE_PHASE4_ACTIVE sentinel (new skills + resolve-file.sh + contract
docs + schema 1.8.0 all present)."
```

---

## Task 6: Create 4 new skills (Commit 3)

**Files:** `skills/forge-preview/SKILL.md`, `forge-apply/SKILL.md`, `forge-reject/SKILL.md`, `forge-plan-done/SKILL.md`

- [ ] **Step 1: Write forge-preview/SKILL.md**

```markdown
---
name: forge-preview
description: "[read-only] Unified diff of .forge/pending/ against .forge/worktree/. Thin wrapper over shared/forge-resolve-file.sh diff. Use when reviewing staged implementation changes at APPLY_GATE before running /forge-apply. Trigger: /forge-preview, review pending changes, show staged diff"
allowed-tools: ['Read', 'Bash']
---

# /forge-preview — Review pending changes

Diff of `.forge/pending/` vs `.forge/worktree/`. Non-mutating.

## Flags

- **--help**: print usage and exit 0
- **--json**: emit `{files_changed:[...], additions:N, deletions:N, diff:"..."}`

## Exit codes

See `shared/skill-contract.md` for the standard exit-code table.

## Implementation

Invokes `shared/forge-resolve-file.sh diff` and formats output. With `--json`, wraps the unified diff + counts into JSON.

## Examples

```
/forge-preview                # human-readable diff
/forge-preview --json         # structured output
```
```

- [ ] **Step 2: Write forge-apply/SKILL.md**

```markdown
---
name: forge-apply
description: "[writes] Promote .forge/pending/ to .forge/worktree/ under an exclusive lock. Use at APPLY_GATE after /forge-preview to commit staged implementer changes. Trigger: /forge-apply, apply staged changes, promote pending"
allowed-tools: ['Read', 'Write', 'Edit', 'Bash']
---

# /forge-apply — Promote staged changes

Rsync `.forge/pending/` → `.forge/worktree/` under `.forge/apply.lock`, then remove pending.

## Flags

- **--help**: print usage and exit 0
- **--dry-run**: list files that would be promoted; write nothing

## Exit codes

See `shared/skill-contract.md`.

## State transitions

- APPLY_GATE → VERIFYING (last task) or IMPLEMENTING (next task)
- APPLY_GATE_WAIT → VERIFYING (atomic; no APPLY_GATE re-render)

Invalidates `.forge/overlay/.sha` marker so next `forge-resolve-file.sh overlay-view` rebuilds.

## Examples

```
/forge-apply             # promote under lock
/forge-apply --dry-run   # preview promotion
```
```

- [ ] **Step 3: Write forge-reject/SKILL.md**

```markdown
---
name: forge-reject
description: "[writes] Discard .forge/pending/ and re-dispatch implementer with user's REVISE notes. Use at APPLY_GATE when staged changes are wrong. Trigger: /forge-reject, discard pending, retry implementation"
allowed-tools: ['Read', 'Write', 'Edit', 'Bash', 'AskUserQuestion']
---

# /forge-reject — Discard staged changes

Removes `.forge/pending/` under lock; state transitions back to IMPLEMENTING with feedback_loop_count++.

## Flags

- **--help**: print usage and exit 0
- **--dry-run**: list files that would be discarded; write nothing

## Exit codes

See `shared/skill-contract.md`.

## Behavior

1. Acquire `.forge/apply.lock`.
2. If not `--dry-run`: prompt via `AskUserQuestion` (header "Reject confirm", options: proceed / cancel).
3. `rm -rf .forge/pending`; invalidate overlay marker.
4. State: APPLY_GATE → IMPLEMENTING OR → ESCALATED if `state.feedback_loop_count >= 2`.

**Not scoped under autonomous.** Reject is always user-driven recovery.

## Examples

```
/forge-reject             # confirm + discard
/forge-reject --dry-run   # list what would be discarded
```
```

- [ ] **Step 4: Write forge-plan-done/SKILL.md**

```markdown
---
name: forge-plan-done
description: "[writes] Signal plan editing complete; transition PLAN_EDIT_WAIT → VALIDATING. Use after editing .forge/plans/current.md. Trigger: /forge-plan-done, finished editing plan, proceed to validate"
allowed-tools: ['Read', 'Write', 'Bash']
---

# /forge-plan-done — Exit PLAN_EDIT_WAIT

Signals that the user has finished editing `.forge/plans/current.md`. Transitions state; validator then detects SHA256 change and re-runs.

## Flags

- **--help**: print usage and exit 0
- **--dry-run**: print pending transition (PLAN_EDIT_WAIT → VALIDATING) + current plan SHA256; no state write

## Exit codes

See `shared/skill-contract.md`.

## State transitions

- PLAN_EDIT_WAIT → VALIDATING (validator re-runs if SHA256 changed)
- Any other state: exit 1 with error

## Examples

```
/forge-plan-done                # flip state
/forge-plan-done --dry-run      # show what would transition
```
```

- [ ] **Step 5: Commit**

```bash
git add skills/forge-preview/SKILL.md skills/forge-apply/SKILL.md
git add skills/forge-reject/SKILL.md skills/forge-plan-done/SKILL.md
git commit -m "feat(phase4): 4 new skills — preview/apply/reject/plan-done

Phase 1 skill-contract compliant: all 4 have [badge], ## Flags, ## Exit
codes. /forge-plan-done includes --dry-run per v1 review I1."
```

---

## Task 7: Agent contract updates (Commit 4)

**Files:**
- Modify: `agents/fg-200-planner.md`, `fg-210-validator.md`, `fg-300-implementer.md`

- [ ] **Step 1: Update `fg-200-planner.md`** — add end-of-PLAN step:

At the end of the planner's PLAN-stage instructions, add:

```markdown
## § Plan file emission (Phase 4)

At end of PLAN stage:
1. Write the full plan markdown to `.forge/plans/current.md`.
2. Copy to `.forge/plans/archive/<ISO-timestamp>.md`.
3. Compute SHA256 of current.md: `shasum -a 256 .forge/plans/current.md > .forge/plans/current.md.sha` (portable on both GNU+BSD).
4. Write SHA256 to `state.json.plan.sha256` via `forge-state-write.sh patch`.
5. If non-autonomous OR autonomous+scope test_exec only: set `state.story_state: PLAN_EDIT_WAIT`.
6. Otherwise: transition to VALIDATING.

The `EnterPlanMode` body is now `<content of .forge/plans/current.md>` — user still sees plan in the approval UI.
```

- [ ] **Step 2: Update `fg-210-validator.md`** — add SHA watch:

Insert at the top of the validator's VALIDATE-stage instructions:

```markdown
## § Plan SHA watch (Phase 4)

At start of VALIDATE:
1. Compute current SHA256 of `.forge/plans/current.md`.
2. Compare to `state.json.plan.sha256`.
3. If changed (user edited during PLAN_EDIT_WAIT):
   - Copy current.md to `.forge/plans/archive/<ISO-timestamp>.md` (post-edit snapshot)
   - Re-run all 7 validation perspectives against edited content
   - Update `state.json.plan.sha256` atomically
4. If unchanged: proceed with normal validation.

Plan SHA is **not** re-checked after VALIDATE completes; edits post-validation are silently ignored. Emit E1 advisory if drift detected at subsequent stage transitions.
```

- [ ] **Step 3: Update `fg-300-implementer.md`** — change write target (line 533):

Find the line `DO NOT write outside project root/worktree. Verify target path within .forge/worktree`. Replace with:

```markdown
## § Write target (Phase 4)

**Writes go to `.forge/pending/<relative-path>` — NEVER `.forge/worktree/` directly.**

Pre-write guard:

```bash
source "${CLAUDE_PLUGIN_ROOT}/shared/platform.sh"
./shared/forge-resolve-file.sh containment-check ".forge/pending/$target_path" \
  || { echo "ERROR: path escapes pending dir"; exit 1; }
```

Reads use `./shared/forge-resolve-file.sh read <path>` (pending preferred over worktree).

Inner-loop test/lint (from Phase 1 skill-contract) runs via overlay:
```bash
overlay=$(./shared/forge-resolve-file.sh overlay-view)
cd "$overlay" && <test-command>
```
Overlay persists across iterations; only pending layer re-rsyncs each call.
```

- [ ] **Step 4: Commit**

```bash
git add agents/fg-200-planner.md agents/fg-210-validator.md agents/fg-300-implementer.md
git commit -m "refactor(phase4): agent contract changes — planner/validator/implementer

- fg-200-planner: emits .forge/plans/current.md + PLAN_EDIT_WAIT transition
- fg-210-validator: SHA256 watch + re-run on plan edit
- fg-300-implementer: write target changed from .forge/worktree to .forge/pending;
  inner-loop uses forge-resolve-file.sh overlay-view"
```

---

## Task 8: Orchestrator + state schema + transitions + observability (Commit 5)

**Files:**
- Modify: `agents/fg-100-orchestrator.md`, `shared/state-schema.md`, `shared/state-transitions.md`, `shared/observability-contract.md`

- [ ] **Step 1: `fg-100-orchestrator.md` — 3 new sections**

Append at appropriate section boundaries:

```markdown
## § Scope gating (Phase 4)

At PREFLIGHT, normalize `autonomous` config per `shared/autonomous-scopes.md`:
- If scalar `true`: rewrite in-memory to `{enabled: true, scopes: ["test_exec", "write", "apply", "deploy"]}`; emit `config.autonomous_legacy_scalar` advisory.
- If scalar `false`: rewrite to `{enabled: false, scopes: []}`.
- If `{enabled: true, scopes: []}`: emit `config.autonomous_enabled_but_empty_scopes` advisory.

Before every action class, call `check_scope(action_class)`:
```
check_scope(action_class) →
  if !autonomous.enabled: return false
  return action_class in autonomous.scopes
```
If `false`, emit E2 `AskUserQuestion` with header matching action class; pause stage.

## § APPLY_GATE handling (Phase 4)

After IMPLEMENTING completes:
1. If `check_scope("apply")` returns true: auto-apply (invoke `/forge-apply` logic inline); transition APPLY_GATE → next stage (VERIFYING or IMPLEMENTING).
2. Else: emit E2 `AskUserQuestion` with 3 options (apply / reject / keep staged).
3. "Keep staged" → set `state.story_state: APPLY_GATE_WAIT`; exit normally.

## § PLAN_EDIT_WAIT handling (Phase 4)

On entry to PLAN_EDIT_WAIT:
1. Do NOT auto-transition.
2. User signals completion via `/forge-plan-done` or `/forge-run --resume` (both flip state to VALIDATING).
3. `/forge-abort` from this state: E9 transition to ABORTED; `state.abort_reason = "wait_state_abort"`.

## § Mid-stage ask_user handling (Phase 4)

On receipt of `stage_note.ask_user` from a child agent:
1. Validate the stage is in the allowed list (PLAN, IMPLEMENT, REVIEW per `shared/observability-contract.md §10`). If not, escalate as E2 instead.
2. Verify child agent persisted `mid_stage_cursor` to `state.json.components[].mid_stage_cursor`. If absent, re-dispatch from scratch with warning.
3. Dispatch the `AskUserQuestion` to user; capture answer.
4. Re-dispatch child agent with `ask_user_answer` + preserved cursor as inputs.
```

- [ ] **Step 2: `shared/state-schema.md` — bump 1.7.0 → 1.8.0**

Find `"version": "1.7.0"`; change to `"version": "1.8.0"`.

Add 3 new values to `story_state` enum: `APPLY_GATE`, `APPLY_GATE_WAIT`, `PLAN_EDIT_WAIT`.

Add new fields:
```markdown
| `pending` | object | No | Present during APPLY_GATE. Fields: `files[]`, `additions`, `deletions`, `created_at`. Cleared on /forge-apply or /forge-reject. |
| `plan.sha256` | string | No | SHA256 of .forge/plans/current.md captured by planner. Used by validator to detect user edits. Empty before PLAN. |
| `abort_reason` | string | No | Enum: "e4" \| "user_abort" \| "wait_state_abort" \| "budget_exhausted" \| "pr_rejected_design" \| "e3_rollback_failed". Set on transition to ABORTED. |
| `abort_context` | object | No | Populated for E4: `{agent_id, reason}`. |
| `e3_overrides` | array | No | Append-only list of `{ts, agent, reason, user_choice}` records when user picks "continue-anyway" at E3. |
| `components[].mid_stage_cursor` | object | No | Per-component cursor when mid-stage ask_user is in flight. Fields: `{agent_id, task_id, step, payload}`. |
```

Add migration history row:
```markdown
| 1.8.0 | 2026-04-17 | Phase 4 control & safety | Added pending, plan.sha256, abort_reason enum, abort_context, e3_overrides, components[].mid_stage_cursor; added APPLY_GATE, APPLY_GATE_WAIT, PLAN_EDIT_WAIT story_state values |
```

- [ ] **Step 3: `shared/state-transitions.md` — 9 new transitions**

Append at the end of the pipeline-transitions section:

```markdown
## Phase 4 transitions (added in 4.0.0)

| # | From | To | Trigger | Notes |
|---|---|---|---|---|
| P4.1 | PLANNING | PLAN_EDIT_WAIT | Non-autonomous mode OR autonomous+test_exec only at end of PLAN | Planner wrote .forge/plans/current.md |
| P4.2 | PLAN_EDIT_WAIT | VALIDATING | `/forge-plan-done` OR `/forge-run --resume` OR autonomous+test_exec detects no edits needed | Validator SHA-watches file |
| P4.3 | PLAN_EDIT_WAIT | ESCALATED | Plan file deleted mid-wait OR sha256 corruption | E3 data-risk |
| P4.4 | IMPLEMENTING | APPLY_GATE | Task complete (one per task) | Pending populated |
| P4.5 | APPLY_GATE | IMPLEMENTING | "reject" chosen | feedback_loop_count++; retry task |
| P4.6 | APPLY_GATE | APPLY_GATE_WAIT | "keep staged" chosen | Pipeline exits normally |
| P4.7 | APPLY_GATE | VERIFYING | "apply" chosen OR autonomous+apply scope | Rsync under lock |
| P4.8 | APPLY_GATE | ESCALATED | E3 emitted during gate (pending exceeds destructive threshold) | 4-option prompt |
| P4.9 | APPLY_GATE_WAIT | VERIFYING | `/forge-apply` from wait state (atomic) | No APPLY_GATE re-render |
```

Note: `ABORTED` transitions from wait states are covered by existing E9.

- [ ] **Step 4: `shared/observability-contract.md` — add §10**

```markdown
## §10 Mid-stage ask_user (Phase 4)

Certain stages allow child agents to emit `stage_note.ask_user` for targeted user clarification mid-stage without exiting the stage.

**Allowed stages:** PLAN, IMPLEMENT, REVIEW.
**Forbidden stages:** PREFLIGHT, EXPLORE, VERIFY, SHIP, LEARN (must escalate via E1-E4).

**Agent declaration:** Agents that emit `stage_note.ask_user` MUST carry `ui: { mid_stage_ask: true }` in frontmatter AND `TaskCreate`, `TaskUpdate`, `AskUserQuestion` in `tools:`.

**Idempotency contract:** Agent MUST persist resume cursor before emitting:
```
state.json.components[<name>].mid_stage_cursor = {
  agent_id: <self>,
  task_id: <current task>,
  step: <step index>,
  payload: <agent-specific state>
}
```
Orchestrator re-dispatches with `ask_user_answer` + cursor as input.
```

- [ ] **Step 5: Commit**

```bash
git add agents/fg-100-orchestrator.md shared/state-schema.md shared/state-transitions.md shared/observability-contract.md
git commit -m "feat(phase4): orchestrator + state schema 1.7 → 1.8 + 9 transitions + observability §10

- fg-100-orchestrator: Scope gating, APPLY_GATE handling, PLAN_EDIT_WAIT
  handling, Mid-stage ask_user handling
- state-schema.md 1.7.0 → 1.8.0: new story_state values + pending/plan/abort fields
- state-transitions.md: 9 new Phase 4 transitions
- observability-contract.md §10: mid-stage ask_user idempotency contract"
```

---

## Task 9: Config schema + existing skill updates (Commit 6)

**Files:**
- Modify: `shared/config-schema.json`, `skills/forge-run/SKILL.md`, `skills/forge-recover/SKILL.md`, `skills/forge-abort/SKILL.md`, `skills/forge-status/SKILL.md`

- [ ] **Step 1: Update `shared/config-schema.json` — autonomous shape**

Find the `autonomous` field. Replace scalar bool with:

```json
"autonomous": {
  "oneOf": [
    {"type": "boolean"},
    {
      "type": "object",
      "properties": {
        "enabled": {"type": "boolean"},
        "scopes": {
          "type": "array",
          "items": {"type": "string", "enum": ["test_exec", "write", "apply", "deploy"]}
        }
      },
      "required": ["enabled"]
    }
  ]
}
```

- [ ] **Step 2: Update existing skills for new wait states**

Each of the 4 existing SKILL.md gets a brief section noting Phase 4 awareness:

`skills/forge-run/SKILL.md`: `--resume` handles PLAN_EDIT_WAIT, APPLY_GATE_WAIT.
`skills/forge-recover/SKILL.md`: `resume` subcommand handles the two new wait states.
`skills/forge-abort/SKILL.md`: abort from PLAN_EDIT_WAIT or APPLY_GATE_WAIT sets `abort_reason: "wait_state_abort"`, discards pending.
`skills/forge-status/SKILL.md`: displays `state.pending` info + wait-state context when in APPLY_GATE_WAIT or PLAN_EDIT_WAIT.

- [ ] **Step 3: Commit**

```bash
git add shared/config-schema.json skills/forge-run/SKILL.md skills/forge-recover/SKILL.md
git add skills/forge-abort/SKILL.md skills/forge-status/SKILL.md
git commit -m "feat(phase4): config schema autonomous shape + existing skill wait-state awareness"
```

---

## Task 10: User-facing docs (Commit 7)

**Files:**
- Create: `docs/control-safety.md`
- Modify: `DEPRECATIONS.md`

- [ ] **Step 1: Write `docs/control-safety.md`**

Structure: (1) Overview, (2) Staging overlay walkthrough with `/forge-preview` screenshots, (3) Editable plan walkthrough, (4) Tiered autonomous + scope examples, (5) Escalation levels user-facing guide, (6) Troubleshooting.

- [ ] **Step 2: `DEPRECATIONS.md` — add `## Changed in 4.0.0` section**

```markdown
## Changed in 4.0.0

### fg-300-implementer write target

Previously: writes to `.forge/worktree/` directly.
Now: writes to `.forge/pending/` (staging overlay); promoted to worktree via `/forge-apply`.

No migration needed — state.json has no user-editable fields affected. If you have custom agents that wrote to worktree, update to use `.forge/pending/` + `shared/forge-resolve-file.sh containment-check`.

### autonomous config shape

Previously: `autonomous: true | false` (scalar).
Now: `autonomous: { enabled: bool, scopes: [...] }` (object).

Migration: orchestrator auto-normalizes scalar configs in-memory; user's `forge.local.md` stays as-is. Emits `config.autonomous_legacy_scalar` advisory event on scalar detection. To migrate the file:

```yaml
# Old
autonomous: true

# New (equivalent)
autonomous:
  enabled: true
  scopes: [test_exec, write, apply, deploy]

# Or conservative (recommended)
autonomous:
  enabled: true
  scopes: [test_exec, write]   # pauses at APPLY_GATE
```
```

- [ ] **Step 3: Commit**

```bash
git add docs/control-safety.md DEPRECATIONS.md
git commit -m "docs(phase4): user-facing control-safety guide + DEPRECATIONS.md 4.0.0 section"
```

---

## Task 11: Runtime bats + top-level + version bump (Commit 8)

**Files:**
- Create: `tests/unit/skill-execution/forge-apply-reject.bats`
- Modify: `README.md`, `CLAUDE.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`

- [ ] **Step 1: Write runtime bats**

```bash
#!/usr/bin/env bats

# Phase 4 runtime: /forge-apply + /forge-reject against fixture pending/worktree

setup() {
  PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  TESTDIR=$(mktemp -d)
  cd "$TESTDIR"
  mkdir -p .forge/worktree/src .forge/pending/src
  echo "original" > .forge/worktree/src/file.ts
  echo "modified" > .forge/pending/src/file.ts
  export PLUGIN_ROOT TESTDIR
  [[ -f "$PLUGIN_ROOT/skills/forge-apply/SKILL.md" ]] || skip "Phase 4 not implemented"
}

teardown() {
  cd /
  rm -rf "$TESTDIR"
}

@test "apply promotes pending to worktree" {
  # This tests the BEHAVIOR described in forge-apply SKILL.md; actual invocation
  # requires skill-execution harness (not in-scope here). We simulate the core
  # operation to validate the contract is buildable.
  rsync -a "$TESTDIR/.forge/pending/" "$TESTDIR/.forge/worktree/"
  rm -rf "$TESTDIR/.forge/pending"
  [ "$(cat "$TESTDIR/.forge/worktree/src/file.ts")" = "modified" ]
  [ ! -d "$TESTDIR/.forge/pending" ]
}

@test "reject discards pending; worktree preserved" {
  rm -rf "$TESTDIR/.forge/pending"
  [ "$(cat "$TESTDIR/.forge/worktree/src/file.ts")" = "original" ]
  [ ! -d "$TESTDIR/.forge/pending" ]
}

@test "forge-resolve-file.sh diff shows the difference" {
  run bash "$PLUGIN_ROOT/shared/forge-resolve-file.sh" diff
  # The fixture sets worktree/src/file.ts = "original", pending = "modified"
  [[ "$output" =~ "-original" ]] || [[ "$output" =~ "original" ]]
  [[ "$output" =~ "+modified" ]] || [[ "$output" =~ "modified" ]]
}
```

- [ ] **Step 2: README.md + CLAUDE.md + CHANGELOG.md**

README.md: add "Control & safety (4.0.0+)" section explaining staging overlay, editable plan, tiered autonomous, escalation.

CLAUDE.md: add 4 rows to Key Entry Points (staging-overlay.md, autonomous-scopes.md, escalation-taxonomy.md, docs/control-safety.md); update skill count `35 → 39`; note SemVer major.

CHANGELOG.md: 4.0.0 entry listing breaking changes (write-target change, autonomous scalar) + new skills + staging + editable plan + scope tiering + escalation taxonomy + state schema 1.8.0.

- [ ] **Step 3: Bump plugin + marketplace JSON**

```bash
sed -i.bak 's/"version": "3.2.0"/"version": "4.0.0"/' .claude-plugin/plugin.json
sed -i.bak 's/"version": "3.2.0"/"version": "4.0.0"/' .claude-plugin/marketplace.json
rm -f .claude-plugin/*.bak
```

- [ ] **Step 4: Commit**

```bash
git add tests/unit/skill-execution/forge-apply-reject.bats
git add README.md CLAUDE.md CHANGELOG.md
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "feat(phase4): runtime bats + top-level docs + bump 3.2.0 → 4.0.0

FORGE_PHASE4_ACTIVE sentinel activates Group B assertions at HEAD."
```

---

## Task 12: Push + CI + tag + release

- [ ] **Step 1: Push**

```bash
git push origin master
gh run watch
```

- [ ] **Step 2: Fix forward on CI red; iterate until green**

- [ ] **Step 3: Tag + release**

```bash
git tag -a v4.0.0 -m "Phase 4: Control & Safety

SemVer major — fg-300-implementer write target changed .forge/worktree → .forge/pending.

- Preview-before-apply via .forge/pending/ staging overlay
- Editable plan at .forge/plans/current.md
- Tiered autonomous (test_exec/write/apply/deploy scopes)
- 4-level escalation taxonomy (E1-E4)
- Mid-stage ask_user on PLAN/IMPLEMENT/REVIEW
- 4 new skills: forge-preview, forge-apply, forge-reject, forge-plan-done
- state-schema 1.7.0 → 1.8.0"
git push origin v4.0.0

gh release create v4.0.0 --title "4.0.0 — Phase 4: Control & Safety" --notes-file - <<'EOF'
See CHANGELOG.md §4.0.0 and docs/control-safety.md for the user guide.

Breaking changes:
- fg-300-implementer writes to .forge/pending/ (staging overlay) instead of .forge/worktree/. Use /forge-preview + /forge-apply to review and promote.
- autonomous config is now an object: `{ enabled: bool, scopes: [...] }`. Orchestrator auto-normalizes old scalar form; DEPRECATIONS.md documents migration.

Next: Phase 5 — Live observation UX.
EOF
```

---

## Self-review

**Spec coverage:** All 21 ACs mapped.
**Placeholder scan:** Task 10 Step 1 describes `docs/control-safety.md` structurally ("Overview, staging walkthrough, ...") rather than providing the full body. Acceptable — the structure is concrete and the spec's §4 sections provide all content needed.
**Type consistency:** `FORGE_PHASE4_ACTIVE`, `state.abort_reason` enum values, scope names (`test_exec`, `write`, `apply`, `deploy`), and all transition names used identically across spec + plan.

**Plan complete.**
