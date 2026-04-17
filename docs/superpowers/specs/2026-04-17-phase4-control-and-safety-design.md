# Phase 4 — Control & Safety (Design)

**Status:** Draft for review
**Date:** 2026-04-17
**Target version:** Forge 4.0.0 (**SemVer major** — `fg-300-implementer` write target changes from `.forge/worktree/` to `.forge/pending/`)
**Author:** Denis Šajnar (authored with Claude Opus 4.7)
**Phase sequence:** 4 of 7
**Depends on:** Phase 3 merged (3.2.0 released — uses `release_lock`, `safe_realpath`, `acquire_lock_with_retry` from the extended `platform.sh`).

---

## 1. Goal

Give the user a **steering wheel during a long autonomous run**. Today's control points are start (user invokes `/forge-run`) and end (user approves the PR). Phase 4 adds four continuous control mechanisms: (1) preview-before-apply via a `.forge/pending/` staging overlay; (2) an editable plan file the user can tweak before implementation begins; (3) tiered auto-approve scopes (`read_test`, `write`, `apply`, `deploy`) so autonomous mode is configurable rather than all-or-nothing; (4) a formal 4-level escalation taxonomy so error-escalation flows are auditable and consistent.

## 2. Context and motivation

The April 2026 UX audit graded control/safety **C** and identified:

1. **No preview before apply.** `fg-300-implementer` writes directly to `.forge/worktree/`. A rogue run can only be undone via `git reset` or `/forge-recover rollback`. Competing tools (Plandex, Cline) ship a staging layer.
2. **Plan is opaque.** `EnterPlanMode`/`ExitPlanMode` is a black-box; user can't edit the plan mid-flow. Gemini CLI lets users edit the plan file before acting.
3. **Autonomous is binary.** `autonomous: true/false` — no middle ground. User who wants "auto-run tests, ask before writing" must either fully trust or fully supervise.
4. **Escalation levels are implicit.** `CLAUDE.md` mentions E1-E4 in multiple places but no contract defines them. Each agent improvises the escalation flow.

No backwards compatibility required (single-user plugin).

## 3. Non-goals

- **No time-machine rollback.** `/forge-reject` + standard git are the rollback tools. No snapshot history beyond `.forge/plans/archive/`.
- **No multi-user approval workflows.** Single-user plugin; any "approver" is the user.
- **No TUI.** Deferred to Phase 5 (`/forge-watch`). Phase 4 uses `AskUserQuestion` and plain-text `/forge-preview` diffs.
- **No automatic E3 data-risk heuristics.** Agents emit E3 explicitly; no magic "this destroys 100 files — escalate" detection.
- **No changes to recovery engine strategies.** Phase 4 adds emission flow (E1-E4 taxonomy) but the existing recovery strategies in `shared/recovery/recovery-engine.md` are unchanged in behavior.
- **No changes to convergence engine.** Plan edits re-trigger VALIDATE but do not reset convergence counters.
- **Deferred to later phases:** TUI (Phase 5), FE UX (Phase 6), Go binary (Phase 7).

## 4. Design

### 4.1 Preview-before-apply — staging overlay

#### 4.1.1 Directory structure

```
.forge/
├─ worktree/                     # stable; git-tracked (unchanged)
├─ pending/                      # NEW — staging overlay
│   ├─ src/
│   │   └─ auth/login.ts         # staged change
│   └─ README.md                 # staged change
└─ plans/
    ├─ current.md                # NEW (§4.2)
    └─ archive/                  # NEW
```

`.forge/pending/` mirrors project structure. Gitignored via the existing `.forge/` entry. No additional git changes.

#### 4.1.2 `fg-300-implementer.md` contract change

Currently (line 533): `DO NOT write outside project root/worktree. Verify target path within .forge/worktree`.

New contract:

