# Self-Consistency Voting — Contract

**Status:** Active. Introduced in forge 3.1.0.
**Callers:** `agents/fg-010-shaper.md`, `agents/fg-210-validator.md`, `agents/fg-710-post-run.md`.
**Dispatch helper:** `hooks/_py/consistency.py`.

---

## 1. Dispatch Contract

```python
vote(
    decision_point: str,            # "shaper_intent" | "validator_verdict" | "pr_rejection_classification"
    prompt: str,                    # exact prompt sent to each sample
    labels: list[str],              # allowed label space, enforced via JSON schema
    state_mode: str,                # state.mode at call time (feeds cache key)
    n: int = 3,                     # odd number; default from config
    tier: str = "fast",             # model-routing tier
    cache_enabled: bool = True,
) -> VoteResult
```

Returns:

```python
@dataclass(frozen=True)
class VoteResult:
    label: str                      # winning label
    confidence: float               # mean confidence of the winning group
    samples: list[tuple[str, float]]
    cache_hit: bool
    low_consensus: bool             # confidence < min_consensus_confidence
```

On unrecoverable schema failures (fewer than `ceil(N/2)` samples survive after one retry), the helper raises `ConsistencyError`. The caller treats `ConsistencyError` as `low_consensus: true` and applies the §5 fallback for that decision point. The caller does NOT re-invoke dispatch.

### 1.1 Subagent dispatch bridge (Tasks 1-3 stub)

The helper's `vote_async(...)` accepts an injected `sampler` callable with signature
`async (prompt, labels, tier, seed) -> {"label": str, "confidence": float}`. This callable
is the bridge that actually invokes a fresh fast-tier subagent per sample. The initial
helper landing ships with NO default sampler — callers MUST inject one or the helper
raises `ValueError("sampler must be provided")`.

The production sampler — which dispatches a real Claude Code subagent (most likely via a
Bash CLI shim such as `hooks/_py/consistency_cli.py` driven from the agent `.md` file) — is
introduced in a follow-up task. Until then, only the
test sampler in `hooks/_py/tests/test_consistency.py` is wired in. This keeps the helper
pure-Python testable without committing to the bridge mechanism (hook vs. orchestrator vs.
Bash subcommand) before that decision is made.

---

## 2. Aggregation Algorithm

Given N samples `[(label_i, confidence_i)]`:

1. Group by `label`. Count group sizes.
2. **Simple majority.** If exactly one group has the maximum count, return that label with the `mean(confidence_i)` over the winning group.
3. **Soft self-consistency tie-break.** If two or more groups share the max count, compute `sum(confidence_i)` per tied group and pick the highest. Return that label with the mean confidence of its members.
4. **Highest-single-confidence fallback.** If the confidence sums are also equal (degenerate for N=3 with distinct samples; possible for N=2 after a schema-drop), return the single sample with the highest individual confidence; `confidence = that sample's confidence`.
5. **Low-consensus flag.** If the returned `confidence` < `consistency.min_consensus_confidence` (default 0.5), set `low_consensus = true`.

---

## 3. Cache Schema

**Path:** `.forge/consistency-cache.jsonl`. Append-only, one JSON object per line.

**Key:**

```
cache_key = sha256(
    decision_point || "\0" ||
    state.mode     || "\0" ||    # REQUIRED — see §3.1
    prompt         || "\0" ||
    str(n_samples) || "\0" ||
    model_tier
).hexdigest()
```

### 3.1 Why `state.mode` is in the key

A shaper-intent vote cached in `state.mode = "standard"` must NOT be reused in `state.mode = "bugfix"` for the same raw `$ARGUMENTS`, because the classification context differs (a bugfix-shaped argument in bugfix mode should not inherit a standard-mode label). The prompt body captures plan text / PR feedback, but `state.mode` is metadata the callers do not always inject into the prompt. Including `state.mode` in the key is cheap belt-and-suspenders.

### 3.2 Line format

```json
{"ts":"2026-04-19T10:00:00Z","key":"sha256:…","decision":"shaper_intent","mode":"standard","n":3,"tier":"fast","result":{"label":"bugfix","confidence":0.87,"samples":[["bugfix",0.9],["bugfix",0.85],["bugfix",0.86]]}}
```

