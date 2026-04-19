# Review — Phase 05 Skill Consolidation Implementation Plan

**Plan:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/plans/2026-04-19-05-skill-consolidation-plan.md`
**Spec:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-05-skill-consolidation-design.md`
**Spec review:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/reviews/2026-04-19-05-skill-consolidation-spec-review.md`
**Date:** 2026-04-19
**Reviewer role:** Senior code reviewer (implementation plan pass)

---

## Verdict

**APPROVE WITH MINOR REVISIONS.**

The plan is detailed, internally consistent, and directly reflects the spec's intent while lifting the three spec-review issues (I1, I2, S1) out of "Open Questions" into concrete, testable tasks. Every task ends in a conventional-commit commit, full SKILL.md bodies are inlined (no "TODO: fill this in" placeholders), and the 35 − 2 − 4 − 1 = 28 arithmetic is maintained in both `EXPECTED_SKILL_NAMES` (which I counted — exactly 28 entries) and the structural tests.

The task ordering is pragmatic: CI is allowed to go red from Task 2 through Task 10, with Task 11 the explicit "tests green" flip. This is called out in both the task introduction and the self-review — reviewers won't be surprised by red CI mid-sequence.

Three minor issues remain before dispatch; none invalidate the design.

---

## Criteria checklist

| # | Criterion | Met? | Evidence |
|---|---|---|---|
| 1 | writing-plans format (Goal, Architecture, Tech Stack, File Structure, Task Breakdown, Self-Review) | Yes | Header block present; 12 numbered tasks with checkbox steps; Self-Review section at tail |
| 2 | No placeholders; complete SKILL.md contents shown | Yes | All three unified SKILL.md bodies (review, graph, verify) shown inline — not "TODO". The graph subcommand sections use "(Body preserved verbatim from the old .../)" — see issue I1 below, but this is a deliberate preservation pointer, not a placeholder |
| 3 | Type consistency (subcommand names, arg flags) | Yes | `--scope=all --fix`, `### Subcommand: all --fix` used consistently in Task 3, Task 7, Task 11 |
| 4 | Each task commits | Yes | Every task except Task 2 (scout, explicitly "no commit") and Task 12 Step 6 (conditional) ends with a `git commit -m` block. Task 12 has its own final `chore(phase5): bump plugin version` commit |
| 5 | Spec coverage (3 merges, /forge-help tree, CLAUDE.md update, CI tests) | Yes | Explicit coverage table in Self-Review mapping each spec section to task numbers. Review = Task 3, Graph = Task 4, Verify = Task 5, help tree = Task 7, CLAUDE.md = Task 6, CI tests = Task 11 |
| 6 | Review feedback addressed (I2 safety gate, I1 validate-config read-only, S1 schema_version) | Yes | Top "Review-Feedback Resolution" table + concrete requirements in Task 3 (gate), Task 5 (read-only preservation), Task 7 (`schema_version: "2"`), with regression tests in Task 11 |
| 7 | Skill count arithmetic: 35 − 7 = 28 verified | Yes | `EXPECTED_SKILL_NAMES` fixture in Task 10 has exactly 28 entries (I counted); `MIN_SKILLS=28` constant; Task 11 `@test "skill count is exactly MIN_SKILLS (28)"` |
| 8 | Old skills deletion task present (no zombie aliases) | Yes | Task 3 (codebase-health, deep-health), Task 4 (graph-status/query/rebuild/debug via `git rm -r`), Task 5 (config-validate). `forge-graph-init` rename via `git mv` is explicit and called out as load-bearing in self-review risk #2 |
| 9 | Cross-repo reference sweep task | Yes | Task 2 generates the manifest; Task 8 applies the rewrites with an explicit mapping table; Task 11 asserts zero dangling references (outside allowed allowlist: docs/superpowers, CHANGELOG, forge-help Migration section) |
| 10 | Subcommand dispatch pattern doc | Yes | Task 1 creates `shared/skill-subcommand-pattern.md` with full algorithm, `parse_args` helper, default-subcommand table, layout contract, exit-2-on-unknown. Referenced from all three unified SKILL.md bodies |

All 10 criteria met.

---

## What was done well

