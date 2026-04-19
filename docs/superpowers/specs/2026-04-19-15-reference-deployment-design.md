# Public Reference Deployment + Marketplace Cross-Listing Design Spec

**Phase:** 15 (A+ roadmap)
**Priority:** P2 — marketing / adoption
**Status:** Draft
**Date:** 2026-04-19
**Backwards compatibility:** N/A (marketing-only; no runtime behavior changes)
**Testing policy:** No local test execution. Eval harness runs in CI.

---

## 1. Goal

Ship a public reference deployment — a small open-source library rewritten end-to-end by `/forge-run` with the full PR history and eval trace published — and cross-list `forge` on the `anthropics/claude-plugins-official` marketplace so prospective users can both (a) see proof the 10-stage pipeline works on real code and (b) install forge from the default marketplace surface.

---

## 2. Motivation

Superpowers established the template: in October 2025 the author rewrote `chardet` 7.0.0 end-to-end with the Superpowers methodology and published the result as a public reference deployment ([blog.fsck.com 2025-10-09](https://blog.fsck.com/2025/10/09/superpowers/)). The rewrite is now cited in every "does this actually work?" conversation about Superpowers, and the `anthropics/claude-plugins-official` listing makes the plugin discoverable to every Claude Code user by default.

forge today has neither. The plugin ships only through the `quantumbitcz` marketplace (Git submodule or `/plugin marketplace add quantumbitcz/forge`). Users outside our immediate circle have no way to find it and no public artifact proving the pipeline produces shippable output. Our eval harness (Phase 01) measures internal quality but nobody else can see those numbers.

This phase closes both gaps in one move:

1. **Evidence:** a public PR history + `.forge/evidence.json` + ADR set on a real library is concrete, falsifiable proof — anyone can read the diffs and judge the output themselves.
2. **Discoverability:** cross-listing to `anthropics/claude-plugins-official` puts forge on the default marketplace. Proprietary license does not prevent listing; the Anthropic marketplace accepts proprietary plugins so long as the manifest and license are clear.
3. **Trajectory:** a quarterly refresh on the same library shows forge improving over time — a leading indicator that the 42-agent system is genuinely self-improving, not static.

**URLs:**
- Superpowers chardet precedent: <https://blog.fsck.com/2025/10/09/superpowers/>
- Anthropic marketplace repo: <https://github.com/anthropics/claude-plugins-official>
- Claude Code plugin docs: <https://docs.claude.com/en/docs/claude-code/plugins>

---

## 3. Scope

### In

- **Target selection:** evaluate a shortlist of three candidate libraries against explicit criteria and pick one.
- **Public fork:** create `github.com/forge-reference-deployments/<lib-name>` (new GitHub org owned by QuantumBit).
- **Full pipeline rewrite:** run `/forge-run` end-to-end on the forked library, producing PR history, eval scores, token usage, and elapsed time.
- **Evidence publication:**
  - PR history (one PR per major stage milestone, or one atomic PR with full commit history — decided per library).
  - `.forge/evidence.json` committed to the repo + attached as a GitHub release asset.
  - ADR set (`examples/reference-deployments/<lib-name>/ADR.md`) explaining each major pipeline decision.
- **Forge repo updates:** `examples/reference-deployments/README.md`, root `README.md` link + badge, `docs/marketing/case-study.md`.
- **Marketplace cross-listing:** submission PR to `anthropics/claude-plugins-official` with manifest updates, screenshots, and eval badge.
- **Quarterly refresh cadence:** a cron automation that re-runs the rewrite on the same library every 90 days to track score drift.

### Out

- **Long-term maintenance of the reference library.** We fork, rewrite, publish, walk away. The fork is a snapshot, not a living project. README states this explicitly.
- **Rewriting widely-used libraries.** No `lodash`, `requests`, `serde`, etc. The licensing risk, community backlash risk, and "is this really a fair demo?" risk are all unacceptable. We choose something small, niche, and unmaintained.
- **Multi-library showcase.** One reference deployment now. If the first one lands well, Phase 15.1 can add a second.
- **Runtime changes to forge.** This is a marketing phase. No agent changes, no config changes, no new skills. Only docs, manifest, and a new `examples/` subtree.

---

## 4. Architecture

### 4.1 Target selection criteria

A candidate library is **eligible** only if it meets all of:

| Criterion | Threshold | Why |
|---|---|---|
| Source lines of code | <5,000 SLOC (excluding vendored deps, tests) | Fits in a single `/forge-run` budget; keeps token cost bounded |
| License | MIT, Apache-2.0, BSD-3-Clause, or equivalent permissive | Legal clarity for forking and republishing |
| Test suite present | ≥30% line coverage or explicit test directory | forge needs a signal to optimise against |
| Maintenance status | Last meaningful commit ≥12 months ago OR explicitly archived | Avoids "you rewrote my living project without asking" backlash |
| Public interest | ≥100 GitHub stars OR listed in a known awesome-list | Nobody cares about a demo on a library with 3 stars |
| Domain demonstrability | Has at least one forge framework/language module that covers it | Otherwise we are demoing the bootstrap case, not the pipeline |
| Single-purpose | No framework, no plugin system, no domain-specific runtime | Keeps the rewrite scope tractable and the diff readable |

### 4.2 Candidate shortlist (three)

All three pass the eligibility criteria. Selection tie-break = "what does forge currently do worst that we want to prove we handle?"

| # | Candidate | Language | SLOC | License | Last commit | Why shortlist |
|---|---|---|---|---|---|---|
| 1 | `detect-secrets-patterns` (a small Python secret-scanning library, not Yelp's `detect-secrets`) | Python | ~2,800 | Apache-2.0 | ~18 months | Python + `pytest` is our most-exercised stack; secret-scanning is a domain where `fg-411-security-reviewer` can demonstrably add value; small enough to rewrite twice if needed |
| 2 | A small Rust JSON formatter (e.g. `jsonxf`-style fork) | Rust | ~1,500 | MIT | ~24 months | Rust is our newest-added language module; proving the pipeline works on Rust is more differentiating than another Python demo; small enough to keep the eval cheap |
| 3 | A small TypeScript date utility (sub-`date-fns` scope, e.g. a relative-time formatter) | TypeScript | ~2,200 | MIT | ~14 months | TypeScript + Vitest is the most common frontend stack in our target market; a polished TS rewrite is the most shareable artifact on Twitter/Bluesky |

**Default pick: candidate #1 (Python secret-scanner).** Rationale: (a) our most-tested language path, (b) security-reviewer work is differentiating vs other pipelines, (c) Python eval fixtures already exist from Phase 01. We keep candidates #2 and #3 in reserve for Phase 15.1 / 15.2.

The concrete library name is chosen at rollout step (a) rather than locked in the spec — we verify license, maintenance status, and absence of owner objection before committing.

### 4.3 Fork + rewrite workflow

```
Step 1. Selection
  - Verify all criteria on the chosen candidate.
  - Confirm license compatibility with our "rewrite + republish" intent.
  - Send a courtesy email to the original author describing what we are doing
    and offering to withdraw if they object. Wait 14 days.

Step 2. Fork and fresh branch
  - Create github.com/forge-reference-deployments/<lib-name>
  - Mirror original repo at the tagged release we are rewriting against.
  - Tag as `v<upstream>-original` for diff comparison.
  - Create branch `forge-rewrite` from that tag.

Step 3. /forge-init
  - Run /forge-init on the fork.
  - Let it auto-detect framework/language/testing modules.
  - Commit the generated .claude/, .forge/, and config files.

Step 4. /forge-run
  - Single invocation: /forge-run "Rewrite <lib-name> end-to-end preserving
    the public API and test contract. Improve internal structure, typing,
    error handling, and test coverage."
  - Let the full 10-stage pipeline execute.
  - If it stalls, use /forge-recover. Do NOT hand-patch — the entire point
    is that the pipeline produces the diff.
  - Capture final state.json, evidence.json, and PR.

Step 5. Evidence capture (see 4.4)

Step 6. Publish
  - Push forge-rewrite branch.
  - Open PR from forge-rewrite -> main inside the fork (not upstream).
  - Merge PR. Tag as `v<upstream>-forge-rewrite-1`.
  - Attach evidence.json + state.json + PR.md as release assets.
```

### 4.4 Evidence capture

The evidence bundle is what a skeptical reader downloads. It must be self-contained and reproducible.

**Committed to the fork repo:**

| Path | Source | Purpose |
|---|---|---|
| `.forge/evidence.json` | Produced by `fg-590-pre-ship-verifier` | Machine-readable build/test/lint/review verdicts with `verdict: SHIP` |
| `.forge/state.json` (final) | Pipeline state at LEARNING completion | Score history, convergence counters, findings, tokens |
| `.forge/events.jsonl` (redacted) | Event-sourced pipeline log | Full causal chain for replay |
| `.forge/run-history.db` (single row export as JSON) | Run history store (F29) | Retrospective summary |
| `REWRITE_LOG.md` | Hand-written intro + auto-generated agent transcript summary | Human-readable narrative |
| `ADR.md` | Hand-written ADR set — see 4.5 | Decision rationale |

**GitHub release asset bundle:**

Single tarball `forge-rewrite-evidence-<lib>-v<n>.tar.gz` containing all of the above plus the full PR diff.

**No secrets, no API keys, no proprietary prompts in the bundle.** A scrub step runs before publication (verify: grep for `sk-ant-`, grep for `ANTHROPIC_API_KEY`, grep for local paths under `/Users/`).

### 4.5 ADR format

One `ADR.md` file per reference deployment, using the MADR-lite structure used elsewhere in forge docs:

```markdown
# ADR: <Decision title>

**Status:** Accepted | Superseded | Deprecated
**Date:** YYYY-MM-DD
**Stage:** <pipeline stage that produced this decision>
**Agent:** <fg-NNN-role>

## Context
<Why this decision was needed>

## Decision
<What was decided>

## Consequences
<Trade-offs, follow-ups>

## Evidence
<Links to specific commits, findings, or state.json fields>
```

We target **5-10 ADRs per rewrite**, covering at minimum:
1. Why forge selected this library (selection rationale).
2. Module stack selected at PREFLIGHT (language, framework, testing modules).
3. Architecture decision from PLAN (the Challenge Brief's core trade-off).
4. Any REVISE loop from the validator — why the plan changed.
5. Notable CRITICAL finding + fix during REVIEW.
6. Final scoring trajectory and convergence outcome.

### 4.6 Marketplace cross-listing process

`anthropics/claude-plugins-official` accepts plugin submissions via PR. The submission touches:

1. The marketplace index (format defined by the official repo at PR time).
2. A plugin metadata block (name, description, homepage, license, keywords, category).
3. Screenshots and/or an eval badge referencing the reference-deployment evidence.

**Submission PR contents (draft in our repo first, then upstreamed):**

- Updated `plugin.json` description within the 160-character limit Anthropic enforces.
- Updated `README.md` quick-start that works for users installing from either marketplace.
- Three screenshots: (a) `/forge-run` output, (b) `.forge/state.json` visualized, (c) a merged PR from the reference deployment.
- Badge: `![Reference deployment](https://img.shields.io/badge/reference-<lib-name>-blue)` linking to the fork.
- License clarity: `License: Proprietary (see LICENSE). Plugin source is readable but not redistributable under an OSS license.`

**We do not modify `quantumbitcz/marketplace.json`.** Cross-listing means forge appears in **both** marketplaces. The `quantumbitcz` listing remains the canonical source of truth.

### 4.7 Alternatives considered

**Alternative A — Build a from-scratch library and publish it.**

Pitch: forge bootstraps a brand-new small library (e.g. a new CLI tool) from an empty directory, which showcases `/forge-bootstrap` rather than a rewrite.

Rejected because: (a) there is no baseline to compare against — "forge wrote a library" is less persuasive than "forge took this specific library and demonstrably improved it against its own test suite", (b) greenfield means we pick the easy path and skeptics correctly call it cherry-picked, (c) Superpowers' precedent is specifically a rewrite of `chardet`, not a new library, and readers recognize that pattern.

**Alternative B — Benchmark-only with no public artifact.**

Pitch: run the eval harness from Phase 01 over a public library internally, publish the numeric results (scores, tokens, elapsed) in the README. No fork, no PR history, no ADRs.

Rejected because: (a) numbers without a diff are unfalsifiable — readers cannot audit whether the score is earned, (b) it reinforces the "another AI marketing post" reaction rather than counteracting it, (c) the public fork IS the marketing material — it is what gets shared, not the numbers.

---

## 5. Components

### 5.1 New files

| Path | Purpose | Approx size |
|---|---|---|
| `examples/reference-deployments/README.md` | Index of all reference deployments. Explains selection criteria, links to the fork(s), explains what evidence lives where. | ~150 lines |
| `examples/reference-deployments/<lib-name>/README.md` | Per-library: what was rewritten, headline numbers, link to the fork, link to the evidence release. | ~80 lines |
| `examples/reference-deployments/<lib-name>/ADR.md` | 5-10 ADRs in the format from §4.5. | ~300-500 lines |
| `examples/reference-deployments/<lib-name>/evidence-summary.md` | Human-readable digest of `.forge/evidence.json` (the raw file lives in the fork). | ~60 lines |
| `docs/marketing/case-study.md` | Long-form narrative case study. Intended for linking from blog posts, marketplace listing, tweets. Assumes reader has no forge context. | ~400 lines |
| `docs/marketing/submission-checklist.md` | Pre-flight checklist for the `anthropics/claude-plugins-official` submission PR (see 5.4). | ~120 lines |

### 5.2 Updates to existing files

| Path | Change |
|---|---|
| `README.md` | Add "Reference deployment" section above "Quick start" with badge, one-paragraph summary, and link to `examples/reference-deployments/`. Add "Ships on Anthropic marketplace" badge once listing is live. |
| `.claude-plugin/plugin.json` | Tighten `description` to ≤160 chars (current: 136, OK). Add `homepage` field if not already present. Verify `keywords` are marketplace-compliant. |
| `.claude-plugin/marketplace.json` | No changes — `quantumbitcz` marketplace is unaffected. |
| `CLAUDE.md` | One-line addition to §Distribution noting the Anthropic cross-listing once live. |

### 5.3 New GitHub org + fork repo

- **Org:** `forge-reference-deployments` (owned by QuantumBit s.r.o.).
- **Visibility:** public.
- **First repo:** `forge-reference-deployments/<lib-name>` (mirror of upstream + `forge-rewrite` branch).
- **README pins:** explicit disclaimer "This is a reference deployment, not a maintained fork. Do not depend on this for production."

### 5.4 Anthropic marketplace submission PR (prep doc)

`docs/marketing/submission-checklist.md` contains:

1. Link to current `anthropics/claude-plugins-official` contribution guide (read-only reference; we verify at submission time that the format has not changed).
2. Copy-ready `plugin.json` snippet for the marketplace index.
3. Copy-ready description (≤160 chars).
4. Three screenshot sources + pixel dimensions.
5. License disclosure statement.
6. Reference-deployment URL + badge markdown.
7. PR body template with sections: Summary / Plugin metadata / License / Evidence / Maintainer contact / Screenshots.

The actual PR is opened in rollout step (d), not in this spec.

---

## 6. Data / State / Config

**No runtime changes.** This phase does not touch:

- Any agent `.md` file.
- Any `shared/` contract.
- Any `modules/` module.
- The check engine.
- `state.json` schema.
- `forge-config.md` schema.
- `.forge/` layout.

The only data produced is static (markdown + JSON in the reference-deployment fork). The quarterly refresh automation (§9) writes to `.forge/` during its run on the fork, not in the forge plugin repo.

---

## 7. Compatibility

**None required.** Marketing-only phase. No version bump of the plugin needed to ship the reference deployment; however we may choose to bump `plugin.json` to v3.1.0 when the Anthropic listing goes live, purely so the listing reflects the current feature set. That bump, if taken, is tracked in a separate change.

---

## 8. Testing Strategy

**CI-only. No local test runs.**

### 8.1 Eval harness integration (Phase 01 dependency)

The Phase 01 eval harness (`tests/evals/` and `evals/pipeline/fixtures/`) gains one new scenario: **`reference-deployment-<lib-name>`**. This scenario:

1. Clones `forge-reference-deployments/<lib-name>` at the `v<upstream>-original` tag.
2. Runs the same `/forge-run` invocation used for the published rewrite.
3. Compares the resulting score + token count + elapsed time against the baseline captured at publish time.
4. Reports drift.

The scenario runs in CI on every PR to forge master, gated behind a label (`eval:reference`) because it is expensive. Without the label it is skipped — the baseline drift signal matters, but not on every commit.

### 8.2 Quarterly refresh automation

A scheduled GitHub Actions workflow on `forge-reference-deployments/<lib-name>` runs every 90 days:

```
on:
  schedule:
    - cron: '0 0 1 */3 *'  # 00:00 UTC on day 1 of every third month
```

The workflow:
1. Installs the latest `forge` from the `quantumbitcz` marketplace.
2. Runs the same `/forge-run` invocation against the `v<upstream>-original` tag on a fresh branch.
3. Produces a new evidence bundle.
4. Opens an automated PR into the fork titled `chore: quarterly forge-rewrite refresh YYYY-QN`.
5. Appends the new run to a `TRAJECTORY.md` file showing score/time/token trend over quarters.

If CI finds a regression (score drops, tokens balloon, elapsed >2x baseline), the PR is labeled `regression` and surfaced in the forge `/forge-insights` dashboard via the F29 run history store.

### 8.3 Submission PR testing

The Anthropic marketplace submission PR has its own CI defined by the upstream repo; we do not add tests for it. We do add a `docs/marketing/submission-checklist.md` validation step to our own CI that fails if the checklist references files that do not exist in the repo (e.g. a screenshot path that was renamed).

---

## 9. Rollout

Four staged sub-releases, each independently reversible.

### (a) Select library [week 1]

- Confirm the three shortlist candidates are still eligible against §4.1 criteria.
- Pick one.
- Send courtesy email to original author. Wait 14 days.
- Write `docs/marketing/selection-decision.md` documenting the choice.
- Ship: a single commit to forge master adding `examples/reference-deployments/README.md` listing the chosen library as "in progress".
- Rollback: revert the commit. No public impact.

### (b) Rewrite + publish private [weeks 2-4]

- Create private `forge-reference-deployments` GitHub org (staying private for now).
- Mirror upstream, run `/forge-run`, capture evidence.
- Write ADRs + evidence-summary + README in the fork.
- Internal review by QuantumBit team. Fix issues.
- Ship: org stays private; nothing public yet.
- Rollback: delete the private repo. No public impact.

### (c) Publish public [week 5]

- Flip `forge-reference-deployments` org + repo to public.
- Tag the fork release with evidence bundle attached.
- Update forge root `README.md` to link the fork.
- Add `examples/reference-deployments/<lib-name>/*` docs to forge master.
- Write `docs/marketing/case-study.md`.
- Ship: one PR to forge master with all docs, plus the org flip.
- Rollback: revert the forge PR + flip the org back to private. Link is dead but the fork still exists for future re-publication.

### (d) Submit to Anthropic marketplace [week 6]

- Validate `docs/marketing/submission-checklist.md` against current upstream requirements.
- Open submission PR in `anthropics/claude-plugins-official`.
- Iterate on feedback from Anthropic reviewers.
- On merge: add "Ships on Anthropic marketplace" badge to forge `README.md` + bump `plugin.json` to v3.1.0.
- Ship: merged upstream PR + follow-up forge master PR with the badge.
- Rollback: Anthropic controls the listing; we cannot unilaterally remove it once merged. Pre-submission rollback is trivial (close our PR). Post-merge rollback requires a request to Anthropic maintainers.

---

## 10. Risks / Open Questions

| # | Risk | Likelihood | Severity | Mitigation |
|---|---|---|---|---|
| R1 | Selected library's license is actually restrictive on closer reading (e.g. a clause barring "derivative AI-generated works") | Low | High | Legal review of the exact LICENSE text in rollout step (a) before the fork. Fall back to candidate #2 or #3. |
| R2 | Original author objects to the rewrite after publication | Medium | Medium | Courtesy email in step (a) with 14-day wait. If they object post-publication, we take the fork private and select a new candidate. Public apology + retraction post if needed. |
| R3 | Library is "too easy" — the rewrite is trivial and the demo unconvincing | Medium | Medium | The selection criteria require ≥30% existing test coverage AND ≥100 stars. If the result feels hollow, we extend scope to candidate #2 or #3 before publishing. |
| R4 | Library is "too hard" — forge stalls mid-rewrite and we cannot ship the evidence | Low | High | The <5K SLOC cap keeps scope tractable. If it stalls, we use `/forge-recover` and document the recovery path as part of the evidence — "here is the failure mode and how the pipeline self-healed" is also a persuasive artifact. |
| R5 | Anthropic marketplace rejects the submission (license or description concerns) | Medium | Low | We iterate on feedback. Worst case: the public reference deployment still ships; only the badge does not land. Phase 15 is still 80% successful without cross-listing. |
| R6 | Quarterly refresh reveals a regression (score drops over time) | Low | Medium | This is a feature, not a bug — the whole point of the refresh is to surface regressions. Regressions feed back into the roadmap as follow-up work. |
| R7 | Selection bias: we pick a library forge happens to be good at | High | Medium | Explicit in the README: "Reference deployment is illustrative, not a comprehensive benchmark. See `tests/evals/` for the full eval suite." Add candidate #2 and #3 in follow-up phases to broaden the signal. |
| R8 | Maintainer burden creep — the fork accumulates issues/PRs from external users | Medium | Low | README states unambiguously: "Issues and PRs on this repo are disabled. This is a snapshot, not a maintained fork." Disable issues and PRs in repo settings. |

### Open questions

- **OQ1:** Do we publish the rewrite as a single atomic PR or as a sequence of per-stage PRs? Single atomic is easier to review; per-stage is more pedagogical. **Decision deferred to rollout step (b)** — whoever runs the pipeline decides based on how the state.json history reads.
- **OQ2:** Do we offer the original author co-attribution on the fork? **Default yes** — their name stays in the LICENSE + a `CREDITS.md` in the fork names them as original author. No opt-out from our side.
- **OQ3:** Should the eval-harness scenario (§8.1) run on every PR regardless of label? **Default no** — too expensive. Revisit if eval harness runtime drops below 5 minutes.

---

## 11. Success Criteria

All four must hold at Phase 15 completion:

1. **Public repo live.** `github.com/forge-reference-deployments/<lib-name>` is public, has the merged `forge-rewrite` PR, and has a tagged release with the evidence bundle attached.
2. **Forge README updated.** Root `README.md` shows: (a) reference-deployment badge linking to the fork, (b) headline numbers (eval score, elapsed time, token count) pulled from `.forge/evidence.json`.
3. **Anthropic marketplace listing live.** forge appears in the `anthropics/claude-plugins-official` index and is installable via `/plugin install forge@anthropics` (exact install command depends on the upstream format at submission time).
4. **Quarterly refresh automation running.** The scheduled workflow in the fork has completed at least one successful run without human intervention.

Secondary signals (not gating but tracked):

- GitHub stars on the fork within 30 days of public release.
- Referrer traffic to `forge` main repo from the fork + Anthropic marketplace.
- First external PR / issue on `forge` main repo that references the case study.

---

## 12. References

- Superpowers chardet precedent: <https://blog.fsck.com/2025/10/09/superpowers/>
- Anthropic marketplace repo: <https://github.com/anthropics/claude-plugins-official>
- Claude Code plugin documentation: <https://docs.claude.com/en/docs/claude-code/plugins>
- forge Phase 01 eval harness spec: `docs/superpowers/specs/2026-04-19-01-evaluation-harness-design.md`
- forge Distribution section: `CLAUDE.md` §Distribution
- forge `plugin.json`: `.claude-plugin/plugin.json`
- forge `marketplace.json`: `.claude-plugin/marketplace.json`
- MADR ADR format: <https://adr.github.io/madr/>
- GitHub Actions cron schedule reference: <https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#schedule>
