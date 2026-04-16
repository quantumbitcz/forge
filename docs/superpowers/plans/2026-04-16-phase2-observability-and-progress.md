# Phase 2 — Observability & Progress Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every sub-agent dispatch visible, stream cost live, surface silent hook failures, and add inline error-recovery guidance. Ship as Forge 3.1.0.

**Architecture:** 6 logical commits in one PR. Additive only — no breaking changes. `forge-token-tracker.sh` is extended, not replaced. The existing 6 color dots in `shared/agent-ui.md` are preserved; 18 hues collapse onto 8 dots.

**Tech Stack:** Bash 4+, Bats, YAML frontmatter, Markdown, JSON. No new runtime dependencies.

**Verification policy:** No local test runs per user instruction. Static parse checks (`bash -n`, `python3 -m json.tool`) are permitted. Each commit pushed, CI validates. Fix-forward on CI red.

**Spec reference:** `docs/superpowers/specs/2026-04-16-phase2-observability-and-progress-design.md`
**Depends on:** Phase 1 merged (3.0.0 released and all Phase 1 files present) before Phase 2 implementation starts. **Task 0 verifies preconditions.**

---

## File Structure

| File | Responsibility |
|---|---|
| `docs/error-recovery.md` | 22-entry user-facing error catalog |
| `shared/observability-contract.md` | Authoritative contract (§1-§9) |
| `shared/cost-tracking.md` | Cost stream + cap escalation contract |
| `shared/model-pricing.json` | Per-model per-1K rates + unknown fallback |
| `shared/color-to-emoji-map.json` | 18-hue → 8-dot map with ASCII fallback |
| `tests/helpers/forge-fixture.sh` | Reusable .forge/ fixture helpers |
| `tests/unit/skill-execution/forge-recover-runtime.bats` | Closes Phase 1 AC #23 |
| `tests/contract/observability-contract.bats` | Contract assertions (new file, distinct name) |

Extended files:
- `shared/forge-token-tracker.sh` — loads pricing from JSON; emits `cost.inc`; sprint-mode path
- `hooks/session-start.sh` — hook-failure banner + cost suffix
- 15 dispatch agent `.md` files — new `## Sub-agent dispatch` section
- `agents/fg-100-orchestrator.md` — cost cap escalation + hook diagnose branch (in addition to being in the 15)
- 6 shared docs + 1 skill + 4 tests + 5 top-level

---

## Rollout Strategy

Commit order (do not reorder without updating spec §9):

