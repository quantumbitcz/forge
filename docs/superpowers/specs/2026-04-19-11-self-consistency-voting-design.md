# Phase 11 — Self-Consistency Voting for High-Stakes Decisions

**Status:** Draft
**Phase:** 11 (A+ Roadmap)
**Priority:** P2
**Author:** forge maintainers
**Date:** 2026-04-19
**Dependencies:** Phase 02 (Cross-Platform Python Hooks) — provides `hooks/_py/` infrastructure that hosts the dispatch helper.

---

## 1. Goal

Apply N-sample majority voting with soft self-consistency tie-breaking to three
high-stakes pipeline decisions — shaper intent classification, validator
GO/REVISE/NO-GO verdict, and post-run PR-rejection feedback classification — so
that a single unlucky sample can no longer flip the pipeline into the wrong
mode, block a correct plan, or misroute a retry loop.

---

## 2. Motivation

### Audit W12 — single-sample decisions at load-bearing seams

The W12 audit identified three pipeline seams where a single LLM call
unilaterally decides the entire run's trajectory, and where a flip of the
verdict has high downstream cost:

1. **`fg-010-shaper` intent classification** — the routing table in
   `shared/intent-classification.md` (bugfix / migration / bootstrap /
   multi-feature / vague / testing / documentation / refactor / performance /
   single-feature) selects the pipeline mode. A wrong classification sends the
   user through the wrong mode overlay (`shared/modes/`), which is only
   recoverable by `/forge-recover reset` after the user notices.
2. **`fg-210-validator` GO / REVISE / NO-GO verdict** — the 7-perspective
   verdict (architecture, security, edge_cases, test_strategy, conventions,
   approach_quality, documentation_consistency) gates Stage 4
   (IMPLEMENTING). A spurious REVISE wastes a full planner re-dispatch cycle;
   a spurious GO lets bad plans through to implementation where the fix cost
   is 10x-50x higher.
3. **`fg-710-post-run` PR-rejection feedback classification** — classifying
   reviewer feedback as `design` vs `implementation` decides whether the
   pipeline rewinds to Stage 2 (PLAN) or Stage 4 (IMPLEMENT). A mis-classified
   `design` issue handled as `implementation` produces a second PR with the
   same flaw and increments `feedback_loop_count`, which escalates at 2.

Every one of these three decisions is emitted by a single-sample LLM call with
no cross-check.

### Evidence from the research literature

Self-consistency (sampling the same prompt multiple times at non-zero
temperature, then taking the majority answer) lifts reasoning-task accuracy by
5-15 percentage points across GSM8K, SVAMP, StrategyQA and ARC — see Wang et
al. 2022, <https://arxiv.org/abs/2203.11171>. Soft self-consistency (weighting
each sample by its self-reported confidence so ties break toward the more
confident vote rather than an arbitrary first-seen) closes the gap on
low-consensus prompts — see Wang et al. 2024,
<https://arxiv.org/html/2402.13212v1>.

These are exactly the shape of the three forge decisions: discrete label
space, model-native confidence is cheap to extract, and the cost of a wrong
label dwarfs the cost of 3 extra fast-tier calls.

### CLI plugin context

forge already spends premium-tier tokens on these three agents (`model:
inherit` in the frontmatter resolves to the caller's active model, typically
standard or premium tier). Adding 2 extra fast-tier samples per decision is
cheaper than the existing single premium-tier call — and the existing call
stays unchanged as sample 1, so the worst-case regression is zero.

---

## 3. Scope

### In scope

1. Introduce a reusable **consistency dispatch** primitive that takes a
   prompt, N samples, and a model tier, and returns a voted result plus
   per-sample confidence.
2. Wrap the three decision points:
   - `agents/fg-010-shaper.md` — the Phase 1 intent classification step (the
     agent's one-shot categorization of the raw `$ARGUMENTS`, NOT the whole
     shaping dialogue).
   - `agents/fg-210-validator.md` — the final GO / REVISE / NO-GO verdict
     emitted after the 7 perspectives. Per-perspective findings are NOT voted;
     only the aggregate verdict.
   - `agents/fg-710-post-run.md` — the PR-rejection classification
     (`design` vs `implementation` vs `other`).
