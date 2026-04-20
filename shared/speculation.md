# Speculation (Phase 12) — Authoritative Contract

## Trigger Logic

Predicate: `triggered = (confidence == MEDIUM) AND (shaper_alternatives_ok OR keyword_hit OR multi_domain_hit OR marginal_cache_hit)`.

Signal sources (OR-combined inside `ambiguity_signal_hit`):
1. `shaper_alternatives_ok` = shaper emitted >=2 alternatives with strength delta <=10 pts.
2. `keyword_hit` = requirement regex: `(?i)\b(either|or|could|maybe|consider|multiple approaches)\b` OR `/` between nouns (`REST/GraphQL`).
3. `multi_domain_hit` = domain detection returns >=2 candidate domains with confidence delta <=0.15.
4. `marginal_cache_hit` = plan cache similarity in [0.40, 0.59].

Shaper override rule: if signal 1 fires, `trigger_reason[0] = "shaper_alternatives>=2"`; shaper is elevated above keyword/domain/cache signals.

Skip modes: `bugfix`, `bootstrap` (configurable via `speculation.skip_in_modes`). Plan-cache hit >=0.60 skips speculation (cached plan preferred). Requirement length floor: 15 words.

## Dispatch Protocol

N candidates (default 3, valid 2-5). Each `fg-200-planner` receives:
- `candidate_id`: `cand-{1..N}`
- `exploration_seed`: `hash(run_id + candidate_id) % 2**31`
- `emphasis_axis`: round-robin from `[simplicity, robustness, velocity]`
- `speculative: true` (abbreviated 200-word Challenge Brief)

Concurrency: orchestrator dispatches N Agent-tool invocations back-to-back; harness runs them in parallel. Validator dispatches N parallel `fg-210-validator` calls after all planners return.

## Diversity Check

Threshold: `min_diversity_score` (default `0.15`). Definition: `diversity = 1 - max_pairwise_jaccard(plan_content_tokens)` where `plan_content_tokens` is the word-token set of each plan's markdown body (lowercased, stopwords removed). If `diversity < min_diversity_score`, speculation is degraded: use top-1 plan, skip N-way validation (single validator run), log `speculation.degraded = "low_diversity"`.

## Cost Guardrails

Pre-dispatch estimate: `estimated = baseline + (mean(recent_planner_tokens[-10:]) or cold_start_default) * N` where `cold_start_default = 4500` when `recent_planner_tokens` is empty. Abort if `estimated > baseline * token_ceiling_multiplier` (default `2.5`). Fallback: single-plan path with WARNING logged.

## Selection

Formula:
```
selection_score = validator_score + verdict_bonus + 0.1 * token_efficiency_bonus
verdict_bonus = {GO: 0, REVISE: -15, NO-GO: eliminated}
token_efficiency_bonus = (max_batch_tokens - candidate_tokens) / max_batch_tokens * 100
```

Rules (see §4.4 of design spec for full table): auto-pick when delta > `auto_pick_threshold_delta` (default 5); interactive mode asks user on tie; autonomous auto-picks top-1 with `[AUTO]` log.

## Persistence

Path: `.forge/plans/candidates/{run_id}/cand-{N}.json`. Schema: v1.0.0 (fields per design spec §5.4). Index: `.forge/plans/candidates/index.json`. FIFO eviction: keep last 20 runs. Survives `/forge-recover reset`.

## Eval Methodology

Corpus: `evals/speculation/corpus.json`, 12 curated ambiguous requirements across auth/migrations/API/state/UI. Metrics: quality lift >= +5 (floor 0), token ratio <= 2.5x (hard ceiling), selection precision >= 60% (target 75%), trigger rate in 20-50%. Baseline: `speculation.enabled: false` captured on identical seeds.

## Forbidden Actions

- No speculation outside PLAN stage.
- No speculation in bugfix/bootstrap modes.
- No speculation when plan_cache hit >= 0.60.
- No auto-retry on all-NO-GO; escalate to user.
- No recursive N escalation on validator tie.