1. **Review-Feedback Resolution table at the top.** The three spec-review concerns (I1/I2/S1) are promoted out of "Open Questions" into concrete task assignments before the file structure. A reader doesn't have to scroll to verify the spec-review was honored.
2. **Exact, commit-aligned task boundaries.** Tasks 3, 4, 5 each do exactly one cluster consolidation + deletion + commit. This matches the spec's "single PR" rollout while giving reviewers per-cluster granularity.
3. **File Structure section with Created/Modified/Renamed/Deleted breakdown.** Reviewers can see at a glance that the change is 2 created + 7 modified + 1 renamed + 6 deleted files.
4. **Task 2 is explicitly non-committing** ("scout task — produce a manifest, don't edit yet"). This prevents the engineer from committing the `/tmp/forge-phase5-refs.txt` manifest.
5. **Task 9 separates test updates from Task 11's new test authoring.** `tests/contract/skill-contract.bats`, `tests/contract/graph-debug-skill.bats`, and `tests/unit/skill-execution/skill-error-handling.bats` are explicitly updated, not left for discovery.
6. **`EXPECTED_SKILL_NAMES` fixture is enumerated in full in Task 10.** No "the 28 names are obvious" hand-wave. I verified the count: exactly 28 entries, alphabetized, none of the 7 removed names present.
7. **Task 11 assertions are specific, not aspirational.** The structural-test file has 17 named `@test` blocks, each checking a concrete grep or file existence — not a vague "tests that the consolidation worked".
8. **Self-Review section includes a risks-for-implementer block.** The git-mv-before-content-rewrite ordering risk, the CI-red-until-Task-11 expectation, and the schema-version quote-exactness risk are all flagged to the executing engineer.

---

## Issues

### Important (should fix before dispatch)

**I1 — Graph SKILL.md uses "(Body preserved verbatim from the old ..)" placeholders instead of inlined content.**

Task 4's `skills/forge-graph/SKILL.md` body shows five `### Subcommand:` sections each with a line like:

> `(Body preserved verbatim from the old /forge-graph-init — Steps 1–8: VERIFY PREREQUISITES, PREPARE COMPOSE FILE, ...)`

This is ambiguous for the executing engineer. "Preserved verbatim" implies a literal copy of the old file's body — but the new file has a single shared-prerequisites block at the top, so the old step-1 "VERIFY PREREQUISITES" is structurally different. The engineer must either (a) copy the old body verbatim and create duplicated prerequisites, or (b) edit the old body to remove the duplicated prerequisites and risk silently dropping a check. The plan does not specify which.

**Contrast:** Task 3's `skills/forge-review/SKILL.md` inlines the full body including the review-fix loop pseudocode, the report format block, and the file-discovery bash. There is no ambiguity about what "verbatim" means.

**Action:** Either (a) inline the five graph subcommand bodies the same way Task 3 inlines the review body, OR (b) add an explicit direction in Task 4 Step 2: "For each `(Body preserved verbatim...)` line: (1) open the named old SKILL.md; (2) copy its body starting after its own prerequisites section; (3) paste under the corresponding `### Subcommand:` heading; (4) if the pasted body duplicates a shared-prerequisite block, remove the duplicate." This removes the "what does verbatim mean here" ambiguity.

Task 5's `### Subcommand: build` and `### Subcommand: config` have the same "(Body preserved verbatim from the old ...)" pattern and carry the same risk — apply the same fix.

**I2 — The 3-levels-deep tree-depth grep in Task 11 is brittle against a common indent choice.**

The assertion reads:

```bash
deep=$(grep -cE '^│[[:space:]]+│[[:space:]]+│' "$file" || true)
```

This only fires if a line begins with three `│` bars. But the tree in Task 7 uses `│   ` (bar + three spaces) as the indent unit — for a level-4 line the actual prefix would be `│   │   │   ├──`. The bare-bones regex `^│[[:space:]]+│[[:space:]]+│` DOES match that, so the check works for the specific indent Task 7 uses. However: (a) the self-review calls this out as a known risk ("if Task 7's tree uses a different indent, update the grep pattern accordingly") but (b) the plan doesn't actually pin the indent width anywhere — Task 7 just pastes the tree from spec §4.3. If a linter ever normalizes indentation or the engineer subtly retypes the tree, the depth check silently stops working.

**Action:** Add a structural assertion to Task 11 that the tree uses 4-char `│   ` indents. A one-line grep: `grep -qE '^├── ' "$file" && grep -qE '^│   ├── ' "$file"` — ensures both level-1 (root-adjacent) and level-2 (nested) forms are present. Combined with the existing depth-guard, this becomes a positive + negative check pair.

### Suggestions (not blocking)

**S1 — The `validate-config.sh` read-only regression test in Task 11 has an over-broad forbidden-pattern grep.**

The test (lines 1459–1463 of the plan) uses:

```bash
grep -nE '(\b(touch|mkdir|tee)\b|>\s*[./a-zA-Z]|>>\s*[./a-zA-Z])' \
```

