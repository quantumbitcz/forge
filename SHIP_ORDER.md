# Forge 13-Plan Ship Order

Canonical sequence for the A+ roadmap (8 phases) + mega-consolidation (5 plans). Each phase ships independently — code review after every phase via `superpowers:requesting-code-review`, then version bump + tag + push + GitHub release.

## Order

| # | Plan | File | Notes |
|---|---|---|---|
| 1 | Phase 1 — Truth & Observability | `docs/superpowers/plans/2026-04-22-phase-1-truth-and-observability.md` | Minimal agent touches; ships first |
| 2 | Phase 2 — Contract Enforcement | `docs/superpowers/plans/2026-04-22-phase-2-contract-enforcement.md` | |
| 3 | Phase 3 — Correctness Proofs | `docs/superpowers/plans/2026-04-22-phase-3-correctness-proofs.md` | Bumps `plugin.json` to **3.7.0** |
| 4 | Phase 4 — Learnings Dispatch Loop | `docs/superpowers/plans/2026-04-22-phase-4-learnings-dispatch-loop.md` | |
| 5 | Phase 5 — Pattern Modernization, Judges | `docs/superpowers/plans/2026-04-22-phase-5-pattern-modernization.md` | Renames `fg-205-planning-critic` → `fg-205-plan-judge` and `fg-301-implementer-critic` → `fg-301-implementer-judge`. Bumps `plugin.json` to **4.0.0**. Sets `state-schema` version to **2.0.0** |
| 6 | Phase 6 — Cost Governance | `docs/superpowers/plans/2026-04-22-phase-6-cost-governance.md` | Bumps `plugin.json` to **4.1.0** |
| 7 | Phase 7 — Intent Assurance | `docs/superpowers/plans/2026-04-22-phase-7-intent-assurance.md` | Adds `fg-540-intent-verifier`. **Prereq Edit 3 applied:** fg-540 reads ACs from `state.brainstorm.spec_path` with `.forge/specs/index.json` fallback |
| 8 | Mega A — Helpers + Schema | `docs/superpowers/plans/2026-04-27-mega-consolidation-A-helpers.md` | Auto-bumps `state-schema` from 2.0.0 → **2.1.0** in A6 |
| 9 | Mega B — Skill Surface | `docs/superpowers/plans/2026-04-27-mega-consolidation-B-skill-surface.md` | **Prereq Edit 6 applied:** B3 absorbs `forge-status` `--- live ---` content from Phase 1 Task 24. B12 deletes 26 old skills (incl. `/forge-init`, `/forge-run`, `/forge-status`) |
| 10 | Mega C — Brainstorming | `docs/superpowers/plans/2026-04-27-mega-consolidation-C-brainstorming.md` | Ports superpowers brainstorm pattern into `fg-010-shaper`; populates `state.brainstorm.spec_path` |
| 11 | Mega D — Pattern Parity | `docs/superpowers/plans/2026-04-27-mega-consolidation-D-pattern-parity.md` | **Prereq Edit 1 applied:** D8 references `fg-301-implementer-judge.md` (post-P5 name) |
| 12 | Mega E — Docs | `docs/superpowers/plans/2026-04-27-mega-consolidation-E-docs.md` | **Prereq Edit 2 applied:** README enumeration uses post-P5 agent names. Bumps `plugin.json` to **5.3.0** |
| 13 | Phase 8 — Measurement | `docs/superpowers/plans/2026-04-22-phase-8-measurement.md` | **Prereq Edit 4 applied:** benchmark runner uses `/forge run --eval-mode=...` (post-mega surface). Bumps `plugin.json` to **6.0.0** |

## Prerequisite cross-cutting edits (status checklist)

These must be in master before Phase 1 starts. Run `git log --oneline | grep "cross-verification"` to confirm.

- [x] **Edit 1** — Mega D8 file path: `agents/fg-301-implementer-critic.md` → `agents/fg-301-implementer-judge.md`
- [x] **Edit 2** — Mega E1 agent enumeration: post-P5 names in README content
- [x] **Edit 3** — Phase 7 fg-540 reads `state.brainstorm.spec_path` with fallback
- [x] **Edit 4** — Phase 8 subprocess.run uses `/forge run --eval-mode=...` (no `/forge-run`)
- [x] **Edit 5** — Phase 1 string-anchored Edits replace line-number pins (Task 17)
- [x] **Edit 6** — Mega B3 absorbs `forge-status` `--- live ---` content from Phase 1 Task 24
- [x] **Edit 7** — This document

If any checkbox above is unchecked, do NOT begin Phase 1.

## plugin.json version sequence

Per the working convention "minor bump per phase", every phase ships under its own version tag. Major bumps (`x.0.0`) reserved for spec-impacting milestones (P5 judges rename, Mega skill surface change, Phase 8 measurement layer).

```
3.6.0  current → 3.7.0 (Phase 1 ships) → 3.8.0 (Phase 2)
       → 3.9.0 (Phase 3) → 3.10.0 (Phase 4) → 4.0.0 (Phase 5 — judges rename, breaking)
       → 4.1.0 (Phase 6) → 4.2.0 (Phase 7) → 4.3.0 (Mega A — schema v2.1.0)
       → 5.0.0 (Mega B — skill surface delete, breaking)
       → 5.1.0 (Mega C) → 5.2.0 (Mega D) → 5.3.0 (Mega E)
       → 6.0.0 (Phase 8 — measurement layer, possibly breaking)
```

Each phase's final commit bumps `plugin.json` accordingly. Tag immediately after the bump (`v<version>`); push tag; create GitHub release with the phase summary.

## state-schema version handoff

- Phase 5 Task 6 sets `shared/state-schema.md` version to **2.0.0** (introduces `state.judges.*` fields).
- Mega A Task 6 auto-bumps to **2.1.0** (introduces `state.brainstorm.*` and `state.shape.*` fields).
- No backward-compat shims — forge is a personal tool; new versions freely break old `.forge/state.json`. Users running an old session through a new version will hit `STATE_SCHEMA_MISMATCH` and must `/forge-admin recover reset`.

## Per-phase release workflow

After every phase merges to master:

1. `superpowers:requesting-code-review` — fix all critical/important/minor/deferred items.
2. Bump `plugin.json` if the version table calls for it.
3. `git tag v<version>` (signed if user has GPG configured; otherwise unsigned).
4. `git push origin master --tags`.
5. `gh release create v<version> --title "<phase title>" --notes "<phase summary>"`.

No `--no-verify`, no `Co-Authored-By` lines, no manual hook bypassing.

## Why a fixed order

The cross-verification scan (recorded in `docs/superpowers/HANDOFF-2026-04-27-mega-consolidation.md`) found 6 file-level edit collisions and 13 coordination items across the 13 plans. The order above minimizes line-number drift and name-collision blast radius. Reordering without re-running the cross-verification will likely break execution.
