# 0013 — Weekly benchmark extension

- Status: Accepted
- Date: 2026-04-22
- Supersedes: —
- Superseded by: —

## Context

`tests/evals/pipeline/` already measures ten synthetic scenarios for per-PR smoke. No artifact in the repo substantiates the phrase "state of the art" as a solve-rate number against user-owned features. Peer benchmarks (SWE-bench Verified, OpenHands, SWE-agent) publish comparable single-agent numbers in the 45–70% range. Until forge produces a comparable number, the claim is aspiration.

## Decision

1. **Extend-in-place pipeline harness.** `tests/evals/benchmark/` imports `tests/evals/pipeline/runner/executor.py` rather than forking. Shared code is edited in place per ADR 0008 no-backcompat stance. The `extend-in-place` strategy avoids a parallel harness fork.
2. **Solve predicate = SHIP or CONCERNS ∧ ≥0.9 AC ∧ 0 critical.** CONCERNS counted deliberately. Stricter SHIP-only rate reported alongside as `ship_rate`.
3. **Regression gate at 10pp delta.** Below that threshold, week-to-week variance dominates; above it, the signal is real.
4. **6-cell matrix: 3 OS × 2 model.** Haiku excluded by design (quality not cost is the question). Sonnet 4.6 + Opus 4.7.
5. **Direct bot-commit to master.** Forge is a personal tool; master has no branch protection for `github-actions[bot]`. PR-fallback path documented but not built (Open Question #9).
6. **Explicit model override via `forge.local.md` fragment.** Env-only propagation is insufficient because `shared/model-routing.md` fixes `Agent.model` to {haiku, sonnet, opus} aliases. The helper writes `model_routing.overrides.{fast,standard,premium}` to the ephemeral project tempdir — never into the plugin repo.
7. **Cost ceiling starts at $200/week**, conservatively. Empirical refresh after 90 days of Phase-6-wired data.

## Consequences

- Per-PR CI stays fast (collect + unit + contract + integration). Weekly cron is the only path invoking real Anthropic API.
- Corpus is user-authored; `curate.py` is interactive.
- Every matrix cell exercises exactly one model end-to-end (all three tiers pinned), so solve-rate differences are attributable.
- `SCORECARD.md` is a first-class repo artifact. External readers see the number without leaving the repo.

## Alternatives rejected

- **Dedicated benchmark repo.** Adds CI secrets, CODEOWNERS, release coordination — hostile to personal-tool inertia.
- **Third-party SaaS (W&B, Braintrust).** Secret provisioning + per-run spend outside forge-config.
- **Patching shared/model-routing.md at runtime.** Mutates a repo-tracked contract file.
- **Per-commit benchmark.** Cost-prohibitive at 10+ entries × 6 cells × 90 min.
