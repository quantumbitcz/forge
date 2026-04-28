# Handoff — Forge A+ Roadmap (Late-Execution)

**Date:** 2026-04-27 (continuation of `HANDOFF-2026-04-27-mid-roadmap.md`)
**Branch:** `docs/a-plus-roadmap` (already checked out)
**Working dir:** `/Users/denissajnar/IdeaProjects/forge`
**Last commit on branch:** `714edf5f` (`release(mega-a): bump to 4.3.0 — Helpers + Schema (state v2.1.0) ships`)
**Last shipped tag:** `v4.3.0`

## Status snapshot

**8 of 13 plans shipped** as independent releases (3 added this session: Phase 7, Mega A, plus the v4.0.0/v4.1.0 from prior handoff already counted):

| # | Tag | Phase | Highlights |
|---|---|---|---|
| 1 | v3.7.0 | Phase 1 — Truth & Observability | install.sh/.ps1, hook crash audit, support-tier badges |
| 2 | v3.8.0 | Phase 2 — Contract Enforcement | 5 pytest contract tests, `/forge --help` deleted, feature matrix |
| 3 | v3.9.0 | Phase 3 — Correctness Proofs | convergence `>=` boundary, e2e dry-run smoke, mutation harness |
| 4 | v3.10.0 | Phase 4 — Learnings Dispatch Loop | 12-agent injection, marker reinforcement, v1→v2 migration |
| 5 | v4.0.0 | Phase 5 — Pattern Modernization + Judges (BREAKING) | `*-critic` → `*-judge` with binding REVISE; state schema v2.0.0 |
| 6 | v4.1.0 | Phase 6 — Cost Governance | `cost_governance.py`, SAFETY_CRITICAL list, dispatch-gate |
| 7 | **v4.2.0** | **Phase 7 — Intent Assurance (this session)** | F35 `fg-540-intent-verifier` + F36 `fg-302-diff-judge` voting; finding schema v2; 50 agents |
| 8 | **v4.3.0** | **Mega A — Helpers + Schema (this session)** | `ac-extractor.py` + `bootstrap-detect.py` + `platform-detect.py`; state v2.1.0; BRAINSTORMING stage |

**5 plans remaining** (in canonical ship order from `SHIP_ORDER.md` at repo root):

| # | Target | Plan | Notes |
|---|---|---|---|
| 9 | **v5.0.0** | **Mega B — Skill Surface (BREAKING; NEXT UP)** | B12 deletes 26 old skills (incl. `/forge`, `/forge run`, `/forge-ask status`); B3 absorbs `forge-status --- live ---` from Phase 1 Task 24 (prereq Edit 6 already applied) |
| 10 | v5.1.0 | Mega C — Brainstorming | Ports superpowers brainstorm pattern into `fg-010-shaper`; populates `state.brainstorm.spec_path` (Mega A laid the schema slot); wires `brainstorm_complete` / `resume_with_cache` into `shared/python/state_transitions.py` (Mega A deferred this) |
| 11 | v5.2.0 | Mega D — Pattern Parity | D8 references `agents/fg-301-implementer-judge.md` (post-P5 name; prereq Edit 1 applied) |
| 12 | v5.3.0 | Mega E — Docs | README enumeration uses post-P5 names (prereq Edit 2 applied). **Last mega plan to ship — also `git rm` the shared `docs/superpowers/specs/2026-04-27-skill-consolidation-design.md`** at this point (retained until E ships because Mega A/B/C/D/E all reference it) |
| 13 | v6.0.0 | Phase 8 — Measurement | Benchmark runner uses `/forge run --eval-mode=...` (prereq Edit 4 applied) |

The 7 prereq cross-coordination edits from `HANDOFF-2026-04-27-mega-consolidation.md` are all checked in (see `SHIP_ORDER.md` checklist).

## Established workflow (proven across 8 phases)

Same loop as prior handoff (still validated):

