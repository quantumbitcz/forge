# Anthropic Marketplace Submission Checklist

**Target repo:** <https://github.com/anthropics/claude-plugins-official>
**Our plugin:** forge (quantumbitcz)
**Cross-list does NOT modify `quantumbitcz/marketplace.json`** — we ship in both marketplaces.

> **This is a preflight template.** Fill `<lib-name>` substitutions at submission time (after Phase 15 plan Task 3 selects a library and Task 10 publishes the fork). CI validation (Task 12 Step 3) is deferred until the three screenshots referenced below exist under `docs/marketing/screenshots/`.

---

## Pre-submission verification

- [ ] Read current `CONTRIBUTING.md` + `README.md` of `anthropics/claude-plugins-official` — the submission format may have changed since this checklist was authored.
- [x] `plugin.json` description length ≤160 chars — **verified 128 chars as of 2026-04-21** via `jq -r '.description | length' .claude-plugin/plugin.json`.
- [x] `plugin.json` `homepage` field present — `https://github.com/quantumbitcz/forge`.
- [x] `plugin.json` `keywords` present (29 entries including language tags + domain tags) — verify upstream has no count cap at submission time.
- [ ] `plugin.json` `license: "Proprietary"` is accepted by upstream (verify at PR time).
- [ ] All three screenshots exist at referenced paths (to be validated by `.github/workflows/submission-checklist-validate.yml` in Task 12 Step 3 — deferred until screenshots ship in Task 12 Step 4).
- [ ] Reference deployment is public (`examples/reference-deployments/<lib-name>/` exists and links to live fork).
- [ ] Case study exists at `docs/marketing/case-study.md` (shipped by Task 11).

## Copy-ready manifest snippet

```json
{
  "name": "forge",
  "description": "Autonomous 10-stage development pipeline with multi-language support, self-healing recovery, and generalized code quality checks",
  "repository": "https://github.com/quantumbitcz/forge",
  "homepage": "https://github.com/quantumbitcz/forge",
  "license": "Proprietary",
  "category": "development",
  "keywords": [
    "forge", "pipeline", "tdd", "code-review", "quality-gate", "linear",
    "kotlin", "typescript", "python", "go", "rust", "swift", "java", "c",
    "cpp", "csharp", "dart", "elixir", "php", "ruby", "scala",
    "documentation", "graph", "migration", "testing", "bootstrap",
    "code-quality", "crosscutting", "knowledge-graph"
  ]
}
```

## Copy-ready short description (128 chars, ≤160 cap)

> Autonomous 10-stage development pipeline with multi-language support, self-healing recovery, and generalized code quality checks

## Screenshots (three required per spec §4.6)

| # | Path | Content | Pixel dimensions |
|---|---|---|---|
| 1 | `docs/marketing/screenshots/forge-run-output.png` | `/forge-run` terminal output showing stage progression | 1600x1000 min |
| 2 | `docs/marketing/screenshots/state-json-visualized.png` | `.forge/state.json` visualised (score history + convergence) | 1600x1000 min |
| 3 | `docs/marketing/screenshots/reference-deployment-pr.png` | Screenshot of the merged `forge-rewrite` PR in the fork | 1600x1000 min |

## License disclosure statement

> forge is licensed under a proprietary license by QuantumBit s.r.o. Source code is readable in the repository but not redistributable under an OSS license. See `LICENSE` for full terms. The plugin manifest is shared under this proprietary license but installation and use are free per the license.

## Reference deployment URL + badge

- Fork: `https://github.com/forge-reference-deployments/<lib-name>`
- Badge markdown: `![Reference deployment](https://img.shields.io/badge/reference-<lib--name>-blue)` (double-dash escape per shields.io syntax; a literal single dash inside the `message` slot is rendered as a separator).

## PR body template

```
## Summary
Submitting the `forge` plugin for cross-listing. `forge` is an autonomous 10-stage development pipeline with 48 agents, TDD loop, quality gate with 9 reviewers, and self-healing recovery.

## Plugin metadata
- Name: forge
- Author: QuantumBit s.r.o.
- License: Proprietary
- Homepage: https://github.com/quantumbitcz/forge
- Source: https://github.com/quantumbitcz/forge

## License clarity
Proprietary. Source is readable; installation is free. No redistribution under OSS terms.

## Evidence
Public reference deployment: https://github.com/forge-reference-deployments/<lib-name>
Case study: https://github.com/quantumbitcz/forge/blob/master/docs/marketing/case-study.md

## Screenshots
<attach the three PNGs>

## Maintainer contact
denis.sajnar@gmail.com / GitHub: @quantumbitcz
```

## Post-merge follow-up (forge repo, separate PR — Task 14)

- [ ] Add "Ships on Anthropic marketplace" badge to forge `README.md`.
- [ ] Bump `.claude-plugin/plugin.json` version — **plan drift note:** the plan prescribes `3.0.1` (written against a 3.0.0 baseline), but plugin.json is `3.5.0` as of 2026-04-21 (post-#92 CHANGELOG backfill). The correct post-merge bump is **`3.5.1`** (patch bump from current). Update the plan if the drift matters long-term; for submission, use 3.5.1.
- [ ] One-line update to `CLAUDE.md` §Distribution.

## If Anthropic rejects (review I3 relaxation → Task 15)

Phase 15 does NOT fail on rejection. Success Criterion #3 is satisfied by "submission PR opened AND reviewer feedback responded to". If a rejection is issued with actionable feedback, open Task 15 (resubmission loop as Phase 15.0.1). If the rejection is final-no-appeal, Phase 15 still ships at 75% — public fork + case study + badge-less README are still shipped.

## Delta from plan Task 12 as authored

| Item | Plan text | This file | Rationale |
|---|---|---|---|
| Agent count | "42 agents" | "48 agents" | Agent count grew from 42 → 48 post-Phase 07 (see CLAUDE.md §Agents). |
| Reviewer count | "8 reviewers" | "9 reviewers" | Quality gate now includes `fg-419-infra-deploy-reviewer`; 9 total (410-419 range, minus 415). |
| Post-merge version | "3.0.1" | "3.5.1" | plugin.json is at 3.5.0 today, not 3.0.0. Patch-bump from current. |
| Case study branch | "main" | "master" | Forge default branch is `master`. |

These drifts do not require touching the plan file; they are baked into this canonical checklist so the future submission session can use it as copy-ready.
