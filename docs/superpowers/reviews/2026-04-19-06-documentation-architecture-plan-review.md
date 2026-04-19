# Plan Review — Phase 06 Documentation Architecture Refactor

**Plan:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/plans/2026-04-19-06-documentation-architecture-plan.md`
**Spec:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-06-documentation-architecture-design.md`
**Spec Review:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/reviews/2026-04-19-06-documentation-architecture-spec-review.md`
**Reviewed:** 2026-04-19
**Verdict:** APPROVE WITH MINOR ISSUES

---

## Criteria check

| # | Criterion | Result | Evidence |
|---|-----------|--------|----------|
| 1 | writing-plans format | PASS | Goal, Architecture, Tech Stack, File Structure, Task N with Files + checkbox Steps + commit; Self-Review; Execution Handoff |
| 2 | No placeholders (TBD/TODO/XXX) | PASS | Only `<!-- paste-point -->` markers in Task 10/11 (explicit source citations, not TBDs) and ADR-template `<short decision title>` (template artefact) |
| 3 | Type consistency (file paths match across tasks) | PASS | `shared/agents.md` anchors in Task 10 match CSV (Task 9) match CI anchor check (Task 15); exempt list `state-schema-fields.md` + `learnings-index.md` consistent in Tasks 6/7/15 |
| 4 | Each task commits | PASS | Every task ends with a `git commit -m` step using `docs(phase06):` / `feat(phase06):` / `ci(phase06):` — Conventional Commits |
| 5 | Spec coverage | PASS | Split state-schema (T7), trim convergence (T8), merge 3→agents.md + rewrite agent-communication (T9–12), delete dead file (T12), ADR dir + 11 ADRs (T1–4), generator + index (T5–6), Start Here + framework-count (T16), shared/README (T14), CI workflow (T15), config key (T18), deferred spec (T17), verification (T19) |
| 6a | Review I1 (<90 deferral) | PASS | T17 creates `2026-04-19-06b-shared-sub-directory-split.md`; plan header resolves it explicitly |
| 6b | Review I2 (agents.md split) | PASS | Plan pre-commits to 2-way split: `agents.md` (~400L) + narrowed `agent-communication.md` (~300L, rewritten not deleted). Deleted-files list corrected to 3 |
| 6c | Review I3 (anchor map CSV) | PASS | T9 creates CSV at `docs/superpowers/plans/2026-04-19-06-anchor-map.csv` with 48 rows; consumed by T10, T11, T13, T16 |
| 7 | ADR template + 11 ADRs listed | PASS | T1 template (Context / Decision / Consequences / Alternatives / References + Status/Date/Deciders/Supersedes/Superseded by); T3–T4 seed all 11 (0001 Neo4j, 0002 SQLite fallback, 0003 FSM, 0004 ship gate, 0005 composition, 0006 scoring, 0007 bash→Python, 0008 no-backcompat, 0009 MCP read-only, 0010 worktree, 0011 compression) |
| 8 | Learnings-index generator spec | PASS | T5 has full Python source (~140L), correctly flags spec's YAML-frontmatter assumption is wrong, parses existing `# Cross-Project Learnings:` + `### ID: title` + `- **Confidence:**` / `- **Hit count:**` format, exit codes 0/1/2, `--check` strips timestamp before hashing |
| 9 | Framework-count drift fix | PASS | T16 Step 2 rewrites line 16 from `(21)` to `(23)`; T15 adds CI `Framework-count guard` comparing `ls modules/frameworks/ \| wc -l` against claim |
| 10 | CI anchor/link check workflow | PASS | `.github/workflows/docs-integrity.yml` (T15) has 6 steps: learnings-freshness, ADR format, framework-count, 600L ceiling, anchor-existence (inline Python walks `[text](path#anchor)` links, slugifies headings, handles `<a id="...">` explicit anchors), lychee pinned `@v2` |

All 10 required criteria satisfied. All 3 spec-review Important items (I1/I2/I3) addressed. All spec-review Suggestions (S1/S2/S3/S4/S5) addressed or correctly dismissed.

---

## Strengths

1. **Review feedback reconciliation is explicit.** Plan opens with a dedicated section mapping each I1/I2/I3 and S1–S5 item to the specific task that resolves it. Reviewer can verify each in place.
2. **Honest correction of spec's YAML-frontmatter assumption.** T5 flags that `shared/learnings/*.md` do NOT use YAML frontmatter (they use `### ID: title` + `- **Confidence:**` lines) and the generator targets the real format. This catches a latent spec bug that would have blocked CI on first run.
3. **Anchor map CSV is substantive, not aspirational.** 48 rows, source file + source anchor → target file + target anchor. Review sweep (T13) consumes it as data, not prose.
4. **600L exemption list is principled.** `state-schema-fields.md` and `learnings-index.md` are the only two exempt; documented in both T7 (field reference justification) and T15 (CI guard). No ad-hoc exemptions.
5. **Commit granularity is reviewable.** 19 tasks, 19+ commits, each scoped to one structural change — a reviewer can bisect any regression to a single task.
6. **Rollout ordering (task order) is dependency-correct.** Generator (T5) before index (T6); CSV (T9) before merged docs (T10/T11); merged docs before delete (T12); delete before sweep (T13); sweep before CLAUDE.md edit (T16); everything before final verification (T19).
7. **Success criterion pre-validation.** T16 Step 5 has three `awk`/`grep` checks (heading in first 50 lines, ≤30 lines, exactly 3 numbered steps) that mirror the spec §11 success bullets.

---

## Issues

### Critical (must fix before implementation)