3. **Aggregation:** simple majority over N samples → on a tie, weight each
   sample by its self-reported confidence (soft self-consistency) → on a
   still-perfect tie after weighting (e.g. N=2 after a cache hit dedup), fall
   back to the highest-confidence sample.
4. **Model tier selection:** samples run on the fast tier via
   `shared/model-routing.md`, regardless of the caller's tier. Premium-tier
   cost is avoided by using cheap samples to cross-check the expensive one.
5. **Caching:** a persistent JSONL cache at `.forge/consistency-cache.jsonl`
   keyed by `(decision_point, prompt_hash, n_samples, model_tier)` — avoids
   re-voting on identical re-entries (e.g. a validator re-run after REVISE
   with the same plan text).
6. **Config-gated decision list** — `consistency.decisions` is a list so more
   decisions can be added later without a code change to the dispatch helper.
7. **State counter** — `state.consistency_cache_hits` surfaces via
   `/forge-insights` for calibration.

### Out of scope

1. Voting on **every** agent call. Doing this on the 42 pipeline agents would
   3x the token budget for marginal quality lift. Voting is reserved for
   decisions where a single bit flip is load-bearing.
2. **Code-generation voting.** Majority vote over three code samples produces
   Frankenstein code, not better code. Code quality is already handled by the
   TDD inner loop + verify + review gates. Different technique (e.g.
   best-of-N with reviewer scoring) is needed and is out of scope here.
3. **Per-perspective validator voting.** Findings (ARCH-1, SEC-1, etc.) stay
   single-sample; only the final verdict is voted. Voting per finding would
   require structured agreement over dissimilar strings, which is a harder
   problem than label voting.
4. **Backwards compatibility.** Per the Phase preamble, voting adds latency at
   three seams and there is no opt-out other than `consistency.enabled:
   false`. A "voting bypass" flag per decision is intentionally NOT provided.

---

## 4. Architecture

### 4.1 Consistency dispatch pattern

```
┌────────────────────────────────────────────────────────────────────┐
│ Caller (shaper / validator / post-run)                             │
│                                                                    │
│ 1. Build decision prompt as it would today                         │
│ 2. Call consistency.vote(                                          │
│      decision_point="shaper_intent",                               │
│      prompt=prompt,                                                │
│      n=config.consistency.n_samples,                               │
│      tier=config.consistency.model_tier)                           │
│ 3. Receive VoteResult{ label, confidence, samples[], cache_hit }   │
└────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────────┐
│ hooks/_py/consistency.py (dispatch helper, Phase 02 dep)            │
│                                                                    │
│ 1. Hash prompt + decision_point + n + tier → cache_key              │
│ 2. Look up .forge/consistency-cache.jsonl by cache_key              │
│    - Hit → return cached VoteResult, increment                      │
│      state.consistency_cache_hits                                   │
│    - Miss → continue                                                │
│ 3. Dispatch N parallel Task() calls, each with:                     │
│    - fresh subagent context (no shared history)                     │
│    - model tier = config.consistency.model_tier (fast by default)   │
│    - same prompt, same decision schema                              │
│ 4. Collect N (label, confidence) tuples                             │
│ 5. Aggregate: simple majority → tie-break by confidence-weighted    │
│    sum → final tie-break by single highest confidence               │
│ 6. Append { cache_key, result, samples } to                          │
│    .forge/consistency-cache.jsonl                                   │
│ 7. Return VoteResult                                                │
└────────────────────────────────────────────────────────────────────┘
```

### 4.2 Aggregation logic

Given N samples `[(label_i, confidence_i)]`:

1. **Majority vote.** Group by `label`, pick the group with the highest count.
   If exactly one group wins, return that label with the **mean** confidence
   of its members.
2. **Tie-break via soft self-consistency.** If two or more groups are tied on
   count, compute `sum(confidence_i)` per group and pick the group with the
   highest confidence sum. Return that label with the mean confidence of its
   winning members.
3. **Final fallback.** If confidence sums are also tied (degenerate case; rare
   for N=3 with three distinct confidences), return the single sample with
   the highest individual confidence.
