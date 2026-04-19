# Review — Phase 07 Agent Layer Refactor (PLAN)

**Plan:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/plans/2026-04-19-07-agent-layer-refactor-plan.md`
**Spec:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-07-agent-layer-refactor-design.md`
**Spec review:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/reviews/2026-04-19-07-agent-layer-refactor-spec-review.md`
**Reviewer:** Senior Code Reviewer
**Date:** 2026-04-19
**Verdict:** **APPROVE with minor fixes** — 3 Important, 2 Suggestions

---

## Criterion-by-criterion audit

| # | Criterion | Result | Notes |
|---|---|---|---|
| 1 | writing-plans format (File Structure, Task List, commits per task) | **PASS** | Top-level skill banner present; "File Structure" + "Task List (15 tasks, ~18 commits)" + per-task `**Files:**` + `- [ ]` steps + explicit `git commit` at end of each task. 15 tasks, 18 commits (Tasks 4/7 each ship 1 commit but touch 2 files). |
| 2 | No placeholders; full frontmatter + body for each new agent | **PASS** | fg-155, fg-506, fg-143, fg-555, fg-414 all have complete YAML frontmatter (name, description, model, color, tools, trigger, ui) and real body content (Scope, Checks/Detection, Output, Constraints). No TBD/TODO/XXX. fg-414 correctly omits `ui:` (Tier-4). Others correctly include it (Tier-3). |
| 3 | Type consistency (fg-506 not fg-505 for migration-verifier) | **PASS** | Line 18 states "migration-verifier is numbered **`fg-506`** (not `fg-505`)". All 13 occurrences of the migration-verifier agent ID use `fg-506`. File path `agents/fg-506-migration-verifier.md`, category-registry `"agents": ["fg-506-migration-verifier"]`, dispatch graph, agent-colors, tier tables, test fixtures — consistent throughout. Task 6 has an explicit "Do **not** use 505" guardrail. |
| 4 | Each task commits | **PASS** | Every task ends with a `git add … && git commit -m "…(phase07): …"` step. Commit messages follow Conventional Commits (refactor/feat/docs/test). Task 15 adds Step 11 for push + `gh pr create`. |
| 5 | Spec coverage (12 ui removals, 5 trigger adds, fg-417 split, fg-413 slim, 5 new agents, 5 learnings, colors, categories) | **PASS** | 12 ui removals (Task 1 lists all 12). 5 trigger adds (Task 2). fg-417 split + fg-414 creation (Task 4). fg-413 slim to ≤400 + fg-416 absorb (Task 3). 5 new agents (Tasks 4, 5, 6, 7, 8). 5 learnings files (Tasks 5/6/7/8/9 — fg-143's `observability.md` already exists, prepended rather than created — documented in plan). Colors (Task 10). Categories (Task 13). |
| 6 | Review feedback addressed (I1 license fail-open, I3 trigger grammar, I2 fg-205 dedup, I4 eval gating) | **PASS** | Explicit "Review-issue resolution map" at end (lines 1678-1687). I1 → Task 13 Step 4 + Task 4 Step 3 (config block + agent §2-3 with `fail_open_when_missing: true` + `embedded_defaults`). I2 → Task 11 Step 1 (grep count then delete). I3 → Task 12 (new `shared/trigger-grammar.md` with EBNF, namespaces, operators, error handling, canonical examples). I4 → Task 15 Step 9 (skip marker until Phase 01 merges). |
| 7 | Agent count math: 42 + 5 = 47 | **PASS** | Line 18 states the math explicitly. fg-417 split correctly counted as +1 (fg-417 stays, +fg-414). All downstream asserts use 47 (`agent-registry.bats` line 1420, CLAUDE.md bump Task 14 Step 4, PR body line 1653). |
| 8 | Trigger grammar EBNF + namespaces + examples | **PASS** | Task 12 defines full EBNF (expr, or, and, not, primary, comparison, op, rhs, literal, path), 3 namespaces (`config.*`, `state.*`, `always`), operators (`==`, `!=`, `<`, `<=`, `>`, `>=`, `&&`, `\|\|`, `!`), null-safety, parse-error handling, and a canonical-examples table covering all 10 phase-07 agents. Plus a regex-based syntactic check test in `agent-registry.bats`. |
| 9 | Category-registry.json update task | **PASS** | Task 13 Steps 1-3 add 14 entries (3 I18N-*, 3 MIGRATION-*, 3 RESILIENCE-*, 3 LICENSE-*, 3 OBS-*) — OBS-BOOTSTRAP-APPLIED is a legitimate addition beyond spec §6.1 (documented). Step 2 re-wires existing I18N-* affinity to `fg-155`. Step 3 validates strict JSON. Uses strict JSON (resolves S1). |
| 10 | Color collision check | **PASS** | Task 10 adds 5 rows. Task 15 Step 4 ships `agent-colors.bats` with 3 cluster-scoped distinctness tests (PREFLIGHT 6, Review 10, Verify/Test 6). Spec §5.4 verified cluster-collision-free: crimson+magenta (PREFLIGHT), coral+navy (Verify/Test), lime (Review). Cross-cluster reuse (navy used by Verify/Test fg-555 AND referenced in spec review as Review-cluster color) is permitted per `shared/agent-colors.md` invariant (intra-cluster only). |

---

## Issues

### Critical
None.

### Important (should fix before execution)

**I1. `agent-registry.bats` regex is too permissive and will accept malformed triggers.**
Task 15 Step 3's regex at line 1462 (`local allowed_re='^(always|…)'`) does not properly anchor the alternation — `always` matches only as a full string, but the right-hand side of the alternation accepts a single comparison and then optional chained comparisons via `&&`/`||`. Three gaps:

- Parenthesized sub-expressions from the EBNF (§3 Task 12 allows `"(" expr ")"`) are NOT accepted by this regex. Any agent using grouping fails the test.
- `!` (negation) from EBNF is missing from the regex.
- The RHS allows only a literal or bare path; the EBNF allows `path` on RHS too (it does — confirmed). But the regex's RHS class `("[^"]*"|true|false|[0-9.]+|[a-z_.]+)` allows bare identifiers like `true` and `false` as literals AND as paths — fine. However `!=` on strings: `config.deployment.strategy != "none"` passes. Good.

