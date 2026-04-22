# Phase 5: Pattern Modernization — Design

## Goal

Replace two multi-agent anti-patterns in the forge pipeline with patterns that
match Claude Code's platform capabilities and the published multi-agent
literature:

1. **REVIEW (Stage 6)** moves from "batched dispatch with dedup hints" to the
   **Agent Teams** pattern (shared findings store, parallel fan-out, pure
   aggregation).
2. **Critic agents** (`fg-205-planning-critic`, `fg-301-implementer-critic`)
   become **Judges with binding veto**. A REVISE verdict blocks advancement;
   the parent re-dispatches. Bounded to two veto loops per task/plan, then
   user escalation.

## Problem Statement

**A. Protocol-as-shared-memory (Stage 6).** `shared/agent-communication.md:44-98`
defines a "shared findings context" that is not actually shared — it is a
dedup-hint protocol where the quality gate manually includes top-20 findings
from prior batches in each subsequent dispatch prompt. This:

- Reinvents shared memory through prompt concatenation, burning tokens on every
  batch-2+ dispatch (domain-filtered, but still sizable — `agent-communication.md:66-72`
  explicitly concedes "compress to single-line entries" when the domain set
  exceeds 50 findings).
- Serializes what ought to parallelize: `fg-400-quality-gate.md:91-100` says
  "Wait for ALL in batch before starting next. Batches sequential." On a 9-reviewer
  run this produces 3 serial waves where 1 would suffice.
- Couples dedup accuracy to the prompt-budget engineering in every reviewer
  (`fg-400-quality-gate.md:95-100`), creating per-reviewer skew.

