# Review — Phase 03 Prompt Injection Hardening Design Spec

**Spec:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-03-prompt-injection-hardening-design.md`
**Reviewer:** Senior Code Reviewer (Claude)
**Date:** 2026-04-19
**Verdict:** APPROVE WITH MINOR REVISIONS

---

## Criteria checklist

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | All 12 sections present | PASS | §1 Goal, §2 Motivation, §3 Scope, §4 Architecture, §5 Components, §6 Data/State/Config, §7 Compatibility, §8 Testing, §9 Rollout, §10 Risks/Open Questions, §11 Success Criteria, §12 References — all present and numbered. |
| 2 | No placeholders | PASS | No `TBD`, `TODO`, `FIXME`, `[...]`, `<placeholder>` markers found. Regex examples are labeled "illustrative" but `shared/prompt-injection-patterns.json` is explicitly deferred to the component file with a concrete sample — acceptable. |
| 3 | Envelope XML format concrete (example shown) | PASS | §4.2 provides a full XML example with all five attributes (`source`, `origin`, `classification`, `hash`, `ingress_ts`), plus nesting and escape rules. Grammar-level details deferred to `shared/untrusted-envelope.md` with ABNF commitment. |
| 4 | Standard header block text quoted verbatim | PASS | §4.3 contains the full 120-word header inside a ```markdown fence``` and §5.3 requires SHA256-match enforcement — meaning the quoted text is the canonical version, not a paraphrase. |
| 5 | Every external data source classified to a tier | PASS WITH NOTE | §4.1 table maps: Context7, wiki, Neo4j project-local → T-S; Linear, Slack, Figma, GitHub (remote), explore-cache, cross-project-learnings → T-L; Playwright, WebFetch, GitHub (non-local repo), deprecation-refresh → T-C; credentials → T-B. NOTE: `plan-cache` is mentioned in §5.5 as a filter consumer but is not explicitly tiered in §4.1 — infer T-L by analogy with explore-cache, but recommend explicit entry. |
| 6 | New scoring categories enumerated (SEC-INJECTION-*) | PASS | §6.3 enumerates six: `SEC-INJECTION-OVERRIDE` (W), `-EXFIL` (C), `-TOOL-MISUSE` (C), `-BLOCKED` (C), `-TRUNCATED` (I), `-DISABLED` (C). Dedup key specified. `SEC-INJECTION-HISTORICAL` appears in §10 as a proposed 7th — not registered in §6.3; minor inconsistency. |
| 7 | Testing includes red-team adversarial scenarios | PASS | §8.3 lists 10 concrete scenarios with asserted outcomes. Hard bar: zero successful injections. Covers wiki, Linear, Playwright, Context7, cache-poisoning, cross-project, size-bomb, nested envelope, role-hijack, and disabled-config regression. |
| 8 | Breaking changes exhaustive | PASS | §7 lists 5 categories: agent-file structure, MCP output format, third-party agent extensions, config-key validation, autonomous-mode UX exception. Each explicitly labeled breaking. |
| 9 | 2 alternatives rejected with rationale | PASS | §4.6 presents (A) Tool-level sandboxing of MCP servers — rejected with three concrete reasons, and (B) Runtime allowlists / schema validation — rejected with concrete reasoning about free-text fields. Rationale strong. |
| 10 | Confirmed-tier + shell = user confirm even in autonomous mode | PASS | §4.1 T-C row, §4.5 data-flow diagram, §7 item 5, and §3 in-scope bullet all state the rule with identical wording: "even in autonomous mode" / "even under `autonomous: true`." Consistent across doc. |

---

## What was done well

- **Tier model is clean and enforced both in config (tightening-only) and at the filter.** The "tier is immutable for the lifetime of that datum" line prevents a whole class of confused-deputy bugs.
- **Quantified threat model.** §2 cites SQMagazine, Anthropic 2026, Cogent Infoworks, OWASP ASI — avoids hand-waving. The concrete Linear-ticket exploit example grounds the motivation in a real scenario.
- **Forensic audit trail.** `.forge/security/injection-events.jsonl` with SHA256 correlation means even Silent-tier events are investigable after the fact. Retention aligned to existing `security.audit_trail.retention_runs` — good reuse.
- **Hard bar for success.** "Zero successful injections across 10 scenarios" is measurable and non-negotiable. This is what separates an eval from a vibe check.
- **`expose_flags_to_agent` trade-off explicitly surfaced** in §10 rather than being a hidden config default. The self-censorship-vs-self-awareness discussion is exactly the kind of second-order reasoning most specs omit.

---

## Issues

### Important (should fix before merge)

1. **`plan-cache` missing from §4.1 tier table.** Listed as a filter consumer in §5.5 but not mapped. Add row to the tier table: `plan-cache` → `logged` (symmetric with explore-cache). Without this the filter's "refuses to deliver unmapped data" rule would fail-closed on every run after plan-reuse. Also worth explicitly tiering the docs-discovery output mentioned in §2.

2. **`SEC-INJECTION-HISTORICAL` appears in §10 but not §6.3.** If it's a real category it needs registry enumeration; if it's speculative ("proposed answer") it should be qualified as "pending Phase 04." Current state risks an undocumented category leaking into the registry.

3. **Size limit unit inconsistency.** §5.1 says "single envelope ≤ 64 KiB; per-prompt aggregate ≤ 256 KiB"; §6.1 config says `max_envelope_bytes: 65536` and `max_aggregate_bytes: 262144`. These are consistent (64×1024 and 256×1024) but the doc uses KiB in prose and raw bytes in YAML. Standardize — either "65536 # 64 KiB" with comment or KiB in both places.

### Suggestions (nice to have)

4. **§5.5 step 6 "append to injection-events.jsonl for every invocation"** should clarify what "silent" logging looks like for a T-S source with zero findings. Skimming the JSONL schema in §5.6, the `findings: []` case is implied but not stated. A single sentence: "For zero-finding T-S evaluations, a minimal record with empty `findings` is still appended" would remove ambiguity.

5. **§6.1 comment "Setting false emits CRITICAL at PREFLIGHT; pipeline halts."** The word FORCED is in allcaps but the halt-on-disable behavior is worth cross-referencing the PREFLIGHT constraints doc (`shared/preflight-constraints.md`) so the rule is canonical in one place.

6. **§8.3 scenario 3 (Playwright tool-coercion)** asserts the "user-declined path cancels task" but §7 item 5 says "autonomous mode occasionally pauses." For autonomous runs with no interactive user, what happens when `AskUserQuestion` fires? The alert hook (`.forge/alerts.json` per CLAUDE.md) should be named explicitly as the fallback. Currently ambiguous.

7. **Token-overhead claim in §5.3** ("~120 tokens × 42 agents = ~5K tokens") undercounts per-run cost since not every run dispatches every agent, but also doesn't include envelope wrapper tokens per datum. §10 Risk 1 caveats this with "output-compression offsets," but a concrete benchmark plan (reference hello-world run measured pre/post) would strengthen Success Criterion 7.

---

## Verdict

**APPROVE WITH MINOR REVISIONS.** All 10 review criteria pass. The three Important issues (plan-cache tiering, SEC-INJECTION-HISTORICAL registration, size-limit consistency) are local, surgical edits — none requires re-architecting. Spec is implementable as-is; revisions can land in the same bulk PR.

Recommend proceeding to implementation planning after Important issues addressed.
