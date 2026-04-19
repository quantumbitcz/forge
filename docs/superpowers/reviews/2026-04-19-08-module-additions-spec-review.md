# Phase 08 Spec Review — Module Additions (Flask, Laravel, Rails, Swift)

**Spec:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-08-module-additions-design.md`
**Reviewer:** Senior Code Reviewer
**Date:** 2026-04-19
**Verdict:** APPROVE WITH MINOR REVISIONS

---

## 1. Section coverage (12 required)

All 12 sections present and non-trivial: Goal, Motivation, Scope, Architecture, Components, Data/State/Config, Compatibility, Testing Strategy, Rollout, Risks/Open Questions, Success Criteria, References. PASS.

## 2. Placeholder scan

No `TBD`, `TODO`, `FIXME`, `<placeholder>`, `XXX`, or `???` tokens found. Version strings concrete (Flask 3.0.x, Laravel 11.x, Rails 7.2, Swift 5.9+). PASS.

## 3. Per-framework file inventory exhaustiveness

| Required artifact | Flask | Laravel | Rails |
|---|---|---|---|
| `conventions.md` | yes (§5.1 #1) | yes (§5.2 #1) | yes (§5.3 #1) |
| `local-template.md` | yes (#2) | yes (#2) | yes (#2) |
| `forge-config-template.md` | yes (#3) | yes (#3) | yes (#3) |
| `rules-override.json` | yes (#4) | yes (#4) | yes (#4) |
| `known-deprecations.json` | yes (#5) | yes (#5) | yes (#5) |
| `variants/` | 3 files (#6-8) | 5 files (#6-10) | 4 files (#6-9) |
| `testing/` binding | `pytest.md` (#9) | `phpunit.md` (#11) | `rspec.md` (#10) |
| `shared/learnings/<name>.md` | yes (#10) | yes (#12) | yes (#11) |

All required artifacts enumerated per framework. PASS.

## 4. Deprecation v2 schema conformance

§6.4 example includes all 9 CLAUDE.md-required keys: `pattern`, `replacement`, `package`, `since`, `removed_in`, `applies_from`, `applies_to`, `added`, `addedBy`. Structural test `deprecation-schema.bats` (§8.1) enumerates the same keys. PASS.

**Minor:** spec requires 5-15 entries per CLAUDE.md contract; §5.1 commits "8-10", §5.2 "10-12", §5.3 "10-12" — within bounds but §11 success-criteria line 3 restates "5-15 entries each" (consistent). PASS.

## 5. `MIN_FRAMEWORKS` bump quantified

Explicit: 21 → 24. Present in §3 (line 54), §5.5 (line 206), §6.2 (lines 243-247), §11 (line 428). Four-way consistency. PASS.

## 6. Composition precedence vs CLAUDE.md

CLAUDE.md canonical order: `variant > framework-binding > framework > language > code-quality > generic-layer > testing`. §4.2 example reproduces this exact order for Flask+SQLAlchemy+pytest. §4.2 explicitly states "framework-binding beats generic-testing" — matches CLAUDE.md. PASS.

## 7. Eval scenarios per framework

§8.4 enumerates three scenarios with fixture paths, requirement strings, and pass criteria:
- `evals/fixtures/flask-blog/` — "add draft-post feature with preview URL"
- `evals/fixtures/laravel-shop/` — "add discount-code support to checkout"
- `evals/fixtures/rails-blog/` — "add comment threading with Turbo Stream updates"

Pass criteria: completion, score ≥ 80, convention-appropriate code (FormRequest, strong params, `current_app`), zero deprecation false positives. PASS.

## 8. Swift async/await scope estimate

§4.4 commits ~200 lines across 8 new subsections (~20-30 lines each), file grows to ~315 lines total. §11 criterion 7 tolerates ±20%. Structural test `swift-concurrency-section.bats` asserts header presence. PASS.

## 9. References cite official framework docs

Flask (palletsprojects.com), Laravel (laravel.com), Rails (rubyonrails.org), Swift (docs.swift.org + swift-evolution + Apple WWDC). No third-party blog posts. §10.2 explicitly bans them. PASS.

## 10. CLAUDE.md framework-count drift vs Phase 06

§2 (line 25), §5.6, §10.3 explicitly coordinate with Phase 06. Gate: new `claude-md-framework-count.bats` (§8.2) asserts string matches `MIN_FRAMEWORKS`. Branch logic for either merge order documented. PASS.

---

## Top 3 issues (all minor)

### Issue 1 (Important): File count arithmetic error

§5.7 sums to **33 new + 3 modified = 36 affected**, but:
- Flask enumeration is 10 items
- Laravel enumeration is 12 items
- Rails enumeration is 11 items
- Subtotal new: 10 + 12 + 11 = **33** (matches)
- Modified: Swift (1) + `module-lists.bash` (1) + `CLAUDE.md` (1) = **3** (matches)

Arithmetic is correct. However, §5.1 header says "Flask (14 files)", §5.2 "Laravel (15 files)", §5.3 "Rails (14 files)" — these section headers contradict the actual rows counted (10/12/11) and the §5.7 total. Either update headers to 10/12/11 or add missing rows. Recommendation: fix section headers to match the actual enumeration (10/12/11). Implementer will copy whichever number they see first.

### Issue 2 (Important): Rollout commit plan drops Flask files

§9 PR composition checklist commit 1 says "Flask module (10 files) **+** `shared/learnings/flask.md`". The `shared/learnings/flask.md` is **already inside** the 10-file count per §5.1 row #10. The "+" implies 11 files; the section header said "14" (Issue 1); actual is 10 inclusive. Same ambiguity for Laravel (commit 2) and Rails (commit 3). Recommendation: rewrite as "Flask module (10 files, includes `shared/learnings/flask.md`)" for all three framework commits to prevent double-counting during implementation.

### Issue 3 (Suggestion): Variant calibration open question lacks decision gate

§10.5 defers variant calibration to implementation's "first task" but doesn't specify the **stop criterion** — what makes variant selection final? If implementation discovers a needed 4th Flask variant (e.g., `async-flask`) or 6th Laravel variant (e.g., `octane`), the spec doesn't say whether that extends Phase 08 or defers to a follow-up. Recommendation: add a sentence to §10.5 — "Adding variants at implementation time is allowed if they surface from the validation step; removing variants requires spec amendment." This prevents scope creep while permitting small positive-direction refinements.

---

## What was done well

- **Composition example (§4.2)** is concrete and reproduces CLAUDE.md's canonical order verbatim — removes ambiguity for the implementer.
- **Alternative A (§4.3)** is rejected with specific forward-looking reasoning (second-class tier, partial config, reviewer fallback noise) rather than hand-waving.
- **Deprecation entries (§5.1, §5.2, §5.3)** are **real and verifiable** — `flask.Markup`, `before_filter` → `before_action`, `Str::random` — not invented.
- **Risk register (§10)** addresses real risks (version drift, link rot, Phase 06 coordination, Swift 6 strict-concurrency nuance) with named mitigations, not generic boilerplate.
- **References (§12)** are all stable, versioned, upstream URLs. WWDC session IDs included for Swift.
- **CI coverage (§8)** extends existing harness rather than inventing a new one; named bats files map to CLAUDE.md validation contract.

---

## Final verdict

**APPROVE WITH MINOR REVISIONS.** All 10 review criteria satisfied. Three issues are editorial / clarity, not structural. Fix Issue 1 (section-header numbers) and Issue 2 (commit-plan double-count wording) before implementation starts; Issue 3 is optional. Spec is ready to hand off to Phase 08 planning.

Alignment with CLAUDE.md `§"Adding new modules"` contract: complete. Alignment with project roadmap (A+ P1, audit W7 closure): complete. Safe to merge as single PR per §9.
