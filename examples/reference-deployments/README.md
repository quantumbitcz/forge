# forge Reference Deployments

This directory indexes public, open-source libraries that have been rewritten end-to-end by `/forge-run`, with full PR history and evidence bundles published in dedicated forks under the forthcoming `forge-reference-deployments` GitHub org (created by Phase 15).

## Purpose

Reference deployments are concrete, falsifiable proof that the forge 10-stage pipeline produces shippable output. Anyone can download the diff, read the PR, and judge the work for themselves.

## Selection criteria

See `docs/marketing/shortlist-research.md` for the research method and current shortlist. The eligibility criteria (SLOC < 5,000, permissive license, archived/unmaintained, ≥100 stars, forge module coverage, single-purpose) are enforced in `docs/superpowers/specs/2026-04-19-15-reference-deployment-design.md` §4.1.

## Deployments

| Library | Status | Fork | Evidence | Score | Tokens | Elapsed |
|---|---|---|---|---|---|---|
| *(selected library — see Task 3)* | In progress | — | — | — | — | — |

## Disclaimer

Reference deployments are **illustrative, not a comprehensive benchmark**. See `tests/evals/` for the full eval suite. The library was chosen because it fits the selection criteria and is covered by existing forge modules — selection bias is acknowledged in the spec (R7) and addressed by adding candidates in Phase 15.1 / 15.2.

## Evidence location

Each row in the table above links to:
1. The public fork under `forge-reference-deployments` org.
2. The GitHub release with `forge-rewrite-evidence-<lib>-v<n>.tar.gz` attached.
3. Per-library docs in this directory: `<lib-name>/README.md`, `<lib-name>/ADR.md`, `<lib-name>/evidence-summary.md`.
