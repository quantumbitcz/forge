# Review — Phase 06 Documentation Architecture Refactor

**Spec:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-06-documentation-architecture-design.md`
**Reviewed:** 2026-04-19
**Verdict:** APPROVE WITH MINOR ISSUES

---

## Criteria check (10/10)

| # | Criterion | Result | Evidence |
|---|-----------|--------|----------|
| 1 | All 12 sections | PASS | §1 Goal, §2 Motivation, §3 Scope, §4 Architecture, §5 Components, §6 Data/State/Config, §7 Compatibility, §8 Testing Strategy, §9 Rollout, §10 Risks/Open Questions, §11 Success Criteria, §12 References — all present, all substantive |
| 2 | No placeholders (TBD/TODO/XXX) | PASS | Only legitimate ADR-template placeholders (`<short decision title>`, `<names>`) which are part of the template artifact, not spec content |
| 3 | Every file move/split/delete listed | PASS | §5.1 has exhaustive tables: Split (2), Merge (3→1), Delete (4), Create (14), Edit (2). All file paths explicit |
| 4 | ADR template (Context/Decision/Consequences) | PASS | §4.4 provides full template including `## Context`, `## Decision`, `## Consequences` (with Positive/Negative/Neutral), `## Alternatives Considered`, `## References`, plus Status/Date/Deciders/Supersedes frontmatter |
| 5 | ≥10 initial ADRs with topics | PASS | 10 seeded (0001 Neo4j, 0002 SQLite fallback, 0003 FSM, 0004 evidence shipping, 0005 composition order, 0006 87-category scoring, 0007 bash→Python, 0008 no-backcompat, 0009 MCP read-only, 0010 worktree isolation) + optional 11th (output compression) |
| 6 | Learnings-index script path | PASS | `scripts/gen-learnings-index.py` — specified in §4.2, §5.2 (with exit-code contract), and §5.1 create table |
| 7 | CI workflow named | PASS | `.github/workflows/docs-integrity.yml` — specified in §5.3 with 5 steps (freshness, ADR format, link-check, framework-count, structural) |
| 8 | CLAUDE.md framework-count fix (21→23) | PASS | §5.1 edits table: `"frameworks/ (21)" → "frameworks/ (23; 21 production + base-template scaffolding + k8s ops)"`. Directory verified: 23 entries. §5.3 step 5 adds a CI guard preventing recurrence |
| 9 | "Start Here" ≤30 lines, content sketched | PASS | §4.5 provides exact markdown (~17 lines), 3 numbered steps (install, dry-run, skill picker), plus an "Already familiar?" escape hatch |
| 10 | Link-check tool named | PASS | `lychee` (pinned GitHub Action) in §5.3 step 4 and §12 references (`https://github.com/lycheeverse/lychee-action`). Internal/relative links hard-fail; external URLs warn-only — correct policy |

**Overall: 10/10 required criteria satisfied.**

---

## Strengths

1. **Self-aware about the <90 target miss.** §4.1 note + §10 risk #5 openly acknowledge that a file-merge-only refactor lands ~114, not <90, and documents a Phase 06b carry-over with sub-directory moves. This is honest planning, not target-gaming.
2. **CI-only enforcement is correctly operationalized.** Five distinct CI checks (freshness, ADR format, link-check, framework-count, anchor-existence) — not a vague "CI validates docs" handwave.
3. **Anchor-existence check (§8 step 6) is the right catch.** The biggest risk of the 3→1 merge is dead `#section` anchors across agents/skills; this check addresses it directly.
4. **ADR numbering policy is explicit.** "Gaps forbidden. Superseded ADRs are never renumbered." This prevents the common ADR-repo rot where numbering becomes incoherent after 2 years.
5. **`--check` mode design for the generator is idempotent-safe.** Stripping the timestamp line before hash comparison avoids the "CI fails because the file was regenerated 1 second later" trap.
6. **Rollout ordering in §9 is debuggable.** Reviewers can verify each of 10 steps independently; a reviewer lost mid-PR can jump to a specific step.

---

## Issues

### Critical (must fix before implementation)

None.

### Important (should fix before PR)

