# Phase 7: Intent Assurance — Design

**Status:** Draft
**Date:** 2026-04-22
**Audience:** forge maintainer (solo)
**Depends on:** Phase 1 (observability), Phase 5 (findings store), Phase 6 (cost-skip pattern), F05 (living specs), F33 (consistency voting), F34 (handoff)
**Supersedes:** partial — extends F05 Living Specs from a soft drift-detection layer into a hard SHIP gate; extends F33 voting scope from 3 seams to a 4th (implementer diff) under a confidence gate.

## Goal

Close the "plan misread intent" gap with two coordinated interventions: (F35) a **fresh-context intent verifier** at Stage 5 VERIFY that probes the running system against original user ACs without ever seeing the plan or the tests, and (F36) a **confidence-gated N=2 implementer vote** that catches divergent implementations on the narrow slice of high-risk / low-confidence tasks where a single sample is most likely wrong.

## Problem Statement

Five structural gaps:

1. **Implementer writes tests AND code.** `agents/fg-300-implementer.md:140-169` runs RED-GREEN-REFACTOR in a single instance. If the planner misread intent, RED encodes it, GREEN satisfies it, tests pass for the wrong behavior.
2. **Critics scope is test↔impl, not intent↔system.** `agents/fg-301-implementer-critic.md:38-56` asks "does the diff satisfy the **intent** of the test" — and `fg-301-implementer-critic.md:81` explicitly forbids questioning the test ("Do NOT assume the test is wrong — the test is the contract"). When the test encodes the misreading, the critic is blind.
3. **Pre-ship verifier gates signal fidelity, not intent.** `agents/fg-590-pre-ship-verifier.md:94-102` verdicts `SHIP` on build=0, lint=0, tests=0 failed, 0 critical review findings. It never replays ACs against the running system.
4. **Living Specs is advisory.** `shared/living-specifications.md:82-108` emits `SPEC-DRIFT-*` findings but is not a hard SHIP gate; `unmapped_ac_severity` defaults to WARNING.
5. **Confidence gate is pipeline-level, not task-level.** `shared/confidence-scoring.md:30-36` gates entry (HIGH/MEDIUM/LOW) but every IMPLEMENT task is single-sampled.

User's diagnosis (verbatim): *"the implementer both writes the tests AND the code, so a plan that's wrong about intent produces green tests for the wrong behavior."*

## Non-Goals

- **Not changing Stage 1 shaper.** AC capture stays as-is; F35 consumes whatever the shaper emits.
- **Not adding LLM judgment to VERIFY's test pass/fail.** Build/test/lint gate stays deterministic.
- **Not voting on reviewers.** Phase 5 handles reviewer parallelism via Agent Teams; F33 already decided not to vote on review findings.
- **Not re-opening F33's non-voting agents.** F36 adds voting only on fg-300 under a narrow confidence/risk gate.
- **Not adding backwards-compat shims.** State schema bumps to v2.0.0 (coordinated cross-phase bump with Phase 5/6), config additions break old files; per `feedback_no_backcompat`.
- **Not introducing MCP dependencies.** fg-540 uses WebFetch + Read/Grep/Glob only (no raw Bash; probes go through `hooks/_py/intent_probe.py`).
- **Not running voting on every task.** Cost is the reason F33 stopped at 3 seams; F36 respects that by gating on confidence/risk/history.

## Approach

**A (selected).** Intent verification + confidence-gated impl voting. F35 catches "plan misread intent → tests encode it → everything passes." F36 catches "plan right, single sample unlucky on a high-variance task." ~10-20% added cost, ~40% infrastructure reuse (F05 registry, fg-590 gate, category-registry.json).

**B (rejected).** Intent verification alone — leaves complex single-sample implementations vulnerable on bugs that don't surface in runtime probes.

**C (rejected).** Full N=3 voting everywhere — F33 capped at 3 seams because voted accuracy saturates at +5pp over single-sample (`shared/consistency/voting.md:146`); 3× cost on ~80% mechanical tasks isn't justified.

## Components

### 1. `fg-540-intent-verifier` agent

Tier 3 (tasks only). Dispatched after Stage 5 Phase A passes, before Stage 6.

- **Tools:** `Read`, `Grep`, `Glob`, `WebFetch`. **Explicitly no raw `Bash`** — DB/filesystem probes go through the sandbox wrapper `hooks/_py/intent_probe.py` (see §5) invoked as a constrained probe API surfaced by the orchestrator; HTTP probes use `WebFetch` whose allow-list is enforced by the wrapper and by `intent_verification.forbidden_probe_hosts`. **Forbidden:** `Edit`, `Write`, `Agent`, `Task`, `TaskCreate`, `TaskUpdate`, `Bash`. If raw `Bash` is ever deemed necessary in the future, it must be routed through `hooks/_py/intent_probe.py`, never added directly to the tool list.
- **Allowed inputs:** requirement text, active spec slug + AC list from `.forge/specs/index.json`, runtime config (endpoints, docker-compose services, local DB URI), probe sandbox config.
- **Forbidden inputs:** plan (`.forge/stage_2_notes_*.md`), test files (`tests/**`, `src/**/test/**`, `spec/**`, `**/__tests__/**`), commit diff, implementer TDD history, prior findings, OTel spans.
- **Output:** per-AC verdicts to `.forge/runs/<run_id>/findings/fg-540.jsonl` (Phase 5 findings store format; schema conforms to Phase 5 findings-store with Phase 7 nullability extensions per §Data Model).

### 2. Context exclusion enforcement (layered)

"Fresh context" is load-bearing. The contract is enforced at Layer 1; Layer 2 is a defense-in-depth fallback.