4. **Confidence floor on the returned VoteResult.** If the winning group's
   mean confidence is below `consistency.min_consensus_confidence` (default
   0.5), surface the result to the caller with a `low_consensus: true` flag.
   The caller decides what to do — the validator treats `low_consensus` as an
   automatic REVISE; the shaper asks the user to confirm routing; the
   post-run classifier falls back to the safer side (`design`, which routes
   back further, so a bad plan gets re-planned rather than re-implemented).

### 4.3 Caching

- **Path:** `.forge/consistency-cache.jsonl`. JSONL so it's append-only and
  safe under concurrent appends (one line per vote).
- **Key:** `sha256(decision_point || '\0' || prompt || '\0' || n_samples ||
  '\0' || model_tier)`. The cache is invalidated naturally by prompt changes.
- **Eviction:** no active eviction. File grows unbounded. `/forge-recover
  reset` does **not** clear it (same rule as `explore-cache.json` and
  `plan-cache/`) because votes on unchanged prompts remain valid across
  resets. Manual `rm` removes it.
- **Disable:** `consistency.cache_enabled: false` skips both reads and
  writes. Used by the eval harness to measure raw voting quality.

### 4.4 Integration points

| Caller | Call site | Decision label space | Fallback on `low_consensus` |
|---|---|---|---|
| `fg-010-shaper` | Phase 1 (Understand Intent), ONE-shot classification of the raw argument against the intent table | `bugfix` / `migration` / `bootstrap` / `multi-feature` / `vague` / `testing` / `documentation` / `refactor` / `performance` / `single-feature` | Ask user to confirm via `AskUserQuestion` (shaper already uses `AskUserQuestion`, zero new UI) |
| `fg-210-validator` | End of section 5 (Verdict Rules), after all 7 perspectives have run | `GO` / `REVISE` / `NO-GO` | Force `REVISE` — orchestrator re-dispatches fg-200 |
| `fg-710-post-run` | PR-rejection feedback classifier, section that sets `state.feedback_classification` | `design` / `implementation` / `other` | Force `design` (routes back further, safer) |

### 4.5 Alternatives considered

**Alt 1: Single-sample with confidence threshold.** Keep one LLM call, but
ask the model to return `(label, confidence)`. If confidence < threshold,
escalate to the user. Rationale for rejection: LLM self-reported confidence
on a single sample is poorly calibrated (Kadavath et al. 2022, *Language
Models (Mostly) Know What They Know*, figure 2: confidence is bimodal at 0
and 1 on short-answer tasks). A single sample claiming 0.95 confidence on a
wrong label is the exact failure mode we are trying to catch. Voting exposes
disagreement that a single confidence score hides.

**Alt 2: Chain-of-thought ensemble with a judge.** Run N samples that each
produce a reasoning trace plus an answer, then dispatch a single judge agent
that reads all N traces and picks the best answer. Rationale for rejection:
adds a fourth LLM call on the critical path, and the judge is itself a
single-sample decision — it moves the problem rather than solving it. The
self-consistency paper (arXiv 2203.11171, §4.2) explicitly compares against
this and finds pure voting is within noise of judge-based ensembling while
being 2-3x cheaper.

---

## 5. Components

### 5.1 New — `shared/consistency/voting.md`

Contract document describing the dispatch helper, aggregation logic, cache
schema, and call-site requirements. Agents reference this instead of
duplicating the protocol. Sections:

1. Dispatch contract (input schema, output schema)
2. Aggregation algorithm (pseudocode)
3. Cache schema (JSONL line format, key derivation)
4. Low-consensus semantics
5. Fallback rules per decision point
6. Testing expectations (links to eval harness, Phase 01 dep)

### 5.2 New — `hooks/_py/consistency.py`

Dispatch helper. Depends on Phase 02 (`hooks/_py/` Python infrastructure).

Public API:

```python
def vote(
    decision_point: str,            # e.g. "shaper_intent"
    prompt: str,                    # exact prompt sent to each sample
    labels: list[str],              # allowed label space, enforces return
    n: int = 3,                     # odd number; default from config
    tier: str = "fast",             # model-routing tier
    cache_enabled: bool = True,
) -> VoteResult: ...
```

`VoteResult` is a dataclass:

```python
@dataclass(frozen=True)
class VoteResult:
    label: str
    confidence: float        # mean of winning-group confidences
    samples: list[tuple[str, float]]
    cache_hit: bool
    low_consensus: bool      # confidence < min_consensus_confidence
```

