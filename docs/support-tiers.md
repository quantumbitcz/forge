# Support tiers

> Tier is determined solely by which CI matrix jobs exercise the module.
> Not by author claim, not by module age, not by popularity.

Tier identifiers are lowercase-with-hyphen (`ci-verified`, `contract-verified`,
`community`) — that is the literal string emitted into the `> Support tier:`
badge of every module file. Headings below use title case for readability, but
the badge value and any programmatic comparison must use the lowercase ID.

| Tier | Meaning | How to qualify |
|---|---|---|
| `ci-verified` | A `pipeline-smoke` matrix leg runs the full 10-stage pipeline against a seed project using this module. | Added to `.github/workflows/pipeline-smoke.yml` (Phase 2). |
| `contract-verified` | The module has `conventions.md`, `rules-override.json` (optional), `known-deprecations.json` (if applicable), and passes `tests/run-all.sh contract`. | Default for `modules/languages/`, `modules/frameworks/<root>/`, `modules/testing/`. |
| `community` | Module ships docs only — no dedicated CI or contract gating. | Default for `modules/documentation/`, `modules/ml-ops/`, `modules/data-pipelines/`, `modules/feature-flags/`, `modules/build-systems/`, `modules/code-quality/`, `modules/api-protocols/`, and any framework `documentation/` sub-binding. |

## CI-verified (planned — Phase 2)

Four seed stacks are scoped for `pipeline-smoke` coverage:

- `kotlin + spring + (kotest | junit5) + gradle`
- `typescript + react + vitest`
- `python + fastapi + pytest`
- `go + stdlib + go-testing`

Until the Phase 2 matrix lands, these carry the `contract-verified` badge.
They graduate automatically when the matrix job is green.

## Contract-verified (current)

Every module under `modules/languages/`, `modules/frameworks/<root>/`, and
`modules/testing/` whose contract tests pass. The badge is injected below
the module H1 by `tests/lib/derive_support_tiers.py`.

## Community

Layers shipped as conventions-only — no dedicated contract suite, no
pipeline-smoke matrix entry. Today this covers `modules/documentation/`,
`modules/ml-ops/`, `modules/data-pipelines/`, `modules/feature-flags/`,
`modules/build-systems/`, `modules/code-quality/`, `modules/api-protocols/`,
and every framework `documentation/` sub-binding. A module also lands here
if its directory carries a `.community` marker file. The authoring team is
responsible for repair — the pipeline does not carry community-tier modules
through gating logic.

## Drift detection

`docs-integrity.yml` runs `derive_support_tiers.py --check` on every
pull-request. Drift (a stale badge) fails CI.
