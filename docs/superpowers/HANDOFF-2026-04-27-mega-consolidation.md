# Handoff — Forge Mega-Consolidation + 8-Phase A+ Roadmap Integration

**Date:** 2026-04-27
**Branch:** `docs/a-plus-roadmap`
**Working dir:** `/Users/denissajnar/IdeaProjects/forge`
**Last session HEAD:** `50acb277` (`docs(consolidation): apply self-review fixes...`)

## What was done in the prior session

1. Wrote forge mega-consolidation spec (29 → 3 skills + superpowers pattern parity + multi-platform PR support + 4 beyond-superpowers improvements). 951 lines, 72 ACs. Spec at `docs/superpowers/specs/2026-04-27-skill-consolidation-design.md` (commit `660dbef7`).

2. Wrote 5-phase implementation plans for the mega-spec:
   - `2026-04-27-mega-consolidation-A-helpers.md` — 6 commits
   - `2026-04-27-mega-consolidation-B-skill-surface.md` — 13 commits
   - `2026-04-27-mega-consolidation-C-brainstorming.md` — 2 commits
   - `2026-04-27-mega-consolidation-D-pattern-parity.md` — 9 commits
   - `2026-04-27-mega-consolidation-E-docs.md` — 2 commits
   - Total: 32 commits, 9895 lines.

3. Ran spec/plan code review via `superpowers:requesting-code-review` (twice — initial + mega-expansion) and applied all critical/important fixes.

4. Ran self-review checklists on each of the 5 plans via parallel subagents. Applied 22 fixes.

5. **Cross-verified the 5 mega plans against 8 prior unimplemented A+ roadmap plans** (`docs/superpowers/plans/2026-04-22-phase-{1..8}-*.md`). **Found 6 critical conflicts and 13 important coordination items.** Conflicts include:
   - File-level edit collisions (e.g. Mega D8 references `fg-301-implementer-critic.md` which Phase 5 renames)
   - Phase 1 line-number-pinned edits that drift when other plans land first
   - Phase 2 edits skills that Mega B12 deletes
   - State schema version literal contention across P5/P6/P7/Mega-A6
   - Phase 8 benchmark runner hardcodes `/forge-init` and `/forge-run` (deleted by Mega B12)
   - Spec §14 coordination claims not honored in actual plan diffs

## Decision (user-approved this session)

**Option 1: integrate all 13 plans into one coherent ship train.**

Apply 7 prerequisite cross-cutting edits, document ship order, then begin execution at Phase 1 (recommended first). Treats all 13 plans as a coherent integrated roadmap.

The alternatives (drop mega, drop prior 8, different ordering) were rejected.

## Recommended ship order

```
1. Phase 1  (truth & observability)              — minimal agent touches
2. Phase 2  (contract enforcement)
3. Phase 3  (correctness proofs)
4. Phase 4  (learnings dispatch loop)
5. Phase 5  (pattern modernization, judges)      — renames fg-205, fg-301
6. Phase 6  (cost governance)
7. Phase 7  (intent assurance)                   ⚠ PREREQ: add fg-540 brainstorm task
8. Mega A   (helpers + schema)                   — bumps schema to 2.1.0
9. Mega B   (skill surface)                      ⚠ PREREQ: B7 sed pass post-prior-plans
10. Mega C  (brainstorming)
11. Mega D  (pattern parity)                     ⚠ PREREQ: D8 file path → fg-301-implementer-judge
12. Mega E  (docs)                               ⚠ PREREQ: agent enumeration uses post-P5 names
13. Phase 8 (measurement)                        ⚠ PREREQ: subprocess.run uses /forge run
```

## Prerequisite edits to apply BEFORE execution starts

These are mechanical fixes to the plans so each plan is execution-safe regardless of which neighbors have shipped. Apply via parallel subagents.

### Edit 1 — Mega D8 file path fix
**File:** `docs/superpowers/plans/2026-04-27-mega-consolidation-D-pattern-parity.md`
**Lines:** 65, 2624, 2849
**Change:** `agents/fg-301-implementer-critic.md` → `agents/fg-301-implementer-judge.md`
**Reason:** Phase 5 Task 6 renames this file. After P5 ships, the old name is gone.
**Defer-able:** No — would Edit-fail at execution time.