Internals:
- Uses `asyncio.gather` over N parallel Task() invocations. Each Task receives
  a fresh subagent with only the voting prompt (no shared history).
- Each sample's response is forced through a JSON schema with keys `label`
  (enum of `labels`) and `confidence` (float [0,1]).
- On schema violation, the sample is retried once; if it violates again, the
  sample is dropped and N-1 samples are aggregated. If fewer than `ceil(N/2)`
  samples survive, raise `ConsistencyError` — caller falls back to single-
  sample behavior.
- Appends to `.forge/consistency-cache.jsonl` via `hooks/_py/state_write.py`
  (atomic append from Phase 02).
- Increments `state.consistency_cache_hits` on cache hit via
  `hooks/_py/state_write.py`.

### 5.3 Modified — `agents/fg-010-shaper.md`

Phase 1 "Understand Intent" replaces the inline classification with a single
paragraph directing the shaper to call the consistency dispatch for the
routing label. Label space is the intent table from
`shared/intent-classification.md`. On `low_consensus`, fall through to the
shaper's existing dialogue (the shaping dialogue is already the right
recovery path when routing is ambiguous).

### 5.4 Modified — `agents/fg-210-validator.md`

Section 5 (Verdict Rules) splits into two sub-steps:

1. Compute the deterministic verdict from the finding rules (SEC → NO-GO,
   HARD ARCH → NO-GO, 3+ EDGE/TEST → REVISE, etc.) as today. This still
   happens single-sample because it's a rule evaluation over structured
   findings, not a judgment.
2. For the **final verdict synthesis** — the summarization step that decides
   GO vs REVISE when findings are borderline (e.g. 2 EDGE + 2 TEST + 1 SOFT
   ARCH, which today is a coin-flip depending on how the LLM weights them) —
   call the consistency dispatch with the structured findings as input and
   labels `[GO, REVISE, NO-GO]`. On `low_consensus`, force `REVISE`.

### 5.5 Modified — `agents/fg-710-post-run.md`

The PR-rejection classification step (currently a single-sample call that
sets `state.feedback_classification`) is wrapped with consistency dispatch
over labels `[design, implementation, other]`. On `low_consensus`, force
`design`.

---

## 6. Data / State / Config

### 6.1 New config block

Added to `forge-config.md` defaults:

```yaml
consistency:
  enabled: true
  n_samples: 3                       # odd; recommended 3 or 5
  decisions:
    - shaper_intent
    - validator_verdict
    - pr_rejection_classification
  model_tier: fast                   # fast | standard | premium
  cache_enabled: true
  min_consensus_confidence: 0.5      # low_consensus threshold
```

### 6.2 PREFLIGHT constraints

Added to `shared/preflight-constraints.md`:

- `consistency.enabled` must be boolean.
- `consistency.n_samples` must be odd and in [1, 9]. If 1, voting is
  effectively disabled for that run — logged as WARNING.
- `consistency.decisions` must be a subset of `{shaper_intent,
  validator_verdict, pr_rejection_classification}` in 3.1.0 (the set expands
  in later phases).
- `consistency.model_tier` must be one of the tiers declared in
  `model_routing.tiers`.
- `consistency.min_consensus_confidence` must be in [0.0, 1.0].

### 6.3 New state fields

Added to `shared/state-schema.md` (bumps `_seq` version from 1.6.0 to 1.7.0):

```json
{
  "consistency_cache_hits": 0,
  "consistency_votes": {
    "shaper_intent": { "invocations": 0, "cache_hits": 0, "low_consensus": 0 },
    "validator_verdict": { "invocations": 0, "cache_hits": 0, "low_consensus": 0 },
    "pr_rejection_classification": { "invocations": 0, "cache_hits": 0, "low_consensus": 0 }
  }
}
```

### 6.4 New file

`.forge/consistency-cache.jsonl` — append-only, one line per vote:

```json
{"ts":"2026-04-19T10:00:00Z","key":"sha256:…","decision":"shaper_intent","n":3,"tier":"fast","result":{"label":"bugfix","confidence":0.87,"samples":[["bugfix",0.9],["bugfix",0.85],["bugfix",0.86]]}}
```

