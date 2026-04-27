# Handoff — Forge A+ Roadmap (Mid-Execution)

**Date:** 2026-04-27
**Branch:** `docs/a-plus-roadmap` (already checked out)
**Working dir:** `/Users/denissajnar/IdeaProjects/forge`
**Last commit on branch:** `c41de347` (`release(phase-6): bump to 4.1.0`)
**Last shipped tag:** `v4.1.0`

## Status snapshot

**6 of 13 plans shipped** as independent releases:

| # | Tag | Phase | Highlights |
|---|---|---|---|
| 1 | v3.7.0 | Phase 1 — Truth & Observability | install.sh/.ps1, hook crash audit (`.hook-failures.jsonl`), support-tier badges, live-progress surface |
| 2 | v3.8.0 | Phase 2 — Contract Enforcement | 5 pytest contract tests, `/forge-help` deleted (LLM routing), `--config` folded into `/forge-status`, feature matrix |
| 3 | v3.9.0 | Phase 3 — Correctness Proofs | convergence `>=` boundary fix, e2e dry-run smoke, mutation harness, T-* coverage 86.3% |
| 4 | v3.10.0 | Phase 4 — Learnings Dispatch Loop | 12-agent injection, marker reinforcement (`LEARNING_APPLIED/FP/VINDICATED`), v1→v2 schema migration (292 files) |
| 5 | v4.0.0 | Phase 5 — Pattern Modernization + Judges (BREAKING) | `*-critic` → `*-judge` with binding REVISE veto; state schema v2.0.0 (no shim); findings store; fg-400 stays as dispatcher |
| 6 | v4.1.0 | Phase 6 — Cost Governance | `cost_governance.py`, 10-agent SAFETY_CRITICAL, dispatch-gate cutoff, soft throttle, 24 framework templates, 9 scenario tests |

**7 plans remaining** (in canonical ship order from `SHIP_ORDER.md`):

| # | Target | Plan | Notes |
|---|---|---|---|
| 7 | v4.2.0 | Phase 7 — Intent Assurance | Adds `fg-540-intent-verifier`. Reads ACs from `state.brainstorm.spec_path` with `.forge/specs/index.json` fallback (prereq Edit 3 already applied). |
| 8 | v4.3.0 | Mega A — Helpers + Schema | Auto-bumps `state-schema` 2.0.0 → 2.1.0 (introduces `state.brainstorm.*`, `state.shape.*`) |
| 9 | v5.0.0 | Mega B — Skill Surface (BREAKING) | B12 deletes 26 old skills (incl. `/forge-init`, `/forge-run`, `/forge-status`); B3 absorbs `forge-status --- live ---` from Phase 1 Task 24 (prereq Edit 6 applied) |
| 10 | v5.1.0 | Mega C — Brainstorming | Ports superpowers brainstorm pattern into `fg-010-shaper`; populates `state.brainstorm.spec_path` |
| 11 | v5.2.0 | Mega D — Pattern Parity | D8 references `agents/fg-301-implementer-judge.md` (post-P5 name; prereq Edit 1 applied) |
| 12 | v5.3.0 | Mega E — Docs | README enumeration uses post-P5 names (prereq Edit 2 applied) |
| 13 | v6.0.0 | Phase 8 — Measurement | Benchmark runner uses `/forge run --eval-mode=...` (prereq Edit 4 applied) |

The 7 prereq cross-coordination edits from `HANDOFF-2026-04-27-mega-consolidation.md` are all checked in — see `SHIP_ORDER.md` checklist (all 7 boxes ticked).

## Established workflow (proven across 6 phases)

For each phase, the loop is:

1. **Read the plan** at `docs/superpowers/plans/2026-04-22-phase-N-*.md` to enumerate tasks.
2. **Wave-dispatch implementer subagents** in parallel where files are disjoint:
   - Wave 1: foundation tasks (sequential dependencies)
   - Wave 2-3: independent batches in parallel