This matches any `>` redirection to a path-like string. But `validate-config.sh` — per Task 5's own assertion — uses stderr redirection (`>&2`). The test filters that out with `grep -vE '>\s*&\s*[12]'`, but the pattern `>\s*[./a-zA-Z]` is tight and any future legitimate use of e.g. `>/dev/null` (common in `if` guards like `command -v x >/dev/null`) would trip this test. Consider tightening to only forbid `>` redirections to `.forge/`, `.claude/`, or `$HOME` paths, OR explicitly allowlist `/dev/null` and `/tmp/` in the filter chain.

**S2 — No task for updating `hooks/hooks.json` if any hook registration references old skill names.**

Task 8's file list includes `hooks/automation-trigger.sh` but not `hooks/hooks.json`. A quick grep would confirm whether any hook definitions reference removed skills. If the sweep in Task 2 Step 1 turns up `hooks/hooks.json`, the engineer should add it to Task 8's git-add list; consider naming this file explicitly in Task 2's "at minimum" expected list so the engineer notices.

**S3 — Task 12 Step 7 version bump from 3.0.0 to 3.1.0 conflicts with the spec's §9 statement.**

Spec §9 item 10 says "`plugin.json` stays at v3.x.0 with a minor bump (new feature — consolidation changes user-facing surface)." Plan Task 12 Step 7 bumps to 3.1.0, which is a minor bump — consistent. But the change is explicitly labeled **BREAKING** in three commit messages (Tasks 3, 4, 5 use `feat(phase5)!:` with `BREAKING CHANGE:` footers). SemVer strictly requires a MAJOR bump for breaking changes. The plan's minor-bump choice is defensible (forge is pre-1.0-esque in maturity; skills are user-facing sugar, not a public API), but it's worth a one-line rationale in Task 12 Step 7: "Minor rather than major because skill names are user-facing surface, not a typed API contract; BREAKING markers in commits aid changelog generation without committing to SemVer-major semantics for skill renames." Otherwise a future contributor will file an issue saying "this should have been 4.0.0."

**S4 — Structural-test assertion for `### Subcommand: all --fix` ordering.**

Task 11's assertion `grep -q '^### Subcommand: all --fix'` will pass if the section is anywhere in the file. If the `### Subcommand: all --fix` section were accidentally placed before `### Subcommand: all`, the dispatcher's partial-match logic in Task 3 Step 1 (dispatch-rule 5: "If `$SUB` is in the subcommand allow-list") could misroute. This is unlikely given the plan's explicit section ordering but cheap to guard. Add: `grep -n '^### Subcommand:' skills/forge-review/SKILL.md | sort -t: -k1n | head -4` should produce `changed` before `all` before `all --fix`. Not blocking.

---

## Top 3 issues (per review instructions)

1. **I1 — Graph (and to a lesser extent verify) subcommand sections use `(Body preserved verbatim...)` pointer notation instead of inlining the content the way Task 3 does for review.** Ambiguous for the executing engineer. Fix: either inline the full bodies, or add an explicit "copy the old body after its prerequisites; remove duplicated shared-prerequisite block" direction in Tasks 4 and 5.

2. **I2 — The 3-levels-deep tree-depth check in Task 11 is tightly coupled to the exact 4-char `│   ` indent choice in Task 7 but that coupling is not pinned.** If indent width ever drifts, the check silently passes. Add a positive assertion that the tree uses the expected indent unit.

3. **S3 — Version bump to 3.1.0 is a minor bump despite the commits being labelled `feat!:` with `BREAKING CHANGE:` footers.** Consistent with the spec but may invite SemVer confusion. Add a one-line justification in Task 12 Step 7.

---

## Recommendation

**APPROVE — dispatch to the implementer with I1 and I2 resolved first.** Both are small spec-clarity edits, not design changes. S1/S2/S3/S4 are low-priority polish and can be addressed in Task 12 Step 6 ("If any fix is needed, commit it") rather than blocking dispatch.

All 10 original review criteria are met. The plan faithfully reflects the spec and the spec-review, and the Self-Review block demonstrates that the plan author audited their own coverage.

---

## Final response (≤80 words)

**APPROVE WITH MINOR REVISIONS.** All 10 criteria met; arithmetic holds (35 − 7 = 28, verified in `EXPECTED_SKILL_NAMES` fixture); spec-review issues I1/I2/S1 promoted to concrete tasks with regression tests. Top 3 issues: (1) graph/verify `(Body preserved verbatim...)` pointers are ambiguous vs Task 3's fully-inlined review body — inline or add explicit copy-paste direction; (2) tree-depth grep in Task 11 is coupled to `│   ` 4-char indent but not pinned; (3) 3.1.0 minor bump despite `BREAKING CHANGE:` commits needs a one-line SemVer rationale.
