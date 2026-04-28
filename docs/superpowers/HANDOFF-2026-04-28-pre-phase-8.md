# Handoff — Forge A+ Roadmap (Pre-Phase-8)

**Date:** 2026-04-28 (continuation of `HANDOFF-2026-04-27-late-roadmap.md`)
**Branch:** `docs/a-plus-roadmap` (already checked out)
**Working dir:** `/Users/denissajnar/IdeaProjects/forge`
**Last commit on branch:** `4a91bb09` (`release(mega-e): bump to 5.3.0 — Documentation Rollup ships`)
**Last shipped tag:** `v5.3.0`
**This session:** 41 commits on the branch (`d5f6b7df..4a91bb09`), 5 release tags shipped (v5.0.0, v5.1.0, v5.2.0, v5.3.0).

## Status snapshot

**12 of 13 plans shipped.** The mega-consolidation train (Phases A-E) is COMPLETE; only Phase 8 remains.

| # | Tag | Phase | Highlights |
|---|---|---|---|
| 1-6 | v3.7.0 - v4.1.0 | Phases 1-6 | (prior sessions) |
| 7 | v4.2.0 | Phase 7 — Intent Assurance | (prior session) F35 + F36 |
| 8 | v4.3.0 | Mega A — Helpers + Schema | (prior session) state v2.1.0; helper modules shipped as libraries |
| 9 | **v5.0.0** | **Mega B — Skill Surface (BREAKING)** | this session; 27 skills retired; 3 SKILLs (forge / forge-ask / forge-admin); ~150 file rewires |
| 10 | **v5.1.0** | **Mega C — Brainstorming** | this session; fg-010-shaper rewrite; orchestrator BRAINSTORMING + PREFLIGHT platform detection; helper CLIs backfilled |
| 11 | **v5.2.0** | **Mega D — Pattern Parity Uplifts** | this session; 5 superpowers ports + 4 beyond-superpowers; new fg-021-hypothesis-investigator (T4); agent count 50 → 51 |
| 12 | **v5.3.0** | **Mega E — Docs (mega train complete)** | this session; CLAUDE.md + README.md rewrite; FEATURE_MATRIX regenerated F35-F44; shared spec retired |

**1 plan remaining** (in `SHIP_ORDER.md` at repo root):

| # | Target | Plan | Notes |
|---|---|---|---|
| 13 | **v6.0.0** | **Phase 8 — Measurement (NEXT UP)** | 31 tasks, ~3774 lines; fresh-from-scratch benchmark subsystem under `tests/evals/benchmark/`. Plan target version is **stale** (says `3.8.0`; reality is v5.3.0 → v6.0.0). |

## Why a separate session for Phase 8

Phase 8 is fundamentally different from Megas A-E:

| Dimension | Megas (just shipped) | Phase 8 |
|---|---|---|
| Tasks | 2-9 each | **31** |
| Plan size | 700-3500 lines | **3774** |
| Style | Agent prose / sed rewires | **Fresh-from-scratch Python subsystem** |
| New code | ~50 lines (agent helpers) | ~3000+ lines (runner, scoring, curate, schemas, dataclasses) |
| New artifacts | none/few | corpus + GH workflow + ADR + scorecard renderer + OTel spans |
| Stale plan target | reasonable | "v3.8.0" — 3 majors stale, needs version mapping upfront |

The post-Mega session context is loaded with skill-surface / agent-prompt / sed-rewire patterns. Phase 8 requires fresh thinking: dataclass design, JSON schemas, Python CLI scaffolding, GH Actions YAML, baseline-freeze idempotency. A clean session grounds better in the benchmark spec without dragging mega-train baggage.

## Established workflow (proven across 5 megas)

Same loop as the late-roadmap handoff (still validated):