3. **`git push origin docs/a-plus-roadmap`** after all waves commit.
4. **`superpowers:requesting-code-review`** with `superpowers:code-reviewer` agent type. The review brief includes the full commit list + git range + scope hints.
5. **Dispatch parallel fix agents** for every flagged item (critical / important / minor — the user explicitly asked for **fix EVERYTHING; no item too minor**).
6. **`git push`** the fixes.
7. **Bump version triplet:** `.claude-plugin/plugin.json` + `pyproject.toml` (CLAUDE.md auto-tracks via doc edits if needed).
8. **Update CHANGELOG** under `[Unreleased]` → new `[N.N.N]` block above prior entries.
9. **Single release commit:** `release(phase-N): bump to N.N.N — <title> ships`.
10. **Tag + push tag:** `git tag -a vN.N.N -m "..." && git push origin vN.N.N`.
11. **`gh release create vN.N.N`** with structured notes.
12. **TaskUpdate** to mark phase + release tasks complete.

### Dispatch tips that work

- Read the plan's `### Task N` / `## Task N` headers via `grep -nE "^### Task |^## Task "` first; it disambiguates the format.
- Each subagent gets the plan path + task number range + branch directive (do NOT switch branches; we work on `docs/a-plus-roadmap` despite plan-internal branch names like `feat/phase-N-*`).
- Skip "Push and verify in CI" steps inside per-task instructions; push happens once at end of phase.
- "No local test suite runs" — but single-file pytest/bats during implementation is acceptable for sanity. CI verifies on push.
- Always tell agents: "Don't stage unrelated dirty files (`kotlin.md`, `spring/*`, `ac-extractor.py`, `ac_extractor_test.py`)." These pre-date this session and persist across all phases.
- Always tell agents: pathlib-only (no slashy literals); no emoji in new files; no `--no-verify`; no `Co-Authored-By` lines.
- For phases that bump `plugin.json`, tell agents to **SKIP** the version-bump task; do it at release time after review.

### Constraints (immutable across all phases)

- `superpowers:*` skills/agents only — NOT `pr-review-toolkit:*` or `feature-dev:*`. (See memory `feedback_use_superpowers_plugins`.)
- No `/forge-review` (forge reviewing forge is circular; see memory `feedback_no_self_review`).
- No backwards-compat shims; new schemas freely break old `.forge/state.json`.
- Code review after every PHASE (not every task). Per-task implementation only.
- Fix EVERYTHING — critical, important, minor, deferred.

## Known patterns / gotchas (from review findings across phases)

These have been fixed in their respective phases but are worth watching for in remaining phases:

1. **`os.path.join` slips into inline Python** in bats heredocs and helper scripts. Phase 1's `tests/structural/pathlib-only.bats` only checks Python files in some scopes — extend its file list when adding new harnesses.
2. **Description vs implementation drift** in agent prompts (e.g., fg-300 still saying "critic" after rename; fg-400 said "aggregator-only" in commit message but body kept dispatching). Reviewer catches these.
3. **Test fixtures with hardcoded counts** (e.g., agent count `42` vs reality `48`) — prefer `>= MIN_AGENTS` floor checks via `tests/lib/module-lists.bash`.
4. **JSON Schema regex over-permissive** (e.g., reviewer_registry matching tier-matrix rows). Always anchor to specific section markers when scraping markdown.
5. **`write_*` helpers without never-raise contract** crash the orchestrator at the worst moment. Pattern: try-primary → fallback to `tempfile.gettempdir()` → log to stderr → return path.
6. **Dirty test fixtures with stale arrows** (`-` vs `→`) trip `--check` modes. Always regenerate after schema changes.
7. **Cross-phase plan rename leakage** — Phase 5's judge rename had references in Phase 2/6/7/D plans. When a phase renames things, sweep ALL downstream plans + specs.
8. **`KNOWN_CONFIG_FIELDS` drift** — every new top-level config block (e.g., `cost:`) must be added to `shared/config_validator.py:KNOWN_CONFIG_FIELDS` or PREFLIGHT will warn-spam.

## Active uncommitted changes (carry-over from session-start; intentionally not staged)

```
 M modules/frameworks/spring/conventions.md
 M modules/frameworks/spring/persistence/hibernate.md
 M modules/frameworks/spring/rules-override.json
 M modules/languages/kotlin.md
?? shared/ac-extractor.py
?? tests/unit/ac_extractor_test.py
```