### Edit 2 — Mega E1 agent enumeration
**File:** `docs/superpowers/plans/2026-04-27-mega-consolidation-E-docs.md`
**Lines:** 411, 449, 492 (per cross-verification report)
**Change:**
- `fg-205-planning-critic` → `fg-205-plan-judge`
- `fg-301-implementer-critic` → `fg-301-implementer-judge`
**Reason:** README enumeration must list post-P5 agent names since P5 ships before Mega E.
**Defer-able:** No — would write wrong README content.

### Edit 3 — Phase 7 add `state.brainstorm.spec_path` consumption task
**File:** `docs/superpowers/plans/2026-04-22-phase-7-intent-assurance.md`
**Change:** Add a new task to `fg-540-intent-verifier` rewrite that reads ACs from `state.brainstorm.spec_path` first, falling back to existing `.forge/specs/index.json` source when absent.
**Reason:** Mega spec §14 line 771 commits to this coordination but Phase 7 plan has zero references to `brainstorm` or `spec_path`. fg-540 will read stale AC sets if not fixed.
**Defer-able:** Yes (only matters if mega + P7 both shipped) — but cheaper to fix now.

### Edit 4 — Phase 8 subprocess.run rewrite
**File:** `docs/superpowers/plans/2026-04-22-phase-8-measurement.md`
**Lines:** ~1430-1442 (`tests/evals/benchmark/runner.py` task)
**Change:**
- `subprocess.run(["claude", "code", "--non-interactive", "/forge-init"], ...)` → remove (auto-bootstrap handles this)
- `subprocess.run(["claude", "code", "--non-interactive", f"/forge-run --eval-mode {entry.entry_id}", entry.requirement], ...)` → `subprocess.run(["claude", "code", "--non-interactive", "/forge", "run", f"--eval-mode={entry.entry_id}", entry.requirement], ...)`
**Reason:** Mega B12 deletes `/forge-init` and `/forge-run`. Phase 8 ships last so it must use the post-mega skill surface.
**Defer-able:** No — every benchmark run breaks otherwise.

### Edit 5 — Phase 1 string-anchor Edits (replace line-number pins)
**File:** `docs/superpowers/plans/2026-04-22-phase-1-truth-and-observability.md`
**Affected tasks:** 16, 17 (line-numbered references like `agents/fg-100-orchestrator.md:1245`, `agents/fg-505-build-verifier.md:39`/`:55`/`:140`, `shared/state-schema-fields.md:693`)
**Change:** Replace each line-number pin with a string-anchored Edit that uses an `old_string` matching the exact text being changed.
**Reason:** Phase 1 ships first per recommended order, so line-numbers AS-WRITTEN are valid against current master. But if any plan is reordered, line numbers drift.
**Defer-able:** Yes if Phase 1 ships first — safer to fix anyway.

### Edit 6 — Mega B3 absorb `forge-status` `--- live ---` content
**File:** `docs/superpowers/plans/2026-04-27-mega-consolidation-B-skill-surface.md`
**Task:** B3 (`skills/forge-ask/SKILL.md` rewrite)
**Change:** When B3 absorbs `status` subcommand from old `forge-status` skill, include the `--- live ---` section that Phase 1 Task 24 added to `forge-status/SKILL.md`. Do NOT lose the live-progress feature.
**Reason:** Phase 1 ships first; Mega B12 deletes forge-status. Without this absorption, Phase 1's live-progress work is dropped.
**Defer-able:** No (loses content).

### Edit 7 — `SHIP_ORDER.md` document
**File:** `SHIP_ORDER.md` (new) at repo root
**Content:** Snapshot of the recommended ship order with prerequisite edit checklist, plugin.json version sequence (3.6.x → 3.7.0 after P3 → 4.0.0 after P5 → 4.1.0 after Mega → 4.2.0 after P8), and state-schema version handoff (P5 sets 2.0.0; Mega A6 auto-bumps to 2.1.0).
**Reason:** Plan-level coordination needs a single source of truth. Without this, the version sequence drifts across plans.
**Defer-able:** Yes but recommended.