The practical issue: any future agent using `!` or `(...)` will fail CI even though its `trigger:` is valid per the grammar Task 12 just committed. Either (a) loosen the regex to match the full EBNF, or (b) drop the regex to "non-empty, no newlines" and let Phase 08's evaluator do the real validation.

Recommendation: replace Step 3's regex test with a non-emptiness check plus a forbidden-token check (reject `;`, backticks, `$(`, `|` as pipe, newlines). Keep the strict parser for Phase 08.

**I2. Task 14 Step 4 undercounts CLAUDE.md "42 agents" occurrences.**
The plan asserts "Two occurrences confirmed by grep" (line 1325) and names lines 23 and 116. Spec §3.1 item 6 claimed "4 sites". The current CLAUDE.md I can see has at least:
- Line 23 (top summary)
- Line 116 (Agents section header)
- Plus references like "43 entries" in the spec footnote that the Hierarchy doc currently lists — if that propagates into CLAUDE.md anywhere, it's a third site.

Safer: Task 14 Step 4 should grep for both `\b42\b` and `42 agent` and `42 total`, enumerate all hits, and update whichever match the semantic pattern "count of agents". The "two sites only" assertion risks leaving a stale "42" elsewhere. Run `grep -n "\b42\b" CLAUDE.md` during the step and reconcile before committing.

**I3. Task 3's fg-413 line-count target is not verified against the actual current file.**
Plan line 56 says "Target: ≤400 lines (current 534)" and line 264 says sections 17-21 span "lines 379-419 inclusive … That's ~41 lines". 534 - 41 = 493 lines, not 380. Even after removing the Part D divider and trailing whitespace, the net removal of "~50-60 lines" (line 264) lands at ~474-484 lines — still well above the 400 cap in Success Criteria (spec §11) and the verification check at line 1669 (`wc -l … → ≤400`).