These predate the consolidation work and have been preserved untouched across all 6 shipped phases. Subagents have been told to skip them on every commit.

## How to resume

### From a fresh Claude Code session

1. `cd /Users/denissajnar/IdeaProjects/forge`
2. Confirm branch: `git status` — should show `docs/a-plus-roadmap` with the 6 dirty files above.
3. Read this handoff + `SHIP_ORDER.md` at repo root.
4. Pick up at **Phase 7 (Intent Assurance, target v4.2.0)**:
   - Plan: `docs/superpowers/plans/2026-04-22-phase-7-intent-assurance.md`
   - Spec: `docs/superpowers/specs/2026-04-22-phase-7-intent-assurance-design.md`
   - Reads ACs from `state.brainstorm.spec_path` first, fallback to `.forge/specs/index.json` (prereq Edit 3 already in plan)
   - Adds `fg-540-intent-verifier`
5. Run the established workflow: enumerate tasks → wave-dispatch → push → review → fix all → release.

### Memory references

User auto-memory at `/Users/denissajnar/.claude/projects/-Users-denissajnar-IdeaProjects-forge/memory/` includes the canonical workflow rules:

- `user_forge_personal_tool.md`
- `feedback_no_local_tests.md`
- `feedback_implementation_workflow.md` — code review per phase, fix everything, version bump + tag + push + release
- `feedback_no_self_review.md` — never `/forge-review`; use `superpowers:requesting-code-review`
- `feedback_no_backcompat.md`
- `feedback_use_superpowers_plugins.md` — superpowers:* only, NOT pr-review-toolkit:*
- `feedback_cleanup_after_ship.md` — at feature ship: delete `docs/superpowers/{specs,plans}/<feature>` + update CLAUDE.md/README/arch docs
- `feedback_cross_verify_unimplemented_plans.md`
- `feedback_plan_drift.md`

These are loaded automatically into the new session's context.

## Files referenced

- `/Users/denissajnar/IdeaProjects/forge/SHIP_ORDER.md` — canonical 13-plan order, version sequence, prereq checklist
- `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/HANDOFF-2026-04-27-mega-consolidation.md` — original handoff with prereq edit details
- `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/plans/2026-04-22-phase-{1..8}-*.md` — A+ roadmap plans
- `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/plans/2026-04-27-mega-consolidation-{A..E}-*.md` — Mega Consolidation plans
- `/Users/denissajnar/IdeaProjects/forge/CHANGELOG.md` — release entries v3.7.0 through v4.1.0

## Decision log (this session)

| Decision | Outcome | Reason |
|---|---|---|
| Phase 1 branching | Stayed on `docs/a-plus-roadmap`, ignored plan's `feat/phase-N-*` recommendation | User explicitly named the working branch |
| Per-task vs per-phase review | Per-phase | User memory `feedback_implementation_workflow` |
| Fix scope | Everything (critical/important/minor/deferred) | Explicit user directive |
| Reviewer agent | `superpowers:code-reviewer` | User feedback when `pr-review-toolkit:*` was used in Phase 1 |
| Dispatched in parallel within waves | Subagents that touch disjoint files | Speed; git lock auto-serializes commits |
| Version bumps | Phase release commit, after fixes | Validator passes; clean release commits |
| Phase 1 forge-help work | Shipped in v3.7.0 even though Phase 2 deletes the skill | User's "fix everything" applied at each phase boundary independently |
| Mutation harness rename (Phase 3 review) | Renamed semantically to "scenario sensitivity probe" without renaming the directory | Honesty over disruption |
| Migration `003-cost-columns.sql` | Used 003 instead of plan's 002 | 002 was taken by Phase 2 feature_usage; deviation documented in SQL header |
| Phase 5 judge rename | Atomic git mv per agent (separate commit) + sibling spec sweep | Bisect-friendly + minimal blast radius |

## What I won't do without confirmation

Per session policy:
- Won't push to remotes other than `origin/docs/a-plus-roadmap`.
- Won't merge `docs/a-plus-roadmap` into `master`.
- Won't delete the carried-over dirty files (kotlin/spring/ac-extractor) without explicit instruction.
- Won't run a force-push, hard-reset, or amend-published commits.
- Won't open a PR to merge the roadmap branch.