Survives `/forge-recover reset`. Listed in the "survives reset" section of
CLAUDE.md alongside `explore-cache.json`, `plan-cache/`, etc.

### 6.5 `/forge-insights` surface

`/forge-insights` gains a "Consistency Voting" section showing cache hit
rate, low-consensus rate per decision point, and flipped-verdict count
(votes where the majority label differs from the first sample's label — a
direct measure of voting's value-add).

---

## 7. Compatibility

**Breaking changes — no opt-out flags per the phase preamble.**

1. **Latency.** Each wrapped decision adds one fast-tier parallel
   roundtrip on the critical path. Measured ceiling: the slowest of N
   parallel samples. Budget:
   - Shaper intent classification: +800ms-2s (fast tier one-shot).
   - Validator verdict: +800ms-2s.
   - Post-run PR rejection: +800ms-2s.
   Total worst case at the three seams: +6s. See section 11 for the <30%
   end-to-end latency bound.
2. **Cost.** Each wrapped decision adds N-1 fast-tier samples. At N=3 and
   fast-tier pricing, this is additive but below the noise floor of the
   overall pipeline cost (measured per `forge-token-tracker.sh`).
3. **No "bypass" flag per decision.** `consistency.enabled: false` is the
   single global kill switch. Per-decision disable is rejected because it
   produces a silent quality gradient that is hard to reason about.
4. **State schema bump** `1.6.0 → 1.7.0`. Older state files missing the new
   fields are upgraded in place at PREFLIGHT (fields default to `0` and
   empty maps).
5. **CI dependency.** Per the phase preamble, we rely on CI for validation;
   no local test execution is required. The eval harness (section 8) runs
   in CI only.

---

## 8. Testing Strategy

Depends on Phase 01 (Evaluation Harness).

### 8.1 Labeled dataset

`tests/consistency/datasets/`:

- `shaper_intent.jsonl` — ~100 prompts across the 10 intents, hand-labeled
  from real `.forge/reports/` across the maintainers' projects.
- `validator_verdict.jsonl` — ~60 plans with ground-truth verdicts derived
  from post-hoc outcome (did the plan ship? was it reverted?).
- `pr_rejection.jsonl` — ~40 reviewer-comment samples with hand-labeled
  design/implementation/other tags.

### 8.2 Eval harness assertions

Run in CI under the Phase 01 harness:

1. **Deterministic prompts are unanimous.** Prompts with an obvious label
   (e.g. `"fix: crash on null user in /api/orders"` for shaper) must return
   all N samples with the same label. Assert unanimity rate > 95% on the
   labeled "easy" subset.
2. **Adversarial prompts expose consensus failure.** Prompts constructed to
   straddle two intents (e.g. `"migrate our auth to fix the crash"`) must
   show `low_consensus: true` at least 80% of the time. Assert this is the
   primary mechanism by which hard prompts are escalated.
3. **Voting lift ≥ 5pp.** On the combined dataset, voted accuracy must
   exceed single-sample accuracy by at least 5 percentage points. This is
   the success criterion (section 11).
4. **Cache correctness.** Run the dataset twice; assert the second run has
   100% cache hit rate and identical results.
5. **Latency budget.** Assert p95 added latency at each decision point is
   under 2.5s on the fast tier.

### 8.3 No local execution

Per the phase preamble, maintainers do not run the eval harness locally.
CI is the ground truth. Failures appear as a PR check.

---

## 9. Rollout

**Single PR.** No staged rollout, no behind-flag soak period. Per the phase
preamble:

1. Add `hooks/_py/consistency.py` (dep: Phase 02 merged).
2. Add `shared/consistency/voting.md`.
3. Modify `agents/fg-010-shaper.md`, `agents/fg-210-validator.md`,
   `agents/fg-710-post-run.md`.
4. Add config defaults and PREFLIGHT constraints.
5. Add state schema fields, bump `_seq` version to 1.7.0.
6. Add eval-harness datasets and CI job.
7. Update CLAUDE.md: add `.forge/consistency-cache.jsonl` to the "survives
   reset" list; add "Self-consistency voting" row to the v2.0 features
   table; update the "Core contracts" section to mention voting at the
   three seams.

---

## 10. Risks & Open Questions

### R1 — Fast-tier models may systematically disagree with premium-tier

If the fast tier has a different bias than the premium tier, voting with
fast-tier samples could drag a correct premium-tier verdict to a wrong
majority. Mitigation: the eval harness (section 8) measures voted accuracy
directly, not agreement rate. If the data shows fast-tier voting is
strictly worse than premium-tier single-sample for a given decision,
`consistency.model_tier` is reconfigured to `standard` or `premium` for
that decision (per-decision tier is deferred to a later phase — for 3.1.0
the tier is global).

### R2 — Cache poisoning via non-determinism

A vote is cached by prompt hash. If the same prompt is re-asked in a
different codebase state (different explore cache, different PREEMPT
items), the cached answer may be wrong. Mitigation: the prompt already
includes the relevant context (the validator's prompt includes the full
plan; the shaper's prompt includes only the user argument, which doesn't
depend on codebase state; the post-run classifier's prompt includes the
PR feedback verbatim). So the hash already captures the relevant state.
Open question: do we need to include `state.mode` in the cache key for the
validator? Leaning yes — added to the cache key as belt-and-suspenders.

### R3 — Low-consensus storms on ambiguous domains

A codebase with unusual conventions could produce persistent low-consensus
results on the validator, causing a REVISE storm. Mitigation: the
orchestrator's existing `validation.max_validation_retries` already caps
the REVISE loop and escalates to the user. Voting doesn't change that
cap; it only changes what triggers the REVISE.

### Open questions

- **N=5 for validator?** The validator verdict is the highest-stakes of the
  three (wrong GO ships bad code). Should the validator run at N=5 while
  shaper and post-run run at N=3? Deferred to post-launch calibration —
  `consistency.decisions` is currently a list of strings; a later phase
  can extend it to `list[dict]` with per-decision `n_samples`.
- **Cache TTL?** Currently unbounded. If the label space for an intent
  expands (new intent added), old cache entries become stale. Not yet a
  problem — deferred.

---

## 11. Success Criteria

1. **Accuracy lift:** voted accuracy on the labeled dataset exceeds
   single-sample accuracy by ≥ 5 percentage points, measured in CI by the
   eval harness.
2. **Latency ceiling:** added end-to-end pipeline latency at the three
   integration points is < 30%, measured as p95 over the eval harness run
   set. The cache hit rate on repeated prompts (e.g. validator re-runs
   after REVISE) must be > 50% on a realistic mixed workload, which is the
   mechanism that keeps the ceiling hit.
3. **Low-consensus escalation works:** adversarial prompts trigger
   `low_consensus: true` ≥ 80% of the time, and the fallback path (REVISE
   for validator, user confirm for shaper, `design` for post-run) fires
   deterministically.
4. **Zero cost regression on unused decisions:** decisions not in
   `consistency.decisions` are untouched (no wrapper overhead).
5. **Ship in one PR** with no backwards-compat shims, per the phase
   preamble.

---

## 12. References

- Self-consistency: Wang, X. et al. 2022, *Self-Consistency Improves Chain
  of Thought Reasoning in Language Models*,
  <https://arxiv.org/abs/2203.11171>.
- Soft self-consistency: Wang, H. et al. 2024, *Soft Self-Consistency
  Improves Language Model Agents*,
  <https://arxiv.org/html/2402.13212v1>.
- Confidence calibration: Kadavath, S. et al. 2022, *Language Models
  (Mostly) Know What They Know*, <https://arxiv.org/abs/2207.05221>.
- forge intent classification contract:
  `/Users/denissajnar/IdeaProjects/forge/shared/intent-classification.md`.
- forge confidence scoring contract:
  `/Users/denissajnar/IdeaProjects/forge/shared/confidence-scoring.md`.
- forge shaper agent:
  `/Users/denissajnar/IdeaProjects/forge/agents/fg-010-shaper.md`.
- forge validator agent:
  `/Users/denissajnar/IdeaProjects/forge/agents/fg-210-validator.md`.
- Phase 01 design (eval harness dep):
  `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-01-evaluation-harness-design.md`.
- Phase 02 design (Python hooks dep):
  `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-02-cross-platform-python-hooks-design.md`.
