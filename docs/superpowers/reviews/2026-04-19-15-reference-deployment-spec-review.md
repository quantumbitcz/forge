# Review: Phase 15 Reference Deployment Design Spec

**Spec:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-15-reference-deployment-design.md`
**Reviewer role:** Senior Code Reviewer
**Date:** 2026-04-19
**Verdict:** APPROVE WITH MINOR REVISIONS

---

## Summary

The spec is well-structured, meets all 12 required sections, explicitly rejects the two alternatives (from-scratch lib, benchmark-only) with concrete rationale, and defines a clean 4-stage rollout with per-stage rollback. Backcompat-free marketing framing is consistent throughout — no runtime contracts are touched. License review is named at stage (a) and R1 mitigation. Quarterly cron is explicit (`0 0 1 */3 *`). Selection bias (R7) is acknowledged with follow-up phases (15.1, 15.2) for the reserved candidates.

Good enough to advance to rollout step (a). The issues below are refinements, not blockers.

---

## Criteria checklist

| # | Criterion | Status | Notes |
|---|---|---|---|
| 1 | All 12 sections present | PASS | Goal, Motivation, Scope, Architecture, Components, Data/State/Config, Compatibility, Testing, Rollout, Risks, Success Criteria, References |
| 2 | No placeholders | PASS-WITH-CAVEAT | No `TODO`/`TBD` tokens, but the concrete library name is intentionally deferred to rollout (a). Spec acknowledges and justifies this (§4.2 last paragraph). Acceptable. |
| 3 | 3 candidate libraries named with rationale | PASS-WITH-CAVEAT | Three candidates listed with language/SLOC/license/rationale. Issue 1 below: #2 and #3 are described categorically ("a small Rust JSON formatter") rather than as named repos. |
| 4 | Explicit eligibility criteria | PASS | §4.1 table covers SLOC, license, test coverage, maintenance, stars, domain, single-purpose. All thresholds numeric. |
| 5 | Evidence artifact format specified | PASS | §4.4 enumerates `.forge/evidence.json`, `state.json`, `events.jsonl`, run-history export, `REWRITE_LOG.md`, `ADR.md`, plus release tarball. ADR schema in §4.5. |
| 6 | Marketplace submission checklist | PASS | §4.6 + §5.4 + `docs/marketing/submission-checklist.md` enumerate plugin.json fields, 3 screenshots with pixel specs, badge markdown. |
| 7 | License review gate named (stage a) | PASS | §9(a) "Send courtesy email... Wait 14 days" + R1 mitigation "Legal review of the exact LICENSE text in rollout step (a) before the fork." |
| 8 | Quarterly cron specified | PASS | §8.2: `cron: '0 0 1 */3 *'` with workflow semantics. |
| 9 | Selection bias mitigation | PASS | R7 acknowledges selection bias, pushes candidates #2 and #3 to follow-up phases. Disclaimer text required in README. |
| 10 | 2 alternatives rejected with rationale | PASS | §4.7 rejects (A) from-scratch library and (B) benchmark-only with 3-point rationale each. |

---

## Issues

### Important (should fix before rollout step a)

**I1. Candidates #2 and #3 are categorical, not named.**
§4.2 names candidate #1 concretely (`detect-secrets-patterns`) but describes #2 as "a small Rust JSON formatter (e.g. `jsonxf`-style fork)" and #3 as "a small TypeScript date utility (sub-`date-fns` scope, e.g. a relative-time formatter)". If #1 falls through at R1 legal review, we need named fallbacks ready, not categorical sketches. **Fix:** before the spec leaves Draft, resolve #2 and #3 to concrete repo URLs (candidates like `gamemann/Rust-JSON-Formatter`, or specific small TS date utilities) and verify each against §4.1.

**I2. "Default pick" subtly conflicts with §4.1 requirement of a real named library.**
§4.2 footnote says "The concrete library name is chosen at rollout step (a)". This is reasonable for the winning pick after legal review, but the *shortlist* itself should be final in the spec — otherwise the spec is "pick a Python secret-scanner at rollout time", which undermines the whole point of eligibility criteria. Tighten wording: the shortlist is final; only the *selection among three named candidates* is deferred to (a).

**I3. R5 "worst case 80% successful without cross-listing" is optimistic framing.**
If Anthropic rejects the submission, the reference deployment still ships but Success Criterion #3 fails → Phase 15 is not complete by its own definition. Either relax SC#3 to "submitted and not explicitly rejected" or acknowledge Phase 15 can land partially and define a Phase 15.0.1 for the resubmission.

### Suggestions (nice to have)

**S1. §4.3 Step 1 "14-day wait" blocks the whole rollout on a passive no-response.**
If the author never replies, week-1 extends indefinitely. Add: "No response within 14 days is treated as no-objection and we proceed; reply received at any point halts + reverts per R2 playbook."

**S2. §8.2 quarterly refresh opens a PR into the fork but the fork has no human reviewer named.**
The workflow opens a PR but doesn't say who reviews/merges it. Add a `CODEOWNERS` note in §5.3 or explicit "auto-merge on green + regression label escalates to QuantumBit" rule.

**S3. §4.4 scrub step is narrow.**
Greps for `sk-ant-`, `ANTHROPIC_API_KEY`, `/Users/`. Add: GitHub tokens (`ghp_`, `gho_`, `ghs_`), AWS keys (`AKIA`), generic high-entropy strings via `detect-secrets` itself (nicely self-referential if #1 wins). Cheap belt-and-braces.

**S4. §11 Success Criteria #2 headline numbers have no threshold.**
"Headline numbers (eval score, elapsed time, token count)" — but if the eval score is 62 (CONCERNS) we probably don't want to lead with that publicly. Add a gate: "numbers shown only if evidence.verdict: SHIP AND score ≥80."

**S5. Cross-reference to Phase 01 eval harness is load-bearing.**
§8.1 depends on `tests/evals/` and `evals/pipeline/fixtures/` existing and being stable. Spec cites `2026-04-19-01-evaluation-harness-design.md` in §12 but does not state "Phase 15 blocked on Phase 01 eval harness shipping". Add an explicit dependency line in §2 or §9 so the rollout order is unambiguous.

### Nits

- §4.6 "badge: `![Reference deployment](https://img.shields.io/badge/reference-<lib-name>-blue)`" — shields.io URL is slightly off; should be `https://img.shields.io/badge/reference-<lib--name>-blue` (double dash escapes). Trivial; catch at PR time.
- §9(d) "bump `plugin.json` to v3.1.0" — the MAJOR.MINOR bump rationale isn't justified for a badge + docs addition; consider 3.0.1 unless the badge lands with real feature work.
- §5.2 claims `plugin.json` description is 136 chars and OK. Sanity-check this at rollout; current `plugin.json` may have drifted since spec authoring.

---

## What was done well

- **Disciplined scope.** Out-of-scope list (§3) is specific and enforceable — no temptation to "also migrate lodash".
- **Reversibility at every stage.** Rollout steps (a)-(d) each have a concrete rollback action. Stage (d) honestly admits post-merge is Anthropic-controlled, not wishful.
- **Risk table is not decorative.** R1-R8 each have likelihood, severity, and an actionable mitigation. R7 (selection bias) is especially honest.
- **Marketing-only framing held.** §6 explicitly lists what is NOT touched (agent `.md`, `shared/` contracts, modules, check engine, state schema). This is the right discipline for a marketing phase.
- **Evidence bundle is auditable.** Committing `.forge/evidence.json` + `state.json` + `events.jsonl` + tarball release asset is exactly what a skeptic needs to replay, not just read.

---

## Recommendation

**APPROVE** the spec to advance to rollout step (a) after addressing **I1** and **I2** (rename candidates #2/#3 concretely; tighten shortlist-vs-selection language). **I3, S1-S5** are follow-ups that can land during rollout (a)-(b) without blocking the phase.