**I1 — Success target contradiction (§11 vs §3 motivation).**
§2 Motivation cites W6 target of "<90 items." §11 Success Criteria lists "≤115 items." §4.1 and §10 risk #5 reconcile this but §11 does not. A reader skimming §11 alone will see the looser target and assume the audit was relaxed. Fix: add a one-line note under the §11 bullet: *"Strict <90 deferred to Phase 06b per §4.1 note."*

**I2 — `shared/agents.md` target ~600–700L sits on the 600L success-criterion line.**
§4.1 says merge target "~600-700L." §11 says "No file in `shared/` or `CLAUDE.md` exceeds 600 lines." If the merge deduplicates less than hoped, CI fails on the file this spec created. §10 risk #2 acknowledges this but the mitigation (split again into 2) is reactive. Fix: either (a) relax §11 to 700L for `agents.md` specifically, or (b) pre-commit to the 2-way split in §4.1 and update `agents.md` target to ~400L.

**I3 — Anchor map for the 3→1 merge is not specified.**
§5.1 Merge table lists target subsections (`#communication`, `#conflict-resolution`, `#ui-tiers`, `#dispatch`, `#registry`, `#model`) but does not map *source* anchors to *target* anchors. The sweep in §5.1 edits table says "update link target to `shared/agents.md#<anchor>`" — but implementers won't know which source anchor maps to which target anchor. Fix: add an anchor-map table in §5.1 (e.g., `agent-communication.md#tier-routing` → `agents.md#communication-tier-routing`).

### Suggestions (nice to have)

**S1 — §6 config key placement is under-specified.** `docs.learnings_index.auto_update` is introduced as a new top-level `docs:` section. List whether this lives in `forge-config.md` (plugin defaults), `forge.local.md` (per-project), or both, and which file the plugin template ships.

**S2 — ADR-0008 (no-backcompat) pre-emption.** §10 open question #3 proposes marking 0008 `Accepted` on merge date citing the A+ roadmap constraints. Good call — recommend making this a decision in the spec rather than an open question, since the phase explicitly restates the stance.

**S3 — Consider adding a `docs/adr/README.md` legend sample.** §4.3 says the index is "hand-maintained (one-line table)" but no sample row is shown. One concrete example would clarify the expected density.

**S4 — Lychee config pinning.** §5.3 step 4 says "pinned GitHub Action" but no version pin is given. Recommend specifying `lycheeverse/lychee-action@v2` (or current stable) to prevent silent major bumps.

**S5 — Pre-PR frontmatter sweep.** §10 risk #3 mentions "a pre-PR sweep fixes stragglers once" for learning-file frontmatter. Worth lifting this into §9 Rollout as step 0.5 ("run generator dry, fix any parse-errors, then proceed") — otherwise step 2 ("run generator, commit output") blocks on discovery.

---

## Architecture review

- **Merge is correctly scoped.** Three agent docs → one, with subsections preserving the three original vantage points. Not a blind concatenation — the `#model` intro (§5.1) frames the merged content.
- **Split is correctly scoped.** `state-schema.md` split at the right seam (overview vs field reference); `convergence-engine.md` trim completes a prior partial split (good — finishes debt rather than creating new debt).
- **No runtime impact.** §6 confirms `state.json` schema untouched; §7 confirms all skill entry points and agents unchanged. Pure doc refactor.
- **Phase 07/08 interaction** (merged-agent docs dependency): §5.1 establishes `shared/agents.md` as the canonical merged doc; downstream phases can reference stable anchors. The §10-risk-#2 fallback (2-way split if size grows) would break these references — flag to Phase 07/08 authors to pin anchor names, not file names.

---

## Top 3 issues + verdict

**Verdict: APPROVE WITH MINOR ISSUES.** All 10 required criteria pass. Three Important items (I1–I3) are fix-before-PR, not fix-before-implementation.

**Top 3:**

1. **I1** — §11 success target (≤115) contradicts §2 motivation (<90); add a cross-reference to §4.1 deferral note.
2. **I2** — `shared/agents.md` ~600–700L target collides with §11's 600L ceiling; either relax the ceiling for this file or pre-commit to the 2-way split.
3. **I3** — No anchor-map for the 3→1 merge; sweep will be guesswork without it.