1. **Read the plan** at `docs/superpowers/plans/<phase-or-mega>.md` to enumerate tasks (use `grep -nE "^### Task |^## Task "`).
2. **Cross-verify against unimplemented downstream plans** — `grep -lE 'shared-surface' docs/superpowers/plans/<remaining>` (memory `feedback_cross_verify_unimplemented_plans`).
3. **Wave-dispatch implementer subagents** in parallel where files are disjoint.
4. **`git push origin docs/a-plus-roadmap`** after all waves commit.
5. **Dispatch superpowers code review** — split into 2 narrow-scope parallel reviewers when scope > ~30 files (single reviewer times out at 21 min). Per-scope examples: "Python modules security/correctness" + "agents+schemas+tests contract correctness".
6. **Dispatch parallel fix agents** for every flagged item (CRITICAL / IMPORTANT / MINOR / NIT — all of them, per the maintainer's "fix EVERYTHING" directive).
7. **`git push`** the fixes.
8. **Bump version triplet:** `.claude-plugin/plugin.json` + `pyproject.toml` + `CLAUDE.md` (line ~19 `v<x.y.z>` mention).
9. **Insert new `[<x.y.z>]` block** in `CHANGELOG.md` between `[Unreleased]` and the prior `[<a.b.c>]`. Body mirrors prior phase entries' Added/Changed/Dependencies sections.
10. **`git rm` the consumed plan** (per memory `feedback_cleanup_after_ship`). For mega plans, **keep the shared spec** until E ships (5-plan reference).
11. **Single release commit:** `release(<phase>): bump to <x.y.z> — <title> ships`.
12. **Tag + push tag:** `git tag -a v<x.y.z> -m "<title>" && git push origin v<x.y.z>`.
13. **`gh release create`** with `--notes "$(awk '/^## \[<x.y.z>\]/{flag=1} /^## \[<prior>\]/{flag=0} flag' CHANGELOG.md)"`.

### Dispatch tips that work (additions from this session)

- **Reviewer scope splits** — "Python modules" vs "agents+schemas+tests" carved cleanly along file-extension boundaries (`*.py` vs `*.md`/`*.json`/`*.bats`). Each reviewer fits the 21-min timeout. The single-reviewer attempt for Phase 7 timed out; split worked. Use `superpowers:code-reviewer` agent type with `run_in_background: true` so you can dispatch both in parallel.
- **Parallel fix waves on disjoint files** — Mega A's fix waves (Wave A: Python helpers; Wave B: docs+test pins) ran in parallel. **One git-index race occurred** — Wave B's `git reset HEAD~1` recovery wiped Wave A's first commit. Wave A re-staged and recommitted; both ended up on master cleanly. Future parallel waves should use `git stash` boundaries OR worktree isolation OR (simplest) sequential dispatch when wall-clock is acceptable.
- **Stale plan version literals** — every plan written before Phase 5 says state-schema is at v1.10.0 → v1.11.0. Reality after Phase 5/6/7: v2.0.0 → v2.1.0. Always grep `grep -E '^\*\*Version:\*\*' shared/state-schema.md` first.
- **Stale plan target versions** — plans say things like "bump to 3.7.0" because they were written assuming Phase 7 = first release. SHIP_ORDER.md is the canonical version sequence; override the plan's target.
- **Carry-over discipline** — the `?? shared/ac-extractor.py` + `?? tests/unit/ac_extractor_test.py` carry-overs were Mega A1's deliverables (not "leave alone"). Verify carry-over status against the upcoming wave's task list. Other carry-over (`spring/*`, `kotlin.md`, `tests/lib/bats-core`) genuinely persists across phases.
- **Coordination bumps need parallel sweep** — when bumping a schema version, grep ALL hardcodes: `grep -rnE '\b<old-version>\b' --include='*.py' --include='*.bats' --include='*.json' --include='*.md'`. Mega A's v2.0.0→v2.1.0 bump caught a stale `1.6.0` pin in `tests/unit/python-state-init.bats` that had been wrong since Phase 5 but never tripped CI.
- **pytest discovery convention drift** — `pyproject.toml` had `python_files = ["test_*.py"]`. Mega A added `*_test.py` files (Java/Go convention preserved from carry-over). They were silently skipped by `pytest tests/unit -q` until Mega A's release commit added `*_test.py` to the discovery list. Lesson: match existing convention OR update discovery in the SAME wave that adds the new convention.

### Constraints (immutable across all phases)

- `superpowers:*` skills/agents only — NOT `pr-review-toolkit:*` or `feature-dev:*`. (See memory `feedback_use_superpowers_plugins`.)
- No `/forge review` (forge reviewing forge is circular; see memory `feedback_no_self_review`).
- No backwards-compat shims; new schemas freely break old `.forge/state.json` (see memory `feedback_no_backcompat`).
- Code review after every PHASE (not every task). Per-task implementation only.
- Fix EVERYTHING — critical, important, minor, nit, deferred. The maintainer's directive.
- pathlib only; no `os.path.join`; no slashy literals; cross-platform.
- No emoji in any file or commit message.
- No `--no-verify`. No `Co-Authored-By:` lines or AI attribution footers.
- Worktree-relative paths in any agent prose (no absolute paths in subagent briefs).

## Known patterns / gotchas (cumulative across 8 phases)

Original 8 from prior handoff PLUS new ones from this session:

1. **`os.path.join` slips into inline Python** in bats heredocs and helper scripts.
2. **Description vs implementation drift** in agent prompts.
3. **Test fixtures with hardcoded counts** (e.g., agent count `48` vs reality `50` after Phase 7) — prefer `>= MIN_AGENTS` floor checks.
4. **JSON Schema regex over-permissive.**
5. **`write_*` helpers without never-raise contract** crash the orchestrator at the worst moment.
6. **Dirty test fixtures with stale arrows** trip `--check` modes.
7. **Cross-phase plan rename leakage.**
8. **`KNOWN_CONFIG_FIELDS` drift** — every new top-level config block must be added to `shared/config_validator.py:KNOWN_CONFIG_FIELDS`.

**New from Phase 7 + Mega A:**

9. **Stale stage numbering** — plans say "Stage 9 SHIP" but codebase numbers SHIP as Stage 8 (LEARN is Stage 9). Verify against `shared/stage-contract.md` overview table before committing stage-numbered prose.
10. **Cost field name reality vs plan** — `state.cost.pct_consumed` IS authoritative (Phase 6 maintains it alongside `remaining_usd`/`ceiling_usd`). Plan-author confusion appears in multiple Phase 7 references.
11. **Two finding-schema files** — `shared/checks/finding-schema.json` (singular, the L0/L1 review schema) and `shared/checks/findings-schema.json` (plural, the Phase 5 store JSONL schema). Different files, both valid; verify which one a task targets.
12. **Orchestrator size budget** — `tests/contract/test_fg100_size_budget.py:MAX_LINES`. Phase 7 bumped 1800 → 2000. Per memory `feedback_orchestrator_size`, raising the cap is acceptable (orchestrator loads once per run).
13. **Pytest discovery filename convention** — `pyproject.toml` accepts both `test_*.py` AND `*_test.py` since v4.3.0. New tests can use either; the existing codebase uses both.
14. **State-schema canonical-example drift** — `shared/state-schema.md` has a top-level JSON example that hardcodes `"version"`. When bumping the version-literal header, also bump the example. Reviewer caught this at v2.0.0→v2.1.0; will recur on every future bump.
15. **`shared/state-integrity.sh` is a *validator*, not a *cleanup* script** — Phase 7 added `.forge/dispatch-contexts/` cleanup to the orchestrator's PREFLIGHT prose, NOT to state-integrity.sh. Don't put destructive cleanup in the validator.
16. **JSON schema filename retains old version** — `shared/checks/state-schema-v2.0.json` still has the v2.0 filename even though contents now declare v2.1.0 (avoids breaking grep refs). When the file actually changes structure (vs just version-literal bump), rename and sweep refs.

## Active uncommitted changes (carry-over reduced from 7 to 5)

```
 M modules/frameworks/spring/conventions.md
 M modules/frameworks/spring/persistence/hibernate.md
 M modules/frameworks/spring/rules-override.json
 M modules/languages/kotlin.md
?? tests/lib/bats-core
```

Pre-Mega-A also had `?? shared/ac-extractor.py` and `?? tests/unit/ac_extractor_test.py` — these were absorbed by Mega A1 (commit `38ab7796`). Remaining 5 carry-over files are pre-session and persist intentionally.

`tests/lib/bats-core` is the bats-core git submodule pointer that the maintainer hasn't initialized.

## How to resume

### From a fresh Claude Code session

1. `cd /Users/denissajnar/IdeaProjects/forge`
2. Confirm branch: `git status` — should show `docs/a-plus-roadmap` with the 5 dirty files above.
3. Read this handoff + `SHIP_ORDER.md` at repo root + `HANDOFF-2026-04-27-mid-roadmap.md` (predecessor for fuller context on Phases 1-6).
4. Pick up at **Mega B (Skill Surface, target v5.0.0 BREAKING)**:
   - Plan: `docs/superpowers/plans/2026-04-27-mega-consolidation-B-skill-surface.md`
   - Spec (shared with all megas): `docs/superpowers/specs/2026-04-27-skill-consolidation-design.md`
   - **B12 is the breaking change**: deletes 26 old skills including `/forge`, `/forge run`, `/forge-ask status`. Verify SHIP_ORDER's prereq Edit 6 (B3 absorbs `forge-status --- live ---` from Phase 1 Task 24) is in the plan.
   - Cross-verify against Mega C/D/E + Phase 8 — what skill surfaces do they assume exist?
5. Run the established workflow: enumerate → wave-dispatch → push → 2-reviewer split → fix all → release.

### Mega B specific notes (read before dispatching)

- **Breaking-change communication.** v5.0.0 is the second BREAKING bump (Phase 5 was v4.0.0). CHANGELOG should clearly enumerate every deleted skill in a `### Removed (BREAKING)` section. Users of the prior skill surface need migration guidance — but per `feedback_no_backcompat`, no shims/aliases.
- **Skill files live at `skills/<name>/SKILL.md`.** Mass deletion of 26 skills is `git rm -r skills/<name>/` for each. Verify each deletion via `git ls-files skills/` before vs after.
- **`fg-100-orchestrator.md` size budget** is currently 2000 lines (raised by Phase 7). Mega B may not affect orchestrator size, but verify after edits.
- **`shared/python/state_transitions.py` has the FSM gap** — `brainstorm_complete` and `resume_with_cache` events aren't wired in. That's Mega C2's scope, NOT B's. `tests/contract/state-machine-contract.bats:59` will remain red until Mega C ships.

### Memory references

User auto-memory at `/Users/denissajnar/.claude/projects/-Users-denissajnar-IdeaProjects-forge/memory/` includes the canonical workflow rules:

- `user_forge_personal_tool.md`
- `feedback_no_local_tests.md` — don't run pytest whole-suite locally; CI verifies
- `feedback_implementation_workflow.md` — code review per phase, fix everything, version bump + tag + push + release
- `feedback_no_self_review.md` — never `/forge review`; use `superpowers:requesting-code-review`
- `feedback_no_backcompat.md` — new versions freely break old state/configs
- `feedback_use_superpowers_plugins.md` — superpowers:* only, NOT pr-review-toolkit:*
- `feedback_cleanup_after_ship.md` — at feature ship: delete plan + (when last to share) the spec
- `feedback_cross_verify_unimplemented_plans.md`
- `feedback_plan_drift.md`
- `feedback_defend_positions.md` — when reviewer challenges a deliberate design decision, defend it (e.g., Phase 7's `ast.dump` syntactic-not-semantic was correct by design; Wave 1's three doc clarifications were the right fix, not refactoring the engine)
- `feedback_orchestrator_size.md` — raising the size cap is fine; orchestrator loads once per run
- `project_plan_template_gaps.md`
- `feedback_version_freshness.md` — always web-search latest stable before pinning (validated this session: `tree-sitter-language-pack` was 5 days stale in Phase 7's plan)

## Files referenced

- `/Users/denissajnar/IdeaProjects/forge/SHIP_ORDER.md` — canonical 13-plan order, version sequence, prereq checklist
- `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/HANDOFF-2026-04-27-mid-roadmap.md` — prior handoff (Phases 1-6 detail)
- `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/HANDOFF-2026-04-27-mega-consolidation.md` — original handoff with prereq edit details
- `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/plans/2026-04-22-phase-{8}-*.md` — remaining A+ roadmap plan
- `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/plans/2026-04-27-mega-consolidation-{B,C,D,E}-*.md` — remaining mega plans
- `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-27-skill-consolidation-design.md` — shared mega spec (retained until E ships)
- `/Users/denissajnar/IdeaProjects/forge/CHANGELOG.md` — release entries v3.7.0 through v4.3.0

## Decision log (this session)

### Phase 7 (v4.2.0)

| Decision | Outcome | Reason |
|---|---|---|
| Stage numbering | Codebase Stage 8 = SHIP, not plan's "Stage 9" | Verified `shared/stage-contract.md` overview table |
| `ast.dump` syntactic-not-semantic call | Defended; added 3 doc clarifications, did NOT refactor | Memory `feedback_defend_positions`; voting gate is "structural agreement" not "semantic equivalence"; tiebreak reconciles |
| Reviewer scope | Split into 2 parallel narrow-scope reviewers | Single-reviewer for Phase 7 timed out at 21 min |
| `state-integrity.sh` cleanup wiring | Cleanup directive added to fg-100 orchestrator PREFLIGHT prose, not state-integrity.sh | state-integrity.sh is a validator; orchestrator owns destructive ops |
| `MAX_LINES` cap on orchestrator | Bumped 1800 → 2000 in Phase 7 release wave | Memory `feedback_orchestrator_size`; orchestrator loads once per run |
| `tree-sitter-language-pack` pin | `>=1.6.3,<2.0` (plan said 1.6.2 — 5 days stale) | Memory `feedback_version_freshness`; PyPI verified |

### Mega A (v4.3.0)

| Decision | Outcome | Reason |
|---|---|---|
| State schema bump | v2.0.0 → v2.1.0 (NOT plan's v1.11.0) | Phase 5/6/7 already coordinated to v2.0.0; per `feedback_no_backcompat`, no migration |
| Carry-over `shared/ac-extractor.py` | Staged unchanged (matched plan Step 3 byte-for-byte) | Verified via diff before staging |
| Carry-over `tests/unit/ac_extractor_test.py` | Replaced with full 9-test version per plan Step 5 | Was the 2-test minimal Step 1 |
| FSM event wiring | Deferred to Mega C2 | Genuine FSM surgery; pure A6 schema doc only |
| `state-schema-v2.0.json` filename | Retained (only contents bumped to v2.1.0) | Avoid breaking grep refs across codebase |
| Mega A spec deletion | Spec retained; only Mega A plan deleted | Spec shared across A/B/C/D/E; deletes when E ships |
| Pytest discovery convention | `python_files` accepts both `test_*.py` AND `*_test.py` | Mega A used `*_test.py` (Java/Go style preserved from carry-over) |
| Parallel fix waves | Recovered from one git-index race; both committed cleanly | Future: stash boundaries OR worktree isolation OR sequential |

## What I won't do without confirmation

Per session policy:
- Won't push to remotes other than `origin/docs/a-plus-roadmap`.
- Won't merge `docs/a-plus-roadmap` into `master`.
- Won't delete the carried-over dirty files (`spring/*`, `kotlin.md`, `tests/lib/bats-core`) without explicit instruction.
- Won't run a force-push, hard-reset, or amend-published commits.
- Won't open a PR to merge the roadmap branch.
- Won't delete the shared `2026-04-27-skill-consolidation-design.md` spec until Mega E ships.