- **Reads** go through a new `shared/forge-resolve-file.sh` helper that prefers `.forge/pending/<path>` over `.forge/worktree/<path>`. Implementer gets up-to-date context even across multi-task runs where an earlier task's changes haven't been applied yet.
- **Writes** go to `.forge/pending/<path>` exclusively. Path verification changes from `Verify target path within .forge/worktree` to `Verify target path within .forge/pending`.
- **Tests and lint** (inner loop from Phase 1) run against the overlay view: shell helper composes overlay by copying pending files into a scratch directory layered on worktree, then runs the test command there. Scratch cleanup on return.

#### 4.1.3 `shared/forge-resolve-file.sh` (new)

```
Usage: forge-resolve-file.sh <subcommand> <args>

Subcommands:
  read <relative-path>       Print file contents (prefers pending over worktree).
                             Exits 2 if neither exists.
  exists <relative-path>     Returns 0 if file exists in pending or worktree.
  overlay-view <out-dir>     Copies worktree into out-dir, then overlays pending.
                             Used by inner-loop test/lint execution.
  diff                        Emit unified diff of pending vs worktree (used by
                             /forge-preview).
```

Behavior:
- `read`: `[[ -f .forge/pending/$path ]] && cat .forge/pending/$path || cat .forge/worktree/$path`
- `overlay-view`: `rsync -a .forge/worktree/ $out/` then `rsync -a .forge/pending/ $out/`
- `diff`: `diff -Nur .forge/worktree .forge/pending` with `-x .git`

#### 4.1.4 New skills — `/forge-preview`, `/forge-apply`, `/forge-reject`

**`/forge-preview`** — `[read-only]`:
- Invokes `shared/forge-resolve-file.sh diff`
- `--json` flag emits `{files_changed: [...], additions: N, deletions: N, diff: "..."}`
- Exit codes per `shared/skill-contract.md`

**`/forge-apply`** — `[writes]`:
- Promotes `.forge/pending/` → `.forge/worktree/` via:
  ```bash
  rsync -a .forge/pending/ .forge/worktree/
  rm -rf .forge/pending
  ```
- `--dry-run` lists files that would be promoted, does not write
- Emits `apply.committed` event to `.forge/events.jsonl`
- State transition: APPLY_GATE → IMPLEMENTING (next task) OR → VERIFYING (last task)