1. Plan commit
2. New docs + foundations (additive only — CI green because new files don't break anything)
3. Token tracker refactor (must preserve existing bats assertions)
4. 15 dispatch agent contract sections + ui-frontmatter bats extension
5. Orchestrator + hook + skill + 4 shared docs + 3 bats + validate-plugin.sh
6. Config schema + top-level docs + version bump
7. Push + CI + tag + release

---

## Task 0: Verify Phase 1 preconditions

**Not a file change — a gate.** If any check fails, stop and merge Phase 1 first.

- [ ] **Step 1: Verify plugin is at 3.0.0**

```bash
grep '"version": "3.0.0"' .claude-plugin/plugin.json \
  || { echo "ABORT: plugin.json not at 3.0.0. Phase 1 not merged."; exit 1; }
grep '"version": "3.0.0"' .claude-plugin/marketplace.json \
  || { echo "ABORT: marketplace.json not at 3.0.0. Phase 1 not merged."; exit 1; }
```

- [ ] **Step 2: Verify Phase 1 files exist**

```bash
test -f skills/forge-recover/SKILL.md   || { echo "ABORT: /forge-recover missing (Phase 1 deliverable)."; exit 1; }
test -f shared/agent-colors.md          || { echo "ABORT: agent-colors.md missing."; exit 1; }
test -f shared/skill-contract.md        || { echo "ABORT: skill-contract.md missing."; exit 1; }
test -f shared/ask-user-question-patterns.md || { echo "ABORT: ask-user-question-patterns.md missing."; exit 1; }
! test -d skills/forge-diagnose || { echo "ABORT: forge-diagnose should be deleted by Phase 1."; exit 1; }
! test -d skills/forge-caveman  || { echo "ABORT: forge-caveman should be deleted by Phase 1."; exit 1; }
```

- [ ] **Step 3: Verify agent frontmatter contract in place**

```bash
# Every agent has explicit `ui:` block (Phase 1 contract)
for f in agents/fg-*.md; do
  grep -q "^ui:" "$f" || { echo "ABORT: $f missing ui: (Phase 1 contract)."; exit 1; }
done
# Every agent has `color:` field
for f in agents/fg-*.md; do
  grep -q "^color:" "$f" || { echo "ABORT: $f missing color: (Phase 1 contract)."; exit 1; }
done
```

All three checks must pass before proceeding. If any fail, Phase 1 must be merged first.

---

## Task 1: Commit this plan

**Files:**
- Create: `docs/superpowers/plans/2026-04-16-phase2-observability-and-progress.md` (this file)

- [ ] **Step 1: Stage and commit**

```bash
git add docs/superpowers/plans/2026-04-16-phase2-observability-and-progress.md
git commit -m "docs(phase2): add observability and progress implementation plan"
```

---

## Task 2: Create `shared/model-pricing.json`

**Files:**
- Create: `shared/model-pricing.json`

- [ ] **Step 1: Write the JSON file**

```json
{
  "version": "2026-04-16",
  "_unit": "USD per 1,000,000 tokens (per-MTok) — matches existing forge-token-tracker.sh convention",
  "models": {
    "claude-opus-4-7":         {"input_per_mtok": 15.0,  "output_per_mtok": 75.0},
    "claude-opus-4-7-1m":      {"input_per_mtok": 18.0,  "output_per_mtok": 90.0},
    "claude-sonnet-4-6":       {"input_per_mtok": 3.0,   "output_per_mtok": 15.0},
    "claude-haiku-4-5-20251001": {"input_per_mtok": 0.8, "output_per_mtok": 4.0}
  },
  "unknown_model_fallback": {"input_per_mtok": 15.0, "output_per_mtok": 75.0}
}
```

**Unit rationale:** Existing `shared/forge-token-tracker.sh` uses per-MTok rates (`DEFAULT_PRICING_TABLE` haiku 0.25/1.25, sonnet 3.0/15.0, opus 15.0/75.0). Using per-MTok in the JSON keeps math identical; no per-1K/per-MTok conversion needed. Field keys are `input_per_mtok` / `output_per_mtok` to be explicit.

- [ ] **Step 2: Validate**

```bash
python3 -m json.tool shared/model-pricing.json > /dev/null
```

Expected: no output (valid JSON).

- [ ] **Step 3: Held for commit in Task 9**

---

## Task 3: Create `shared/color-to-emoji-map.json`

**Files:**
- Create: `shared/color-to-emoji-map.json`

- [ ] **Step 1: Write the JSON file**

Copy the full map from spec §4.1.1 including both `map` and `ascii_fallback` sub-objects, all 19 keys (18 palette hues — the table shows 19 including both gray and brown, matching agent-colors.md's 18 hues plus gray).

```json
{
  "version": "2026-04-16",
  "map": {
    "green":   "🟢",
    "lime":    "🟢",
    "teal":    "🟢",
    "olive":   "🟢",
    "red":     "🔴",
    "crimson": "🔴",
    "blue":    "🔵",
    "navy":    "🔵",
    "cyan":    "🔵",
    "yellow":  "🟡",
    "amber":   "🟡",
    "magenta": "🟣",
    "pink":    "🟣",
    "orange":  "🟣",
    "coral":   "🟣",
    "purple":  "🟤",
    "brown":   "🟤",
    "white":   "⚪",
    "gray":    "⬜"
  },
  "ascii_fallback": {
    "green":   "[G]",
    "lime":    "[G+]",
    "teal":    "[T]",
    "olive":   "[O]",
    "red":     "[R]",
    "crimson": "[R+]",
    "blue":    "[B]",
    "navy":    "[N]",
    "cyan":    "[C]",
    "yellow":  "[Y]",
    "amber":   "[A]",
    "magenta": "[M]",
    "pink":    "[P]",
    "orange":  "[O+]",
    "coral":   "[C+]",
    "purple":  "[V]",
    "brown":   "[B-]",
    "white":   "[W]",
    "gray":    "[-]"
  }
}
```

- [ ] **Step 2: Validate**

```bash
python3 -m json.tool shared/color-to-emoji-map.json > /dev/null
```

- [ ] **Step 3: Held for commit in Task 9**

---

## Task 4: Create `shared/observability-contract.md`

**Files:**
- Create: `shared/observability-contract.md`

- [ ] **Step 1: Write the contract with all 9 sections**

Use the spec §4.7 section list as the structure. Every section must be concrete, not aspirational. Cross-references to other files must be exact paths.

Skeleton to fill:

```markdown
# Observability Contract

Authoritative reference for Phase 2 observability primitives. Enforced by `tests/contract/observability-contract.bats` and extensions to other bats files. Created in Phase 2 (Forge 3.1.0).

## 1. Hierarchical sub-agent TaskCreate rule

**Rule.** Every agent whose `tools:` list includes `Agent` MUST, before every sub-agent dispatch:

1. `TaskCreate` with status `pending`; subject template `{dot} {agent_id} {short_purpose}` where `{dot}` comes from `shared/color-to-emoji-map.json` (§2).
2. Immediately before `Agent` invocation: `TaskUpdate` status → `in_progress`.
3. Immediately after `Agent` return: `TaskUpdate` status → `completed`; set `metadata.summary` to agent's exit verdict.

**Affected today:** 15 dispatchers listed in spec §4.1.
**Enforcement:** `tests/contract/ui-frontmatter-consistency.bats` asserts every agent with `Agent` in tools contains the `## Sub-agent dispatch` section referencing this file.

## 2. Color-to-emoji mapping

See `shared/color-to-emoji-map.json` for the full 19-entry map (18 agent-colors palette + gray). Two sub-objects: `map` (Unicode emoji) and `ascii_fallback` (bracket tags).

**Resolution helper (inline bash, for agent authors):**
```bash
resolve_dot() {
  local color=$1
  if [[ "${TERM:-}" == "dumb" ]] || [[ "${FORGE_NO_EMOJI:-0}" == "1" ]]; then
    python3 -c "import json,sys;d=json.load(open('${CLAUDE_PLUGIN_ROOT}/shared/color-to-emoji-map.json'));print(d['ascii_fallback'].get(sys.argv[1], '[?]'))" "$color"
  else
    python3 -c "import json,sys;d=json.load(open('${CLAUDE_PLUGIN_ROOT}/shared/color-to-emoji-map.json'));print(d['map'].get(sys.argv[1], '⬜'))" "$color"
  fi
}
```

**Note:** Within any dispatch cluster, `shared/agent-colors.md` guarantees unique `color:` field. The 18→8 dot collapse means some clusters show identical dots for different agents (e.g., `green` and `lime` both render 🟢). Agent-id in subject disambiguates.

## 3. Event types (Phase 2 additions)

New events added to `shared/event-log.md` in Phase 2:

- `cost.inc` — schema: `{ts, type, run_id, stage, agent, model, tokens_in, tokens_out, cost_usd, run_cost_usd, cap_usd}`. Emitted after every `Agent` return by `shared/forge-token-tracker.sh`.
- `cap.breach` — schema: `{ts, type, run_id, at_cost_usd, cap_usd}`. Emitted when `run_cost_usd >= cap_usd` (first crossing).
- `hook.failure.surfaced` — schema: `{ts, type, window_hours, failure_count, top_type}`. Emitted by `hooks/session-start.sh` when it displays the banner.
- `dispatch.child` — schema: `{ts, type, parent_stage, parent_task_id, child_agent, child_task_id}`. Emitted by dispatch contract after TaskCreate.

Existing `RECOVERY` event gains optional `phase: start|end` field. No event split.

Total Event Types: 12 → 16.

## 4. Cost cap escalation flow

Logic centralized in `agents/fg-100-orchestrator.md §Cost cap escalation`. See also `shared/cost-tracking.md §3`.

## 5. Hook failure banner mechanics

Implementation in `hooks/session-start.sh`. Parser handles pipe-delimited format `{ts} | {script} | {reason[:context]} | {detail}`.

Window: `observability.hook_failure_surface_window_hours` (default 24).
Log truncation: `observability.hook_failure_log_max_entries` (default 100, truncate to 50).

## 6. Error-escalation AskUserQuestion allowlist

Headers that identify error-escalation prompts (bats-checkable):

```
Cost cap, Quality gate, Lint fail, Test fail, Feedback loop, Build fail,
Context overflow, MCP down, Recovery, Escalation
```

Every `AskUserQuestion` with one of these headers MUST have a `question:` field containing `docs/error-recovery.md#`.

## 7. Recovery-engine task emission rule

See `shared/recovery/recovery-engine.md §Task emission rule`. Exceptions: FLAKY_TEST single-retry, wait_and_retry with <1000ms wait.

## 8. Sprint-mode events.jsonl per-run-path rule

`shared/forge-token-tracker.sh` checks `state.run_id`. If `.forge/runs/{run_id}/` exists, writes `cost.inc` events there. Otherwise writes to `.forge/events.jsonl`. Lock via existing `mkdir`-based mechanism documented in `shared/event-log.md`.

## 9. Enforcement map

| Rule | Enforced in |
|---|---|
| §1 Hierarchical TaskCreate | `tests/contract/ui-frontmatter-consistency.bats` |
| §2 Color-dot map presence | `tests/contract/observability-contract.bats` |
| §3 Event types doc | `tests/contract/observability-contract.bats` (grep event-log.md header) |
| §4 Cost cap escalation | `tests/contract/cost-observability.bats` (extended) |
| §5 Hook banner | `tests/contract/observability-contract.bats` (grep session-start.sh) |
| §6 Error-escalation allowlist | `tests/contract/observability-contract.bats` (scan all agent .md) |
| §7 Recovery task emission | `tests/contract/recovery-engine.bats` (extended) |
| §8 Sprint-mode path | `tests/contract/cost-observability.bats` (extended) |
```

- [ ] **Step 2: Held for commit in Task 9**

---

## Task 5: Create `shared/cost-tracking.md`

**Files:**
- Create: `shared/cost-tracking.md`

- [ ] **Step 1: Write the contract**

```markdown
# Cost Tracking Contract

Authoritative doc for Phase 2 cost streaming. Pairs with `shared/observability-contract.md §3-§4`.

## 1. Infrastructure

**Existing (Phase 2 extends):**
- `shared/forge-token-tracker.sh` — per-model pricing, state.cost accumulation
- `shared/cost-alerting.sh` — alert handler
- `tests/contract/cost-observability.bats` — existing assertions

**New (Phase 2):**
- `shared/model-pricing.json` — externalized pricing table
- `shared/model-pricing.local.json` — optional user-specific override (git-ignored)

## 2. Pricing load order

`forge-token-tracker.sh` loads pricing in this order (shallow merge at `models` key):

1. `${CLAUDE_PLUGIN_ROOT}/shared/model-pricing.json` (canonical)
2. `${CLAUDE_PLUGIN_ROOT}/shared/model-pricing.local.json` (override, if exists)

Unknown model → `unknown_model_fallback` (conservative: opus-equivalent). Emits `cost.model_unknown` event (WARN severity).

## 3. Cost cap escalation

Config:
```yaml
cost_cap:
  usd: 5.00                # 0 disables
  action_on_breach: ask    # ask | abort | warn_continue
```

Check happens at each stage boundary in `fg-100-orchestrator`. When `state.cost.cap_breached == true`:

- **ask:** dispatch `AskUserQuestion` with header `"Cost cap"`. Recommended option = raise cap 2×. Decision recorded in `state.cost_cap_decisions`.
- **abort:** transition to `ABORTED` immediately.
- **warn_continue:** stderr warn, continue.

## 4. Autonomous-mode rules

When `autonomous: true`:
- `action_on_breach: ask` → auto-resolves to Recommended option (raise 2×), logged `[AUTO: cap breach raised to $N]`.
- `action_on_breach: abort` → honored.
- `action_on_breach: warn_continue` → honored.

To make autonomous STRICT on cost, set `action_on_breach: abort` explicitly.

## 5. Sprint mode

`forge-token-tracker.sh` detects sprint child via `state.run_id`; writes `cost.inc` to `.forge/runs/{run_id}/events.jsonl` when that path exists, else to `.forge/events.jsonl`.
```

- [ ] **Step 2: Held for commit in Task 9**

---

## Task 6: Create `docs/error-recovery.md`

**Files:**
- Create: `docs/error-recovery.md`

**Target:** 22 entries matching `shared/error-taxonomy.md` names. Each entry ~25-40 lines. Expected total length ~600 lines.

- [ ] **Step 1: Read `shared/error-taxonomy.md` to extract the 22 error names**

The taxonomy file contains multiple tables; only the first table (Error Types) has the 22 canonical entries. Narrow the grep to that table's row range.

```bash
# Extract names from the Error Types table only
awk '/^## Error Types/,/^## Error Severity Ordering/' shared/error-taxonomy.md \
  | grep '^| `[A-Z_]*`' \
  | awk -F'|' '{print $2}' \
  | tr -d '` '
```

Expected output: 22 lines, one name per line (e.g., `CONFIG_INVALID`, `LINT_FAILURE`, `CONTEXT_OVERFLOW`, etc.).

Validate count:

```bash
count=$(awk '/^## Error Types/,/^## Error Severity Ordering/' shared/error-taxonomy.md \
  | grep -c '^| `[A-Z_]*`')
[ "$count" = "22" ] || { echo "FAIL: expected 22 errors, found $count"; exit 1; }
```

- [ ] **Step 2: Write the document opening**

```markdown
# Error Recovery Guide

User-facing companion to `shared/error-taxonomy.md`. If you hit an error during a Forge run, find the error name below and follow the recovery steps.

All anchor slugs use lowercase-with-underscores: `LINT_FAILURE` → `#lint_failure`, `CONTEXT_OVERFLOW` → `#context_overflow`.

## Contents

(Alphabetical list of 22 entries — auto-generated during plan execution.)

---
```

- [ ] **Step 3: Write 3 fully-worked examples to establish the pattern**

Fully-written entries for 3 common error types:

````markdown
## LINT_FAILURE

**Symptom.** Agent output says `LINT_FAILURE: lint exit code != 0 after auto-fix`. Stage is IMPLEMENTING or VERIFYING.

**Severity.** MEDIUM.

**What Forge tried.** Auto-fix loop (`eslint --fix`, `ruff --fix`, or configured formatter) up to 3 times. See `shared/recovery/recovery-engine.md §3.2`.

**What to do now.**
1. Look at the last committed diff: `git diff HEAD~1 HEAD -- <paths>`.
2. Run the lint tool directly (e.g., `pnpm lint`, `ruff check .`). The agent's output references the command.
3. Common cause: prettier vs eslint-fix disagree on line-break style.
4. If disagreement: update `.eslintrc` or `.prettierrc` to align; re-invoke `/forge-run --from=verify`.
5. If a single file is the problem: comment out just that file's rule via `// eslint-disable-next-line` with a TODO; investigate later.

**Example log line.**
```
[fg-300-implementer] LINT_FAILURE: eslint --fix exited 2 after 3 attempts. Files: src/auth/login.ts, src/auth/logout.ts. Stage: IMPLEMENTING.
```

---

## CONTEXT_OVERFLOW

**Symptom.** Agent returns `CONTEXT_OVERFLOW` in stage notes. Often during PLAN or VERIFY with very large inputs.

**Severity.** HIGH (pipeline cannot converge).

**What Forge tried.** Adaptive context compression (via `shared/input-compression.md`). If compression already active, recovery engine tries `split_or_escalate` strategy.

**What to do now.**
1. Shape the requirement smaller: `/forge-shape <original spec>` — produces a decomposed spec.
2. Or dispatch as a sprint: `/forge-sprint` if features are independent.
3. If a single PR is genuinely too large: split by subsystem and run Phase-by-Phase manually.
4. Raise context budget (opt-in, premium cost): set `model_routing.default: premium` in `forge.local.md` to use the 1M-context model.

**Example log line.**
```
[fg-200-planner] CONTEXT_OVERFLOW: input exceeded 200K token limit after compression (budget 180K). Stage: PLANNING.
```

---

## BUILD_FAILURE

**Symptom.** Stage VERIFYING or PREFLIGHT returns `BUILD_FAILURE`. Script in `shared/build-systems/*` exited non-zero.

**Severity.** HIGH (blocks IMPLEMENT/VERIFY progression).

**What Forge tried.** Up to 2 retries with environment reset (if configured). See `shared/recovery/recovery-engine.md §3.4`.

**What to do now.**
1. Read the build output from stage notes or the `.forge/run.log`.
2. Most common causes:
   - Missing dep: run the project's install command (`pnpm i`, `bundle`, `mvn dependency:resolve`).
   - Dirty worktree state: `/forge-recover reset` (or `diagnose` first to inspect).
   - Java/Node version mismatch: check `.nvmrc` / `.sdkmanrc`.
3. Fix the underlying cause in your dev environment.
4. Resume: `/forge-recover resume`.

**Example log line.**
```
[fg-505-build-verifier] BUILD_FAILURE: gradle build exit=1. Missing task: ':integrationTest'. Stage: VERIFYING.
```

---
````

- [ ] **Step 4: Write 19 remaining entries following the pattern, plus 1 extra-taxonomy entry**

Enumerate all 22 error names from Step 1. For each remaining entry (22 − 3 = 19), produce a `## {ERROR_NAME}` section with all 5 fields: Symptom, Severity, What Forge tried, What to do now, Example log line.

**Plus one extra-taxonomy entry: `COST_CAP_BREACH`.** This is not in `shared/error-taxonomy.md` (it's an operational signal, not an error); still, the orchestrator's cost-cap `AskUserQuestion` references `docs/error-recovery.md#cost_cap_breach`. Add a section:

````markdown
## COST_CAP_BREACH

**Symptom.** Pipeline pauses with `AskUserQuestion` header `Cost cap`. Run has spent >= `cost_cap.usd`.

**Severity.** Operational (not an error; user decision point).

**What Forge tried.** Nothing — the cap is a user-set budget guard, not a failure. `emit_cap_breach` event appended to events log; `state.cost.cap_breached` set to `true`; orchestrator pauses at next stage boundary.

**What to do now.**
1. Look at `/forge-insights` to see where the cost went (per-stage breakdown).
2. If the cost was reasonable: pick "Raise cap" (default doubles: $5 → $10). Records in `state.cost_cap_decisions`.
3. If costly due to misconfigured model routing: abort, edit `model_routing` in `forge.local.md` (downgrade to sonnet/haiku for low-risk stages), then `/forge-recover resume`.
4. If autonomous mode: configure `cost_cap.action_on_breach: abort` to hard-stop on breach.

**Example log line.**
```
[fg-100-orchestrator] cap.breach at_cost_usd=5.02 cap_usd=5.00
[AUTO: cap breach raised to $10.00]
```
````

Total entries: **23** (22 taxonomy + 1 operational).

Source of truth for each field:
- **Severity.** From `shared/error-taxonomy.md` Severity column.
- **What Forge tried.** From `shared/recovery/recovery-engine.md` strategy table; find the strategy paired with this error type in the taxonomy.
- **What to do now.** Derived from the recovery strategy + common developer practice. Keep under 5 numbered steps.
- **Example log line.** Format: `[{agent}] {ERROR_NAME}: {message}. Stage: {STAGE}.` Matches the log format used by existing agents (verify by grep on agent `.md` files).

Expected output: 22 total `## {NAME}` sections, alphabetized within the document (easier grep).

- [ ] **Step 5: Auto-generate the Contents section**

Replace the `## Contents` placeholder from Step 2 with an alphabetical list. Uses `awk` + `tr` for cross-platform portability (macOS BSD sed lacks `\L`):

```bash
grep '^## [A-Z_][A-Z_]*$' docs/error-recovery.md \
  | sort \
  | awk '{name=$2; lower=tolower(name); printf "- [%s](#%s)\n", name, lower}'
```

Expected: 22 Markdown links. Example first few lines:
```
- [AGENT_CRASH](#agent_crash)
- [BUILD_FAILURE](#build_failure)
- [CONTEXT_OVERFLOW](#context_overflow)
```

Insert the output above the first `---` divider (replacing the `(Alphabetical list of 22 entries — auto-generated during plan execution.)` placeholder from Step 2).

- [ ] **Step 6: Held for commit in Task 9**

---

## Task 7: Create `tests/helpers/forge-fixture.sh`

**Files:**
- Create: `tests/helpers/forge-fixture.sh`

- [ ] **Step 1: Write the helper script**

```bash
#!/usr/bin/env bash
# Forge fixture helpers for runtime integration tests.
# Invoked as a command, not sourced. All output is stable and deterministic.

set -euo pipefail

FORGE_FIXTURE_VERSION=1

cmd_create() {
  local dest="${1:-}"
  [[ -n "$dest" ]] || { echo "usage: forge-fixture.sh create <dest-path>" >&2; exit 1; }
  mkdir -p "$dest/.forge"
  cat > "$dest/.forge/state.json" <<'EOF'
{
  "version": "1.7.0",
  "run_id": "test-run-01",
  "status": "FAILED",
  "stage": "IMPLEMENTING",
  "score": 45,
  "cost": {"estimated_cost_usd": 0.12, "cap_breached": false, "per_stage": {"4": 0.12}},
  "tokens": {"total_in": 12400, "total_out": 892}
}
EOF
  echo "$dest"
}

cmd_destroy() {
  local path="${1:-}"
  [[ -n "$path" && -d "$path" ]] || { echo "usage: forge-fixture.sh destroy <path>" >&2; exit 1; }
  rm -rf "$path"
}

cmd_snapshot() {
  local path="${1:-}"
  [[ -n "$path" && -d "$path" ]] || { echo "usage: forge-fixture.sh snapshot <path>" >&2; exit 1; }
  # Sort files by relative path; hash each file's content; write sorted list
  (cd "$path" && find . -type f -not -name '*.snapshot' -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 shasum -a 256 2>/dev/null || xargs -0 sha256sum 2>/dev/null) \
    > "$path.snapshot"
}

cmd_diff() {
  local path="${1:-}"
  [[ -n "$path" && -d "$path" ]] || { echo "usage: forge-fixture.sh diff <path>" >&2; exit 1; }
  local expected="$path.snapshot"
  [[ -f "$expected" ]] || { echo "No snapshot at $expected — run 'snapshot' first" >&2; exit 1; }
  local actual
  actual=$(cd "$path" && find . -type f -not -name '*.snapshot' -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 shasum -a 256 2>/dev/null || xargs -0 sha256sum 2>/dev/null)
  diff <(cat "$expected") <(echo "$actual")
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    create)   cmd_create "$@" ;;
    destroy)  cmd_destroy "$@" ;;
    snapshot) cmd_snapshot "$@" ;;
    diff)     cmd_diff "$@" ;;
    *) echo "usage: forge-fixture.sh {create|destroy|snapshot|diff} [args]" >&2; exit 1 ;;
  esac
}

main "$@"
```

- [ ] **Step 2: chmod +x**

```bash
chmod +x tests/helpers/forge-fixture.sh
```

- [ ] **Step 3: Static parse check**

```bash
bash -n tests/helpers/forge-fixture.sh
```

Expected: no output.

- [ ] **Step 4: Held for commit in Task 9**

---

## Task 8: Create `tests/contract/observability-contract.bats` and `tests/unit/skill-execution/forge-recover-runtime.bats`

**Files:**
- Create: `tests/contract/observability-contract.bats`
- Create: `tests/unit/skill-execution/forge-recover-runtime.bats`

- [ ] **Step 1: Write `observability-contract.bats` with two-phase activation**

Assertions split into two groups. **Group A** checks the 7 new files that ship in Commit 2 (Task 9) — these pass immediately. **Group B** checks content in files that don't get Phase 2 edits until Commits 3-5 — these are `skip`ped in Commit 2 and un-skipped via a `FORGE_PHASE2_ACTIVE` env var that CI sets once all commits land.

The CI pipeline sets `FORGE_PHASE2_ACTIVE=1` only when running against `HEAD` after Commit 5 has merged (enforced by a check that all Phase 2 files exist). Intermediate commits run with the env var unset → Group B `skip`s cleanly.

```bash
#!/usr/bin/env bats

# Observability Contract assertions — enforces shared/observability-contract.md
# Group A: active from Commit 2 (foundations)
# Group B: skipped until Commit 5 (full content); controlled by FORGE_PHASE2_ACTIVE env var

setup() {
  PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export PLUGIN_ROOT
  # Phase 2 is "fully active" once Commit 5 (Task 22) lands. Until then, Group B skips.
  # Detection: check for the presence of the new Cost cap escalation section in orchestrator.
  if grep -q "^## § Cost cap escalation\|^## Cost cap escalation" "$PLUGIN_ROOT/agents/fg-100-orchestrator.md" 2>/dev/null; then
    export FORGE_PHASE2_ACTIVE=1
  fi
}

# -------- Group A (active from Commit 2) --------

@test "[A] shared/observability-contract.md exists with 9 sections" {
  local f="$PLUGIN_ROOT/shared/observability-contract.md"
  [ -f "$f" ]
  for section_n in 1 2 3 4 5 6 7 8 9; do
    grep -qE "^## $section_n\. " "$f" || { echo "Missing §$section_n"; return 1; }
  done
}

@test "[A] shared/color-to-emoji-map.json parses with 19 map entries and 19 ascii_fallback entries" {
  local f="$PLUGIN_ROOT/shared/color-to-emoji-map.json"
  [ -f "$f" ]
  local map_count ascii_count
  map_count=$(python3 -c "import json;print(len(json.load(open('$f'))['map']))")
  ascii_count=$(python3 -c "import json;print(len(json.load(open('$f'))['ascii_fallback']))")
  [ "$map_count" = "19" ]
  [ "$ascii_count" = "19" ]
}

@test "[A] shared/model-pricing.json has all 4 required models and per-MTok schema" {
  local f="$PLUGIN_ROOT/shared/model-pricing.json"
  [ -f "$f" ]
  for m in claude-opus-4-7 claude-opus-4-7-1m claude-sonnet-4-6 claude-haiku-4-5-20251001; do
    python3 -c "import json,sys;d=json.load(open('$f'));m=d['models'].get('$m');sys.exit(0 if m and 'input_per_mtok' in m else 1)" \
      || { echo "Missing model or wrong schema: $m"; return 1; }
  done
}

@test "[A] docs/error-recovery.md exists and has ≥22 headings" {
  local f="$PLUGIN_ROOT/docs/error-recovery.md"
  [ -f "$f" ]
  local count
  count=$(grep -c '^## [A-Z_][A-Z_]*$' "$f")
  [ "$count" -ge 22 ]
}

# -------- Group B (skipped until Commit 5 — Phase 2 fully landed) --------

@test "[B] shared/event-log.md declares 16 event types in header" {
  [[ "${FORGE_PHASE2_ACTIVE:-0}" = "1" ]] || skip "Phase 2 not fully landed (activates in Commit 5)"
  grep -qE "Event Types \(16\)" "$PLUGIN_ROOT/shared/event-log.md"
}

@test "[B] shared/event-log.md documents 4 new event types" {
  [[ "${FORGE_PHASE2_ACTIVE:-0}" = "1" ]] || skip "Phase 2 not fully landed (activates in Commit 5)"
  local f="$PLUGIN_ROOT/shared/event-log.md"
  for ev in "cost\.inc" "cap\.breach" "hook\.failure\.surfaced" "dispatch\.child"; do
    grep -qE "$ev" "$f" || { echo "Missing event type: $ev"; return 1; }
  done
}

@test "[B] hooks/session-start.sh defines print_hook_failure_banner function" {
  [[ "${FORGE_PHASE2_ACTIVE:-0}" = "1" ]] || skip "Phase 2 not fully landed (activates in Commit 5)"
  grep -q "print_hook_failure_banner" "$PLUGIN_ROOT/hooks/session-start.sh"
}

@test "[B] hooks/session-start.sh status badge includes cost suffix marker" {
  [[ "${FORGE_PHASE2_ACTIVE:-0}" = "1" ]] || skip "Phase 2 not fully landed (activates in Commit 5)"
  grep -q '• \$' "$PLUGIN_ROOT/hooks/session-start.sh" \
    || grep -q '\. \$' "$PLUGIN_ROOT/hooks/session-start.sh"
}

@test "[B] every agent with Agent in tools has Sub-agent dispatch section" {
  [[ "${FORGE_PHASE2_ACTIVE:-0}" = "1" ]] || skip "Phase 2 not fully landed (activates in Commit 4-5)"
  for f in "$PLUGIN_ROOT"/agents/fg-*.md; do
    local has_agent
    has_agent=$(awk '/^tools:/,/^[a-z_]+:/' "$f" | grep -c "Agent" || true)
    if [ "$has_agent" -gt 0 ]; then
      grep -q "^## Sub-agent dispatch" "$f" \
        || { echo "Missing ## Sub-agent dispatch in $f"; return 1; }
    fi
  done
}

@test "[B] escalation AskUserQuestion payloads include docs/error-recovery.md reference" {
  [[ "${FORGE_PHASE2_ACTIVE:-0}" = "1" ]] || skip "Phase 2 not fully landed (activates in Commit 5)"
  local allowlist='Cost cap|Quality gate|Lint fail|Test fail|Feedback loop|Build fail|Context overflow|MCP down|Recovery|Escalation'
  local bad=0
  for f in "$PLUGIN_ROOT"/agents/fg-*.md; do
    awk -v allow="$allowlist" '
      /^```json$/ {inj=1; blk=""; next}
      /^```$/ {
        if (inj && match(blk, "\"header\": *\"(" allow ")\"") && index(blk, "docs/error-recovery.md#") == 0) {
          print FILENAME ": allowlist header block lacks docs/error-recovery.md ref"
          exit 1
        }
        inj=0; blk=""; next
      }
      inj {blk = blk $0 "\n"; next}
    ' "$f" || bad=1
  done
  [ "$bad" -eq 0 ]
}

@test "[B] autonomous cap-breach auto-resolution is documented" {
  [[ "${FORGE_PHASE2_ACTIVE:-0}" = "1" ]] || skip "Phase 2 not fully landed (activates in Commit 5)"
  # Closes spec AC #26: autonomous + ask auto-resolves to Recommended option, logged with specific format
  local f="$PLUGIN_ROOT/shared/cost-tracking.md"
  grep -qE "\[AUTO: cap breach raised to \\\$" "$f" \
    || { echo "Missing [AUTO: cap breach raised to \$N] log format in cost-tracking.md §4"; return 1; }
  grep -q "autonomous" "$PLUGIN_ROOT/agents/fg-100-orchestrator.md" \
    || { echo "fg-100-orchestrator missing autonomous-mode cost-cap documentation"; return 1; }
}
```

- [ ] **Step 2: Static parse check**

```bash
bash -n tests/contract/observability-contract.bats
```

- [ ] **Step 3: Write `forge-recover-runtime.bats`**

```bash
#!/usr/bin/env bats

# Runtime --dry-run verification for /forge-recover (closes Phase 1 AC #23).

setup() {
  PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  FIXTURE_DIR="$(mktemp -d)"
  "$PLUGIN_ROOT/tests/helpers/forge-fixture.sh" create "$FIXTURE_DIR" > /dev/null
  "$PLUGIN_ROOT/tests/helpers/forge-fixture.sh" snapshot "$FIXTURE_DIR"
  export PLUGIN_ROOT FIXTURE_DIR
}

teardown() {
  "$PLUGIN_ROOT/tests/helpers/forge-fixture.sh" destroy "$FIXTURE_DIR" 2>/dev/null || true
}

@test "forge-fixture.sh creates a valid .forge/state.json" {
  [ -f "$FIXTURE_DIR/.forge/state.json" ]
  python3 -m json.tool "$FIXTURE_DIR/.forge/state.json" > /dev/null
}

@test "forge-fixture.sh snapshot/diff round-trip works" {
  "$PLUGIN_ROOT/tests/helpers/forge-fixture.sh" diff "$FIXTURE_DIR"
}

@test "forge-fixture.sh diff detects changes" {
  echo "changed" > "$FIXTURE_DIR/.forge/state.json"
  run "$PLUGIN_ROOT/tests/helpers/forge-fixture.sh" diff "$FIXTURE_DIR"
  [ "$status" -ne 0 ]
}

# True /forge-recover --dry-run invocation requires a live orchestrator.
# Phase 2 ships the fixture infrastructure; orchestrator-mock integration
# tests are scheduled for a later phase that wires an MCP-simulated orch.
# For Phase 2 we assert the skill SKILL.md advertises --dry-run on mutating
# subcommands, as a surface assertion.

@test "forge-recover SKILL.md advertises --dry-run" {
  grep -q "\-\-dry-run" "$PLUGIN_ROOT/skills/forge-recover/SKILL.md"
}
```

- [ ] **Step 4: Static parse check**

```bash
bash -n tests/contract/observability-contract.bats
bash -n tests/unit/skill-execution/forge-recover-runtime.bats
```

- [ ] **Step 5: Held for commit in Task 9**

---

## Task 9: Commit 2 — New docs + foundations

**Files in commit:**
- Create: `shared/model-pricing.json`, `shared/color-to-emoji-map.json`, `shared/observability-contract.md`, `shared/cost-tracking.md`, `docs/error-recovery.md`, `tests/helpers/forge-fixture.sh`, `tests/contract/observability-contract.bats`, `tests/unit/skill-execution/forge-recover-runtime.bats`

- [ ] **Step 1: Stage and commit**

```bash
git add shared/model-pricing.json shared/color-to-emoji-map.json
git add shared/observability-contract.md shared/cost-tracking.md
git add docs/error-recovery.md
git add tests/helpers/forge-fixture.sh
git add tests/contract/observability-contract.bats
git add tests/unit/skill-execution/forge-recover-runtime.bats
git commit -m "feat(phase2): foundations — new docs, contracts, bats, fixtures

Adds all 7 net-new files for observability:
- docs/error-recovery.md (22-entry user guide)
- shared/observability-contract.md (§1-§9)
- shared/cost-tracking.md
- shared/model-pricing.json (externalized per-model rates)
- shared/color-to-emoji-map.json (18-hue → 8-dot + ASCII fallback)
- tests/helpers/forge-fixture.sh (reusable .forge/ fixtures)
- tests/contract/observability-contract.bats (skeleton)
- tests/unit/skill-execution/forge-recover-runtime.bats

Additive only; no existing files changed. CI green because all
assertions reference new files that exist in this commit."
```

- [ ] **Step 2: No push yet** — batch push at Task 27.

---

## Task 10: Refactor Python heredoc in `shared/forge-token-tracker.sh` — load pricing from JSON

**Files modified:**
- Modify: `shared/forge-token-tracker.sh`

**Architectural note (per review):** `shared/forge-token-tracker.sh` is a bash script whose cost/pricing logic lives inside a Python heredoc `_TOKEN_UPDATE_PY` (roughly `:75-220`). The refactor edits the **Python** inside that heredoc, not bash. Pricing-table modifications happen in Python; no bash `eval` path is introduced.

- [ ] **Step 1: Locate the existing hardcoded pricing table inside the Python heredoc**

```bash
grep -n "DEFAULT_PRICING_TABLE\|_TOKEN_UPDATE_PY" shared/forge-token-tracker.sh
```

Expected: `_TOKEN_UPDATE_PY='` heredoc starts around `:79` and `DEFAULT_PRICING_TABLE = {` appears around `:147` inside it.

- [ ] **Step 2: Replace hardcoded pricing inside the Python heredoc with a JSON loader**

Find the `DEFAULT_PRICING_TABLE = {...}` block inside `_TOKEN_UPDATE_PY` and replace it with:

```python
# Load pricing from shared/model-pricing.json (canonical) + optional .local.json (override).
# Maintains per-MTok units matching the previous DEFAULT_PRICING_TABLE values.
import json as _json, os as _os
_FORGE_PLUGIN_ROOT = _os.environ.get("CLAUDE_PLUGIN_ROOT", "")
_PRICING_CANONICAL = _os.path.join(_FORGE_PLUGIN_ROOT, "shared", "model-pricing.json")
_PRICING_LOCAL = _os.path.join(_FORGE_PLUGIN_ROOT, "shared", "model-pricing.local.json")

DEFAULT_PRICING_TABLE = {}
_unknown_fallback = {"input": 15.0, "output": 75.0}

try:
    with open(_PRICING_CANONICAL) as _f:
        _raw = _json.load(_f)
    for _name, _rates in _raw.get("models", {}).items():
        # Map new JSON schema (input_per_mtok) to existing code's field names (input/output)
        DEFAULT_PRICING_TABLE[_name] = {
            "input": float(_rates["input_per_mtok"]),
            "output": float(_rates["output_per_mtok"]),
        }
    if "unknown_model_fallback" in _raw:
        _unknown_fallback = {
            "input": float(_raw["unknown_model_fallback"]["input_per_mtok"]),
            "output": float(_raw["unknown_model_fallback"]["output_per_mtok"]),
        }
    if _os.path.exists(_PRICING_LOCAL):
        with open(_PRICING_LOCAL) as _f:
            _local = _json.load(_f)
        for _name, _rates in _local.get("models", {}).items():
            DEFAULT_PRICING_TABLE[_name] = {
                "input": float(_rates["input_per_mtok"]),
                "output": float(_rates["output_per_mtok"]),
            }
except Exception as _e:
    # Fallback to legacy hardcoded table to preserve behavior if JSON missing
    DEFAULT_PRICING_TABLE = {
        "haiku":   {"input": 0.25,  "output": 1.25},
        "sonnet":  {"input": 3.0,   "output": 15.0},
        "opus":    {"input": 15.0,  "output": 75.0},
    }

# Alias: when a model name (e.g., "claude-sonnet-4-6") resolves to a tier (haiku/sonnet/opus),
# keep existing lookup path working. Add direct keys too.
for _tier_key, _tier in (("haiku","haiku"),("sonnet","sonnet"),("opus","opus")):
    if _tier not in DEFAULT_PRICING_TABLE:
        # Derive tier rate from any model whose name contains the tier
        for _mn, _mr in DEFAULT_PRICING_TABLE.items():
            if _tier in _mn.lower():
                DEFAULT_PRICING_TABLE[_tier] = _mr
                break
```

This preserves the existing `DEFAULT_PRICING_TABLE["haiku"|"sonnet"|"opus"]` lookup path while allowing full model-name lookups (e.g., `"claude-sonnet-4-6"`). Existing code downstream that references `DEFAULT_PRICING_TABLE["sonnet"]` still works.

- [ ] **Step 3: Preserve external interface**

`state.cost.estimated_cost_usd` and `state.cost.per_stage.{N}` fields are unchanged. Existing `tests/contract/cost-observability.bats` assertions about cost math continue to pass because per-MTok rates are identical to the hardcoded table (e.g., sonnet 3.0/15.0).

- [ ] **Step 4: Static parse check**

```bash
bash -n shared/forge-token-tracker.sh
# Also sanity-check the heredoc parses as Python
awk "/^_TOKEN_UPDATE_PY='/,/^'\$/" shared/forge-token-tracker.sh \
  | sed "s/^_TOKEN_UPDATE_PY='//; s/^'\$//" \
  | python3 -c "import sys; compile(sys.stdin.read(), '<heredoc>', 'exec')"
```

Expected: no output (valid bash, valid Python).

- [ ] **Step 5: Held for commit in Task 12**

---

## Task 11: Extend `shared/forge-token-tracker.sh` — emit `cost.inc` event + sprint-mode path

**Files modified:**
- Modify: `shared/forge-token-tracker.sh` (continuation of Task 10's edits)

- [ ] **Step 1: Add `emit_cost_inc` and `emit_cap_breach` functions**

Uses the existing `acquire_lock_with_retry` helper from `shared/platform.sh` (per `shared/event-log.md:374`) and Python (not `bc`) for float comparison. Guards against empty `run_id` and special chars.

Append to the bash section of `shared/forge-token-tracker.sh` (outside the Python heredoc):

```bash
# shellcheck source=./platform.sh
# Lock helper sourced from platform.sh (existing infrastructure).
: "${CLAUDE_PLUGIN_ROOT:?}"
# shellcheck disable=SC1091
source "${CLAUDE_PLUGIN_ROOT}/shared/platform.sh"

# Determine correct events path: sprint-child runs write to per-run file.
_events_log_path() {
  local run_id="$1"
  if [[ -n "$run_id" ]] && [[ "$run_id" =~ ^[a-zA-Z0-9_-]+$ ]] && [[ -d ".forge/runs/${run_id}" ]]; then
    echo ".forge/runs/${run_id}/events.jsonl"
  else
    echo ".forge/events.jsonl"
  fi
}

# Emit a cost.inc event. Args: run_id stage agent model tokens_in tokens_out cost_usd run_cost_usd cap_usd
emit_cost_inc() {
  local run_id="$1" stage="$2" agent="$3" model="$4"
  local tokens_in="$5" tokens_out="$6" cost_usd="$7" run_cost_usd="$8" cap_usd="$9"
  local events_path; events_path=$(_events_log_path "$run_id")
  local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  acquire_lock_with_retry "${events_path}.lock" 50 20 \
    || { echo "emit_cost_inc: could not acquire lock on ${events_path}.lock" >&2; return 1; }

  printf '{"ts":"%s","type":"cost.inc","run_id":"%s","stage":%s,"agent":"%s","model":"%s","tokens_in":%s,"tokens_out":%s,"cost_usd":%s,"run_cost_usd":%s,"cap_usd":%s}\n' \
    "$ts" "$run_id" "$stage" "$agent" "$model" "$tokens_in" "$tokens_out" "$cost_usd" "$run_cost_usd" "$cap_usd" \
    >> "$events_path"

  release_lock "${events_path}.lock"
}

# Emit cap.breach event when run_cost_usd first crosses cap_usd.
emit_cap_breach() {
  local run_id="$1" at_cost_usd="$2" cap_usd="$3"
  local events_path; events_path=$(_events_log_path "$run_id")
  local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  acquire_lock_with_retry "${events_path}.lock" 50 20 \
    || { echo "emit_cap_breach: could not acquire lock" >&2; return 1; }
  printf '{"ts":"%s","type":"cap.breach","run_id":"%s","at_cost_usd":%s,"cap_usd":%s}\n' \
    "$ts" "$run_id" "$at_cost_usd" "$cap_usd" >> "$events_path"
  release_lock "${events_path}.lock"
}

# Float comparison via Python (bc not universally installed).
_cost_gte() {
  python3 -c "import sys;sys.exit(0 if float(sys.argv[1])>=float(sys.argv[2]) else 1)" "$1" "$2"
}
```

(`acquire_lock_with_retry` and `release_lock` are the existing helpers in `shared/platform.sh`; signature per that file. If the exact function name differs, plan-executor must verify via `grep -n "acquire_lock\|release_lock" shared/platform.sh` and adjust.)

- [ ] **Step 2: Call `emit_cost_inc` from the existing cost-accumulation function**

Find the bash function in `forge-token-tracker.sh` that wraps the Python heredoc and commits cost updates. After the existing state write, add:

```bash
emit_cost_inc "$run_id" "$stage" "$agent" "$model" "$tokens_in" "$tokens_out" "$cost_usd" "$new_run_cost_usd" "${cap_usd:-0}"

# Check cap breach (Python float comparison; no bc)
if [[ -n "${cap_usd:-}" ]] && [[ "${cap_usd}" != "0" ]]; then
  if _cost_gte "$new_run_cost_usd" "$cap_usd" && [[ "${cap_breached_already:-false}" != "true" ]]; then
    emit_cap_breach "$run_id" "$new_run_cost_usd" "$cap_usd"
    # Mark state.cost.cap_breached = true. Uses existing forge-state-write.sh API;
    # plan-executor must verify the exact subcommand (set|patch|update) via:
    #   grep "^[a-z_]*()" "${CLAUDE_PLUGIN_ROOT}/shared/forge-state-write.sh"
    "${CLAUDE_PLUGIN_ROOT}/shared/forge-state-write.sh" patch '{"cost":{"cap_breached":true}}'
  fi
fi
```

- [ ] **Step 3: Static parse check**

```bash
bash -n shared/forge-token-tracker.sh
```

- [ ] **Step 4: Held for commit in Task 12**

---

## Task 12: Commit 3 — Token tracker refactor + cost events

**Files:**
- Modify: `shared/forge-token-tracker.sh`

- [ ] **Step 1: Stage and commit**

```bash
git add shared/forge-token-tracker.sh
git commit -m "feat(phase2): refactor forge-token-tracker to load pricing from JSON + emit cost events

- Pricing loaded from shared/model-pricing.json (canonical) with optional
  shared/model-pricing.local.json override (deep-merge at models key)
- New emit_cost_inc function writes cost.inc event to events.jsonl
  (per-run-path in sprint mode, standard path otherwise)
- New emit_cap_breach function + state.cost.cap_breached atomic update
- External state interface unchanged (state.cost.estimated_cost_usd,
  state.cost.per_stage.{N} preserved) — existing cost-observability.bats
  assertions still pass"
```

- [ ] **Step 2: No push yet**

---

## Task 13: Add `## Sub-agent dispatch` section to 15 dispatch agents

**Files modified (15):**
- `agents/fg-010-shaper.md`, `fg-015-scope-decomposer.md`, `fg-020-bug-investigator.md`, `fg-050-project-bootstrapper.md`, `fg-090-sprint-orchestrator.md`, `fg-100-orchestrator.md`, `fg-103-cross-repo-coordinator.md`, `fg-150-test-bootstrapper.md`, `fg-160-migration-planner.md`, `fg-200-planner.md`, `fg-310-scaffolder.md`, `fg-400-quality-gate.md`, `fg-500-test-gate.md`, `fg-590-pre-ship-verifier.md`, `fg-600-pr-builder.md`

- [ ] **Step 1: Define the section template (applied to all 15)**

At the end of each agent's `.md` body (after any existing `## User-interaction examples` section from Phase 1), append:

```markdown

## Sub-agent dispatch

Per `shared/observability-contract.md §1`, every sub-agent dispatch this agent performs MUST:

1. Before dispatch: `TaskCreate` with status `pending`, subject `{dot} {agent_id} {short_purpose}` (where `{dot}` is resolved via `shared/color-to-emoji-map.json` from the target agent's `color:` field).
2. Immediately before `Agent` invocation: `TaskUpdate` to `in_progress`.
3. Immediately after `Agent` return: `TaskUpdate` to `completed` with `metadata.summary` = exit verdict.

Example for dispatching `fg-300-implementer` (color `green` → 🟢):

```
TaskCreate(subject: "🟢 fg-300 impl task 1/3", status: pending)
TaskUpdate(taskId, status: in_progress)  # before Agent call
Agent(...)
TaskUpdate(taskId, status: completed, metadata: {summary: "PASS"})
```

Hierarchical rendering via subject-line tree-drawing characters (`├─`, `└─`) is an orchestrator responsibility; sub-agent dispatchers use plain subject.
```

- [ ] **Step 2: Apply template to all 15 files**

Append the section verbatim to each of the 15 dispatch agent files.

- [ ] **Step 3: Held for commit in Task 15**

---

## Task 14: Extend `tests/contract/ui-frontmatter-consistency.bats` — sub-agent dispatch assertion

**Files modified:**
- Modify: `tests/contract/ui-frontmatter-consistency.bats`

- [ ] **Step 1: Add the assertion**

Append at end of file:

```bash
@test "every agent with Agent in tools has Sub-agent dispatch section" {
  for f in "$PLUGIN_ROOT"/agents/fg-*.md; do
    local has_agent
    has_agent=$(awk '/^tools:/,/^[a-z_]+:/' "$f" | grep -c "Agent" || true)
    if [ "$has_agent" -gt 0 ]; then
      grep -q "^## Sub-agent dispatch" "$f" \
        || { echo "Missing ## Sub-agent dispatch in $f"; return 1; }
      grep -q "shared/observability-contract.md" "$f" \
        || { echo "Dispatch section in $f doesn't reference observability-contract.md"; return 1; }
    fi
  done
}
```

- [ ] **Step 2: Update `shared/agent-ui.md` cross-reference**

Add at the end of `shared/agent-ui.md`:

```markdown
## See also

- `shared/observability-contract.md` — Phase 2 hierarchical TaskCreate rule for dispatching agents
```

- [ ] **Step 3: Static parse check**

```bash
bash -n tests/contract/ui-frontmatter-consistency.bats
```

- [ ] **Step 4: Held for commit in Task 15**

---

## Task 15: Commit 4 — Dispatch contract on 15 agents + ui-frontmatter extension

**Files:**
- Modify: 15 dispatch agent `.md` files + `shared/agent-ui.md` + `tests/contract/ui-frontmatter-consistency.bats`

- [ ] **Step 1: Stage and commit**

```bash
git add agents/fg-010-shaper.md agents/fg-015-scope-decomposer.md \
        agents/fg-020-bug-investigator.md agents/fg-050-project-bootstrapper.md \
        agents/fg-090-sprint-orchestrator.md agents/fg-100-orchestrator.md \
        agents/fg-103-cross-repo-coordinator.md agents/fg-150-test-bootstrapper.md \
        agents/fg-160-migration-planner.md agents/fg-200-planner.md \
        agents/fg-310-scaffolder.md agents/fg-400-quality-gate.md \
        agents/fg-500-test-gate.md agents/fg-590-pre-ship-verifier.md \
        agents/fg-600-pr-builder.md
git add shared/agent-ui.md
git add tests/contract/ui-frontmatter-consistency.bats
git commit -m "feat(phase2): hierarchical sub-agent dispatch contract

- 15 dispatch agents get ## Sub-agent dispatch section referencing
  shared/observability-contract.md §1
- shared/agent-ui.md cross-references the new contract
- tests/contract/ui-frontmatter-consistency.bats asserts every agent
  with Agent in tools has the section"
```

- [ ] **Step 2: No push yet**

---

## Task 16: Update `agents/fg-100-orchestrator.md` — cost cap + hook diagnose

**Files modified:**
- Modify: `agents/fg-100-orchestrator.md`

- [ ] **Step 1: Add `## Cost cap escalation` section**

Append new section after the existing `## Recovery op dispatch` section from Phase 1:

```markdown

## § Cost cap escalation

At each stage boundary, check `state.cost.cap_breached`. If true, read `cost_cap.action_on_breach` from config and act:

| Action | Behavior |
|---|---|
| `ask` (default) | Dispatch `AskUserQuestion` (Pattern 3) with header `"Cost cap"`, 3 options: raise cap 2× (Recommended), abort, force-continue. Record decision in `state.cost_cap_decisions`. |
| `abort` | Transition to `ABORTED` immediately; emit cap.breach event (already done by tracker); no prompt. |
| `warn_continue` | stderr warn; proceed. |

**Autonomous-mode overlay** (see `shared/cost-tracking.md §4`):
- `autonomous + ask` → auto-resolves to Recommended (raise 2×), logged `[AUTO: cap breach raised to $N]`.
- `autonomous + abort` → honored.
- `autonomous + warn_continue` → honored.

Reference: `shared/cost-tracking.md §3`, `docs/error-recovery.md#cost_cap_breach`.
```

- [ ] **Step 2: Extend existing `## Recovery op dispatch` section with `--hooks` branch**

Find the existing `## Recovery op dispatch` section. In the table, add a note to the `diagnose` row:

```markdown
When `--hooks` flag is set, additionally:
- Load `.forge/.hook-failures.log`
- Parse pipe-delimited format: `{ts} | {script} | {reason[:context]} | {detail}`
- Group by `{script, reason_prefix}` (prefix = substring before first `:`)
- Identify top failing hook by count
- For `L0_TIMEOUT` reasons, list "problem files" (files with >3 failures in `context`)
- Emit remediation suggestions per `shared/observability-contract.md §5`
- Output human-readable (default) or JSON (via --json)
```

- [ ] **Step 3: Held for commit in Task 22**

---

## Task 17: Extend `hooks/session-start.sh` — banner + cost suffix

**Files modified:**
- Modify: `hooks/session-start.sh`

- [ ] **Step 1: Find the existing status-badge output**

```bash
grep -n "Pipeline: state" hooks/session-start.sh
```

Expected: one line around `:178` showing the current `[forge] Pipeline: state=... mode=... score=... last_active=...` format.

- [ ] **Step 2: Extend the status-badge format with cost suffix**

Find the `print()` call emitting the badge. Modify to read `state.cost.estimated_cost_usd` and append ` • ${cost}` when > 0:

```python
# Read cost from state (if present)
cost_suffix = ""
try:
    cost = state.get("cost", {}).get("estimated_cost_usd", 0)
    if cost > 0:
        cost_suffix = f" • ${cost:.2f}"
except Exception:
    pass

print(f"[forge] Pipeline: state={stage} mode={mode} score={last_score} last_active={last_active}{cost_suffix}")
```

- [ ] **Step 3: Add `print_hook_failure_banner` function**

Before the main body of the hook (early in the script), add:

```bash
# Phase 2: surface hook failures at session start.
print_hook_failure_banner() {
  local log="${FORGE_HOME:-.forge}/.hook-failures.log"
  [[ -f "$log" ]] || return 0

  # Window: last 24h (configurable via forge-config.md observability.hook_failure_surface_window_hours)
  local window_hours="${FORGE_OBS_WINDOW_HOURS:-24}"
  local cutoff_ts
  cutoff_ts=$(python3 -c "import time,sys;print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(time.time()-$window_hours*3600)))")

  # Count failures newer than cutoff (pipe-delimited parse)
  local count last_entry
  count=$(awk -F' \\| ' -v cutoff="$cutoff_ts" '$1 > cutoff {c++} END {print c+0}' "$log")
  last_entry=$(awk -F' \\| ' -v cutoff="$cutoff_ts" '$1 > cutoff {last=$3 " on " $4} END {print last}' "$log")

  if [[ $count -gt 0 ]]; then
    >&2 echo "⚠️  $count hook check-engine failures in last ${window_hours}h (last: $last_entry)."
    >&2 echo "    Run /forge-recover diagnose --hooks for details."

    # Truncate log if it exceeds max
    local max_entries="${FORGE_OBS_LOG_MAX:-100}"
    local truncate_to="${FORGE_OBS_LOG_TRUNC:-50}"
    local line_count
    line_count=$(wc -l < "$log")
    if [[ $line_count -gt $max_entries ]]; then
      tail -n "$truncate_to" "$log" > "$log.tmp" && mv "$log.tmp" "$log"
    fi
  fi
}

# Call banner before the main status output
print_hook_failure_banner
```

- [ ] **Step 4: Static parse check**

```bash
bash -n hooks/session-start.sh
```

- [ ] **Step 5: Held for commit in Task 22**

---

## Task 18: Update `skills/forge-recover/SKILL.md` — add `--hooks` flag

**Files modified:**
- Modify: `skills/forge-recover/SKILL.md`

- [ ] **Step 1: Add `--hooks` to the `## Flags` section**

Find the `## Flags` section (from Phase 1). Under the existing flags, add:

```markdown
- **--hooks**: (diagnose only) include hook-failure analysis in the report
```

- [ ] **Step 2: Update examples to include the new flag**

Add one example to the existing `## Examples` block:

```
/forge-recover diagnose --hooks         # include hook-failure analysis
```

- [ ] **Step 3: Held for commit in Task 22**

---

## Task 19: Update `shared/event-log.md` — 16 types + RECOVERY.phase

**Files modified:**
- Modify: `shared/event-log.md`

- [ ] **Step 1: Update the header count**

Find `Event Types (12)` heading; change to `Event Types (16)`.

Update the envelope `type` field description if it references the count.

- [ ] **Step 2: Add 4 new event type rows to the events table**

Under the existing table, append:

```markdown
| `cost.inc` | Cost tick after Agent dispatch | `{run_id, stage, agent, model, tokens_in, tokens_out, cost_usd, run_cost_usd, cap_usd}` | `forge-token-tracker.sh` |
| `cap.breach` | Cost cap crossed | `{run_id, at_cost_usd, cap_usd}` | `forge-token-tracker.sh` |
| `hook.failure.surfaced` | Banner displayed | `{window_hours, failure_count, top_type}` | `session-start.sh` |
| `dispatch.child` | Sub-agent dispatched | `{parent_stage, parent_task_id, child_agent, child_task_id}` | Dispatcher agents |
```

- [ ] **Step 3: Add RECOVERY.phase note**

Find the existing `RECOVERY` event type. Add a note:

```markdown
**Phase 2 extension.** `RECOVERY` gains optional `phase` field with values `start | end`, emitted bracketing non-transient recovery strategies. See `shared/observability-contract.md §7`.
```

- [ ] **Step 4: Held for commit in Task 22**

---

## Task 20: Update `shared/state-schema.md` + `shared/error-taxonomy.md` + `shared/recovery/recovery-engine.md`

**Files modified:**
- Modify: `shared/state-schema.md`
- Modify: `shared/error-taxonomy.md`
- Modify: `shared/recovery/recovery-engine.md`

- [ ] **Step 1: Update `shared/state-schema.md` — bump 1.6.0 → 1.7.0**

Find `"version": "1.6.0"`. Change to `"version": "1.7.0"`.

Add two new fields to the schema description:
- `cost.cap_breached` (boolean) — true once run_cost_usd >= cap_usd
- `cost_cap_decisions` (array) — per spec §4.2.6, history of user/auto decisions

Find the `schema_version_history` table and append:

```markdown
| 1.7.0 | 2026-04-16 | Phase 2 observability | Added `cost.cap_breached`, `cost_cap_decisions` |
```

- [ ] **Step 2: Update `shared/error-taxonomy.md` — add user_guide links**

For each of the 22 error rows, add an inline link to the `Meaning` column pointing at the anchor in `docs/error-recovery.md`.

Example (before):
```markdown
| LINT_FAILURE | MEDIUM | Agent-reported | Lint/format disagreement after auto-fix | 3-retry auto-fix |
```

After:
```markdown
| LINT_FAILURE | MEDIUM | Agent-reported | Lint/format disagreement after auto-fix. ([User guide](/docs/error-recovery.md#lint_failure)) | 3-retry auto-fix |
```

Slug rule: lowercase the error name, preserve underscores. `CONTEXT_OVERFLOW` → `#context_overflow`.

- [ ] **Step 3: Update `shared/recovery/recovery-engine.md` — add Task emission rule section**

Append a new section:

```markdown
## Task emission rule (Phase 2)

For every recovery **strategy** (not every retry), the agent applying the strategy MUST:

1. Emit `RECOVERY` event with `phase: start`.
2. `TaskCreate` a task with subject `🛟 Recovering from {error_type}: {strategy_name}` at `pending`.
3. `TaskUpdate` to `in_progress` when the strategy begins.
4. On return: `TaskUpdate` to `completed` with `metadata.outcome` = strategy result.
5. Emit `RECOVERY` event with `phase: end`.

**Exceptions — transient recoveries NOT emitted as tasks:**
- `FLAKY_TEST` single-retry
- Any recovery with `strategy: wait_and_retry` AND `wait_ms < 1000`

Enforcement: `tests/contract/recovery-engine.bats` (extended).
```

- [ ] **Step 4: Held for commit in Task 22**

---

## Task 21: Extend 3 bats files + `tests/validate-plugin.sh`

**Files modified:**
- Modify: `tests/contract/cost-observability.bats`
- Modify: `tests/contract/recovery-engine.bats`
- Modify: `tests/validate-plugin.sh`

- [ ] **Step 1: Extend `tests/contract/cost-observability.bats`**

Append Phase 2 assertions:

```bash
@test "Phase 2: forge-token-tracker.sh loads pricing from shared/model-pricing.json" {
  local f="$PLUGIN_ROOT/shared/forge-token-tracker.sh"
  grep -q "model-pricing.json" "$f"
  # No hardcoded DEFAULT_PRICING_TABLE remaining
  run grep -c "DEFAULT_PRICING_TABLE" "$f"
  [ "$status" -ne 0 ] || [ "$output" = "0" ]
}

@test "Phase 2: forge-token-tracker.sh emits cost.inc events" {
  grep -q "emit_cost_inc" "$PLUGIN_ROOT/shared/forge-token-tracker.sh"
}

@test "Phase 2: forge-token-tracker.sh checks sprint-mode per-run path" {
  grep -q ".forge/runs/\${run_id}\|.forge/runs/\$run_id" "$PLUGIN_ROOT/shared/forge-token-tracker.sh"
}

@test "Phase 2: orchestrator documents cost cap escalation section" {
  grep -q "^## § Cost cap escalation\|^## Cost cap escalation" "$PLUGIN_ROOT/agents/fg-100-orchestrator.md"
}
```

- [ ] **Step 2: Extend `tests/contract/recovery-engine.bats`**

Append:

```bash
@test "Phase 2: recovery-engine.md documents Task emission rule" {
  grep -q "^## Task emission rule" "$PLUGIN_ROOT/shared/recovery/recovery-engine.md"
}

@test "Phase 2: recovery-engine.md lists transient exceptions" {
  local f="$PLUGIN_ROOT/shared/recovery/recovery-engine.md"
  grep -q "FLAKY_TEST.*single-retry\|FLAKY_TEST" "$f"
  grep -q "wait_ms < 1000\|wait_and_retry.*1000" "$f"
}
```

- [ ] **Step 3: Extend `tests/validate-plugin.sh` — cross-link validator**

Append (or add to existing structural-check section):

```bash
# Cross-link validator: every user_guide link in shared/error-taxonomy.md
# AND every docs/error-recovery.md# reference anywhere in agents/ or shared/
# must resolve to a real heading in docs/error-recovery.md.
# Uses process substitution to avoid subshell-scope bug (bad=1 in a `while | read`
# pipeline is lost when the pipeline ends).

validate_error_recovery_links() {
  local guide="$PLUGIN_ROOT/docs/error-recovery.md"
  [[ -f "$guide" ]] || return 0

  local bad=0
  # Collect all referenced anchors from taxonomy + all agent .md + all shared .md
  # (forward validation includes orchestrator-referenced anchors like #cost_cap_breach
  # that may not exist in the taxonomy but must still resolve).
  local ref_sources=(
    "$PLUGIN_ROOT/shared/error-taxonomy.md"
    "$PLUGIN_ROOT"/agents/fg-*.md
    "$PLUGIN_ROOT"/shared/*.md
  )

  # Gather unique slug references
  local all_refs
  all_refs=$(grep -hoE 'docs/error-recovery.md#[a-z_][a-z_0-9]*' "${ref_sources[@]}" 2>/dev/null | sort -u)

  # Iterate via process substitution to keep $bad in the outer scope
  while read -r link; do
    [[ -z "$link" ]] && continue
    local slug="${link#*#}"
    local expected_heading
    expected_heading=$(echo "$slug" | tr 'a-z' 'A-Z')
    if ! grep -qE "^## ${expected_heading}\$" "$guide"; then
      echo "ERROR: $link referenced but '## $expected_heading' missing in docs/error-recovery.md"
      bad=1
    fi
  done < <(echo "$all_refs")

  return $bad
}

# Verify tests/helpers/forge-fixture.sh has shebang + chmod +x.
validate_fixture_helper() {
  local f="$PLUGIN_ROOT/tests/helpers/forge-fixture.sh"
  [[ -f "$f" ]] || return 0
  head -1 "$f" | grep -q "^#!/usr/bin/env bash" || { echo "ERROR: forge-fixture.sh missing shebang"; return 1; }
  [[ -x "$f" ]] || { echo "ERROR: forge-fixture.sh not executable"; return 1; }
}

# Run both
validate_error_recovery_links || FAILURES=$((FAILURES+1))
validate_fixture_helper || FAILURES=$((FAILURES+1))
```

- [ ] **Step 4: Static parse check**

```bash
bash -n tests/contract/cost-observability.bats
bash -n tests/contract/recovery-engine.bats
bash -n tests/validate-plugin.sh
```

- [ ] **Step 5: Held for commit in Task 22**

---

## Task 22: Commit 5 — Orchestrator + hook + skill + shared docs + test extensions

**Files:**
- Modify: `agents/fg-100-orchestrator.md`, `hooks/session-start.sh`, `skills/forge-recover/SKILL.md`, `shared/event-log.md`, `shared/state-schema.md`, `shared/error-taxonomy.md`, `shared/recovery/recovery-engine.md`, `tests/contract/cost-observability.bats`, `tests/contract/recovery-engine.bats`, `tests/validate-plugin.sh`

- [ ] **Step 1: Stage and commit**

```bash
git add agents/fg-100-orchestrator.md
git add hooks/session-start.sh
git add skills/forge-recover/SKILL.md
git add shared/event-log.md shared/state-schema.md shared/error-taxonomy.md
git add shared/recovery/recovery-engine.md
git add tests/contract/cost-observability.bats tests/contract/recovery-engine.bats
git add tests/validate-plugin.sh
git commit -m "feat(phase2): orchestrator cost cap + hook banner + skill --hooks + schema

- fg-100-orchestrator: ## Cost cap escalation + --hooks diagnose branch
- session-start.sh: print_hook_failure_banner (pipe-delimited parser)
  + cost suffix on status badge
- forge-recover SKILL.md: --hooks flag added to diagnose
- event-log.md: 12 → 16 types; RECOVERY.phase note
- state-schema.md: 1.6.0 → 1.7.0; cost.cap_breached + cost_cap_decisions
- error-taxonomy.md: user_guide links on all 22 rows
- recovery-engine.md: Task emission rule section
- cost-observability.bats: 4 Phase 2 assertions
- recovery-engine.bats: 2 task-emission assertions
- validate-plugin.sh: cross-link validator + fixture helper validation"
```

- [ ] **Step 2: No push yet**

---

## Task 23: Update `shared/config-schema.json` — observability + cost_cap fields

**Files modified:**
- Modify: `shared/config-schema.json`

- [ ] **Step 1: Inspect current structure**

```bash
python3 -m json.tool shared/config-schema.json | head -60
```

- [ ] **Step 2: Add observability + cost_cap properties to the top-level `properties` object**

Insert the following JSON schema fragments at the appropriate depth (follow the file's existing patterns for style):

```json
"observability": {
  "type": "object",
  "properties": {
    "sub_agent_tasks": {
      "type": "string",
      "enum": ["hierarchical", "flat", "off"],
      "default": "hierarchical"
    },
    "hook_failure_surface_window_hours": {
      "type": "integer",
      "default": 24,
      "minimum": 1
    },
    "hook_failure_log_max_entries": {
      "type": "integer",
      "default": 100,
      "minimum": 10
    },
    "hook_failure_log_truncate_to": {
      "type": "integer",
      "default": 50,
      "minimum": 10
    },
    "cost_streaming": {
      "type": "boolean",
      "default": true
    },
    "recovery_tasks": {
      "type": "string",
      "enum": ["non_transient", "all", "off"],
      "default": "non_transient"
    },
    "ascii_fallback_on_term_dumb": {
      "type": "boolean",
      "default": true
    }
  }
},
"cost_cap": {
  "type": "object",
  "properties": {
    "usd": {
      "type": "number",
      "default": 5.00,
      "minimum": 0
    },
    "action_on_breach": {
      "type": "string",
      "enum": ["ask", "abort", "warn_continue"],
      "default": "ask"
    }
  }
}
```

- [ ] **Step 3: Validate**

```bash
python3 -m json.tool shared/config-schema.json > /dev/null
```

- [ ] **Step 4: Held for commit in Task 26**

---

## Task 24: Update `README.md` — Observability section + version bump

**Files modified:**
- Modify: `README.md`

- [ ] **Step 1: Add "Observability" section**

Near existing feature sections (after "Pipeline" or similar), insert:

```markdown
## Observability (3.1.0+)

Forge streams what it's doing during long runs:

- **Hierarchical task view.** Every sub-agent dispatch appears as a child task, indented under its parent stage. You see which agent is running, which are queued, and what each returned.
- **Live cost.** Every `Agent` call updates `state.cost.estimated_cost_usd` and emits a `cost.inc` event. The session-start badge shows the running total (e.g., `[forge] Pipeline: state=IMPLEMENTING ... • $0.32`). Set `cost_cap.usd` to pause the run when spending crosses a threshold.
- **Hook failure banner.** Silent PostToolUse check-engine failures (tree-sitter L0 timeouts, missing linter deps, bash version warnings) now surface at session start with a one-line banner. `/forge-recover diagnose --hooks` shows per-hook breakdown.
- **Inline error recovery guidance.** When the pipeline escalates an error to you (`AskUserQuestion`), the prompt includes a link to `docs/error-recovery.md` and a 2-sentence recovery summary.

Contract: `shared/observability-contract.md`. Cost model: `shared/cost-tracking.md`.
```

- [ ] **Step 2: Bump version string**

Find any `Forge 3.0.0` / `v3.0.0` → `Forge 3.1.0` / `v3.1.0`.

- [ ] **Step 3: Held for commit in Task 26**

---

## Task 25: Update `CLAUDE.md` — Key Entry Points + CHANGELOG

**Files modified:**
- Modify: `CLAUDE.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add 5 new rows to `CLAUDE.md` Key Entry Points table**

```markdown
| Observability contract | `shared/observability-contract.md` |
| Cost tracking contract | `shared/cost-tracking.md` |
| Model pricing table | `shared/model-pricing.json` |
| Color → emoji map | `shared/color-to-emoji-map.json` |
| Error recovery user guide | `docs/error-recovery.md` |
```

- [ ] **Step 2: Update version references in `CLAUDE.md`**

Find any `3.0.0` and update as appropriate (the version is referenced in introduction).

- [ ] **Step 3: Add 3.1.0 entry to `CHANGELOG.md`**

At top under `# Changelog`:

```markdown
## [3.1.0] — 2026-04-16

### Added

- Hierarchical sub-agent `TaskCreate` contract for 15 dispatch agents (see `shared/observability-contract.md §1`).
- Live cost streaming: `cost.inc` events on every `Agent` return; session-start badge cost suffix; per-stage task-subject cost update.
- Hard `cost_cap.usd` with escalation (`ask` | `abort` | `warn_continue`); autonomous-mode honors action explicitly.
- Hook failure banner at session start (parses existing pipe-delimited `.forge/.hook-failures.log`).
- `/forge-recover diagnose --hooks` flag for hook-failure analysis.
- `docs/error-recovery.md` — 22-entry user-facing error guide.
- Inline `docs/error-recovery.md#` reference in every error-escalation `AskUserQuestion`.
- `shared/observability-contract.md`, `shared/cost-tracking.md`.
- `shared/model-pricing.json` (externalized per-model rates; `.local.json` override).
- `shared/color-to-emoji-map.json` (18 hues → 8 dots + ASCII fallback).
- `tests/helpers/forge-fixture.sh` — reusable `.forge/` fixture helpers.
- `tests/unit/skill-execution/forge-recover-runtime.bats` — closes Phase 1 AC #23.
- `tests/contract/observability-contract.bats` — 9-section contract assertions.
- State schema 1.6.0 → 1.7.0: `cost.cap_breached`, `cost_cap_decisions` fields.
- Event log: 12 → 16 event types; `RECOVERY` gains optional `phase` field.
- Recovery engine: task-emission rule for non-transient strategies.

### Changed

- `shared/forge-token-tracker.sh` refactored to load pricing from `shared/model-pricing.json` (no more hardcoded rates). External state interface unchanged.
- `hooks/session-start.sh` status badge extended with cost suffix.
- `shared/error-taxonomy.md` gains inline `user_guide:` links on all 22 entries.

### Non-breaking

No removals; no command surface changes. All additions are backwards-compatible with 3.0.0.
```

- [ ] **Step 4: Held for commit in Task 26**

---

## Task 26: Commit 6 — Config schema + top-level docs + version bump

**Files:**
- Modify: `shared/config-schema.json`, `README.md`, `CLAUDE.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`

- [ ] **Step 1: Bump plugin + marketplace JSON**

```bash
sed -i.bak 's/"version": "3.0.0"/"version": "3.1.0"/' .claude-plugin/plugin.json
sed -i.bak 's/"version": "3.0.0"/"version": "3.1.0"/' .claude-plugin/marketplace.json
rm -f .claude-plugin/plugin.json.bak .claude-plugin/marketplace.json.bak
```

- [ ] **Step 2: Stage and commit**

```bash
git add shared/config-schema.json README.md CLAUDE.md CHANGELOG.md
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "docs(phase2): config schema + top-level docs + bump 3.0.0 → 3.1.0

- shared/config-schema.json: observability.* + cost_cap.* fields
- README.md: Observability section + version string
- CLAUDE.md: 5 new Key Entry Points (observability-contract, cost-tracking,
  model-pricing, color-to-emoji-map, docs/error-recovery.md)
- CHANGELOG.md: 3.1.0 entry
- .claude-plugin/plugin.json: 3.0.0 → 3.1.0
- .claude-plugin/marketplace.json: 3.0.0 → 3.1.0"
```

- [ ] **Step 3: No push yet**

---

## Task 27: Push + CI + tag + release

- [ ] **Step 1: Push to origin**

```bash
git push origin master
```

- [ ] **Step 2: Wait for CI**

```bash
gh run watch
```

- [ ] **Step 3: If CI red, fix forward**

Identify failing test, fix in a new commit, re-push. No revert.

- [ ] **Step 4: If CI green, tag and release**

```bash
git tag -a v3.1.0 -m "Phase 2: Observability & Progress

- Hierarchical sub-agent TaskCreate for 15 dispatch agents
- Live cost streaming (4 channels: stage-task, events.jsonl, session badge, cost cap)
- Hook failure banner + /forge-recover diagnose --hooks
- docs/error-recovery.md user guide + inline AskUserQuestion refs
- Additive only (no breaking changes)"
git push origin v3.1.0

gh release create v3.1.0 --title "3.1.0 — Phase 2: Observability & Progress" \
  --notes-file - <<'EOF'
See CHANGELOG.md for the full entry. Highlights:

- Every sub-agent dispatch is now a visible task.
- Live cost streams to your terminal and to .forge/events.jsonl.
- Silent hook failures surface at session start.
- Error escalations now include inline recovery guidance.

No breaking changes. Drop-in upgrade from 3.0.0.

Next phase: Phase 3 — Cross-platform hardening.
EOF
```

---

## Self-review (done by plan author)

### 1. Spec coverage

| Spec section | Implementing task(s) |
|---|---|
| §4.1 Hierarchical TaskCreate contract | Task 13 (apply to 15 agents), Task 14 (bats assertion) |
| §4.1.1 Color-to-emoji mapping | Task 3 (create JSON), Task 4 (document in contract) |
| §4.2.1 Externalize model pricing | Task 2 (create JSON), Task 10 (refactor tracker) |
| §4.2.2 Emit cost.inc events | Task 11 |
| §4.2.3 Event log additions | Task 19 |
| §4.2.4 Per-stage task cost | Task 16 (orchestrator cost cap escalation section documents it) |
| §4.2.5 Session-start badge | Task 17 |
| §4.2.6 Cost cap escalation | Task 16, Task 11 (tracker emits cap.breach) |
| §4.3 Hook failure banner + /forge-recover --hooks | Task 17 (banner), Task 16 (--hooks branch), Task 18 (SKILL.md) |
| §4.4.1 docs/error-recovery.md | Task 6 |
| §4.4.2 Inline AskUserQuestion guidance | Task 8 (bats assertion in observability-contract.bats) |
| §4.4.3 error-taxonomy user_guide links | Task 20 |
| §4.5 Recovery task emission | Task 20, Task 21 |
| §4.6 Runtime integration test | Task 7, Task 8 |
| §4.7 Observability contract | Task 4 |
| §4.8 Config schema additions | Task 23 |
| §4.9 Doc updates | Tasks 24, 25, 26 |

Gap check: all spec requirements covered. ✅

### 2. Placeholder scan

- Task 6 Step 4 asks the implementer to write 19 entries following the pattern; 3 full examples provided (LINT_FAILURE, CONTEXT_OVERFLOW, BUILD_FAILURE). Rationale: error catalog content is mechanical (each entry follows the same 5-field template sourced from taxonomy + recovery-engine), so this is not a creative-composition risk. Acceptable.
- Task 10 Step 2 uses `# Wire it:` prose instruction — concrete function body above it. Acceptable.
- No `TBD`, `implement later`, `similar to Task N` found. ✅

### 3. Type consistency

- `FORGE_PRICE_IN_<model>` / `FORGE_PRICE_OUT_<model>` vars — consistent throughout Tasks 10.
- `cost.inc` event schema — identical in Task 11, Task 19, and spec.
- `cost_cap_decisions` field name — identical in Tasks 16, 20, and spec.
- Slug rule — consistent: lowercase, preserve underscores.

### Plan self-review conclusion

Complete and internally consistent. Proceed to code-reviewer dispatch.

---

**Plan complete and saved to `docs/superpowers/plans/2026-04-16-phase2-observability-and-progress.md`.**
