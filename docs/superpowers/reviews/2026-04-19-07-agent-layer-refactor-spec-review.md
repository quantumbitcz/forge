# Review — Phase 07 Agent Layer Refactor (DESIGN spec)

**Spec:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-07-agent-layer-refactor-design.md`
**Reviewer:** Senior Code Reviewer
**Date:** 2026-04-19
**Verdict:** **APPROVE with minor revisions** (4 Important fixes, 3 Suggestions)

---

## Criterion-by-criterion audit

| # | Criterion | Result | Notes |
|---|---|---|---|
| 1 | All 12 sections | **PASS** | Goal, Motivation, Scope, Architecture, Components, Data/State/Config, Compatibility, Testing, Rollout, Risks, Success Criteria, References — all present and non-trivial. |
| 2 | No placeholders | **PASS** | No `TBD`, `TODO`, `XXX`, `FIXME`, or `<placeholder>` strings anywhere. All counts, file paths, and config keys are concrete. |
| 3 | Agent count math (42 + 5 = 47) | **PASS** | §4.1 shows the arithmetic explicitly. Split (fg-417 → fg-417 + fg-414) correctly counted as +1, not +2. Verified against disk: `ls agents/fg-*.md` = 42 today; post-phase target 47 is consistent. |
| 4 | 12 Tier-4 violations listed | **PASS** | §3.1 item 1 lists exactly 12 files. I cross-checked each against `agents/` — all exist. Tier-4 assignment matches `shared/agent-role-hierarchy.md` (Tier 4 row in CLAUDE.md enumerates the same 12 agents plus the new fg-414). |
| 5 | New-agent frontmatter sketches (name, tools, ui, trigger) | **PASS** | §5.3 has all 5 sketches with `name`, `tools`, `trigger`, and `ui:` block (explicitly omitted for fg-414 per Tier-4 rule). `description`, `model`, `color` also included — exceeds the criterion. |
| 6 | Color assignments cluster-collision-free | **PASS (with one unverified claim)** | §5.4 audits per-cluster: PREFLIGHT gets crimson+magenta, Verify/Test gets coral+navy, Review gets lime. However, the spec lists current PREFLIGHT cluster colors as only cyan/navy/teal/olive — the Review cluster already uses `crimson` and `navy` per the same audit. Cross-cluster reuse is allowed by `shared/agent-colors.md`; the claim holds, but the spec should state that cross-cluster reuse is by design (see Issue I2). |
| 7 | New scoring categories enumerated | **PASS** | §6.1 enumerates 14 categories: 3 I18N-*, 3 MIGRATION-*, 3 RESILIENCE-*, 3 LICENSE-*, 2 OBS-*. Severity caps specified. Existing `I18N-*` affinity re-wire called out explicitly. |
| 8 | fg-205 preservation rationale | **PASS** | §3.2 "Out of scope" documents the rejection with three reasons: adversarial independence is load-bearing, two-writer invariant, validator consumes critic findings. Strong rationale. |
| 9 | fg-506 renumbering rationale | **PASS** | §4.3 and §10 R1 both document the collision with existing `fg-505-build-verifier` and the resolution (renumber migration-verifier to 506). Verified against disk — fg-505-build-verifier.md exists; fg-506 slot is free. |
| 10 | License-policy fail-open risk mitigation | **PARTIAL** | §10 R2 acknowledges fail-open requirement and names a default allow-list (MIT, Apache-2.0, BSD-*, ISC, Unlicense, CC0-1.0). But §6.2 only declares the `policy_file` key — the **fail-open default behavior is not specified in the agent frontmatter or §6 config**. The open question about LGPL-2.1+ is left unresolved. See Issue I1. |

---

## Issues

### Critical
None.

### Important (should fix before implementation starts)

**I1. License-policy fail-open default is acknowledged in R2 but not wired into the config contract.**
§10 R2 says "must fail open (WARNING at most) rather than block shipping" and lists a default allow-list. But §6.2 only specifies the `policy_file` key — there is no explicit config field like `license_reviewer.fail_open_default: true` or an `embedded_allow_list:` structure. Downstream, this means two things are underspecified:

- The severity cap when no policy file exists — is it WARNING (per R2) or suppressed entirely?
- Where the default allow-list lives — inlined in the agent `.md`, in `shared/checks/category-registry.json`, or in a new `shared/license-policy-defaults.json`?

Recommendation: add to §6.2:
```yaml
agents:
  license_reviewer:
    policy_file: .forge/license-policy.json   # optional
    fail_open_when_missing: true              # when true, LICENSE-* capped at WARNING
    embedded_defaults:                         # used iff policy_file absent
      allow: [MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause, ISC, Unlicense, CC0-1.0]
      warn:  [LGPL-2.1+, MPL-2.0]
      deny:  [AGPL-*, SSPL-*, Commons-Clause]