**Layer 1 — orchestrator allow-list (ENFORCEMENT).** `build_intent_verifier_context(state)` assembles the brief from `ALLOWED_KEYS = {requirement_text, active_spec_slug, ac_list, runtime_config, probe_sandbox, mode}`. Any other key is excluded by construction. Built context persisted to `.forge/dispatch-contexts/fg-540-<timestamp>.json` so a contract test can grep for forbidden substrings. Ephemeral — see §Data Model for lifecycle.

**Layer 2 — agent-side tripwire (DEFENSE-IN-DEPTH, NON-GUARANTEEING).** fg-540 system prompt contains a "Context Exclusion Contract" clause: if the dispatch brief contains plan/tests/diff/history/findings, STOP and return `CONTRACT-VIOLATION` for all ACs. **This is model-compliance behavior, not enforced by the runtime** — a misbehaving or jailbroken model could ignore it. It exists to catch benign Layer-1 regressions (field renames that evade the grep), not to defend against an adversarial context leak. The contract test in §2 is the regression net; Layer 1 is the enforcement.

**Why both?** Layer 1 guarantees the contract; Layer 2 narrows the blast radius of a Layer-1 bug between when the bug lands and when the contract test catches it in CI.

### 2b. `risk_tags[]` taxonomy

Enum vocabulary for `task.risk_tags[]` on planner-emitted tasks:

```
risk_tags: ["high", "data-mutation", "auth", "payment", "concurrency", "migration"]
```

- **Emitter:** `fg-200-planner` during §3.4 per-task planning — assigns zero or more tags per task based on the plan-level risk heuristics (auth touches → `auth`; write paths → `data-mutation`; concurrent/parallel paths → `concurrency`; any financial flow → `payment`; schema/data moves → `migration`; anything the planner flags as high-blast-radius → `high`).
- **Consumer:** `fg-100-orchestrator` voting gate reads `task.risk_tags` from the plan and triggers N=2 voting if `"high"` is present OR any tag intersects config `impl_voting.trigger_on_risk_tags` (default `["high"]`).
- **Mode overlays may extend** the enum (e.g., bugfix mode adds `"bugfix"`; see §Configuration). Extensions must be declared in the mode overlay to be valid — unknown tags in plan output emit a WARNING at Stage 3 VALIDATE.

### 3. `INTENT-*` scoring categories

Added to `shared/checks/category-registry.json`:

| Code | Severity | Wildcard | Priority | Affinity |
|---|---|---|---|---|
| `INTENT-MISSED` | CRITICAL | false | 1 | `fg-540-intent-verifier` |
| `INTENT-PARTIAL` | WARNING | false | 2 | `fg-540-intent-verifier` |
| `INTENT-AMBIGUOUS` | INFO | false | 5 | `fg-540-intent-verifier` |
| `INTENT-UNVERIFIABLE` | WARNING | false | 3 | `fg-540-intent-verifier` |
| `INTENT-CONTRACT-VIOLATION` | CRITICAL | false | 1 | `fg-540-intent-verifier` |

Scoring impact per standard formula: `max(0, 100 - 20×CRITICAL - 5×WARNING - 2×INFO)`. One `INTENT-MISSED` = -20; three `INTENT-PARTIAL` = -15. `INTENT-UNVERIFIABLE` is WARNING because the AC was written in a way that can't be probed — this surfaces back to living-specs as a spec quality issue that fg-700 picks up for rewrite proposals.

### 4. fg-590 SHIP-gate clause

Extends `agents/fg-590-pre-ship-verifier.md` §6 (Produce Evidence). New pre-verdict clause:

```
Verdict is SHIP only if ALL of:
  - build exit code 0
  - tests 0 failed
  - lint exit code 0
  - review 0 critical + 0 important
  - score >= min_score
  - NEW: intent_verification.open_findings where severity == CRITICAL == 0
  - NEW: intent_verification.verified_pct >= intent_verification.strict_ac_required_pct
```

`verified_pct = VERIFIED / (VERIFIED + PARTIAL + MISSED + UNVERIFIABLE)` — UNVERIFIABLE counts against the denominator so spec-quality issues can't sneak through. Default `strict_ac_required_pct: 100`; users with exploratory features set it to 90.

BLOCK reasons enumerated in `evidence.json.block_reasons[]`:
- `intent-missed: {N} open CRITICAL INTENT-MISSED findings`
- `intent-threshold: verified {pct}% < required {threshold}%`

### 5. Runtime probe sandbox (tier-aligned with fg-610)

Mirrors `fg-610-infra-deploy-verifier` tiers, narrowed for a verifier:

- **T1 static (<10s, always):** AC expressible as string match against OpenAPI/config files; no runtime probe.
- **T2 local runtime (<60s, default):** `curl`/`WebFetch` to `localhost:*` and docker-compose service DNS. `psql`/`redis-cli`/`mongosh` to declared DB containers. Hostname allow-list regex: `^(localhost|127\.0\.0\.1|[a-z-]+\.forge-verify\.svc|<docker-compose-services>)$`.
- **T3 ephemeral cluster (<5min, opt-in):** Only when `probe_tier: 3` AND `infra.max_verification_tier >= 3`. Reuses kind/k3d cluster from fg-610 if already up this run.

**Hard denies:** hosts matching `forbidden_probe_hosts` (default `["*.prod.*", "*.production.*", "*.live.*", "*.amazonaws.com", "*.googleusercontent.com"]`). Deny wins over allow. Violation → `INTENT-CONTRACT-VIOLATION` CRITICAL + pipeline abort.

**Budget:** `max_probes_per_ac: 20`, `probe_timeout_seconds: 30`. Exceeding → `UNVERIFIABLE` with evidence note.

### 6. `fg-302-diff-judge` agent (structural AST diff)

