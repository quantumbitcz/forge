# Support tiers

> Tier is determined solely by which CI matrix jobs exercise the module.
> Not by author claim, not by module age, not by popularity.

| Tier | Meaning | How to qualify |
|---|---|---|
| CI-verified | A `pipeline-smoke` matrix leg runs the full 10-stage pipeline against a seed project using this module. | Added to `.github/workflows/pipeline-smoke.yml` (Phase 2). |
| Contract-verified | The module has `conventions.md`, `rules-override.json` (optional), `known-deprecations.json` (if applicable), and passes `tests/run-all.sh contract`. | Default for all modules shipped today. |
| Community | Module files exist but one or more contract assertions fail. | Automatic — if contract tier fails, the badge downgrades. |

## CI-verified (planned — Phase 2)

Four seed stacks are scoped for `pipeline-smoke` coverage:

- `kotlin + spring + (kotest | junit5) + gradle`
- `typescript + react + vitest`
- `python + fastapi + pytest`
- `go + stdlib + go-testing`

Until the Phase 2 matrix lands, these carry the `contract-verified` badge.
They graduate automatically when the matrix job is green.

## Contract-verified (current)

Every module listed under `modules/languages/`, `modules/frameworks/`, and
`modules/testing/` whose contract tests pass. The badge is injected below
the module H1 by `tests/lib/derive_support_tiers.py`.

## Community

Currently empty. A module appears here automatically if any contract
assertion fails. The authoring team is responsible for repair — the
pipeline does not carry community-tier modules through gating logic.

## Drift detection

`docs-integrity.yml` runs `derive_support_tiers.py --check` on every
pull-request. Drift (a stale badge) fails CI.