## Optional but worth considering (deferred)

- **Phase 8 corpus expansion**: add 2-3 benchmark entries that exercise BRAINSTORMING (autonomous), bug-hypothesis branching, and the new finishing-dialog. Otherwise the scorecard reports parity not improvement after mega ships. Add as Phase 8 follow-up.

## How to resume

### From a fresh Claude Code session

1. `cd /Users/denissajnar/IdeaProjects/forge`
2. Verify branch: `git status` — should be on `docs/a-plus-roadmap`
3. Read this handoff document and the cross-verification report (was returned by an Agent tool call in the prior session — full text not preserved here, but the conflict findings above summarize it).
4. Apply the 7 prerequisite edits — dispatch parallel subagents for edits 1, 2, 3, 4, 5, 6 (each is an independent file edit). Edit 7 is a new file write.
5. Commit edits in one bundle: `docs(coordination): apply cross-verification prerequisite edits for 13-plan ship train`.
6. Begin execution at Phase 1 via `superpowers:subagent-driven-development` skill. Phase 1 plan is at `docs/superpowers/plans/2026-04-22-phase-1-truth-and-observability.md`. Dispatch fresh implementer subagent per task.

### Constraints to honor (from auto-memory)

- **Don't run forge-review on forge changes.** Use `superpowers:requesting-code-review` only.
- **No local test suite runs.** Single-file pytest/bats during TDD inner loop is fine; full suite via CI after push.
- **No backwards compatibility.** Forge is a personal tool; new versions freely break old state.
- **Code review after each phase, fix everything, version bump + tag + push + release per phase.** This is the user's preferred per-phase workflow.
- **No `/forge-review`. No `Co-Authored-By` lines. No `--no-verify` skips.** Standard forge git conventions.

## Files referenced in this handoff

- Specs: `docs/superpowers/specs/2026-04-22-phase-{1..8}-*.md`, `docs/superpowers/specs/2026-04-27-skill-consolidation-design.md`
- Plans: `docs/superpowers/plans/2026-04-22-phase-{1..8}-*.md`, `docs/superpowers/plans/2026-04-27-mega-consolidation-{A..E}-*.md`
- Auto-memory: `/Users/denissajnar/.claude/projects/-Users-denissajnar-IdeaProjects-forge/memory/MEMORY.md`
- Cross-verification subagent transcript: not preserved (was Agent tool result, ephemeral); summary in this document is the canonical record.

## Decision log (this session)

| Decision | Outcome | Reason |
|---|---|---|
| Skill consolidation target | 3 skills (B-shape) | Three intent categories distinct; one-skill matcher would be eager |
| Brainstorm-first scope | Feature mode only | Bug/migrate/bootstrap have specialized first-stage agents already |
| Brainstorm pattern source | Port to fg-010-shaper (C) | Match superpowers quality without runtime dependency |
| Auto-bootstrap trigger | Missing `forge.local.md` | `.forge/` deletion shouldn't re-trigger (recover-reset workflow) |
| Auto-bootstrap UI | Single confirmation prompt | Detect-and-confirm; full wizard via `/forge-admin config wizard` |
| Hybrid grammar | Explicit verbs + NL fallback | Keeps current `/forge run` UX, adds parameterized verbs |
| Phase 9 | Absorbed into mega-consolidation | User: "I want to have it all and working and maybe even better" |
| Quality maximalism | Bayes 0.95/0.75/0.50/0.05/0.20/0.40, fix gate 0.75 | "Almost perfect code" |
| PR autonomous default | `open-pr-draft` | Lands as draft; explicit human promotion |
| Multi-platform | GitHub, GitLab, Bitbucket, Gitea via stdlib urllib | "Support other git repos as well" |
| Plan strategy | 5 phase plans (mega) + 8 prior phase plans = 13 | Granular commits, parallelizable phases |
| Ship order | P1→P8 → Mega A→E → P8 (with prereq edits) | Cross-verification: minimizes line-drift, name-collision |
