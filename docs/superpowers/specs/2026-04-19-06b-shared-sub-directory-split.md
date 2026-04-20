# Phase 06b — `shared/` sub-directory split (deferred from Phase 06)

**Date:** 2026-04-19
**Phase:** 06b (A+ roadmap carry-over)
**Priority:** P2
**Status:** Deferred
**Parent:** `docs/superpowers/specs/2026-04-19-06-documentation-architecture-design.md`

---

## 1. Goal

Drive `shared/` top-level item count from the ~114 left after Phase 06 down to
<90, by introducing sub-directories (`shared/agents/`, `shared/state/`,
`shared/features/`, etc.) and moving existing files into them.

## 2. Why deferred

Phase 06 achieves the structural improvements (merges, splits, ADR dir, Start
Here, CI guards) in a single reviewable PR. The remaining delta to <90 requires
bulk file moves across cross-reference boundaries — a second sweep that multiplies
the review burden of the first. Splitting it avoids a single PR touching 80+
files.

## 3. Scope sketch

- Move all `agent-*.md` into `shared/agents/`.
- Move `state-schema.md`, `state-schema-fields.md`, `state-transitions.md`,
  `sprint-state-schema.md` into `shared/state/`.
- Move feature docs (living-specifications, spec-inference, performance-regression,
  accessibility-automation, i18n-validation, etc.) into `shared/features/`.
- Regenerate `shared/README.md` with deeper groupings.
- Update every cross-reference (full repo sweep).
- Update the CI anchor-existence check and the 600L ceiling rule to recurse into
  subdirs.

## 4. Success criteria

- [ ] `ls shared/ | wc -l` ≤ 90.
- [ ] All CI checks green (freshness, ADR, framework-count, 600L, anchors, lychee).
- [ ] `shared/README.md` reflects the new structure.

## 5. Out of scope

- Any content changes. Pure restructure.
- Deleting files (except possibly replacing `agent-communication.md` with
  `shared/agents/communication.md` after another pass).

## 6. References

- Phase 06 spec (parent)
- Phase 06 plan — `docs/superpowers/plans/2026-04-19-06-documentation-architecture-plan.md`
- W6 audit finding (2026-04-19 A+ audit)