Either (a) the actual Part D is bigger than plan line 264 estimates, (b) the slim target should be relaxed to ~480, or (c) Task 3 Step 1 needs additional content removal beyond sections 17-21. Recommendation: before executing Task 3, `wc -l agents/fg-413-frontend-reviewer.md` and re-audit which sections to remove. If 534 - (Part D) > 400, either expand the removal scope or relax the target in spec §11 + plan line 1669.

### Suggestions

**S1.** Task 7 Step 2 assumes `shared/learnings/observability.md` already exists. The plan should add a `test -f` guard or a fallback "create it if absent" branch; otherwise a fresh clone where the file was never created would fail silently (the `Edit` tool errors on missing files).

**S2.** Task 14 Step 3 ("Regenerate shared/agents.md") probes for a generator script with `ls shared/generate-*.sh` and falls back to manual row insertion. This is acceptable but non-deterministic — two humans executing Task 14 could end up with differently-formatted tables. If Phase 06 committed a generator, name it explicitly; if not, make the manual row insert the canonical path.

---

## What was done well

- **Review-issue resolution map** (lines 1678-1687) is an excellent addition — makes the I1/I2/I3/I4 traceability explicit and prevents the reviewer from re-asking whether each got addressed.
- **`fg-506` renumbering discipline** — every single reference in the plan uses `fg-506`, including the category registry, test fixtures, color map, tier tables, and a guardrail sentence "Do **not** use 505" at the start of Task 6.
- **Task 12's trigger-grammar doc is production-quality** — EBNF, operator table, null-safety semantics, error taxonomy (CRITICAL vs WARNING vs silent), and a canonical-examples table covering all 10 phase-07 agents. This is the kind of contract Phase 08's dispatch-graph generator can actually target.
- **License fail-open wiring is end-to-end**: config template (Task 13 Step 4), agent §2 policy resolution order (Task 4 Step 3), agent §3 embedded defaults with explicit allow/warn/deny buckets. The spec review's I1 is fully resolved, not hand-waved.
- **Per-task commits** preserve bisect sharpness (addresses spec-review S3 about squash). The plan explicitly opts for real-commit history (row S3 in resolution map).
- **Test coverage is disproportionately thorough** — tightening existing bats test + 2 new contract tests (registry, colors) + 3 eval fixtures with `skip: true` guard until Phase 01 harness merges. Belt-and-braces.

---

## Recommendation

**APPROVE to proceed to execution**, conditional on:
- **I3 (fg-413 line-count arithmetic)** — resolve before Task 3 execution; either expand removal scope or relax the ≤400 cap.
- **I1 (registry.bats regex)** — loosen to match the full EBNF or downgrade to a forbidden-token check; Phase 08's evaluator will do the real parsing.
- **I2 (CLAUDE.md grep scope)** — run `grep -n "\b42\b" CLAUDE.md` at Task 14 Step 4 and reconcile before committing.

S1 and S2 are housekeeping and can be folded into the tasks they annotate without blocking execution.

---

## Files referenced

- `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/plans/2026-04-19-07-agent-layer-refactor-plan.md` (plan under review)
- `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-07-agent-layer-refactor-design.md` (spec)
- `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/reviews/2026-04-19-07-agent-layer-refactor-spec-review.md` (prior spec review)
- `/Users/denissajnar/IdeaProjects/forge/CLAUDE.md` (42 → 47 agent count bump target)
- `/Users/denissajnar/IdeaProjects/forge/shared/agent-role-hierarchy.md` (tier tables + dispatch graph + duplicate fg-205 row)
- `/Users/denissajnar/IdeaProjects/forge/shared/agent-colors.md` (cluster uniqueness invariant)
- `/Users/denissajnar/IdeaProjects/forge/shared/checks/category-registry.json` (14 new categories target)
- `/Users/denissajnar/IdeaProjects/forge/agents/fg-413-frontend-reviewer.md` (slim target — ≤400 lines)
- `/Users/denissajnar/IdeaProjects/forge/agents/fg-417-dependency-reviewer.md` (split target)
- `/Users/denissajnar/IdeaProjects/forge/agents/fg-505-build-verifier.md` (existing; confirms fg-506 renumber necessity)