New agent, ~100 lines, Tier 4 (no UI surfaces). Fresh context. Compares two implementation diffs from an N=2 fg-300 vote and returns `SAME | DIVERGES`.

- **Tools:** `Read` only. AST parsing runs inline via Python stdlib (`ast.parse`/`ast.dump`) and `tree-sitter` (via `py-tree-sitter` 0.25+, the actively maintained binding as of 2026). See [py-tree-sitter](https://github.com/tree-sitter/py-tree-sitter).
- **Algorithm:**
  - **Structural AST diff (full strength, N=2 voting reliable):**
    - Python: `ast.parse` both files → `ast.dump(tree, annotate_fields=False, indent=None)` with canonicalized field ordering → SHA256 equal ⇒ SAME, else walk both trees and list differing subtrees.
    - TypeScript/JavaScript: `py-tree-sitter` with the official `tree-sitter-typescript` / `tree-sitter-javascript` grammars from `tree-sitter-language-pack`. Serialize to `(type, child_count, ...)` tuples, compare.
    - Kotlin, Go, Rust, Java, C, C++, Ruby, PHP, Swift: same tree-sitter tuple-serialization approach when `tree-sitter-language-pack` ships the grammar. `tree-sitter-language-pack` (maintained successor to the unmaintained `py-tree-sitter-languages`) is the distribution vehicle for the compiled grammar wheels.
  - **Degraded textual diff (N=2 materially weaker):** all other languages (Elixir, Scala, Dart, C# where the grammar wheel is unavailable, etc.) AND any language above where the tree-sitter parser fails on the actual sample. Degraded mode = whitespace-normalized + comment-stripped textual diff, no semantic awareness. When degraded mode is triggered, fg-302 emits `IMPL-VOTE-DEGRADED` INFO alongside `REFLECT-FALLBACK` so the retrospective can track the degraded-voting rate.
  - **Caveat:** "N=2 voting is materially weaker under degraded mode — structural equivalence under whitespace/comment changes is detectable, but behaviorally-equivalent rewrites (variable renames, control-flow reshapes) will register as DIVERGES and trigger spurious tiebreaks."
  - **Footnote on coverage (as of spec date 2026-04-22):** `tree-sitter-language-pack` ships grammars for Python, TypeScript, JavaScript, Go, Rust, Java, Kotlin, C, C++, Ruby, PHP, Swift. Check the tree-sitter-language-pack docs at plan time for added languages before implementation — do NOT pin this list in code; feature-detect by attempting `get_language(<lang>)` at runtime.
- **Output schema:**

```json
{
  "verdict": "SAME | DIVERGES",
  "confidence": "HIGH | MEDIUM | LOW",
  "divergences": [
    {"file": "src/foo.py", "subtree": "function call_api()", "severity": "structural"}
  ],
  "ast_fingerprint_sample_a": "sha256:...",
  "ast_fingerprint_sample_b": "sha256:..."
}
```

Max output 400 tokens.

### 7. fg-300 N=2 dispatch under gate

> **Cost-field naming:** Field names follow the Phase 6 schema; `cost.pct_consumed` and `cost.remaining_usd` are canonical. `cost.pct_remaining` does NOT exist. The gate computes remaining as `1 - state.cost.pct_consumed`.

```python
def should_vote(task, state, config) -> bool:
    if not config.impl_voting.enabled:
        return False
    # Cost-skip: skip when less than skip_if_budget_remaining_below_pct of budget remains.
    # Phase 6 canonical field is `state.cost.pct_consumed` (fraction 0.0-1.0 of ceiling spent).
    pct_remaining = 1.0 - state.cost.pct_consumed
    if pct_remaining < config.impl_voting.skip_if_budget_remaining_below_pct / 100:
        emit("COST-SKIP-VOTE", "INFO")
        return False
    return (state.confidence.effective_confidence < config.impl_voting.trigger_on_confidence_below
            or any(t in task.risk_tags for t in config.impl_voting.trigger_on_risk_tags)
            or file_has_recent_regression(task.files, config.impl_voting.trigger_on_regression_history_days))
```

Gate passes → dispatch 2 parallel fg-300 with `sample_id: 1|2` (injected dispatch marker for traceability — **not** a reproducibility seed; Claude does not expose a deterministic seed and variance between samples comes from model stochasticity with temperature > 0), isolated sub-worktrees (§8), `dispatch_mode: vote_sample` (skip REFLECT — vote IS the reflection). Then dispatch fg-302-diff-judge:

- `SAME` → pick smallest-line-count sample (deterministic), cherry-pick to main worktree, cleanup both sub-wts.
- `DIVERGES` → dispatch **one** tiebreak fg-300 (`dispatch_mode: vote_tiebreak`) with divergence list; must reconcile.
- Tiebreak also diverges + autonomous → smallest-diff wins, `IMPL-VOTE-UNRESOLVED` WARNING.
- Tiebreak also diverges + interactive → `AskUserQuestion` 3-way diff.

Emit `IMPL-VOTE-TRIGGERED` INFO per sample with trigger reason.

### 8. Sub-worktrees for parallel vote samples

Reuse `fg-101-worktree-manager` `create` API (`agents/fg-101-worktree-manager.md:26-41`):

```
fg-101 create <task_id> sample_1 --base-dir .forge/votes/<task_id>/sample_1 --start-point <parent_head>
fg-101 create <task_id> sample_2 --base-dir .forge/votes/<task_id>/sample_2 --start-point <parent_head>
```

Both branch from the same parent HEAD. Winner's diff cherry-picked onto `.forge/worktree` (`git -C .forge/worktree cherry-pick --allow-empty <sample_commit>`). All sub-worktrees cleaned via `fg-101 cleanup --delete-branch` (idempotent). Stale sweep at PREFLIGHT via `fg-101 detect-stale`.

### 9. Cost-skip at 30% budget

Aligns with Phase 6 information-over-coercion, but uses a **deliberately earlier threshold (30 %) than Phase 6's implementer throttle (20 %)**. Justification: voting doubles a task's cost, so we want the vote gate to stop firing while there is still meaningful budget left for the single-sample main implementer to finish. Hitting the Phase-6 20 % implementer throttle with a voting pipeline already in flight would either abort the vote mid-flight or push the run over-budget; the 10-point buffer preserves main-impl budget. (Phase 6 is canonical for the implementer throttle; Phase 7 adds this stricter voting-only buffer.)

Gate behavior: when `1 - state.cost.pct_consumed < 0.30` at gate time (i.e., `pct_consumed > 0.70`), skip voting, dispatch single fg-300, emit `COST-SKIP-VOTE` INFO (priority 5, zero score impact — telemetry only), log to `impl_vote_history[]` with `skipped_reason: cost`. If user sees persistent skips, they raise `cost.ceiling_usd`.

### 10. Retrospective analytics

`fg-700-retrospective.md` §2j extended with:

```yaml
intent_verification:
  total_acs: int
  verified: int
  partial: int
  missed: int
  unverifiable: int
  verified_pct: float            # verified / total_acs
  unverifiable_pct: float        # unverifiable / total_acs — separate from verified_pct
                                 # so shaper-quality issues (ACs written in unprobable form)
                                 # are distinguishable from implementation-quality issues
                                 # (implementation missed a probable AC).
impl_voting:
  dispatches: int
  diverged: int
  tiebreaks: int
  unresolved: int
  cost_skipped: int
  divergence_rate: float
  per_trigger: {confidence, risk_tag, regression_history}
```

Retrospective renders `verified_pct` and `unverifiable_pct` as **separate** rows in the report so the reader can immediately tell whether the pipeline is failing to meet intent (low `verified_pct` with low `unverifiable_pct` — impl quality) versus failing to probe intent (high `unverifiable_pct` — spec quality, shaper should rewrite ACs).

New auto-tuning Rule 11: `intent_missed_count >= 2` in last 3 runs → propose `living_specs.strict_mode: true`. **Propose-only, surfaced via `/forge-playbook-refine` per the existing F31 rule-promotion flow documented in `shared/learnings/rule-promotion.md`** — never auto-apply.

## Data Model

### State schema bump: v1.10.0 → v2.0.0 (coordinated cross-phase bump)

Phase 7 bumps to **v2.0.0** as a single coordinated major-version bump shared with Phase 5 (findings-store) and Phase 6 (cost tracking). Phase 7's new fields are disjoint with Phase 5's and Phase 6's additions, so all three land together under the v2.0.0 banner rather than each phase minor-bumping independently. Per `feedback_no_backcompat`, old v1.x state files are not migrated.

New top-level keys in `state.json`:

```json
{
  "intent_verification_results": [
    {
      "ac_id": "AC-003",
      "verdict": "VERIFIED | PARTIAL | MISSED | UNVERIFIABLE",
      "evidence": [
        {"probe": "curl http://localhost:8080/users", "status": 200, "body_sha": "...", "duration_ms": 45}
      ],
      "probes_issued": 3,
      "duration_ms": 127,
      "reasoning": "Response body matches expected schema and contains 3 users."
    }
  ],
  "impl_vote_history": [
    {
      "task_id": "CreateUserUseCase",
      "trigger": "confidence | risk_tag | regression_history",
      "samples": [
        {"sample_id": 1, "diff_sha": "a1b2...", "ast_fingerprint": "sha256:..."},
        {"sample_id": 2, "diff_sha": "c3d4...", "ast_fingerprint": "sha256:..."}
      ],
      "judge_verdict": "SAME | DIVERGES",
      "tiebreak_dispatched": false,
      "winner_sample_id": 1,
      "skipped_reason": null | "cost" | "disabled",
      "wall_time_ms": 12400
    }
  ]
}
```

### Finding schema v2 (coordinated with Phase 5 findings-store)

Intent findings cannot carry `file`/`line` because they attach to acceptance criteria, not source lines. Today's `shared/checks/finding-schema.json` makes both fields **required**, which silently breaks any attempt to emit an `INTENT-*` finding through the standard validator. Phase 7 ships a **schema v2** that fixes this:

1. **`file` and `line` become optional** (nullable) for all findings.
2. **`ac_id` becomes required** when `category` starts with `INTENT-`. Conditional required-ness is expressed via JSON Schema `allOf` + `if/then`.
3. **Phase 5 findings-store JSONL validators must accept the nullable form** — this is a hard coordination point; Phase 5 owns `shared/checks/finding-schema.json` and Phase 7 contributes the v2 edits. Both phases' tests must exercise the same schema file.

Example INTENT finding:

```json
{
  "category": "INTENT-MISSED",
  "severity": "CRITICAL",
  "file": null,
  "line": null,
  "ac_id": "AC-003",
  "verdict": "MISSED",
  "evidence_summary": "GET /users returned {} instead of a user list; 3 probes all confirmed empty response.",
  "explanation": "...",
  "suggestion": "..."
}
```

Example conventional reviewer finding (file/line still populated):

```json
{
  "category": "SEC-INJECTION-USER-INPUT",
  "severity": "CRITICAL",
  "file": "src/api/users.py",
  "line": 42,
  "explanation": "...",
  "suggestion": "..."
}
```

The quality gate and insights dashboards treat a null-file finding as "AC-level finding" and group by `ac_id`; line-scoped findings group by `(file, line)` as today.

### Dispatch-context directory lifecycle

`.forge/dispatch-contexts/` is **ephemeral**:

- Written by `fg-100-orchestrator.build_intent_verifier_context(state)` at Stage 5.
- Cleaned at PREFLIGHT of every new run by `shared/state-integrity.sh` (or the Python equivalent); the cleanup list must be extended to cover this directory.
- **NOT preserved on `/forge-recover reset`.** Unlike `explore-cache.json`, `plan-cache/`, `code-graph.db`, etc., there is no cross-run value to preserving a one-off dispatch brief.

## Data Flow

**Stage 5 VERIFY:** Phase A passes → `orchestrator.build_intent_verifier_context(state)` writes `.forge/dispatch-contexts/fg-540-<ts>.json` → `Agent(fg-540, filtered_context)` reads spec registry + runtime config → probes each AC via sandbox → writes `.forge/runs/<id>/findings/fg-540.jsonl` → orchestrator reads findings → populates `state.intent_verification_results[]` → score includes INTENT-*.

**Stage 4 IMPLEMENT (voting path):** planner emits `task.risk_tags[]` → `should_vote` → if true: fg-101 creates two sub-worktrees → parallel `Agent(fg-300)` samples with seeds 1/2 → `Agent(fg-302-diff-judge, diff_1, diff_2)` → SAME: cherry-pick smallest-line-count sample onto main worktree, cleanup; DIVERGES: dispatch tiebreak sample, cherry-pick, cleanup all; escalate per autonomous/interactive policy if tiebreak fails.

**Stage 9 SHIP:** `fg-590` fresh build/test/lint + review + reads `state.intent_verification_results[]` → SHIP iff all existing gates AND 0 open INTENT-MISSED AND `verified_pct >= strict_ac_required_pct`.

## Context Isolation Contract

**Forbidden paths for fg-540 dispatch context:**

- `.forge/stage_2_notes_*.md` (plan)
- `.forge/stage_4_notes_*.md` (implementer TDD history)
- `.forge/stage_6_notes_*.md` (review findings)
- `src/**/test/**`, `tests/**`, `spec/**`, `**/__tests__/**` (test files)
- Any `git diff` output
- `.forge/events.jsonl` (OTel/event log)
- `.forge/decisions.jsonl`
- Any `.forge/runs/<id>/findings/` except its own

**Forbidden tool use for fg-540:**

- `Edit`, `Write`, `NotebookEdit` (read-only verifier)
- `Agent`, `Task`, `TaskCreate`, `TaskUpdate` (no recursive dispatch)

**Contract test** (`tests/contract/test_intent_verifier_context.py`):
1. Inject a synthetic dispatch state with plan/tests/diff populated.
2. Call `build_intent_verifier_context(state)`.
3. Grep the returned JSON for forbidden substrings (`"plan"`, `"test_code"`, `"diff"`, `"implementation_diff"`, plan file basenames, test directory names).
4. Assert zero matches.
5. Parse the agent `.md` frontmatter; assert `tools` excludes `Edit|Write|Agent|Task|TaskCreate|TaskUpdate`.
6. Grep the agent `.md` body for the "Context Exclusion Contract" clause; assert present.

## Concurrency & Race

- Both fg-300 samples launch via orchestrator's existing parallel `Agent(...)` dispatch (reviewer-parallelism pattern). No shared filesystem state beyond parent HEAD.
- fg-101 branch collisions solved by `sample_<N>` suffix + existing epoch-suffix fallback.
- Orchestrator awaits both samples. Per-agent 15-min timeout: if one sample times out, cancel peer, emit `IMPL-VOTE-TIMEOUT` WARNING, use surviving sample (no tiebreak needed).
- Cherry-pick serialized via `.forge/worktree/.vote-merge.lock`.
- Cleanup in orchestrator finally-block; idempotent fg-101 `cleanup`; stale sweep at PREFLIGHT.

## Error Handling

| Failure | Severity | Response |
|---|---|---|
| fg-540 probe timeout (single AC) | WARNING | Mark that AC `UNVERIFIABLE`, don't block others. `UNVERIFIABLE` counts against `verified_pct`. |
| fg-540 all probes fail (runtime unreachable) | WARNING | Mark all ACs `UNVERIFIABLE`. SHIP gate evaluates `verified_pct = 0 < threshold` → BLOCK with `intent-unreachable-runtime` reason. User action: start docker-compose, re-run from SHIP. |
| fg-540 forbidden-host probe attempted | CRITICAL | `INTENT-CONTRACT-VIOLATION`, abort pipeline (safety: this only happens if agent misbehaves or config was tampered with). |
| fg-540 no ACs in active spec | WARNING | Skip verification entirely. Log `INTENT-NO-ACS` WARNING. Gate evaluates to pass (0/0 > threshold vacuously). **Promotion to CRITICAL** when `living_specs.strict_mode: true` — then SHIP refuses until shaper produces ACs. |
| fg-540 dispatch context contains forbidden key | CRITICAL | Orchestrator refuses to dispatch, logs `INTENT-CONTEXT-LEAK` CRITICAL, halts pipeline. Fix: retry after orchestrator rebuild. |
| fg-302 AST parse fails (syntax error in sample) | INFO | `REFLECT-FALLBACK`, fall back to whitespace-normalized diff for that language. |
| fg-302 tree-sitter grammar missing for language | INFO | `REFLECT-FALLBACK`, textual-diff mode. |
| Voting tiebreak sample diverges from both originals | WARNING | Autonomous: pick sample with smallest diff line count (reproducible). Interactive: `AskUserQuestion` 3-way diff. Log `IMPL-VOTE-UNRESOLVED`. |
| One vote sample times out | WARNING | Cancel peer, use surviving sample as single-sample result. Log `IMPL-VOTE-TIMEOUT`. No tiebreak. |
| Sub-worktree create fails (disk full, permissions) | ERROR | Cancel voting for this task, fall back to single-sample in main worktree. Log `IMPL-VOTE-WORKTREE-FAIL` WARNING. |
| Cherry-pick conflict merging winning sample | ERROR | Unexpected (sub-worktrees branched from same HEAD); log CRITICAL, abort task, require manual recovery via `/forge-recover rollback`. |

## Testing Strategy

All tests run in CI only (solo-dev, no local test runs per user policy).

| Test | File | Type |
|---|---|---|
| Context filter excludes forbidden paths | `tests/unit/test_intent_verifier_context_filter.py` | unit |
| Diff judge AST SAME for whitespace-only diff (Python) | `tests/unit/test_diff_judge_ast.py::test_python_same` | unit |
| Diff judge AST DIVERGES for logic diff (Python) | `tests/unit/test_diff_judge_ast.py::test_python_diverges` | unit |
| Diff judge TS parse via py-tree-sitter | `tests/unit/test_diff_judge_ast.py::test_typescript_same` | unit |
| Diff judge fallback for unsupported language | `tests/unit/test_diff_judge_ast.py::test_fallback_mode` | unit |
| fg-540 agent frontmatter validation | `tests/contract/test_fg540_frontmatter.py` | contract |
| fg-540 dispatch context contract | `tests/contract/test_intent_context_exclusion.py` | contract |
| fg-540 runtime probe sandbox (forbidden host denied) | `tests/contract/test_probe_sandbox.py` | contract |
| fg-590 blocks SHIP when INTENT-MISSED open | `tests/scenario/sc-intent-missed/` | scenario |
| Vote divergence triggers tiebreak | `tests/scenario/sc-impl-vote-diverge/` | scenario |
| `impl_voting.enabled: false` skips gate entirely | `tests/scenario/sc-impl-vote-disabled/` | scenario |
| Cost-skip fires at <30% budget | `tests/scenario/sc-impl-vote-cost-skip/` | scenario |
| Autonomous mode never AskUserQuestions from fg-540/302 | `tests/scenario/sc-autonomous-intent/` | scenario |
| Sub-worktree cleanup after vote | `tests/scenario/sc-vote-worktree-cleanup/` | scenario |
| OTel spans emitted for intent verification | `tests/unit/test_otel_intent_spans.py` | unit |
| Category registry schema validation | `tests/unit/test_category_registry_intent.py` | unit |
| Retrospective surfaces intent/vote analytics | `tests/scenario/sc-retrospective-intent-metrics/` | scenario |

## Configuration

Additions to `forge-config.md` template (snake_case, nested — matches existing convention):

```yaml
intent_verification:
  enabled: true                              # Master toggle
  strict_ac_required_pct: 100                # % of ACs that must VERIFY to ship (90 for exploratory)
  max_probes_per_ac: 20
  probe_timeout_seconds: 30
  allow_runtime_probes: true
  probe_tier: 2                              # 1=static, 2=local runtime, 3=ephemeral cluster
  forbidden_probe_hosts:
    - "*.prod.*"
    - "*.production.*"
    - "*.live.*"
    - "*.amazonaws.com"
    - "*.googleusercontent.com"

impl_voting:
  enabled: true
  trigger_on_confidence_below: 0.4           # LOW per confidence-scoring.md
  trigger_on_risk_tags: ["high"]             # task.risk_tags from planner
  trigger_on_regression_history_days: 30     # recent regression window from run-history.db
  samples: 2                                 # N=2 is the only supported value; fixed for cost reasons
  tiebreak_required: true
  skip_if_budget_remaining_below_pct: 30     # cost-gate, mirrors Phase 6
```

PREFLIGHT constraints (enforced in `shared/preflight-constraints.md`):

- `intent_verification.strict_ac_required_pct`: integer 50-100
- `intent_verification.max_probes_per_ac`: 1-200
- `intent_verification.probe_timeout_seconds`: 5-300
- `intent_verification.probe_tier`: 1, 2, or 3
- `impl_voting.trigger_on_confidence_below`: float 0.0-1.0, must be ≤ `confidence.pause_threshold`
- `impl_voting.samples`: exactly 2 (future-reserved)
- `impl_voting.skip_if_budget_remaining_below_pct`: 0-100

Mode overlays:
- **bootstrap mode:** `intent_verification.enabled: false`, `impl_voting.enabled: false` (greenfield has no ACs to verify and no risk baseline).
- **bugfix mode:** `intent_verification.enabled: true`, `impl_voting.trigger_on_risk_tags: ["high", "bugfix"]` (every bugfix task is high-risk by default).
- **migration mode:** `intent_verification.enabled: false` (migrations are structural, not user-feature; use fg-506-migration-verifier instead).

## Acceptance Criteria

- **AC-701:** `agents/fg-540-intent-verifier.md` exists with `ui: {tasks: true, ask: false, plan_mode: false}` (Tier 3); `tools` list is exactly `['Read', 'Grep', 'Glob', 'Bash', 'WebFetch']`; no `Edit|Write|Agent|Task|TaskCreate|TaskUpdate`.
- **AC-702:** `tests/contract/test_intent_context_exclusion.py` passes: synthetic dispatch with plan/tests/diff populated → built context contains none of them.
- **AC-703:** `tests/scenario/sc-intent-missed/` passes: requirement "GET /users returns list of users" with implementation returning `{}` → `fg-590` verdict BLOCK with `intent-missed` in `block_reasons`.
- **AC-704:** `tests/unit/test_diff_judge_ast.py::test_python_same`: two Python files differing only in whitespace and comments return `SAME`.
- **AC-705:** `tests/scenario/sc-impl-vote-disabled/` passes: `impl_voting.enabled: false` → zero extra dispatches regardless of task confidence/risk/history.
- **AC-706:** Retrospective report section "intent_verification" exposes `total_acs`, `verified`, `partial`, `missed`, `unverifiable`, `verified_pct`; section "impl_voting" exposes `dispatches`, `diverged`, `tiebreaks`, `cost_skipped`, `divergence_rate`.
- **AC-707:** `shared/checks/category-registry.json` validates against `finding-schema.json`; all 5 `INTENT-*` entries have severity, priority, affinity, wildcard fields.
- **AC-708:** Autonomous mode: no `AskUserQuestion` calls originate from fg-540 or fg-302 in any scenario test; tiebreak unresolved → smallest-diff tiebreak applied automatically.
- **AC-709:** `CLAUDE.md` §Features includes F35 and F36 rows with default config values (`enabled: true`, `strict_ac_required_pct: 100`, `trigger_on_confidence_below: 0.4`, `skip_if_budget_remaining_below_pct: 30`).
- **AC-710:** `tests/contract/test_probe_sandbox.py`: attempting a probe against `api.prod.example.com` emits `INTENT-CONTRACT-VIOLATION` CRITICAL and aborts.
- **AC-711:** `tests/scenario/sc-vote-worktree-cleanup/` passes: after voting completes (SAME or DIVERGES), `.forge/votes/<task_id>/` has no remaining directories.
- **AC-712:** `tests/unit/test_otel_intent_spans.py`: `hooks/_py/otel.py` emits spans named `forge.intent.verify_ac` (one per AC, with attributes `forge.intent.ac_verdict`, `forge.intent.ac_id`, `forge.intent.probe_tier`) and `forge.impl.vote` (one per voted task, with attributes `forge.impl_vote.sample_id`, `forge.impl_vote.ast_fingerprint`, `forge.impl_vote.verdict`, `forge.impl_vote.trigger`). All OTel span and attribute names use the `forge.*` prefix per the cross-phase naming convention (Phase 1 observability).
- **AC-713:** `tests/scenario/sc-impl-vote-cost-skip/`: when `state.cost.pct_consumed == 0.75` (i.e., `1 - pct_consumed == 0.25`, below the 30 % threshold) and voting would otherwise trigger → the gate computes `pct_remaining = 1 - state.cost.pct_consumed = 0.25 < 0.30`, emits `COST-SKIP-VOTE` INFO, no extra dispatches, single fg-300 runs. Field names follow Phase 6 schema; `cost.pct_consumed` is canonical (`cost.pct_remaining` does not exist).
- **AC-714:** `state.json` at any post-VERIFY checkpoint contains `intent_verification_results[]`; at any post-IMPLEMENT checkpoint where voting fired contains `impl_vote_history[]`.
- **AC-715:** `shared/state-schema.md` bumped to v2.0.0 with schema changelog entry covering both new top-level keys.
- **AC-716:** `agents/fg-590-pre-ship-verifier.md` §6 verdict logic includes the two new clauses; `tests/unit/test_ship_gate_intent.py` exercises both (open INTENT-MISSED → BLOCK; `verified_pct` below threshold → BLOCK; both clear → SHIP).
- **AC-717:** `shared/modes/bootstrap.md` sets `intent_verification.enabled: false, impl_voting.enabled: false` (confirmed by `tests/unit/test_mode_overlays.py`).
- **AC-718:** `shared/agents.md` registry lists `fg-302-diff-judge` (Tier 4) and `fg-540-intent-verifier` (Tier 3); total agent count updates from 48 to 50 at **every** callsite. `CLAUDE.md` references "48 agents" in at least three places (line 27 intro, line 43 `agents/` description, line 140 `Agents` heading) — all three must be updated. Grep gate: `grep -nE '\b(48 agents|48 total)\b' CLAUDE.md` must return zero matches after the change. Test: `tests/contract/test_agent_count_claude_md.py` greps post-merge.
- **AC-719 (finding schema v2):** `shared/checks/finding-schema.json` at v2 validates all four of: (a) a sample intent finding with `file: null, line: null, category: "INTENT-MISSED", ac_id: "AC-042"` — PASS; (b) a sample reviewer finding with `file: "src/x.py", line: 42, category: "SEC-INJECTION-USER-INPUT"` — PASS; (c) a reviewer finding missing `file` — FAIL (non-INTENT categories still require file/line); (d) an INTENT finding missing `ac_id` — FAIL. Test: `tests/unit/test_finding_schema_v2.py`. Coordinated with Phase 5; Phase 5 owns the schema file.
- **AC-720 (Layer 2 tripwire scenario):** `tests/scenario/sc-intent-layer2-tripwire/` monkey-patches `build_intent_verifier_context` to inject a forbidden key (e.g., `"plan": "..."`), dispatches fg-540, asserts fg-540 returns `INTENT-CONTRACT-VIOLATION` CRITICAL for all ACs. Documents Layer 2 as defense-in-depth only; Layer 1 contract test (`tests/contract/test_intent_context_exclusion.py`, AC-702) remains the enforcement gate.
- **AC-721 (sub-worktree stale sweep):** `agents/fg-101-worktree-manager.md` `detect-stale` scan patterns include `.forge/votes/*`. Test: synthetic `.forge/votes/<task-id>/sample_1/` directory with mtime > `stale_hours` is listed in `detect-stale` output; cleanup removes it. `tests/unit/test_worktree_stale_votes.py`.
- **AC-722 (features-without-ACs unchanged):** `tests/scenario/sc-intent-no-acs/` passes: running the pipeline on a requirement whose active spec has zero ACs produces `INTENT-NO-ACS` WARNING but SHIP proceeds (gate vacuously passes at `verified_pct = 0/0`). Documents explicitly: "F35 protects shipped-with-ACs features; features without ACs are unchanged from pre-F35 behavior." Gated by `living_specs.strict_mode: false` (default).

## Documentation Updates

- `CLAUDE.md`: §Agents (48→50) at **all three callsites** (§intro, `agents/` description, §Agents heading) per AC-718, §Features (F35, F36 rows), §Pipeline Flow (Stage 5 + Stage 9 gate), §Core contracts (state v2.0.0), §Supporting systems.
- `shared/checks/finding-schema.json`: **schema v2** — `file` and `line` become optional (nullable); conditional `required: ["ac_id"]` when `category` starts with `INTENT-`. **Phase 5 owns this file**; Phase 7 contributes the v2 edits. Phase 5 findings-store JSONL validators accept the nullable form. See AC-719.
- `shared/state-integrity.sh` (or Python equivalent): extend cleanup list to include `.forge/dispatch-contexts/` at PREFLIGHT.
- `agents/fg-101-worktree-manager.md`: extend `detect-stale` scan patterns to include `.forge/votes/*`. See AC-721.
- `hooks/_py/intent_probe.py`: **NEW** — sandbox wrapper enforcing `forbidden_probe_hosts` allow/deny at entry. Entry point for fg-540 DB/filesystem/HTTP probes. Explicitly gatekeeps against raw `Bash` being re-introduced: if raw Bash is ever deemed necessary, it must route through this wrapper, never through the agent tool list directly.
- `README.md` §Features (if summarized there).
- `shared/stage-contract.md` — Stage 5 ends with fg-540; Stage 9 entry includes intent clearance.
- `shared/agents.md` — registry + dispatch graph: fg-302 (Tier 4), fg-540 (Tier 3).
- `shared/state-schema.md` — v2.0.0 bump; `intent_verification_results[]`, `impl_vote_history[]`.
- `shared/scoring.md` — INTENT-* severities.
- `shared/checks/category-registry.json` — 5 new INTENT-* entries.
- `shared/living-specifications.md` — new §"Intent Verification Integration" + cross-ref to `shared/intent-verification.md`.
- `shared/confidence-scoring.md` — cross-ref vote trigger.
- `shared/agent-communication.md` — fg-540 isolation.
- `shared/intent-verification.md` — NEW architectural doc.
- `shared/modes/{bootstrap,bugfix,migration}.md` — overlay additions.
- `forge-config.md` template — new `intent_verification`, `impl_voting` sections.
- `agents/fg-540-intent-verifier.md` — NEW.
- `agents/fg-302-diff-judge.md` — NEW.
- `agents/fg-590-pre-ship-verifier.md` — §6 gate clauses.
- `agents/fg-300-implementer.md` — new §5.3c "Voting Mode" (`dispatch_mode: vote_sample|vote_tiebreak`, skip REFLECT).
- `agents/fg-200-planner.md` — §3.4 emits `risk_tags[]` per task.
- `agents/fg-700-retrospective.md` — §2j intent+voting analytics; Rule 11.
- `agents/fg-100-orchestrator.md` — `build_intent_verifier_context`, voting gate in IMPLEMENT.
- `hooks/_py/otel.py` — `forge.intent.verify_ac`, `forge.impl.vote` spans.
- `shared/observability.md` — new spans.
- `shared/preflight-constraints.md` — validation ranges.

## Open Questions

- **Recursive verification of sub-ACs:** should fg-540 be allowed to decompose a complex AC into sub-probes and dispatch itself recursively? **Recommendation: no.** Keep the verifier tree shallow. Deep decomposition invites prompt drift; if an AC is too complex to probe directly, it's a spec quality issue and should surface as `INTENT-UNVERIFIABLE` for shaper rewrite.
- **Tiebreak sample tiebreak:** when the tiebreak sample (fg-300 #3) *also* diverges from both originals in autonomous mode, we pick smallest-diff. Is there a smarter signal? **Recommendation: no for now.** Smallest-diff is deterministic and reproducible across runs. Add line-count + branch-count tiebreak only if retrospective shows `IMPL-VOTE-UNRESOLVED` > 5% of voted tasks.
- **Probe tier escalation:** should fg-540 auto-escalate from Tier 2 to Tier 3 when docker-compose isn't running but an ephemeral kind cluster is available? **Recommendation: no — keep tier strictly config-controlled.** Auto-escalation turns a fast stage into a 5-minute stage without user awareness.
- **Tree-sitter dependency:** add `tree-sitter>=0.25` and `tree-sitter-language-pack` to `pyproject.toml`, or keep fg-302 Python-only with fallback? **Recommendation: add the dependency.** `py-tree-sitter` 0.25+ is actively maintained (Sep 2025 release, Python 3.11-3.14) and `tree-sitter-language-pack` is the maintained successor to the deprecated `py-tree-sitter-languages`. Structural diff beats text diff materially for TS/JS — which is ~40% of forge-supported frameworks. Add it.
- **`impl_voting.samples: 2` is fixed.** Should the config even expose it? **Recommendation: keep it exposed, PREFLIGHT-constrained to exactly 2.** Surfaces the design choice in the config and allows future widening without a schema bump if the decision reverses.
- **Should `living_specs.strict_mode: true` become the default?** F35 as specified protects only features whose shaper produced ACs — features without ACs silently bypass the SHIP gate (AC-722). Flipping `strict_mode` to default-true would make ACs mandatory, closing that gap but forcing shaper work on every feature. **Leaving this open for user review before Phase 7 implementation lands.** Recommendation (tentative): default stays `false` for now, revisit once retrospective shows real-world no-AC bypass rate.

Sources:
- [py-tree-sitter](https://github.com/tree-sitter/py-tree-sitter)
- [tree-sitter-language-pack](https://docs.tree-sitter-language-pack.kreuzberg.dev/)
- [py-tree-sitter PyPI (0.25.2)](https://pypi.org/project/tree-sitter/)