```
This also resolves the open LGPL-2.1+ question by moving it from "R2 open" to "warn by default, project overrides if strict."

**I2. Agent-count arithmetic in §4.2 tier table has a footnote that flags a data inconsistency but does not commit to fixing it in this phase.**
Footnote ¹ says "Hierarchy doc currently lists 43 entries… the extra row is a double-listed `fg-205` placeholder to be removed when regenerating the table." That's a pre-existing defect the audit caught — but the Scope (§3.1) and Rollout (§9) do not include "remove the duplicate fg-205 row from agent-role-hierarchy.md" as an explicit commit. It's implied by "update tier tables" but bisect-sharpness would improve if commit 6 explicitly called out the de-duplication.

Recommendation: amend §9 commit 6 to: "docs regen… including removal of the duplicate fg-205 row in agent-role-hierarchy.md (W7 audit artifact)."

**I3. `trigger:` field semantics are not formally specified.**
§3.1 item 2 gives conditions in prose ("frontend files present + frontend_polish.enabled", "preview URL available") and §5.3 uses expression syntax (`mode == "migration"`, `observability.enabled == true`). But there's no spec of:

- Grammar (is `==` required, or does `mode: migration` work?)
- Namespace (is `mode` a top-level state field? `observability.enabled` — is that `config.observability.enabled` or `state.observability.enabled`?)
- Who evaluates it (orchestrator? a new hook?)
- What `trigger: always` means vs. absence of the field (spec says external agents default to `always`, implying absence == always, but then `trigger: always` is redundant)

Phase 08's dispatch-graph generator depends on parseable triggers. Without a grammar, the generator will either need ad-hoc regex or a convention this spec hasn't set. Recommendation: add a short §6.4 "Trigger expression grammar" with EBNF or a reference to an existing shared doc.

**I4. Testing strategy references eval harness (Phase 01) as a dependency but Phase 07 does not list Phase 01 as a prerequisite.**
§8 item 4 calls for "Eval harness (Phase 01) scenarios — add three fixtures." If Phase 01 has not merged, these fixtures have no harness to run in. The "Phase:" header says "07 of the A+ roadmap" and DESCRIPTION says "Depends on Phase 06 (merged agent docs)" — but the eval scenarios implicitly depend on Phase 01 too.

Recommendation: add to §12 References or a new "Dependencies" subsection: "Eval fixtures require Phase 01 (evaluation harness) to be merged. If Phase 01 is not ready, gate the fixtures behind a `.skip` marker and track in Phase 10 cost regression eval."

### Suggestions (nice-to-have)

**S1.** §6.1 uses JSONC (`// comments`) but `shared/checks/category-registry.json` is strict JSON. Either switch the example to strict JSON or note that comments are for illustration only.

**S2.** §5.3 frontmatter sketches show `model: inherit` — verify this is a supported value in current agent frontmatter parser (most existing agents set specific models). If not, drop it or replace with the current convention.

**S3.** §9 rollout has 8 commits squashed into one merge commit. The squash loses the per-commit granularity that bisect needs — consider either (a) merging with real-commit history (no squash) to keep bisect, or (b) dropping the "so bisect stays sharp" justification since squash defeats it.

---

## What was done well

- **Evidence-grounded motivation:** W7/W8 audit citations, line counts for fg-413 (534) and fg-417 (333), and the tier-table inconsistency footnote demonstrate this spec was written against the actual tree, not from memory.
- **Alternatives section is non-performative:** §4.4 Alt A and Alt B both have specific rejection reasons (400-line cap, stage-mixing, `shared/agent-philosophy.md` "one agent, one job") — not generic "considered and rejected" boilerplate.
- **fg-205 preservation is the right call.** The two-writer invariant (critic writes findings → validator consumes them alongside its 7-perspective output) is exactly the kind of load-bearing separation that looks removable until you delete it. The spec defends this well.
- **Token-budget math in R4** (+5-8% net after fg-413 slim) shows the author considered the cost side, not just the feature side.
- **Color audit is cluster-scoped**, which matches the actual invariant in `shared/agent-colors.md` (intra-cluster uniqueness, not global).
- **No backcompat shim** — consistent with project policy per CLAUDE.md "no backwards-compatibility shims."

---

## Recommendation

**APPROVE to proceed to planning**, conditional on addressing I1 (license fail-open config wiring) and I3 (trigger grammar) before Phase 08 starts consuming the `trigger:` field. I2 and I4 are housekeeping and can be folded into the Phase 07 PR itself.

Phase 06 (merged agent docs) is the stated prerequisite. Once Phase 06 is merged, Phase 07 can proceed.

---

## Files referenced

- `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-07-agent-layer-refactor-design.md` (spec under review)
- `/Users/denissajnar/IdeaProjects/forge/CLAUDE.md` (42-agent roster, Tier-4 definitions)
- `/Users/denissajnar/IdeaProjects/forge/shared/agent-role-hierarchy.md` (tier tables — contains duplicate fg-205 row per footnote ¹)
- `/Users/denissajnar/IdeaProjects/forge/shared/agent-colors.md` (cluster uniqueness invariant)
- `/Users/denissajnar/IdeaProjects/forge/shared/checks/category-registry.json` (category extension target)
- `/Users/denissajnar/IdeaProjects/forge/agents/fg-505-build-verifier.md` (existing; confirms fg-506 renumber is needed)
- `/Users/denissajnar/IdeaProjects/forge/agents/fg-413-frontend-reviewer.md` (slim target)
- `/Users/denissajnar/IdeaProjects/forge/agents/fg-417-dependency-reviewer.md` (split target)