**`/forge-reject`** — `[writes]`:
- Discards `.forge/pending/` via `rm -rf`
- `--dry-run` lists files that would be discarded
- Requires confirmation via `AskUserQuestion` unless `FORGE_DRY_RUN=1` or autonomous mode with `scopes: [... reject]` (not a default scope)
- Emits `apply.rejected` event
- State transition: APPLY_GATE → IMPLEMENTING (task retried with user's REVISE notes) OR → ESCALATED if `feedback_loop_count >= 2`

#### 4.1.5 New pipeline state: `APPLY_GATE`

After IMPLEMENTING completes, orchestrator transitions to `APPLY_GATE` instead of directly to VERIFYING.

```
IMPLEMENTING → APPLY_GATE → VERIFYING   (non-autonomous or scope not in autonomous.scopes)
IMPLEMENTING → VERIFYING                 (autonomous + 'apply' in scopes — auto-apply)
```

`APPLY_GATE` behavior:
- Orchestrator emits an `AskUserQuestion` (Pattern 1 — single-choice with preview):
  ```json
  {
    "question": "Implementation task 2 of 3 complete. Review pending changes?",
    "header": "Apply gate",
    "multiSelect": false,
    "options": [
      {"label": "Apply changes (Recommended)", "description": "Promote .forge/pending/ to worktree and continue.", "preview": "<unified diff>"},
      {"label": "Reject changes", "description": "Discard .forge/pending/; implementer retries with your notes."},
      {"label": "Keep staged — I'll review manually", "description": "Pipeline pauses; use /forge-preview and /forge-apply or /forge-reject later."}
    ]
  }
  ```
- If "Keep staged": pipeline sets `state.story_state: APPLY_GATE_WAIT` and exits normally; `/forge-recover resume` picks up from here.

#### 4.1.6 State schema additions

New `state.json` fields:

- `story_state` gains values: `APPLY_GATE`, `APPLY_GATE_WAIT`, `PLAN_EDIT_WAIT`
- `state.pending` object (new):
  ```json
  {
    "files": ["src/auth/login.ts", "README.md"],
    "additions": 45,
    "deletions": 12,
    "created_at": "2026-04-17T15:30:00Z"
  }
  ```
- Schema version 1.7.0 → 1.8.0

### 4.2 Editable plan file

#### 4.2.1 File locations

```
.forge/plans/
├─ current.md                  # editable; one per run
└─ archive/
    ├─ 2026-04-17T12-00-00.md  # pre-edit snapshot
    └─ 2026-04-17T12-15-00.md  # post-validate snapshot
```

Both gitignored.

#### 4.2.2 `fg-200-planner.md` contract change

At the end of PLAN stage, planner writes the full plan markdown to `.forge/plans/current.md`. No longer emits plan content via `EnterPlanMode` body directly; instead:

1. Write plan to `.forge/plans/current.md`.
2. Copy to `.forge/plans/archive/<ISO-timestamp>.md` (pre-validate snapshot).
3. Compute SHA256 of current.md; write to `state.json.plan.sha256`.
4. Emit `state.story_state: PLAN_EDIT_WAIT` (non-autonomous) or transition directly to VALIDATING (autonomous, scope `read_test` only).
5. `EnterPlanMode` invoked with `<content of .forge/plans/current.md>` — user still sees the plan in the existing approval UI, but the source is the file.

#### 4.2.3 `fg-210-validator.md` contract change

At start of VALIDATE:
1. Compute SHA256 of `.forge/plans/current.md`; compare to `state.json.plan.sha256`.
2. If changed → user edited the plan:
   - Copy current.md to `.forge/plans/archive/<ISO-timestamp>.md` (post-edit snapshot).
   - Re-run all 7 validation perspectives against the edited plan.
   - Update `state.json.plan.sha256` to the new SHA.
   - Continue validation normally.
3. If unchanged → proceed with existing validation logic.

Spec AC asserts this two-path behavior.

#### 4.2.4 `PLAN_EDIT_WAIT` state behavior

- Orchestrator in `PLAN_EDIT_WAIT` does NOT auto-transition to VALIDATING.
- User invokes `/forge-run --resume` (uses existing resume skill) OR edits `.forge/plans/current.md` and invokes `/forge-plan-done` (new micro-skill, see §4.2.5).
- `/forge-abort` from this state discards the plan and transitions to ABORTED.

#### 4.2.5 New skill — `/forge-plan-done`

`[writes]` — signals plan editing is complete. Transitions `PLAN_EDIT_WAIT` → `VALIDATING`. Minimal body: read state, update, emit transition event.

No `--dry-run` (it's a state flip; no file writes beyond state.json).

### 4.3 Tiered auto-approve scopes

#### 4.3.1 Config schema addition

`forge.local.md` / `forge-config.md`:

```yaml
autonomous:
  enabled: true             # unchanged from Phase 2
  scopes:                   # NEW: list of auto-approved action classes
    - read_test
    - write
  # absent or empty → no auto-approval even if enabled: true
```

`shared/config-schema.json` gets the new field with enum validation.

#### 4.3.2 `shared/autonomous-scopes.md` (new contract doc)

Scope definitions:

| Scope | Action classes covered | Examples |
|---|---|---|
| `read_test` | Reads, static analysis, test execution, lint, build (no source mutation) | `cat file.ts`, `pnpm test`, `ruff check`, `bash -n script.sh` |
| `write` | Writes to `.forge/pending/` only | `fg-300-implementer` writes |
| `apply` | Promotes pending → worktree | `/forge-apply`, orchestrator APPLY_GATE auto-advance |
| `deploy` | External side-effects | `git push`, `gh pr create`, `gh release create`, PR comments |

**Default scope sets:**
- `autonomous: { enabled: true, scopes: [read_test] }` — conservative default; pipeline runs read-only tests but pauses at every write/apply/deploy
- `autonomous: { enabled: true, scopes: [read_test, write] }` — **recommended default** for automation-friendly users; implementer runs but APPLY_GATE pauses for review
- `autonomous: { enabled: true, scopes: [read_test, write, apply] }` — trust-based; only `deploy` still gates
- `autonomous: { enabled: true, scopes: [read_test, write, apply, deploy] }` — full autonomous (equivalent to current `autonomous: true`)
- `autonomous: { enabled: false }` — all scopes gate (equivalent to current default)

Migration from 3.x config:
- `autonomous: true` (old) → `autonomous: { enabled: true, scopes: [read_test, write, apply, deploy] }` (new)
- `autonomous: false` (old) → `autonomous: { enabled: false }`
- Orchestrator on startup detects old scalar form, logs a warning event `config.autonomous_legacy_scalar`, interprets as above. No BC shim in code beyond detection (per user's no-BC rule — document in `DEPRECATIONS.md ## Changed in 4.0.0`).

#### 4.3.3 Orchestrator scope check

`fg-100-orchestrator.md` gains a new § "Scope gating". Before every action class, orchestrator checks `autonomous.scopes`:

```
check_scope(action_class) → boolean

  if !autonomous.enabled: return false  # always gate
  return action_class in autonomous.scopes
```

If `false`, orchestrator emits E2 `AskUserQuestion` (per §4.4). If `true`, proceeds.

### 4.4 Escalation taxonomy — `shared/escalation-taxonomy.md` (new)

#### 4.4.1 4 levels

| Level | Trigger | Emission | User flow | Rollback path | State impact |
|---|---|---|---|---|---|
| **E1 advisory** | Non-blocking info (recovered transient error, scope auto-approved, plan edit detected) | Event `escalation.e1` on `.forge/events.jsonl` with `{level, source_agent, message, stage}`. Shown in `/forge-status`. | None | N/A | No transition |
| **E2 decision** | Recoverable decision point (scope gate, FAIL verdict, LINT_FAILURE after retries) | Event `escalation.e2` + `AskUserQuestion` using Pattern 3 (safe-default). Must reference `docs/error-recovery.md#<anchor>`. | User picks option; orchestrator acts | User choice directs flow | Stays in current stage |
| **E3 data-risk** | Potential data loss or destructive operation mid-run (>100 lines deleted, bulk rm, force-push candidate) | Event `escalation.e3` + alert in `.forge/alerts.json` + `AskUserQuestion` with options `[roll back, continue, abort]` | User choice; orchestrator can invoke `git reset --hard $prev_sha` for rollback | `git reset` to pre-stage SHA OR discard pending | Pauses until user responds |
| **E4 abort** | Unrecoverable (E3 rollback failed, recovery budget exhausted, user `/forge-abort`) | Event `escalation.e4` + alert; NO `AskUserQuestion` (user already committed) | None | None; use `/forge-run` to start over | `state.story_state → ABORTED`; `state.abort_reason` populated |

#### 4.4.2 Emission contract

Any agent can emit any level. Contract rules:

- **E1:** agent emits `stage_note.escalation = {level: 'E1', ...}` at any point; orchestrator adds to event log
- **E2:** agent stage-return includes `escalation: {level: 'E2', question: {...AskUserQuestion payload}}`; orchestrator dispatches the question
- **E3:** same as E2 but orchestrator ALSO writes to `.forge/alerts.json` and PAUSES all subsequent dispatches in the stage
- **E4:** agent emits `escalation: {level: 'E4', reason: '...'}`; orchestrator transitions state immediately

#### 4.4.3 Auditing existing references

Every `E1|E2|E3|E4` mention in agent `.md` files is audited to reference the taxonomy by level name with a description matching the level's semantics. The implementation plan enumerates the files.

### 4.5 Mid-stage `ask_user` (default behavior — from brainstorming)

#### 4.5.1 Allowed stages

| Stage | Mid-stage `ask_user` allowed? | Rationale |
|---|---|---|
| PREFLIGHT | No (must escalate via E2) | Should run unattended |
| EXPLORING | No | Pure information-gathering; pause with E2 if stuck |
| PLANNING | Yes | Gemini-CLI pattern; planner can ask clarifying Qs |
| VALIDATING | No | Pure validation; emit REVISE verdict instead |
| IMPLEMENTING | Yes | Ambiguous requirements surface here |
| VERIFYING | No (emit E2 on test failure loops) | Should run unattended |
| REVIEWING | Yes | Reviewers can ask about ambiguous finding |
| DOCUMENTING | No | Should generate automatically |
| SHIPPING | No (emit E3 on destructive choice) | Approve PR is the gate |
| LEARNING | No | Retrospective is autonomous |

#### 4.5.2 Mechanism

New `shared/observability-contract.md §10 Mid-stage ask_user`:

- Child agent emits `stage_note.ask_user` = `AskUserQuestion` payload in normal stage output.
- Orchestrator detects in stage notes, dispatches the question to user.
- User response captured, injected into child agent's next dispatch as `ask_user_answer = "..."` input.
- Child agent proceeds.

Agents in forbidden stages that emit `stage_note.ask_user` trigger orchestrator to escalate as E2 with the payload.

### 4.6 State machine updates (`shared/state-transitions.md`)

New transitions:

```
PLANNING      →  PLAN_EDIT_WAIT    # non-autonomous, plan written
PLAN_EDIT_WAIT → VALIDATING        # /forge-plan-done OR /forge-run --resume OR autonomous + read_test scope
IMPLEMENTING  →  APPLY_GATE        # task complete
APPLY_GATE    →  IMPLEMENTING      # "reject" chosen, task retries
APPLY_GATE    →  APPLY_GATE_WAIT   # "keep staged" chosen
APPLY_GATE    →  VERIFYING         # "apply" chosen OR autonomous + apply scope
APPLY_GATE_WAIT → APPLY_GATE       # /forge-apply OR /forge-reject invoked
PLAN_EDIT_WAIT → ABORTED           # /forge-abort
APPLY_GATE_WAIT → ABORTED          # /forge-abort
```

Plus existing transitions to ABORTED/ESCALATED from new states.

### 4.7 Documentation updates

- `README.md` — new "Control & safety" section; mention staging overlay, editable plan, tiered scopes, escalation levels; version bump.
- `CLAUDE.md` — 4 new Key Entry Points (`staging-overlay.md`, `autonomous-scopes.md`, `escalation-taxonomy.md`, `.forge/plans/` layout); new skill rows for `/forge-preview`, `/forge-apply`, `/forge-reject`, `/forge-plan-done`; skill count `35 → 39`.
- `DEPRECATIONS.md` — new `## Changed in 4.0.0` section documenting the implementer write-target change and `autonomous` scalar → object rewrite.
- `CHANGELOG.md` — 4.0.0 entry.
- `docs/control-safety.md` — new user-facing guide explaining the preview/apply/reject workflow, tiered autonomous, and what each escalation level means in practice.
- `.claude-plugin/plugin.json`, `marketplace.json` — `3.2.0 → 4.0.0`.

## 5. File manifest (authoritative)

### 5.1 Delete (0)

None.

### 5.2 Create (11)

```
shared/staging-overlay.md                  # contract doc
shared/autonomous-scopes.md                # contract doc
shared/escalation-taxonomy.md              # contract doc
shared/forge-resolve-file.sh               # pending-over-worktree resolver
skills/forge-preview/SKILL.md              # read-only diff
skills/forge-apply/SKILL.md                # promote pending
skills/forge-reject/SKILL.md               # discard pending
skills/forge-plan-done/SKILL.md            # signal plan edit complete
docs/control-safety.md                     # user guide
tests/contract/escalation-taxonomy.bats    # assertion set
tests/contract/staging-overlay.bats        # assertion set
tests/unit/skill-execution/forge-apply-reject.bats  # runtime test
```

**Count reconciliation:** 11 in §5.2 list above excluding the `tests/unit/` file which is a 12th. Actual total: 12.

Revised creation count: **12 files**.

### 5.3 Update in place

**Agents (4 files):**

- `agents/fg-200-planner.md` — write plan to `.forge/plans/current.md`; emit `PLAN_EDIT_WAIT` in non-autonomous mode
- `agents/fg-210-validator.md` — SHA256 watch + re-run on edit
- `agents/fg-300-implementer.md` — write target change (`.forge/worktree/` → `.forge/pending/`); read via `forge-resolve-file.sh`
- `agents/fg-100-orchestrator.md` — scope gating, APPLY_GATE handling, PLAN_EDIT_WAIT handling, E1-E4 emission; adds `## § Scope gating`, `## § APPLY_GATE handling`, `## § PLAN_EDIT_WAIT handling` sections

**Shared docs (5 files):**

- `shared/state-schema.md` — bump 1.7.0 → 1.8.0; add `pending`, `plan` objects; add new `story_state` enum values
- `shared/state-transitions.md` — add 8 new transitions per §4.6
- `shared/observability-contract.md` — add §10 Mid-stage ask_user
- `shared/config-schema.json` — `autonomous: { enabled, scopes }` schema with enum validation on scopes
- `shared/output-compression.md` — acknowledge new events (`apply.committed`, `apply.rejected`, `escalation.e1-e4`, `config.autonomous_legacy_scalar`) may compress under lite/full/ultra modes

**Skill updates (4 existing skills):**

- `skills/forge-run/SKILL.md` — document `--resume` from `PLAN_EDIT_WAIT`, `APPLY_GATE_WAIT`
- `skills/forge-recover/SKILL.md` — `resume` subcommand handles new wait states
- `skills/forge-abort/SKILL.md` — document abort behavior from new wait states
- `skills/forge-status/SKILL.md` — display `pending` info and wait-state context

**Config (1 file):**

- `.claude-plugin/forge.local.md` templates updated with new `autonomous` shape (if templates are shipped — verify in plan)

**Top-level (6 files):**

- `README.md`, `CLAUDE.md`, `DEPRECATIONS.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`

### 5.4 File-count arithmetic

| Category | Count |
|---|---|
| Creations | 12 |
| Agent updates | 4 |
| Shared doc updates | 5 |
| Skill updates | 4 |
| Config | 1 |
| Top-level | 6 |
| **Unique file operations** | **32** |

## 6. Acceptance criteria

All verified by CI on push.

1. `shared/staging-overlay.md` exists and documents pending-dir mechanics.
2. `shared/autonomous-scopes.md` exists with 4 scope definitions.
3. `shared/escalation-taxonomy.md` exists with 4 levels: E1 advisory, E2 decision, E3 data-risk, E4 abort.
4. `shared/forge-resolve-file.sh` exists, executable, supports `read`, `exists`, `overlay-view`, `diff` subcommands.
5. `skills/forge-preview/SKILL.md`, `forge-apply/SKILL.md`, `forge-reject/SKILL.md`, `forge-plan-done/SKILL.md` exist with Phase 1 skill-contract compliance (`[read-only]`/`[writes]` badge, `## Flags`, `## Exit codes`).
6. `agents/fg-300-implementer.md` write target is `.forge/pending/`; old `.forge/worktree/` write language removed (line 533 patched).
7. `agents/fg-200-planner.md` writes `.forge/plans/current.md`; `agents/fg-210-validator.md` SHA256-watches it.
8. `agents/fg-100-orchestrator.md` contains `## § Scope gating`, `## § APPLY_GATE handling`, `## § PLAN_EDIT_WAIT handling` sections.
9. `shared/state-schema.md` version `1.8.0`; `pending` + `plan` objects documented; new `story_state` enum values present.
10. `shared/state-transitions.md` documents all 8 new transitions per §4.6.
11. `shared/observability-contract.md` contains `§10 Mid-stage ask_user` with the forbidden/allowed stages table.
12. `shared/config-schema.json` validates `autonomous: { enabled: bool, scopes: enum[] }` shape.
13. 4 updated skills reflect new wait states in their descriptions + body.
14. `skill-count` in `CLAUDE.md` is `39` (was 35 after Phase 1; +4 from this phase).
15. `tests/contract/escalation-taxonomy.bats` asserts every `E[1-4]` mention in agent `.md` matches the taxonomy.
16. `tests/contract/staging-overlay.bats` asserts `fg-300-implementer` never references `.forge/worktree/` in write-path sections.
17. `tests/unit/skill-execution/forge-apply-reject.bats` runtime-tests apply + reject against a fixture pending/worktree.
18. `docs/control-safety.md` exists with user-facing walkthroughs for all four deliverables.
19. `DEPRECATIONS.md` has `## Changed in 4.0.0` section covering the two config migrations.
20. `.claude-plugin/plugin.json` + `marketplace.json` set to `4.0.0`.
21. CI green on push.

## 7. Test strategy

**Static validation (bats):**

- New `tests/contract/escalation-taxonomy.bats` — 4 assertions, one per level, plus cross-agent scan.
- New `tests/contract/staging-overlay.bats` — `fg-300-implementer` write-target grep + SKILL.md existence for 4 new skills.
- `tests/contract/skill-contract.bats` (existing, Phase 1) — auto-picks up new skills.
- `tests/contract/ui-frontmatter-consistency.bats` — already validates agent frontmatter; no change here.
- `tests/validate-plugin.sh` — already validates structural rules; extend with skill-count assertion.

**Runtime validation (bats):**

- New `tests/unit/skill-execution/forge-apply-reject.bats`:
  - Seed `.forge/pending/` with 2 files; invoke `/forge-apply`; assert worktree has the files and `.forge/pending/` is gone.
  - Seed pending; invoke `/forge-reject`; assert pending is gone and worktree is unchanged.
  - `/forge-apply --dry-run` lists files, does not write.

Per user constraint: no local runs; CI is the source of truth.

## 8. Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Implementer tests fail because pending-overlay view isn't assembled correctly | Medium | High | `overlay-view` helper has unit test; `fg-300-implementer` inner loop invokes overlay view explicitly via helper |
| Plan edit window races implementer start (user still editing when pipeline transitions) | Medium | Medium | `PLAN_EDIT_WAIT` is explicit; orchestrator NEVER auto-transitions out of it; requires user action (`/forge-plan-done` or `/forge-abort`) |
| Plan SHA256 comparison false-positive if user saves without changes | Low | Low | SHA256 is stable over identical content; CRLF/LF edits are the main false-positive source. Validator normalizes line endings before hashing |
| `autonomous: true` scalar migration surprises existing users | Low | Low | No-BC per user's rule; `DEPRECATIONS.md ## Changed in 4.0.0` documents the rewrite; orchestrator logs `config.autonomous_legacy_scalar` warning on detection |
| APPLY_GATE pauses pipeline indefinitely if user forgets | Low | Low | `/forge-status` shows the wait state + how long; session-start badge indicates `APPLY_GATE_WAIT`; stale-lock check after 24h emits E1 |
| E3 rollback via `git reset --hard` destroys uncommitted user work outside .forge/ | Medium | High | E3 rollback ONLY resets commits the pipeline itself made; reads `state.last_commit_sha` as the reset target. If user committed over it, orchestrator downgrades to E2 (user's choice). Explicitly documented in escalation-taxonomy.md |
| Scope gating interacts badly with recovery engine auto-retries | Medium | Medium | Recovery strategies are explicitly exempt from scope gating (they run under the originating action's approval). Documented in autonomous-scopes.md §3 |
| `forge-resolve-file.sh read` returns stale data if pending file is being written | Low | Low | Implementer is single-writer; no concurrent writes in pipeline. Documented constraint |
| `rsync -a --remove-source-files` fails on read-only files in pending | Low | Low | pending always writable (we control it); implementer verified not to set read-only bits |
| Staging overlay `.forge/pending/` not gitignored by existing `.gitignore` | Low | Low | Repo `.gitignore` already excludes `.forge/`; verified during plan-writing |
| New APPLY_GATE state breaks existing `/forge-resume` logic | Medium | Medium | `forge-recover resume` subcommand updated to handle APPLY_GATE_WAIT; dedicated bats assertion |
| Mid-stage `ask_user` contract allows PLAN agents to spam questions | Low | Medium | Phase 1 Ask pattern doc allowlist caps 3-question batches; observability contract §10 reinforces |

## 9. Rollout (one PR, multi-commit; CI gates on HEAD)

Each commit independently CI-green via the Group A/B pattern established in Phases 2-3 (new contract assertions gate on `FORGE_PHASE4_ACTIVE` sentinel).

1. **Commit 1 — Specs land.** This spec + plan.
2. **Commit 2 — Foundations (new docs + helper + skeleton bats).** 3 shared contract docs; `shared/forge-resolve-file.sh`; 2 skeleton bats files with Group A assertions active, Group B gated. CI green.
3. **Commit 3 — New skills (4).** `/forge-preview`, `/forge-apply`, `/forge-reject`, `/forge-plan-done` SKILL.md. Phase 1 skill-contract bats auto-validates. CI green.
4. **Commit 4 — Agent contract changes (planner + validator + implementer).** Write-target change, plan file write, SHA256 watch. CI green.
5. **Commit 5 — Orchestrator + state schema + transitions.** `fg-100-orchestrator.md` gains 3 sections; `shared/state-schema.md` → 1.8.0 + new objects; `shared/state-transitions.md` + 8 transitions; `shared/observability-contract.md` §10. CI green.
6. **Commit 6 — Config schema + existing skill updates.** `shared/config-schema.json` autonomous shape; 4 existing SKILL.md updates. CI green.
7. **Commit 7 — User-facing docs.** `docs/control-safety.md` + `DEPRECATIONS.md` `## Changed in 4.0.0`. CI green.
8. **Commit 8 — Runtime bats + top-level docs + version bump.** `tests/unit/skill-execution/forge-apply-reject.bats` seeded fixture; README, CLAUDE.md, CHANGELOG, plugin.json, marketplace.json to 4.0.0. Activate `FORGE_PHASE4_ACTIVE=1` sentinel (new skills + contract docs + resolve-file.sh all present). CI green.
9. **Push → CI → tag `v4.0.0` → release.**

## 10. Versioning rationale

Staging-overlay behavior change to `fg-300-implementer` is a **breaking change** in internal contract — agents that expect writes-to-worktree would break. `autonomous` config scalar-vs-object is also a shape change. SemVer major: `3.2.0 → 4.0.0`.

No BC shims in code. Users migrate configs; `DEPRECATIONS.md` documents the changes.

## 11. Open questions

None. All decisions locked in brainstorming.

## 12. References

- Phase 1-3 specs (same directory).
- `shared/platform.sh` (Phase 3 extended — `release_lock`, `safe_realpath`)
- `shared/observability-contract.md` (Phase 2 — extended here with §10)
- `shared/state-schema.md` (Phase 2 bumped to 1.7.0; Phase 4 bumps to 1.8.0)
- `shared/ask-user-question-patterns.md` (Phase 1)
- `shared/skill-contract.md` (Phase 1)
- `skills/forge-recover/SKILL.md` (Phase 1; Phase 4 updates for new wait states)
- April 2026 UX audit
- User instruction: "I want it all except the backwards compatibility"