### 3.3 Eviction

None. File grows unbounded. `/forge-admin recover reset` does NOT clear it (same rule as `explore-cache.json` and `plan-cache/`). Only manual `rm` removes it.

### 3.4 Disable

`consistency.cache_enabled: false` skips reads and writes. Used by the eval harness to measure raw voting quality.

---

## 4. Cost & Latency Delta Table

Per-seam deltas at N=3 on fast tier. Baseline "1 sample" = a single caller-tier call today.

| Seam | Baseline latency | Voting latency (p95) | Delta (ms) | Baseline cost (per call) | Voting cost (per call) | Delta ($ per 1M tokens equivalent) |
|---|---|---|---|---|---|---|
| `shaper_intent` | 1 × caller-tier | max(3 × fast-tier parallel) | +800–2000 | 1 × caller-tier short classification | 1 × caller-tier + 2 × fast-tier | +~$0.30–$1.00 per 1M input tokens added across both extra samples |
| `validator_verdict` | 1 × caller-tier | max(3 × fast-tier parallel) | +800–2000 | 1 × caller-tier verdict synthesis | 1 × caller-tier + 2 × fast-tier | +~$0.30–$1.00 per 1M input tokens added |
| `pr_rejection_classification` | 1 × caller-tier | max(3 × fast-tier parallel) | +800–2000 | 1 × caller-tier short classification | 1 × caller-tier + 2 × fast-tier | +~$0.30–$1.00 per 1M input tokens added |

**Total worst case per run:** +6 s added latency (three seams sequential) and +6 fast-tier short-classification calls. On a cache hit, latency drops to ~5 ms (file read + hash) and cost to 0.

Success criterion §11.2 bounds added end-to-end pipeline latency at <30% p95, relying on cache hit rate >50% on a realistic mixed workload (validator re-runs after REVISE share identical plan text).

---

## 5. Low-Consensus Fallback Rules (per decision point)

| Caller | Label space | Low-consensus fallback |
|---|---|---|
| `fg-010-shaper` | `bugfix` / `migration` / `bootstrap` / `multi-feature` / `vague` / `testing` / `documentation` / `refactor` / `performance` / `single-feature` | Fall through to existing AskUserQuestion dialogue (zero new UI). |
| `fg-210-validator` | `GO` / `REVISE` / `NO-GO` | Force `REVISE`. Orchestrator re-dispatches `fg-200-planner`. |
| `fg-710-post-run` | `design` / `implementation` / `other` | Force `design` (routes back further; safer). |

The same fallback fires on `ConsistencyError` (too few samples survived parsing).

---

## 6. Validator Voting Boundary (scope fence)

- **Voting applies only to** the final GO/REVISE/NO-GO summarization step in `agents/fg-210-validator.md` §5.
- **Voting does NOT apply to** per-perspective findings (ARCH-N, SEC-N, EDGE-N, TEST-N, CONV-N, APPROACH-N, DOC-N). Those remain single-sample.
- **Voting is gated by** the deterministic rule pass. Voting fires only when the rule pass returns `INCONCLUSIVE` (no SEC/HARD-ARCH trigger, no 3+ EDGE/TEST trigger, at least one WARNING-level finding present). Hard verdicts skip voting and do NOT increment `consistency_votes.validator_verdict.invocations`.

---

## 7. Testing

Eval harness datasets at `tests/consistency/datasets/`:
- `shaper_intent.jsonl` (~100 samples)
- `validator_verdict.jsonl` (~60 samples)
- `pr_rejection.jsonl` (~40 samples)

CI assertions in `tests/contract/consistency-eval.bats`:
1. Unanimity rate > 95% on the easy subset of each dataset.
2. Adversarial prompts trigger `low_consensus` ≥ 80% of the time.
3. Voted accuracy ≥ single-sample accuracy + 5 percentage points.
4. Second pass over the dataset has 100% cache hit rate and identical results.
5. p95 added latency per decision point < 2.5 s on fast tier.

Harness is invoked by CI only — see `.github/workflows/eval.yml::consistency-eval` job.