**B. Critics without veto.** `fg-205-planning-critic.md:38-56` and
`fg-301-implementer-critic.md:59-72` emit PROCEED/REVISE/RESHAPE verdicts, but
no structural commitment obligates the parent agent (orchestrator or
implementer) to respect a REVISE. `fg-300-implementer.md:190-215` DOES honor
`fg-301`'s REVISE — but only for `implementer.reflection.*`, not for
other upstream fix loops (the orchestrator does not re-plan on a
`fg-205` REVISE outside of the validator's `critic_revisions` counter).
This is the "critics without hierarchical veto" anti-pattern flagged in
arxiv 2601.14351: half-respected critics are strictly worse than either
full-authority judges OR pure advisors whose output is acknowledged as
optional.

## Non-Goals

- **Not changing reviewer count.** All 9 REVIEW agents (fg-410..419) remain.
- **Not merging reviewers.** Domain separation is preserved.
- **Not touching Stage 5 (VERIFY).** Test gate logic is orthogonal.
- **Not altering the QG scoring formula.** `max(0, 100 − 20·CRITICAL − 5·WARNING
  − 2·INFO)` per `shared/scoring.md` is unchanged.
- **Not introducing new MCP dependencies.** Findings store is local filesystem.
- **Not back-compatible.** Per user policy (`feedback_no_backcompat`), old
  protocols are deleted, state schema is bumped, agents are renamed.

## Approach

### Why Agent Teams over batching

Claude Code's [Agent Teams documentation](https://code.claude.com/docs/en/agent-teams)
defines the pattern: coordinated instances sharing a task list in a project
file (`TASKS.md` or JSON), with teammates claiming and updating work
concurrently. Stage 6 REVIEW is the canonical use case for this pattern —
parallel, domain-independent lenses on the same diff. Replacing dedup-hint
prompts with a shared findings file:

- **Eliminates token overhead** from cross-batch hint summaries.
- **Parallelizes fully** — all qualifying reviewers launch at T0.
- **Moves dedup to read-time, not write-time** — each reviewer reads peers'
  findings and skips duplicates (posts `seen_by` annotation instead).
- **Simplifies the aggregator** — `fg-400` becomes a pure reducer over the
  findings file, not a batch sequencer.

### Why Judge (J1) over Advisor (J2)

Option J1 (binding veto) is selected. Two alternatives considered:

**J1 — Judge with veto (chosen):** REVISE blocks advancement; parent
re-dispatches; bounded at 2 loops per plan/task; third veto escalates via
`AskUserQuestion`.

**J2 — Demote to advisor:** Rename critic → advisor; REVISE verdict removed;
parent may discard findings freely.

J1 is chosen because:

1. The `fg-301-implementer-critic.md:51-56` decision rules are already
   binding-quality for the implementer (catches hardcoded-return, missing
   branches — genuine bug patterns). Demoting them to optional would reduce
   signal without reducing dispatch cost.
2. Per arxiv 2601.14351 (*Critic-as-Judge in multi-agent systems*), "critics
   whose verdicts parent agents may ignore produce worst-of-both: token cost
   of review without reliability gains of enforcement." Either commit to
   veto OR remove the agent.
3. The user's memory `feedback_forge_review_quality` ("forge pipeline must
   match/exceed external reviewers") aligns with stronger enforcement, not
   weaker.

Bounded loops (2) prevent livelock; third veto escalation preserves user
sovereignty over the "should we keep trying?" decision.

## Components

### 1. Findings store (JSONL, append-only)

**Path:** `.forge/runs/<run_id>/findings/<reviewer>.jsonl` — one file per
reviewer, one finding per line. In code: `pathlib.Path(".forge") / "runs" /
run_id / "findings" / f"{reviewer}.jsonl"`. Line endings: `\n` only (LF) on
all platforms so files survive git round-trips intact on Windows.

**Per-line schema:**

```json
{
  "finding_id": "f-<reviewer>-<ulid>",
  "dedup_key": "<file>:<line>:<category>",
  "reviewer": "fg-411-security-reviewer",
  "severity": "CRITICAL|WARNING|INFO",
  "category": "SEC-AUTH-003",
  "file": "src/api/UserController.kt",
  "line": 42,
  "message": "Missing ownership check on PATCH /users/{id}",
  "suggested_fix": "Add principal.id == pathId guard",
  "confidence": "HIGH|MEDIUM|LOW",
  "created_at": "2026-04-22T14:03:11Z",
  "seen_by": []
}
```

**Append-only semantics.** Reviewers only append. Once a line is written it is
never rewritten. Annotations that another reviewer "also saw" a finding are
expressed by writing a NEW line with the same `dedup_key` but a non-empty
`seen_by: ["fg-411-security-reviewer"]` and a minimal payload. The aggregator
collapses such lines during reduction.

**Annotation inheritance rule (explicit).** When reviewer B writes a
`seen_by` annotation for a finding first-written by reviewer A, B's line
inherits `severity`, `category`, `file`, `line`, `confidence`, and `message`
**verbatim** from A's original finding. B is asserting "I saw this too",
not proposing a revised judgment — B does NOT get to override severity,
upgrade confidence, rewrite the message, or reattribute the category. If B
disagrees with any of A's fields, B MUST write a distinct full finding
(different `dedup_key` — e.g., different category code, or a companion line
with an explicit disagreement marker), not a `seen_by` annotation.
`suggested_fix` is also carried verbatim or omitted. The aggregator treats
annotation lines as cardinality-only signals during reduction.

**Why JSONL and not a single file.** Per-reviewer files eliminate write
contention at the filesystem level — two reviewers writing simultaneously
cannot clobber each other's lines when each writes its own file. Interleaved
append to a single file is also tolerated (every reviewer's line is atomic
within the 4KB POSIX write guarantee for the line sizes we produce), but
per-reviewer files are simpler and cheaper to reason about.

### 2. Reviewer read-then-write protocol

Every reviewer `fg-4XX` is updated with the following preamble section:

> **Before emitting findings:**
> 1. `Read` all JSONL files matching `.forge/runs/<run_id>/findings/*.jsonl`.
> 2. Compute the set `seen_keys = { line.dedup_key for line in peer_files }`.
> 3. Apply your own analysis to the changed files.
> 4. For each finding you would produce:
>    - If `dedup_key in seen_keys` → append a `seen_by` annotation line to
>      YOUR own JSONL file (not the peer's) and skip emission.
>    - Else → append a full finding line to your JSONL file.

The protocol is race-tolerant: two reviewers discovering the same issue at
the same instant may both emit a full finding; the aggregator collapses them
using `dedup_key` plus a tiebreaker rule (see §Concurrency & Race
Conditions → "Duplicate emission race" below).

### 3. Judge veto plumbing (state schema bump, loop bounds)

**Agents renamed:**
- `fg-205-planning-critic` → `fg-205-planning-judge`
- `fg-301-implementer-critic` → `fg-301-implementer-judge`

File names, frontmatter `name:` fields, and all references in
`shared/agents.md`, `CLAUDE.md`, `shared/agent-colors.md`, and the dispatch
graph are updated.

**Judge verdict schema** (returned from each judge):

```yaml
judge_verdict: PROCEED | REVISE | ESCALATE
judge_id: fg-205-planning-judge | fg-301-implementer-judge
confidence: HIGH | MEDIUM | LOW
findings: [ ... ]   # same structure as §1 schema, minus seen_by
revision_directives: |
  Specific, actionable guidance for the parent agent to incorporate on
  re-dispatch. Required when verdict == REVISE.
```

**Parent dispatch output.** `fg-200-planner.md` and `fg-300-implementer.md`
MUST populate `judge_verdict` in their structured output blob. Orchestrator
reads it deterministically; no prompt-parsing heuristics.

**State counters (state schema v2.0.0 — pinned in
`shared/checks/state-schema-v2.0.json`):**

```json
{
  "version": "2.0.0",
  "plan_judge_loops": 0,
  "impl_judge_loops": {
    "<task_id>": 0
  },
  "judge_verdicts": []
}
```

Field shapes (authoritative — see the JSON Schema file for the complete
contract):

- `plan_judge_loops` — **integer** at state root. Counts REVISE verdicts
  from `fg-205` for the current plan. Resets to 0 when a new plan is drafted
  (validator REVISE, user-continue, and feedback loops do NOT reset it).
- `impl_judge_loops` — **object** at state root, keyed by `task_id`, values
  are integers. Counts REVISE verdicts from `fg-301` per-task.
- `judge_verdicts` — **array of objects** at state root. See §Data Model.
- **Reset semantics for `plan_judge_loops`:** a "new plan" is defined as any
  `fg-200` dispatch where the requirement text or approach has materially
  changed — the orchestrator detects this via SHA of the requirement +
  approach decision section.

**Loop bounds:**
- 1st REVISE → re-dispatch parent, increment counter.
- 2nd REVISE (counter == 2 after increment) → `AskUserQuestion` with three
  options: accept plan/impl over judge objection, re-dispatch manually with
  user hints, or abort.
- Judge timeout (per `shared/scoring.md:408`: 10-minute ceiling per reviewer;
  judges reuse the same envelope) → log INFO, treat as PROCEED with WARNING
  finding `JUDGE-TIMEOUT`. Never block the pipeline on judge failure.

**Autonomous mode override.** In autonomous mode (`autonomous: true`), a 2nd
judge REVISE is treated as an E-class safety escalation rather than a normal
convergence step. Precedent: autonomous runs only pause on E1–E4 safety
escalations, unrecoverable CRITICAL, and REGRESSING states. A 2nd judge veto
qualifies — the judge has stated twice that the parent's output is wrong,
and silently accepting it would violate the `feedback_forge_review_quality`
invariant. Concrete behavior:

- `AskUserQuestion` fires exactly as in interactive mode (E-class escalations
  always pause, even in autonomous mode).
- In true background/headless runs (no interactive surface available),
  auto-abort fires: the orchestrator logs
  `[AUTO] abort-on-judge-veto judge_id=<fg-205|fg-301> findings=[...]`,
  writes the judge's `revision_directives` and `findings[]` to
  `.forge/alerts.json`, and transitions the run to ABORTED. User resumes
  manually via `/forge-recover resume` after reviewing the alert.

### 4. Quality gate aggregator-only

`fg-400-quality-gate.md` simplifies drastically:

- **Remove** §5.2 (Inter-Batch Finding Deduplication), §5.2 subsections on
  domain-scoped filtering as a dispatch concern, §10 fix-cycle orchestration
  language that references batch re-runs.
- **Keep** §5.1 batching, but reframed: batches become a **parallel-fanout
  throttle** — if the system cannot sustain 9 concurrent subagent dispatches
  (config: `quality_gate.max_parallel_reviewers`, default 9), the quality
  gate groups reviewers into waves of N. Within a wave, dispatch is fully
  parallel; between waves, same findings-store protocol handles dedup, so
  there is NO hint-prompt injection.
- **Keep** §5.0 change-scope filter: small (<50 lines) dispatches batch 1
  contents only (typically `fg-410` alone), medium dispatches all configured
  reviewers, large dispatches all plus an `APPROACH-SCOPE` INFO finding. The
  scope filter controls WHICH reviewers dispatch, not the batching wave
  structure.
- **Keep** §6 inline checks, §6.1 conflict detection, §6.2 deliberation, §7
  finding dedup (now reading the findings store instead of in-memory results),
  §8 scoring, §11 verdict thresholds, §12 partial failure handling.
- **Reduce** dispatch prompt size: prompts no longer carry "previous batch
  findings summary" blocks. Expected net reduction per non-first-wave
  dispatch: 800–1500 tokens.

### 5. Reviewer registry extraction

`fg-400-quality-gate.md` §20 currently inlines a ~40-line reviewer
reference — domain tags, dispatch conditions, focus fields — covering all
9 REVIEW-tier agents. This summary is carried as part of the fg-400 agent
body and is therefore part of fg-400's steady-state system-prompt cost on
every dispatch, regardless of which reviewers actually run.

The inlined reference duplicates content already authoritative in
`shared/agents.md`. Extracting it from the `.md` body to an
orchestrator-injected payload (passed as dispatch context, not embedded in
the agent file) reduces fg-400's steady-state token cost.

**Spec:** §20 of `fg-400-quality-gate.md` is replaced with a single line
referencing `shared/agents.md#review-tier`. The orchestrator reads
`shared/agents.md` once per pipeline run, extracts the REVIEW-tier
registry slice (agent name + domain tag only), and injects it into the
fg-400 dispatch payload alongside the diff context. fg-400 reads the
registry slice from its dispatch context rather than from its own prompt
body. Net savings: ~500 tokens per fg-400 dispatch.

### 6. Deletion of batching-with-dedup-hints

Because forge has no backcompat requirement:

- `shared/agent-communication.md` §Shared Findings Context (lines 44-98) is
  **deleted**. A new §3 "Findings Store Protocol" replaces it with: path
  convention, line schema, read-before-write protocol, concurrency semantics,
  aggregator contract.
- `fg-400-quality-gate.md` §5.2 is deleted; §10 rewritten; §5.1 reframed as
  fan-out throttle.
- All reviewer agents gain a 6-line "Findings Store Protocol" preamble in
  §2 (after Untrusted Data Policy, before their domain sections).
- `shared/agents.md` REVIEW cluster entry updated to note the new protocol.
- Retrospective (`fg-700`) dashboards and `.forge/events.jsonl` emitters are
  updated so `finding_emitted` events reference `<reviewer>.jsonl:<line>`
  instead of batch index.

## Data Model

**Finding schema (§1)**: as above — `finding_id`, `dedup_key`, `reviewer`,
`severity`, `category`, `file`, `line`, `message`, `suggested_fix`,
`confidence`, `created_at`, `seen_by`.

**Dedup key grammar:** `<relative-path>:<line>:<CATEGORY-CODE>`. Path
normalized via `pathlib.PurePosixPath` (forward slashes) so Windows and
Unix runs produce identical keys.

**Judge verdict schema (§3):** `judge_verdict`, `judge_id`, `confidence`,
`findings[]`, `revision_directives`.

**State.json v2.0.0 additions (top-level fields; pinned in
`shared/checks/state-schema-v2.0.json`):**

```json
{
  "version": "2.0.0",
  "plan_judge_loops": 0,
  "impl_judge_loops": { "<task_id>": 0 },
  "judge_verdicts": [
    {
      "judge_id": "fg-205-planning-judge",
      "verdict": "REVISE",
      "dispatch_seq": 12,
      "timestamp": "2026-04-22T14:11:08Z"
    }
  ]
}
```

- `plan_judge_loops` — integer at root.
- `impl_judge_loops` — object at root keyed by `task_id`, values integer.
  (Asymmetry with `plan_judge_loops` is intentional: there is only one live
  plan at a time, but multiple concurrent tasks.)
- `judge_verdicts` — array of objects at root. Each entry records
  `judge_id`, `verdict`, `dispatch_seq`, `timestamp`.

Removed from v1.x:
- `critic_revisions` (superseded by `plan_judge_loops` — also renamed for
  semantic clarity; `tasks[*].implementer_reflection_cycles` superseded by
  `impl_judge_loops[task_id]`).

No migration shim. v1.x state files are invalidated on upgrade; user's
`.forge/state.json` is reinitialized on next run per `feedback_no_backcompat`.

## Cross-Phase Compatibility

### Shared `.forge/runs/<run_id>/findings/` directory

This phase owns the findings-directory contract (§1). Phase 7 (intent
assurance) also writes into this directory — specifically `fg-540` intent
verifier emits into `.forge/runs/<run_id>/findings/fg-540.jsonl`. Non-reviewer
writers MUST conform to the canonical line schema:

- `finding_id`, `dedup_key`, `reviewer` (writer-agent-id, not limited to
  fg-41*), `severity`, `category`, `file` (**nullable** for non-source
  findings), `line` (**nullable**), `message`, `confidence`, `created_at`,
  `seen_by: []`.
- INTENT-* findings (Phase 7) use `file: null`, `line: null`,
  `ac_id: <AC-NNN>`. The schema treats `file` and `line` as optional; the
  aggregator's dedup key grammar becomes `<file|"-">:<line|"-">:<category>`
  with literal `-` substituted for null segments.
- `suggested_fix` remains reviewer-optional (reviewers that don't produce
  structured fixes omit the field).

The aggregator (`fg-400`) reads only `fg-41*.jsonl` during REVIEW; other
stages consuming the directory (Phase 7 intent gating) read only their own
writer's files. No stage reduces across foreign writer files.

### State schema version — unified v2.0.0 bump

Phase 5 introduces `plan_judge_loops`, `impl_judge_loops`, and
`judge_verdicts[]`. Phase 6 introduces cost-governance fields. Phase 7
introduces intent-verification fields. All three phases ship together
(bundled release), so the state schema is bumped **once to v2.0.0**
rather than chaining v1.11 → v1.12 → v1.13. All schema references in this
spec, Phase 6 spec, and Phase 7 spec target v2.0.0. CLAUDE.md §State is
updated in the coordinated commit. If any single phase ships in isolation,
its version bump is re-negotiated at ship time.

### OTel namespace convention

All forge-emitted OTel span attributes MUST use the `forge.*` root namespace
(`forge.run_id`, `forge.stage`, `forge.agent_id`, etc.). Phase 5 does not
add new spans — reviewers remain implicit in the pipeline span tree — but
the convention is restated in `shared/observability.md` so Phase 6 and
Phase 7 can rely on it.

### Phase 4 coexistence

Phase 4 adds a `## Relevant Learnings` block to reviewer dispatch prompts.
Phase 5 adds a "Findings Store Protocol" preamble to reviewer agent
system prompts (`.md` body, not dispatch payload). The two occupy different
prompt slots — one is orchestrator-injected per dispatch, the other is
baked into the agent system prompt — so application order is commutative.
No conflict.

## Data Flow

**REVIEW (Stage 6):**

```
Orchestrator dispatches fg-400-quality-gate
  └─ fg-400 evaluates scope + conditions, selects qualifying reviewers
  └─ fg-400 dispatches wave 1 (up to max_parallel_reviewers in parallel)
       ├─ fg-410 reads all peer JSONL files (initially empty), emits findings
       │   to .forge/runs/<run_id>/findings/fg-410-code-reviewer.jsonl
       ├─ fg-411 reads peer files (fg-410's if ready), emits to own file
       └─ … each in parallel, each appends to own file
  └─ fg-400 waits for all wave-1 subagent handles to complete
  └─ fg-400 (if configured waves > 1) dispatches wave 2 against same store
  └─ fg-400 computes SHA of all JSONL files, reduces to single findings list,
     applies dedup (§7.3), applies conflict detection, computes score
  └─ Return report to orchestrator
```

**JUDGE veto (fg-200 ↔ fg-205, fg-300 ↔ fg-301):**

```
Orchestrator dispatches parent (fg-200 planner OR fg-300 implementer for task)
  └─ Parent produces output
  └─ Orchestrator dispatches judge (fg-205 OR fg-301) with parent output
  └─ Judge returns judge_verdict
       ├─ PROCEED → advance to next stage/task
       ├─ REVISE and loop_counter < 2 → increment counter, re-dispatch parent
       │   with revision_directives appended; on return re-dispatch judge
       └─ REVISE and loop_counter == 2 → AskUserQuestion escalation
```

## Concurrency & Race Conditions

- **Append-only JSONL** tolerates interleaved writes because each reviewer
  writes its own file. No lock needed.
- **Aggregator read barrier:** fg-400 must read all JSONL files at a moment
  when all reviewers have completed. "Completed" is determined by subagent
  handle status (the Task tool returns when the subagent exits), not by file
  modification timestamp — avoids clock-skew issues on Windows.
- **Duplicate emission race (tiebreaker):** when two reviewers write a
  full finding with the same `dedup_key` within microseconds, aggregator
  keeps: (a) highest severity; (b) at equal severity, highest confidence;
  (c) at equal confidence, lowest ASCII `reviewer` string (deterministic).
  Other line becomes a `seen_by` annotation retroactively during reduction.

## Error Handling

- **Reviewer hangs past 10 min** (per `shared/scoring.md:408`): fg-400 logs
  `REVIEW-GAP` finding, the reviewer's JSONL file may be empty or partial,
  aggregator proceeds with remaining reviewers. Critical-domain timeout
  escalates to WARNING per existing rule.
- **Judge subagent fails or times out:** treat as PROCEED with WARNING
  finding `JUDGE-TIMEOUT` (category added to `shared/checks/category-registry.json`).
  Pipeline never blocks on judge failure.
- **Findings file corrupted** (malformed JSON on a line): aggregator logs
  WARNING (tagged with reviewer id and line number), skips the line, and
  continues reduction. Covered by scenario test
  `tests/scenario/findings-store-corrupt-jsonl.bats` (AC #16) which
  injects a partial line and verifies the aggregator's survivor
  handling. Schema validation coverage via
  `tests/contract/findings-store.bats`.
- **Missing peer files** (reviewer dispatched before peers exist): expected
  and harmless. The first reviewer to run reads an empty set and emits all
  its findings; later reviewers see those and annotate.
- **Disk full during append:** reviewer receives I/O error, emits a single
  `SCOUT-STORAGE-FULL` INFO finding via stage notes, and exits. fg-400
  treats as partial failure.

## Testing Strategy

- **Contract test** `tests/contract/findings-store.bats`:
  - Every JSONL line validates against the schema (jsonschema check).
  - Every reviewer agent file contains the "Findings Store Protocol" preamble
    (grep check).
  - `fg-400-quality-gate.md` does NOT contain the strings "previous batch
    findings", "dedup hints", or "top 20" (grep-anti).
- **Scenario test** `tests/scenario/agent-teams-dedup.bats`:
  - 3 synthetic reviewers with overlapping findings on the same
    `(file, line, category)` triplet produce a single deduped entry after
    aggregation, with `seen_by` lists reflecting all three.
- **Unit test** `tests/unit/judge-loops.bats`:
  - 1st REVISE increments `plan_judge_loops` to 1, re-dispatch happens.
  - 2nd REVISE increments to 2, `AskUserQuestion` escalation fires, no
    re-dispatch.
  - New plan drafted (requirement SHA changes) → counter resets to 0.
  - Judge timeout treated as PROCEED + WARNING.
- **State schema test** `tests/unit/state-schema-v11.bats`: verifies
  `state.json.version == "1.11.0"`, presence of `plan_judge_loops`,
  `impl_judge_loops`, `judge_verdicts[]`, absence of `critic_revisions`.
- **Agent registry test** `tests/structural/agent-names.bats`: verifies no
  file named `fg-205-planning-critic.md` or `fg-301-implementer-critic.md`
  exists; `fg-205-planning-judge.md` and `fg-301-implementer-judge.md` do;
  `shared/agents.md` references the new names.

No local test execution per `feedback_no_local_tests`; all tests run in CI
after push.

## Documentation Updates

### Rename reference inventory (authoritative)

Renaming `fg-205-planning-critic` → `fg-205-planning-judge` touches **13
files** (verified via `grep -rl "fg-205-planning-critic"`):

- `agents/fg-205-planning-critic.md` (file rename; frontmatter `name:`)
- `agents/fg-100-orchestrator.md` (dispatch graph)
- `shared/agents.md` (registry entry)
- `shared/agent-colors.md` (crimson palette entry)
- `shared/agent-ui.md` (tier classification)
- `CLAUDE.md` (agent list + review tier)
- `README.md` (if present; public-facing agent list)
- `CHANGELOG.md` (3.7.0 entry)
- `tests/unit/agent-behavior/planning-critic.bats`
- `tests/contract/planning-critic-dispatch.bats`
- `tests/contract/ui-frontmatter-consistency.bats`
- `docs/superpowers/specs/2026-04-22-phase-2-contract-enforcement-design.md`
  (sibling phase; update on ship)
- `docs/superpowers/specs/2026-04-22-phase-5-pattern-modernization-design.md`
  (this spec)

Renaming `fg-301-implementer-critic` → `fg-301-implementer-judge` touches
**17 files** (verified via `grep -rl "fg-301-implementer-critic"`):

- `agents/fg-301-implementer-critic.md` (file rename; frontmatter `name:`)
- `agents/fg-300-implementer.md` (§5.3a dispatch + verdict handling)
- `shared/agents.md` (registry entry)
- `shared/stage-contract.md` (IMPLEMENT stage description)
- `shared/model-routing.md` (tier assignment)
- `shared/scoring.md` (category attribution references)
- `shared/state-schema-fields.md` (cycle counter field)
- `shared/checks/category-registry.json` (REFLECT-* category owners)
- `CLAUDE.md` (agent list + F32 row)
- `CHANGELOG.md` (3.7.0 entry)
- `tests/contract/fg-301-frontmatter.bats`
- `tests/contract/fg-301-fresh-context.bats`
- `tests/contract/reflect-categories.bats`
- `tests/structural/reflection-eval-scenarios.bats`
- `docs/superpowers/specs/2026-04-22-phase-5-pattern-modernization-design.md`
  (this spec)
- `docs/superpowers/specs/2026-04-22-phase-6-cost-governance-design.md`
  (sibling phase; update on ship)
- `docs/superpowers/specs/2026-04-22-phase-7-intent-assurance-design.md`
  (sibling phase; update on ship)

Tests renamed alongside their subjects
(`tests/unit/agent-behavior/planning-critic.bats` →
`planning-judge.bats`, etc.); bats contract file paths updated in
`tests/` directory structure.

### Content edits

- `CLAUDE.md` §Agents: rename `fg-205` and `fg-301`, add `judge_verdict`
  field to dispatch output contract, add Agent Teams note to §Review.
- `shared/agent-communication.md`: DELETE §Shared Findings Context (lines
  44-98); ADD §Findings Store Protocol (path, schema, read-then-write,
  concurrency, aggregator contract).
- `shared/agents.md`: rename entries; update REVIEW cluster description.
- `shared/observability.md`: reinforce that forge-emitted OTel span
  attributes use the `forge.*` root namespace (this phase adds no new
  spans — reviewers remain implicit — but the convention is confirmed).
- `agents/fg-205-planning-judge.md` (renamed from `fg-205-planning-critic.md`):
  verdict names REVISE → REVISE (unchanged semantics, new authority),
  RESHAPE kept, PROCEED → PROCEED. Add "veto authority" clause to §1 Identity.
- `agents/fg-301-implementer-judge.md` (renamed): same authority clause.
- `agents/fg-200-planner.md`: §5 output format adds `judge_verdict` block.
- `agents/fg-300-implementer.md`: §5.3a rewritten — verdict handling is now
  orchestrator-driven, not implementer-internal; `impl_judge_loops[task_id]`
  replaces `implementer_reflection_cycles`.
- `agents/fg-400-quality-gate.md`: §5.1 reframed, §5.2 deleted, §10 rewritten,
  §20 shrunk to single-line reference.
- `agents/fg-410..fg-419`: each gains a 6-line "Findings Store Protocol"
  preamble.
- `shared/state-schema.md` + `shared/state-schema-fields.md`: version bump
  to 2.0.0 (unified cross-phase bump — see §Cross-Phase Compatibility),
  new fields documented, `critic_revisions` and
  `implementer_reflection_cycles` removed.
- `shared/checks/state-schema-v2.0.json` (new): JSON Schema pin for
  `plan_judge_loops`, `impl_judge_loops`, `judge_verdicts`. Referenced
  from AC #3.
- `shared/checks/category-registry.json`: new `JUDGE-TIMEOUT` category, INFO
  severity default.
- `shared/agent-colors.md`: preserve existing colors (crimson for fg-205,
  lime for fg-301) under new names.

## Acceptance Criteria

1. `ls agents/ | grep -c "critic\.md"` returns 0.
2. `agents/fg-205-planning-judge.md` and `agents/fg-301-implementer-judge.md`
   exist with YAML frontmatter `name:` matching filename.
3. `shared/state-schema.md` declares `"version": "2.0.0"` and references
   the pinned JSON Schema at `shared/checks/state-schema-v2.0.json`. That
   schema file defines `plan_judge_loops` (integer, at state root),
   `impl_judge_loops` (object at state root keyed by `task_id`, values
   integer), and `judge_verdicts` (array at state root). Neither
   `critic_revisions` nor `implementer_reflection_cycles` appears in the
   schema or the state doc.
4. `shared/agent-communication.md` contains `§Findings Store Protocol` and
   does NOT contain the string "dedup hints" or "previous batch findings".
5. Every file in `agents/fg-41*.md` and `agents/fg-419-*.md` contains the
   string "Findings Store Protocol" in the first 60 lines.
6. `agents/fg-400-quality-gate.md` §20 is ≤ 3 lines and references
   `shared/agents.md#review-tier`.
7. `agents/fg-400-quality-gate.md` does NOT contain "previous batch findings",
   "dedup hints", or "top 20" as substrings.
8. `agents/fg-200-planner.md` §5 output format includes a `judge_verdict`
   field block.
9. `agents/fg-300-implementer.md` references `impl_judge_loops` and NOT
   `implementer_reflection_cycles`.
10. `tests/contract/findings-store.bats`, `tests/scenario/agent-teams-dedup.bats`,
    `tests/unit/judge-loops.bats`, `tests/unit/state-schema-v11.bats`, and
    `tests/structural/agent-names.bats` all pass in CI.
11. `plugin.json` version bumps appropriately (see note below);
    `CHANGELOG.md` has a matching entry describing both changes.
12. A synthetic pipeline run with 3 injected reviewers producing overlapping
    findings terminates with exactly one scored entry per `dedup_key` and
    non-empty `seen_by` lists.
13. An injected 1st REVISE from fg-205 causes exactly one re-dispatch of
    fg-200; `state.json.plan_judge_loops == 1` after re-dispatch.
14. An injected 3rd REVISE from fg-205 fires `AskUserQuestion` without
    re-dispatching fg-200.
15. `tests/unit/scoring.bats` passes unchanged (scoring formula invariance
    under this phase's changes — findings-store reduction must produce the
    same score as the prior batched dedup path for equivalent finding sets).
16. `tests/scenario/findings-store-corrupt-jsonl.bats` (new): when a
    reviewer's JSONL file contains a malformed line (e.g., truncated
    JSON, invalid UTF-8, binary garbage), the aggregator logs a WARNING
    tagged with the reviewer id and line number, skips the bad line, and
    continues reduction over the remaining well-formed lines. The final
    score is computed from the survivors and the run does not abort.

**Plugin version bump coordination.** Phases 5, 6, and 7 ship as a bundled
release, so `plugin.json` bumps **once to 4.0.0** (major bump: state schema
v1.x → v2.0.0 is a breaking change per `feedback_no_backcompat`, and all
three phases contribute breaking changes). If the phases ship separately
for any reason, Phase 5 alone would bump to 3.7.0 and Phases 6/7 would
bump independently on their ship — but the bundled 4.0.0 path is the
intended outcome.

## Open Questions

1. **Should `fg-418-docs-consistency-reviewer` honor `seen_by` from non-docs
   reviewers?** Docs findings rarely collide with other domains; current
   spec allows cross-domain annotation but adds no value. Leave protocol
   uniform; revisit if empirical noise appears.
2. **Wave scheduling policy when `max_parallel_reviewers < 9`:** LIFO by
   registry order, by domain priority, or random? Defer to v3.7.1 once
   the initial rollout reveals concurrency ceilings on the user's hardware.
3. **Judge revision_directives token budget:** current `fg-205` and `fg-301`
   have unbounded `findings[]`. Cap at 10 findings per REVISE verdict to
   keep parent re-dispatch payloads bounded.
4. **Should judges themselves be subject to veto?** A "judge of judges"
   recursion is explicitly out of scope. If a judge is wrong, the
   `AskUserQuestion` escalation at loop 3 is the backstop.
5. **CAS-based score caching (future optimization):** fg-400 could compute
   `sha256(sorted(file_bytes))` over all JSONL files and cache the
   resulting score keyed by that hash, short-circuiting convergence
   re-invocations where the findings store hasn't changed. A complete
   implementation requires pre-score SHA read, score compute, post-score
   SHA re-read, and a retry-on-mismatch WARNING — non-trivial for the
   initial rollout. Deferred; revisit if `/forge-insights` shows fg-400
   CPU is a bottleneck in long convergence runs.

---

**Phase 5 sizing estimate:** 2 agent renames touching 30 files total
(13 for fg-205, 17 for fg-301, de-duplicated by file path; see §Rename
reference inventory), 1 agent file rewrite (fg-400-quality-gate),
9 agent preamble additions (reviewers), state schema v1.x → v2.0.0
(unified cross-phase bump), 1 shared contract rewrite
(agent-communication.md), 1 new JSON Schema pin
(`shared/checks/state-schema-v2.0.json`), 7 new tests (contract +
scenario + unit + structural, including scoring invariance and corrupt
JSONL), 1 category-registry addition (`JUDGE-TIMEOUT`), 1 plugin version
bump. Plugin version (bundled with Phases 6/7): 3.6.x → 4.0.0.

Sources consulted during spec authoring:
- [Orchestrate teams of Claude Code sessions — Agent Teams docs](https://code.claude.com/docs/en/agent-teams)
- [Create custom subagents — Claude Code docs](https://code.claude.com/docs/en/sub-agents)
- arxiv 2601.14351 (Critic-as-Judge in multi-agent systems)
- `shared/agent-communication.md:44-98` (protocol being replaced)
- `agents/fg-400-quality-gate.md` (aggregator being simplified)
- `agents/fg-205-planning-critic.md`, `agents/fg-301-implementer-critic.md`
  (critics being promoted to judges)
- `shared/scoring.md:408` (10-minute reviewer timeout ceiling)