None.

### Important (should fix before execution)

**I1 — T18 config file path is speculative.**
T18 Step 1 says "locate the forge-config template in the plugin" and hedges with "If no root `forge-config.md` exists in the plugin (only framework templates do), add the config key inside `docs/adr/_template.md`'s counterpart configuration documentation" — this fallback (ADR template as config home) is wrong and the "note" at the end further hedges to `CLAUDE.md`. The plugin root ships `forge-config.md` as a template in some places; the plan should commit to one canonical target. Recommend: explicitly write to `modules/frameworks/base-template.md` or a top-level `docs/forge-config-template.md`, pinned by `Files:` header. As written, an executing agent has 3 possible destinations.

**I2 — T7 split-point identification is underspecified.**
T7 Step 1 instructs "Identify the section heading where field-by-field reference begins (typically a '## Fields' or '## Field Reference' header; if sections are named differently, pick the first section whose content is dominated by `### fieldname` sub-headers and tables)." The 1236-line source has a specific structure; the plan should survey it once now and hard-code the split point (line number or exact heading) rather than leaving heuristic judgment to execution time. Risk: two different executing agents would split at different seams, producing non-reproducible outputs.

**I3 — T15 anchor-existence check uses an incomplete slugify.**
The inline `slugify()` function in the anchor-existence CI step (T15, ~line 1781) does `re.sub(r"[^\w\s-]", "", s)` then `re.sub(r"\s+", "-", s)`. This does not match GitHub's rendered-anchor algorithm for headings containing code spans (backticks), emoji, dots, or consecutive hyphens. Many forge headings contain backticks (e.g. `` ## `forge-state.sh` ``) or dotted names. CI may generate false positives on legitimate links. Recommend: either pre-test the slugify on a sample of actual forge headings (add to T15 Step 1 a "dry-run on current repo" sub-step) or switch to the `python-slugify` / `markdown-anchor` library to match GitHub's algorithm.

### Suggestions (nice to have)

**S1 — T10/T11 paste-point comments risk being left in-place.**
Tasks 10 and 11 scaffold `agents.md` and `agent-communication.md` with `<!-- Merged from ... -->` HTML comments meant as paste instructions. Step 2 says "paste content from the source files." An executing agent might leave the comments in the output. Suggest: add an explicit verification step that `grep -c '<!--' shared/agents.md` returns 0 after Step 2.

**S2 — T13 (sweep) has no rollback guidance if sweep misses a reference.**
The anchor-existence check in CI will catch broken internal anchors, but if T13 misses a reference entirely, the first CI run fails and execution must re-open already-committed tasks. Suggest: add T13 Step 6 that runs the anchor-existence Python block (extracted from T15) locally before committing, to fail fast.

**S3 — T16 Step 3 edit to the Key-entry-points table introduces duplicate rows.**
The spec has `Agent design | shared/agent-philosophy.md + shared/agent-communication.md`. T16 Step 3 proposes adding `Agent model | shared/agents.md` AND keeping the old `Agent design` row AND adding `Agent registry | shared/agents.md#registry`. Three rows for an agent-related concept where one would do. Suggest: collapse to one row `Agent model / registry | shared/agents.md` and one row `Agent communication | shared/agent-communication.md`.

**S4 — T19 (final verification) does not run lychee locally.**
Steps 1–5 cover structural validator, file counts, generator freshness, anchor check, deletion confirmation — but not link-check. Lychee is the 6th CI step in T15; a local dry-run (`docker run lycheeverse/lychee ...` or `cargo install lychee` one-liner) would catch most issues before pushing. Optional because "test in CI" is the project preference — noted in context.

**S5 — T5 generator skips `agent-effectiveness-template.md` by name.**
The `SKIP_FILES` set includes `agent-effectiveness-template.md` — verify this file exists (or future files matching the pattern will be handled) by checking `shared/learnings/` contents. If the plan added this to prevent a known parse failure, document that rationale in a comment above `SKIP_FILES`.

---

## Architecture review

- **Task decomposition is correct.** 19 tasks, each with a single commit, each with clear Files header + checkbox steps. Follows writing-plans format.
- **Dependency DAG is valid.** T1 (template) → T2 (README uses template) → T3/T4 (ADRs) → T5 (generator) → T6 (runs generator) → T7/T8 (splits) → T9 (CSV) → T10/T11 (merged/rewritten docs consuming CSV) → T12 (delete) → T13 (sweep) → T14 (README references new structure) → T15 (CI) → T16 (CLAUDE.md) → T17 (06b spec) → T18 (config) → T19 (verify). No cycles.
- **Spec-review reconciliation is honest.** Plan does not silently adopt the flawed spec assumption about YAML frontmatter; it corrects it in-plan and explains the correction (T5 Step 1 comment, Review Feedback Reconciliation section).
- **No runtime impact.** Confirmed by §6 of spec and absence of any `agents/*.md`, hook script, or state-schema changes. Pure doc refactor.

---

## Top 3 issues + verdict

**Verdict: APPROVE WITH MINOR ISSUES.** All 10 required criteria pass. All 3 spec-review Important items resolved. Three Important items below are fix-before-execution, not fix-before-approval.

**Top 3:**

1. **I1** — T18 picks the config file destination with a hedged "if X then Y else Z" — commit to a single path in the `Files:` header.
2. **I2** — T7 leaves split-point identification to execution-time heuristic; hard-code the exact heading or line number.
3. **I3** — T15 anchor-existence `slugify()` does not match GitHub's algorithm for headings with backticks/dots; risk of CI false positives. Pre-test on current repo or use a library.