1. **Read the plan** at `docs/superpowers/plans/<phase>.md` to enumerate tasks (`grep -nE "^### Task |^## Task "`).
2. **Cross-verify against unimplemented downstream plans** — for Phase 8, this is just verifying nothing references retired Mega plans (those are deleted) and that Phase 8 references current post-mega surface (the plan was written assuming `/forge-run` etc. — needs to be rewritten to `/forge run`).
3. **Wave-dispatch implementer subagents** sequentially (parallel commits caused races in earlier sessions; sequential is safest). For Phase 8, group tasks by dependency: schemas first, then runner skeleton, then components, then integration tests, then CI workflow.
4. **`git push origin docs/a-plus-roadmap`** after each batch commits.
5. **Phase-end code review** — `superpowers:code-reviewer` agent type with `run_in_background: true`. Split into 2 parallel narrow-scope reviewers when scope > ~30 files. For Phase 8: split natural along `python/dataclasses/runner` vs `tests/CI-workflow/docs`.
6. **Dispatch parallel fix agents** for every flagged item (CRITICAL / IMPORTANT / MINOR / NIT — all of them, per the maintainer's "fix EVERYTHING" directive).
7. **`git push`** the fixes.
8. **Bump version triplet:** `.claude-plugin/plugin.json` + `pyproject.toml` + `CLAUDE.md` (line 21 `v<x.y.z>` mention + line 381 `(v<x.y.z>)` plugin.json prose annotation).
9. **Insert new `[<x.y.z>]` block** in `CHANGELOG.md` between `[Unreleased]` and the prior `[<a.b.c>]`. Body mirrors prior entries' structure.
10. **`git rm` the consumed plan** at `docs/superpowers/plans/2026-04-22-phase-8-measurement.md`.
11. **Single release commit:** `release(phase-8): bump to 6.0.0 — Measurement ships`.
12. **Tag + push tag:** `git tag -a v6.0.0 -m "Phase 8 — Measurement"`; `git push origin v6.0.0`.
13. **`gh release create`** with `--notes "$(awk '/^## \[6.0.0\]/{flag=1} /^## \[5.3.0\]/{flag=0} flag' CHANGELOG.md)"`.

### Phase 8 specific dispatch tips

- **Plan target-version remap.** First action of the session: replace every `forge 3.8.0` (and any other stale target literal) with `v6.0.0`. The plan author wrote it when 3.8.0 was the next bump.
- **Plan was written pre-Mega-B.** Phase 8 Task 10 (Phase 7 AC injection + model override + state parse) and other tasks may reference `/forge-run`, `/forge-init`, `/forge-status` etc. Run `grep -nE '/forge-(init|run|fix|shape|sprint|review|verify|deploy|commit|migration|bootstrap|docs-generate|security-audit|status|history|insights|profile|tour|help|recover|abort|config|handoff|automation|playbooks|playbook-refine|compress|graph)\b' docs/superpowers/plans/2026-04-22-phase-8-measurement.md` to find them. Each reference needs mapping per the canonical mapping table (see prior handoff §"Mapping table" or any of the v5.0.0 era CHANGELOG entries). One known-stale ref is at `2026-04-22-phase-8-measurement.md:1315` (per the late-roadmap handoff) which references `/forge run` already (post-coordination edit applied), but the rest of the plan likely has more.
- **Cost ceiling.** Plan §commit-time decision sets `$200` initial weekly ceiling. This is a one-time write to `forge-config.md` template at Task 30; not retroactive to existing user configs.
- **Model matrix.** Plan commits to `claude-sonnet-4-6` and `claude-opus-4-7`. Haiku is excluded by design. Model literals appear in the runner; avoid hardcoding training-data versions and verify against current API at session start.
- **`tests/evals/` already exists.** Phase 8 adds `tests/evals/benchmark/` alongside existing `pipeline/`, `time-travel/`, `scenarios/`, `agents/`. No collision.
- **Dependencies on prior phases.**
  - Phase 1 hook-failure roll-up (Task 20) — pre-existing; just consume.
  - Phase 4 `benchmark.regression` learning type (Task 18) — adds a NEW learning type (extension of pre-existing Phase 4 selector). Verify the selector accepts new types without registry edits.
  - Phase 6 cost ceiling enforcement via simulator (Task 17) — pre-existing `cost_governance.py` infrastructure; Task 17 adds a benchmark-specific simulator fixture.
  - Phase 7 AC injection contract test (Task 19) — Phase 7's `fg-540-intent-verifier` ACs use `AC-S###`/`AC-PLAN-###` namespaces. Phase 8 uses `AC-B001..AC-B999` for benchmark-corpus ACs. Verify namespace separation in the contract test.

### Constraints (immutable across all phases)

- `superpowers:*` skills/agents only — NOT `pr-review-toolkit:*` or `feature-dev:*`. (Memory `feedback_use_superpowers_plugins`.)
- No `/forge review` (forge reviewing forge is circular; memory `feedback_no_self_review`).
- No backwards-compat shims; new schemas freely break old `.forge/state.json` (memory `feedback_no_backcompat`).
- Code review after every PHASE (not every task). Per-task implementation only.
- Fix EVERYTHING — critical, important, minor, nit, deferred. The maintainer's directive.
- pathlib only; no `os.path.join`; no slashy literals; cross-platform.
- No emoji in any file or commit message.
- No `--no-verify`. No `Co-Authored-By:` lines or AI attribution footers.
- Worktree-relative paths in subagent briefs (no absolute paths in briefs; absolute OK for tool invocations).

## Known patterns / gotchas (cumulative across all phases)

Original 16 from prior handoffs PLUS new ones from this session:

1. **`os.path.join` slips into inline Python** in bats heredocs and helper scripts.
2. **Description vs implementation drift** in agent prompts.
3. **Test fixtures with hardcoded counts** — prefer `>= MIN_*` floor checks. (`MIN_AGENTS=51` post-Mega-D; bump if Phase 8 adds new agents.)
4. **JSON Schema regex over-permissive.**
5. **`write_*` helpers without never-raise contract** crash the orchestrator at the worst moment.
6. **Dirty test fixtures with stale arrows** trip `--check` modes.
7. **Cross-phase plan rename leakage.**
8. **`KNOWN_CONFIG_FIELDS` drift** — every new top-level config block must be added to `shared/config_validator.py:KNOWN_CONFIG_FIELDS`. **Phase 8 adds `benchmark.*`** — verify this gets registered.
9. **Stale stage numbering** in plans.
10. **Cost field name reality vs plan** — `state.cost.pct_consumed` IS authoritative; some plans reference older names.
11. **Two finding-schema files** — `shared/checks/finding-schema.json` (singular, L0/L1 review schema) vs `shared/checks/findings-schema.json` (plural, store JSONL schema).
12. **Orchestrator size budget** — `tests/contract/test_fg100_size_budget.py:MAX_LINES`. Currently **2200** post-Mega-D (orchestrator at 2165/2200). Phase 8 doesn't touch the orchestrator significantly; should not need a bump.
13. **Pytest discovery filename convention** — `pyproject.toml` accepts both `test_*.py` AND `*_test.py` since v4.3.0.
14. **State-schema canonical-example drift** — top-level JSON example in `shared/state-schema.md` hardcodes `"version"` literal.
15. **`shared/state-integrity.sh` is a *validator*, not a *cleanup* script.**
16. **JSON schema filename retains old version** — `shared/checks/state-schema-v2.0.json` filename still says v2.0 even though contents declare v2.1.0 (avoids breaking grep refs).

**New from this session (Mega B/C/D/E):**

17. **Sed `\b` word-boundary fires on path separators** — `/forge-config\b` matched both slash-commands AND `.claude/forge-config.md` filesystem paths during Mega B5-B10. Fix: use `(?<![./-])/forge-<verb>\b` or HEAD/TAIL char classes (the AC-S005 hardened regex in `tests/structural/skill-consolidation.bats:80-97` is the canonical reference). For Phase 8 doc rewrites, this matters less (no slash-command renaming at this stage), but if any sed pass touches existing files, use the hardened pattern from the start.
18. **Helper-module CLI gap class** — Mega A shipped Python helpers (`shared/{ac-extractor,platform-detect,bootstrap-detect}.py`) as libraries. Mega C's prose called them as CLIs (`python3 shared/ac-extractor.py --input -`). Neither phase verified the contract. Caught at v5.1.0 review and backfilled. **Lesson for Phase 8:** every Python module that an agent prompt invokes via shell must have an `argparse` `__main__` block AND a CLI test in `tests/unit/`.
19. **Test layer can be silently broken** — Mega D's D9 added 23 test files, multiple of which had:
    - `awk` rule-order bugs (`next` consumed lines before print rule fired → only LAST task ever emitted)
    - bats functions invoked via `sh -c` (subshell can't see bats-scope functions)
    - case-sensitive greps that miss capitalized headers
    - same-line co-occurrence regexes that don't match multi-line agent prose
    
    All passed `bash -n` and structural lints but were no-ops. **Lesson for Phase 8:** for any new bats test, confirm it actually verifies its claim by introducing a deliberate violation and checking the test fails.
20. **Reviewer scope discipline** — Mega B/D 2-reviewer splits worked when carved by file extension (`*.py` vs `*.md`/`*.json`/`*.bats`) or by domain (skill-content vs migration-mechanics). Single reviewer for Mega C/E (small scope) was fine. Phase 8 will likely need 2 reviewers given Python + tests + workflow + ADR + docs scope.
21. **Mega E plan agent count drift** — when adding a new agent (like fg-021 in Mega D), search ALL plans/specs for "(50)" or "50 agents" and bump. Phase 8 doesn't add agents but check `shared/agents.md`, `CLAUDE.md`, `README.md` for `51` consistency at start.
22. **Stale README badges** — Mega E review caught `tests-3040+` (actual 761) and `finding_categories-87+` (actual 149). Phase 8 adds tests; expect to bump `tests-760+` again at v6.0.0 release.
23. **F-number registry vs CLAUDE.md FEATURE_MATRIX vs `shared/feature-matrix.md`** — three sources of truth. Generator (`shared/feature_matrix_generator.py`) is canonical. After Mega E: F35=Intent / F36=Voting / F37-F44=Mega C/D additions. Phase 8 likely adds F45+ (benchmark, regression gate). Update generator + regenerate `shared/feature-matrix.md` + bump CLAUDE.md sentinel block.
24. **Carry-over discipline** — 5 pre-existing dirty files (`modules/frameworks/spring/{conventions,persistence/hibernate,rules-override}.{md,json}`, `modules/languages/kotlin.md`, `tests/lib/bats-core` submodule pointer) persist across all releases. They were unstaged at session start and remain unstaged. Use `git add <explicit-paths>` not `git add -A` or `git add .`.

## Active uncommitted changes (carry-over)

```
 M modules/frameworks/spring/conventions.md
 M modules/frameworks/spring/persistence/hibernate.md
 M modules/frameworks/spring/rules-override.json
 M modules/languages/kotlin.md
?? tests/lib/bats-core
```

`tests/lib/bats-core` is the bats-core git submodule pointer that the maintainer hasn't initialized. Other 4 files are pre-session content the maintainer is keeping out of release commits intentionally.

## How to resume

### From a fresh Claude Code session

1. `cd /Users/denissajnar/IdeaProjects/forge`
2. Confirm branch: `git status` — should show `docs/a-plus-roadmap` with the 5 dirty files above.
3. Confirm last commit: `git log --oneline -1` should be `4a91bb09`.
4. Confirm tags: `git tag` should include v5.0.0 through v5.3.0.
5. Read this handoff + `SHIP_ORDER.md` at repo root + the prior handoff (`HANDOFF-2026-04-27-late-roadmap.md` for fuller context on the mega train).
6. Pick up at **Phase 8 — Measurement (target v6.0.0)**:
   - Plan: `docs/superpowers/plans/2026-04-22-phase-8-measurement.md` (3774 lines, 31 tasks)
   - Spec: `docs/superpowers/specs/2026-04-22-phase-8-measurement-design.md` (646 lines)
   - **Pre-flight steps:**
     - Remap stale "v3.8.0" target literals throughout the plan to "v6.0.0"
     - Cross-verify the plan body for retired-skill-name references; fix to post-Mega-B surface
     - Verify `state.platform` (Mega A6 / Mega C2) and `state.brainstorm` slots are present in `shared/state-schema.md` (they are — last verified at v5.3.0 release)
     - Verify `shared/config_validator.py:KNOWN_CONFIG_FIELDS` is ready to accept `benchmark.*` (or plan to add it in the appropriate task)
7. Run the established workflow: enumerate → wave-dispatch → push → 2-reviewer split → fix all → release.

### Phase 8 high-level dispatch order (suggested)

The 31 tasks have rough dependency layers:

- **Wave 1 — Skeleton + schemas (Tasks 0-5):** directory tree, JSON schemas, `solved` predicate, model override writer, PII scrub. Foundation.
- **Wave 2 — Synthetic fixture (Task 6):** sample corpus entry. Unblocks integration tests.
- **Wave 3 — Runner core (Tasks 7-13):** dataclasses, corpus discovery, dry-run runner, live runner, must_not_touch verifier, trends aggregator, append-only contract.
- **Wave 4 — Outputs (Tasks 14-16):** sparkline encoder, scorecard renderer, baseline freeze, regression gate.
- **Wave 5 — Cross-phase wiring (Tasks 17-21):** cost ceiling enforcement, Phase 4 learning type, Phase 7 AC injection contract, Phase 1 hook-failure roll-up, OTel spans.
- **Wave 6 — Curation + corpus (Tasks 22-23):** `curate.py` interactive curation, first 10 corpus entries.
- **Wave 7 — CI + contracts (Tasks 24-26):** GH workflow, idempotency contract, scorecard template.
- **Wave 8 — Docs (Tasks 27-30):** ADR 0013, README, cross-refs, forge-config template.

Sequential dispatch within a wave; parallel-safe across waves only if file-disjoint (which most are).

### Memory references

User auto-memory at `/Users/denissajnar/.claude/projects/-Users-denissajnar-IdeaProjects-forge/memory/` includes the canonical workflow rules:

- `user_forge_personal_tool.md`
- `feedback_no_local_tests.md` — don't run pytest/bats locally; CI verifies
- `feedback_implementation_workflow.md` — code review per phase, fix everything, version bump + tag + push + release
- `feedback_no_self_review.md` — never `/forge review`; use `superpowers:requesting-code-review`
- `feedback_no_backcompat.md` — new versions freely break old state/configs
- `feedback_use_superpowers_plugins.md` — superpowers:* only, NOT pr-review-toolkit:*
- `feedback_cleanup_after_ship.md` — at feature ship: delete plan
- `feedback_cross_verify_unimplemented_plans.md`
- `feedback_plan_drift.md`
- `feedback_defend_positions.md`
- `feedback_orchestrator_size.md`
- `project_plan_template_gaps.md`
- `feedback_version_freshness.md` — always web-search latest stable before pinning
- `feedback_worktree_isolation.md` — relative-path framing in subagent briefs

## Files referenced

- `/Users/denissajnar/IdeaProjects/forge/SHIP_ORDER.md` — canonical 13-plan order; Phase 8 is the last entry
- `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/HANDOFF-2026-04-27-late-roadmap.md` — prior handoff (entered Mega B at this point)
- `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/HANDOFF-2026-04-27-mid-roadmap.md` — Phases 1-6 context (deep history)
- `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/HANDOFF-2026-04-27-mega-consolidation.md` — original mega-train handoff (prereq edits)
- `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/plans/2026-04-22-phase-8-measurement.md` — Phase 8 plan (only remaining plan)
- `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-22-phase-8-measurement-design.md` — Phase 8 spec
- `/Users/denissajnar/IdeaProjects/forge/CHANGELOG.md` — release entries v3.7.0 through v5.3.0

## Decision log (this session)

### Mega B (v5.0.0)

| Decision | Outcome | Reason |
|---|---|---|
| `forge-help` in B12 deletion list | Dropped from `git rm`; CHANGELOG note | Already deleted in v3.8.0 (Phase 2); rm would fail |
| Mega B plan + shared spec exclusion from B5 sed | Hardcoded skip in B5 perl loop | Self-modifying perl scripts in those files would brick B6-B13 |
| CLAUDE.md scope between B10 and Mega E | B10 sed-rewires CLAUDE.md, E later wholesale rewrites | Cleaner UX between v5.0.0 and v5.3.0 (no broken-command refs in interim) |
| Wave 1 parallelism | Sequential | Mega A's git-index race convinced me to err safe |
| `\b` collision discovered at review | Reverse-sed wave + hardened HEAD/TAIL regex | 75+ files miscorrected (`.claude/forge-config.md` → `.claude/forge-admin config.md` literal-space path) |

### Mega C (v5.1.0)

| Decision | Outcome | Reason |
|---|---|---|
| Phase A helper CLI gap | Backfilled `__main__` blocks on `ac-extractor.py` + `platform-detect.py` | Reviewer found shaper invokes them as CLIs but they had no argparse |
| Mega E plan tautology restoration | Used git history baseline at `1e89e679~1` | Mega B5 collapsed mapping-table LHS = RHS; restored via diff |
| `mode == "feature"` Phase A6 bug | Fixed to `"standard"` in state-transitions | Without fix, BRAINSTORMING never fired for default mode (silent AC-S019 fail) |

### Mega D (v5.2.0)

| Decision | Outcome | Reason |
|---|---|---|
| 9 reviewers Write tool gap | Added `Write` to `tools:` frontmatter on all 9 | D3's prose-output contract required it; Bash workarounds conflict with Untrusted Data Policy |
| fg-590 §10 evidence schema conflict | Replaced with reference to canonical `shared/verification-evidence.md` | D8 added a third schema in one file |
| `acknowledged_local_only` enum gap | Added to `state-schema.md:580` | D5 wrote the value; schema validator would reject it |
| Broken D9 bats parser bugs | Rewrote `parse_tasks` awk + replaced `sh -c` with direct pipelines | Multiple D9 tests passed vacuously (only LAST task emitted; dead `count` variables) |
| fg-021 tier conflict | T4 (correct per role); plan/spec prose updated | Sub-investigator returns JSON; doesn't dispatch tasks or use plan_mode |
| Mega E plan agent count fix | 50 → 51 (was off by 2 — missing fg-302 + fg-540 from Phase 7) | Caught during Mega D review; Phase 7 author missed those |

### Mega E (v5.3.0)

| Decision | Outcome | Reason |
|---|---|---|
| F35 label collision | Dropped `F35` annotation from Cost governance bullet | Cost governance is not a numbered feature in `shared/feature_matrix_generator.py`; F35 is Intent verification gate (Phase 7) |
| F-number sync between three registries | Updated generator FEATURES dict + regenerated `shared/feature-matrix.md` | Generator had F35=Speculative plan branches (never shipped); CLAUDE.md had the correct post-Mega-D mapping |
| `tests-3040+` badge | Bumped to `tests-760+` (actual 761) | Wildly stale; Mega E was the doc rollup so this fell in scope |
| `finding_categories-87+` and "92 categories" | Reconciled to `149` (actual count from registry) | Two-source disagreement; registry is canonical |
| Shared spec retirement | `git rm`'d at v5.3.0 release | E was the last reference; allowlist trimmed 12 → 10 |

## What I won't do without confirmation

Per session policy:

- Won't push to remotes other than `origin/docs/a-plus-roadmap`.
- Won't merge `docs/a-plus-roadmap` into `master`.
- Won't delete the carried-over dirty files (`spring/*`, `kotlin.md`, `tests/lib/bats-core`) without explicit instruction.
- Won't run a force-push, hard-reset, or amend-published commits.
- Won't open a PR to merge the roadmap branch.

## Optional follow-ups (post-Phase-8)

When Phase 8 ships and v6.0.0 is tagged, the maintainer may want to consider:

1. **Merge `docs/a-plus-roadmap` to master** — currently the entire mega train + Phase 8 lives on the feature branch. Standard practice would be a PR to master at v6.0.0; this session policy held off.
2. **Carry-over disposition** — the 5 dirty files have persisted across the entire roadmap. Either commit them (intentional content) or revert (stale).
3. **Final handoff retirement** — once v6.0.0 ships and the roadmap is complete, this handoff (and the prior 3) can be `git rm`'d. The CHANGELOG is the durable artifact.
