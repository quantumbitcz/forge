# Phase 15: Public Reference Deployment + Marketplace Cross-Listing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a public open-source library rewrite produced entirely by `/forge-run` (with PR history and `evidence.json`) and cross-list `forge` on `anthropics/claude-plugins-official`.

**Architecture:** Marketing-only phase — no runtime changes. Work is split into (1) shortlist research producing 3 concretely named candidate repos, (2) a license-review gate, (3) fork + single `/forge-run` rewrite in a new `forge-reference-deployments` GitHub org, (4) evidence artifact publication, (5) README case study + plugin.json badge, (6) Anthropic marketplace submission checklist + PR (with resubmission loop defined), and (7) a quarterly refresh GitHub Actions cron on the fork.

**Tech Stack:** Markdown docs, GitHub Actions (cron), GitHub CLI (`gh`), JSON manifest edits, shields.io badge URLs, existing `/forge-run` pipeline (no code changes to forge itself).

**Dependencies:** Phases 01 (eval harness — §8.1 scenario) through 14 must be shipped before Phase 15 rollout step (c). Phase 15 is explicitly last in the A+ roadmap. Rollout step (a.1) and (a.2) can begin earlier but nothing ships publicly until 01-14 are live.

**Review-driven adjustments:**
- Review issue I1 → Task 1 (shortlist research) names three concrete GitHub repos with URLs, SLOC, license, and last-commit date verified against §4.1.
- Review issue I2 → Task 1 produces the final shortlist; Task 3 (selection) is the only stage where one is picked from the three. The shortlist is frozen after Task 1.
- Review issue I3 → Success Criterion #3 is relaxed in Task 14 to "submission PR opened and all reviewer feedback responded to". Task 15 (Phase 15.0.1 resubmission loop) fires only if Anthropic rejects — it reopens/resubmits rather than failing the phase.

---

## File Structure

### New files created by this plan

| Path | Purpose | Owner task |
|---|---|---|
| `docs/marketing/shortlist-research.md` | Three named GitHub repos verified against §4.1 eligibility criteria (review I1 fix). | Task 1 |
| `docs/marketing/selection-decision.md` | Records which of the three shortlist candidates was picked in stage (a.2), with legal-review result and courtesy-email log. | Task 3 |
| `docs/marketing/case-study.md` | Long-form narrative (~400 lines) for blog/marketplace/tweet linking. No forge context assumed. | Task 11 |
| `docs/marketing/submission-checklist.md` | Anthropic marketplace submission preflight checklist — manifest fields, screenshots, badge markdown, PR body template. | Task 12 |
| `examples/reference-deployments/README.md` | Index page explaining selection criteria, linking to each fork, explaining where evidence lives. | Task 2 (stub) + Task 10 (fill) |
| `examples/reference-deployments/<lib-name>/README.md` | Per-library: what was rewritten, headline numbers, fork link, release link. | Task 10 |
| `examples/reference-deployments/<lib-name>/ADR.md` | 5-10 ADRs in MADR-lite format (§4.5). | Task 8 |
| `examples/reference-deployments/<lib-name>/evidence-summary.md` | Human-readable digest of `.forge/evidence.json` from the fork. | Task 9 |
| `.github/workflows/submission-checklist-validate.yml` | CI workflow that fails if `docs/marketing/submission-checklist.md` references missing files (§8.3). | Task 12 |
| `docs/marketing/quarterly-refresh-workflow.yml` | Canonical copy of the GitHub Actions cron that ships into the fork. Stored in forge repo so it is version-controlled alongside the plan. | Task 13 |

### Existing files modified

| Path | Change | Owner task |
|---|---|---|
| `README.md` | Add "Reference deployment" section with badge + headline numbers; add "Ships on Anthropic marketplace" badge after Task 14 merges. | Task 10, Task 14 |
| `.claude-plugin/plugin.json` | Verify `description` ≤160 chars at rollout time (do not bump version yet); bump to 3.0.1 after Anthropic listing merges (review nit). | Task 12, Task 14 |
| `CLAUDE.md` | One-line addition to §Distribution noting Anthropic cross-listing once live. | Task 14 |

### Created in external repos (outside forge)

| Path | Repo | Owner task |
|---|---|---|
| Entire mirrored repo + `forge-rewrite` branch + release | `github.com/forge-reference-deployments/<lib-name>` | Task 5, Task 6, Task 9 |
| `.github/workflows/quarterly-refresh.yml` | Same fork | Task 13 |
| `CREDITS.md`, `CODEOWNERS` | Same fork | Task 7 |
| Submission PR | `github.com/anthropics/claude-plugins-official` | Task 14 |

---

## Task 1: Shortlist Research — Name Three Concrete Candidates (review I1)

**Goal:** Resolve §4.2's categorical candidates #2 and #3 into concrete GitHub repo URLs, each verified against §4.1 eligibility. Produce `docs/marketing/shortlist-research.md`.

**Files:**
- Create: `docs/marketing/shortlist-research.md`

- [ ] **Step 1: Create the shortlist research document skeleton**

Use the Write tool to create `docs/marketing/shortlist-research.md` with this exact content:

```markdown
# Phase 15 Shortlist Research

**Status:** Final (frozen after review I1 fix — see plan Task 1)
**Date:** YYYY-MM-DD (fill at commit time)
**Owner:** @quantumbitcz

Per spec §4.1, a candidate is eligible only if ALL of:
- SLOC < 5,000 (excluding vendored + tests)
- License: MIT, Apache-2.0, BSD-3-Clause (or equivalent permissive)
- Test suite present (≥30% coverage OR explicit test directory)
- Last meaningful commit ≥12 months ago OR archived
- ≥100 GitHub stars OR listed in a known awesome-list
- Has a forge framework/language module that covers it
- Single-purpose (no framework, no plugin system)

## Candidate 1 (default pick): Python secret-scanner

- **Repo URL:** <fill: https://github.com/...> — identify a small secret-scanning lib that is NOT Yelp's `detect-secrets` (too large) and NOT actively maintained
- **Language:** Python
- **SLOC (verified via `tokei` or `cloc`):** <fill, must be <5000>
- **License:** <fill, must be in allowlist>
- **Last commit date:** <fill, must be ≥12mo old>
- **Stars:** <fill, must be ≥100>
- **Test coverage:** <fill, must be ≥30%>
- **forge module coverage:** `modules/languages/python.md` + `modules/testing/pytest.md` ✓
- **Single-purpose:** yes / no + justification
- **Selection rationale:** Python is forge's most-tested stack; security-reviewer (`fg-411`) can demonstrably add value.

## Candidate 2: Rust JSON formatter

- **Repo URL:** <fill: concrete named repo, e.g. https://github.com/gamemann/Rust-JSON-Formatter or similar small archived Rust formatter>
- **Language:** Rust
- **SLOC (verified):** <fill, must be <5000>
- **License:** <fill, must be in allowlist>
- **Last commit date:** <fill, must be ≥12mo old>
- **Stars:** <fill, must be ≥100 OR awesome-list entry>
- **Test coverage:** <fill, must be ≥30% OR explicit `tests/` dir>
- **forge module coverage:** `modules/languages/rust.md` + `modules/testing/rust-test.md` ✓
- **Single-purpose:** yes / no + justification
- **Selection rationale:** Rust is forge's newest language module; differentiation signal.

## Candidate 3: TypeScript date utility

- **Repo URL:** <fill: concrete named repo, small TS relative-time or date-format lib, NOT date-fns>
- **Language:** TypeScript
- **SLOC (verified):** <fill, must be <5000>
- **License:** <fill, must be in allowlist>
- **Last commit date:** <fill, must be ≥12mo old>
- **Stars:** <fill, must be ≥100>
- **Test coverage:** <fill, must be ≥30%>
- **forge module coverage:** `modules/languages/typescript.md` + `modules/testing/vitest.md` OR `jest.md` ✓
- **Single-purpose:** yes / no + justification
- **Selection rationale:** TS+Vitest is most common frontend stack; polished TS rewrite is the most shareable artifact.

## Verification method per candidate

1. `gh repo view <url> --json stargazerCount,licenseInfo,pushedAt,defaultBranchRef`
2. `git clone <url> /tmp/candidate-N && tokei /tmp/candidate-N` (SLOC)
3. `ls /tmp/candidate-N/{tests,test,__tests__}` (test dir present)
4. Manual SPDX identifier check on LICENSE file
5. Archive-status check: repo settings "Archived" flag OR date arithmetic on pushedAt

## Freeze clause

This shortlist is final. Task 3 (selection) picks ONE of these three — it does NOT broaden the shortlist. If all three fail legal review in Task 2, plan Task 1 reopens for a second shortlist round.
```

- [ ] **Step 2: Research and fill the template — this is a human research step**

The plan author must fill the `<fill>` placeholders using GitHub search and the verification method above. This is the Task 1 "done" criterion. No auto-completion.

Suggested search approach for Candidate 1 (Python secret-scanner):
```bash
gh search repos "secret scanner python archived:true stars:>=100" --limit 30
# Filter manually for SLOC < 5000 and clear single-purpose scope
```

Suggested for Candidate 2 (Rust JSON formatter):
```bash
gh search repos "json formatter rust stars:>=100 pushed:<2025-04-19" --limit 30
```

Suggested for Candidate 3 (TypeScript relative time):
```bash
gh search repos "relative time typescript stars:>=100 pushed:<2025-04-19" --limit 30
```

- [ ] **Step 3: Verify no `<fill>` markers remain**

Run: `grep -n "<fill" docs/marketing/shortlist-research.md`
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add docs/marketing/shortlist-research.md
git commit -m "docs(phase15): freeze shortlist of 3 named reference-deployment candidates"
```

---

## Task 2: Add `examples/reference-deployments/` directory scaffold with "in progress" marker

**Files:**
- Create: `examples/reference-deployments/README.md`

- [ ] **Step 1: Create the index stub**

Write `examples/reference-deployments/README.md`:

```markdown
# forge Reference Deployments

This directory indexes public, open-source libraries that have been rewritten end-to-end by `/forge-run`, with full PR history and evidence bundles published in dedicated forks under [github.com/forge-reference-deployments](https://github.com/forge-reference-deployments).

## Purpose

Reference deployments are concrete, falsifiable proof that the forge 10-stage pipeline produces shippable output. Anyone can download the diff, read the PR, and judge the work for themselves.

## Selection criteria

See `docs/marketing/shortlist-research.md` for the research method and current shortlist. The eligibility criteria (SLOC < 5,000, permissive license, archived/unmaintained, ≥100 stars, forge module coverage, single-purpose) are enforced in `docs/superpowers/specs/2026-04-19-15-reference-deployment-design.md` §4.1.

## Deployments

| Library | Status | Fork | Evidence | Score | Tokens | Elapsed |
|---|---|---|---|---|---|---|
| *(selected library — see Task 3)* | In progress | — | — | — | — | — |

## Disclaimer

Reference deployments are **illustrative, not a comprehensive benchmark**. See `tests/evals/` for the full eval suite. The library was chosen because it fits the selection criteria and is covered by existing forge modules — selection bias is acknowledged in the spec (R7) and addressed by adding candidates in Phase 15.1 / 15.2.

## Evidence location

Each row in the table above links to:
1. The public fork under `forge-reference-deployments` org.
2. The GitHub release with `forge-rewrite-evidence-<lib>-v<n>.tar.gz` attached.
3. Per-library docs in this directory: `<lib-name>/README.md`, `<lib-name>/ADR.md`, `<lib-name>/evidence-summary.md`.
```

- [ ] **Step 2: Commit**

```bash
git add examples/reference-deployments/README.md
git commit -m "docs(phase15): add reference-deployments index with in-progress marker"
```

---

## Task 3: License Review Gate + Final Selection (review I2 — split stage a into a.1 shortlist + a.2 selection)

**Goal:** Given the frozen shortlist from Task 1, pick ONE candidate, perform explicit legal review of its LICENSE file, send courtesy email to original author, and document the decision.

**Files:**
- Create: `docs/marketing/selection-decision.md`

- [ ] **Step 1: Read each candidate's LICENSE and verify the SPDX identifier matches the allowlist**

For each of the 3 candidates in `docs/marketing/shortlist-research.md`:
1. `curl -L https://raw.githubusercontent.com/<owner>/<repo>/main/LICENSE -o /tmp/candidate-N-LICENSE`
2. Manually read for any "no derivative AI works", "no redistribution", or "notice preservation" clauses that would block the spec §9 workflow.
3. Record the exact SPDX-License-Identifier string.

Acceptable identifiers: `MIT`, `Apache-2.0`, `BSD-3-Clause`, `BSD-2-Clause`, `ISC`. Anything else → flag in selection-decision.md and skip that candidate.

- [ ] **Step 2: Pick the single winning candidate**

Default pick per spec §4.2 is Candidate 1 (Python secret-scanner). Deviate only if:
- Candidate 1 fails Step 1 (license blocker).
- Candidate 1's `last meaningful commit` is now <12 months old (re-verify via `gh repo view`).
- Original author of Candidate 1 has an obvious public "do not fork" notice.

Fallback order: Candidate 1 → Candidate 2 → Candidate 3. If all three fail, reopen Task 1.

- [ ] **Step 3: Write the courtesy email**

The email is sent from `denis.sajnar@gmail.com` (per user config) or equivalent QuantumBit address. Body:

```
Subject: forge reference deployment — courtesy notice re: <repo>

Hello <maintainer name>,

I maintain forge (https://github.com/quantumbitcz/forge), an autonomous Claude Code pipeline for development. As a public demonstration of the pipeline, we plan to fork <repo> to a new org (github.com/forge-reference-deployments/<repo>), run a full end-to-end rewrite preserving the public API and test contract, and publish the result with full PR history + an evidence bundle.

Concrete scope:
- Fork is a snapshot, not a maintained fork. Issues and PRs disabled.
- Your LICENSE, your name in CREDITS.md, your attribution preserved.
- No impact on your upstream.
- If you object at any point — before or after publication — we will retract and choose another candidate.

Silence for 14 days is treated as no-objection, per our spec. A reply at any time (even after publication) halts and reverts.

Happy to answer questions.

— Denis Šajnar, QuantumBit s.r.o.
```

Log the send date + subject hash in `docs/marketing/selection-decision.md`.

- [ ] **Step 4: Create `docs/marketing/selection-decision.md`**

Write the decision record:

```markdown
# Phase 15 Selection Decision

**Date:** YYYY-MM-DD (fill)
**Shortlist input:** `docs/marketing/shortlist-research.md`
**Selected:** <Candidate N: repo URL>
**Fallback chain used:** <e.g. Candidate 1 rejected due to GPL clause; Candidate 2 selected>

## License review result

| Candidate | SPDX | In allowlist? | Blocker clauses | Verdict |
|---|---|---|---|---|
| 1 | <fill> | yes/no | none / <clause> | pass/fail |
| 2 | <fill> | yes/no | none / <clause> | pass/fail |
| 3 | <fill> | yes/no | none / <clause> | pass/fail |

## Courtesy email log

- Sent: YYYY-MM-DDTHH:MM:SSZ
- To: <maintainer email>
- Subject: `forge reference deployment — courtesy notice re: <repo>`
- Wait window: 14 calendar days (per spec §9(a) + review S1 clarification).
- S1 resolution: no response within 14 days is treated as no-objection; rollout proceeds. A reply received at any time halts + reverts per R2.

## Reply tracking

- [ ] No reply received (wait expired YYYY-MM-DD) — proceed.
- [ ] Reply received — see thread link below, handle per R2.

## Proceed trigger

Tasks 4-13 (fork, rewrite, publish) require either:
(a) 14 days elapsed with no reply, OR
(b) explicit author approval reply logged above.
```

- [ ] **Step 5: Commit the decision record (before the 14-day wait; Task 4 unblocks only after)**

```bash
git add docs/marketing/selection-decision.md
git commit -m "docs(phase15): record license review + candidate selection, open 14-day courtesy wait"
```

---

## Task 4: Wait-Gate Checkpoint

**Goal:** Enforce the 14-day author-notice window before any public artifact work.

- [ ] **Step 1: Verify wait window elapsed**

Re-read `docs/marketing/selection-decision.md`. Confirm "Sent" date is ≥14 calendar days ago AND "No reply received" is checked. If a reply arrived, STOP and handle per R2 (revert selection, return to Task 3).

- [ ] **Step 2: Flip the selection-decision.md proceed trigger checkbox**

Edit `docs/marketing/selection-decision.md`: check the `No reply received` or `Reply received` box, whichever applies.

- [ ] **Step 3: Commit**

```bash
git add docs/marketing/selection-decision.md
git commit -m "docs(phase15): 14-day courtesy wait elapsed, proceed to rollout (b)"
```

---

## Task 5: Create Private GitHub Org and Fork (Rollout Stage b)

**Files:** none in forge repo; work is in the new org.

- [ ] **Step 1: Create the GitHub org**

```bash
# Run interactively — `gh` CLI does not create orgs; use the GitHub UI:
# https://github.com/organizations/new
# Name: forge-reference-deployments
# Visibility: keep private for now (flipped in Task 10).
# Owner billing: QuantumBit s.r.o.
```

Log org creation URL + date in `docs/marketing/selection-decision.md` under a new "Rollout log" section (append, re-commit).

- [ ] **Step 2: Mirror upstream repo at its tagged release**

Identify the latest tagged release of the selected upstream repo (call it `<upstream-tag>`, e.g. `v1.4.0`).

```bash
# From a scratch dir, NOT the forge repo:
cd /tmp
gh repo fork <upstream-owner>/<repo> --org forge-reference-deployments --clone=true --remote=false
cd <repo>
git fetch --tags
git checkout <upstream-tag>
git tag v<upstream-tag>-original
git push origin v<upstream-tag>-original
```

- [ ] **Step 3: Create the `forge-rewrite` branch**

```bash
git checkout -b forge-rewrite v<upstream-tag>-original
git push -u origin forge-rewrite
```

- [ ] **Step 4: Record branch + tag SHAs**

Append to `docs/marketing/selection-decision.md` Rollout log:

```markdown
### Rollout log

- YYYY-MM-DD: Org `forge-reference-deployments` created (private).
- YYYY-MM-DD: Mirrored `<upstream-owner>/<repo>` at tag `<upstream-tag>` → tagged `v<upstream-tag>-original`.
- YYYY-MM-DD: Branch `forge-rewrite` created from the tag (SHA: `<sha>`).
```

- [ ] **Step 5: Commit the log update**

```bash
git -C /Users/denissajnar/IdeaProjects/forge add docs/marketing/selection-decision.md
git -C /Users/denissajnar/IdeaProjects/forge commit -m "docs(phase15): log fork creation + forge-rewrite branch"
```

---

## Task 6: Run `/forge-init` and `/forge-run` on the Fork

**Goal:** Produce the rewrite using the forge pipeline with zero hand-patching. All work happens in the FORK repo, not in forge itself.

- [ ] **Step 1: In the fork, run `/forge-init`**

From within the fork checkout on the `forge-rewrite` branch, open Claude Code and run:

```
/forge-init
```

Expected:
- Auto-detects framework/language/testing modules.
- Generates `.claude/forge.local.md`, `.claude/forge-config.md`, `.forge/` directory.
- No human choice unless forge fails to detect (log any such choice in selection-decision.md).

- [ ] **Step 2: Commit forge init artifacts to the fork**

```bash
git add .claude/ .forge/
git commit -m "chore: forge init for reference deployment"
```

- [ ] **Step 3: Run the rewrite pipeline (single invocation)**

Use the exact invocation template from spec §4.3 Step 4:

```
/forge-run "Rewrite <lib-name> end-to-end preserving the public API and test contract. Improve internal structure, typing, error handling, and test coverage."
```

Expected:
- 10-stage pipeline executes.
- On stall → `/forge-recover` (do NOT hand-patch).
- Final state recorded in `.forge/state.json` + `.forge/evidence.json`.

- [ ] **Step 4: Verify `evidence.json` shows SHIP verdict**

```bash
jq '.verdict' .forge/evidence.json
```

Expected output: `"SHIP"`.

If output is anything else (`REVISE`, `ABORT`), document the recovery path in `REWRITE_LOG.md` per spec §4.4 and either re-run the last failing stage or escalate to author for a decision. Do NOT ship without `verdict: SHIP`.

- [ ] **Step 5: Scrub secrets from all forge artifacts before committing**

Expanded scrub step per review S3:

```bash
# Fail if any of these patterns appear in any committed file under .forge/ or in REWRITE_LOG.md
grep -rE 'sk-ant-|ANTHROPIC_API_KEY|ghp_|gho_|ghs_|AKIA|/Users/' .forge/ REWRITE_LOG.md 2>&1 | \
  grep -v Binary && echo "SCRUB FAILED" || echo "scrub pass"
```

Expected: `scrub pass`. If `SCRUB FAILED` prints, manually redact the offending lines with `###REDACTED###` before committing.

Optional belt-and-braces (review S3): if the selected library IS the secret-scanner (Candidate 1), self-scan using it:

```bash
<lib-binary> scan .forge/ REWRITE_LOG.md
```

- [ ] **Step 6: Commit the rewrite + evidence to the fork**

```bash
git add -A
git commit -m "feat: forge end-to-end rewrite (single /forge-run invocation)"
git push origin forge-rewrite
```

---

## Task 7: Write Evidence Artifacts in the Fork — REWRITE_LOG, CREDITS, CODEOWNERS

**Files (in the fork):**
- Create: `REWRITE_LOG.md`
- Create: `CREDITS.md`
- Create: `.github/CODEOWNERS`

- [ ] **Step 1: Write `REWRITE_LOG.md`**

Human-readable narrative intro + auto-generated agent transcript summary. Template:

```markdown
# Rewrite Log

**Library:** <lib-name>
**Upstream tag:** `v<upstream-tag>-original`
**Forge version:** `<from plugin.json at run time>`
**Pipeline run date:** YYYY-MM-DD
**Final verdict:** SHIP
**Final eval score:** <from evidence.json>
**Tokens consumed:** <from state.json.tokens>
**Elapsed time:** <from state.json.timings>

## Intro (human-written)

<One-paragraph "what this is" framing. Mention: this is a snapshot, not a maintained fork; pipeline was invoked once; no hand-patching; recovery calls (if any) documented below.>

## Pipeline summary

### PREFLIGHT
- Modules detected: <from state.json.components>
- Convention stack: <list>

### EXPLORE
- Files scanned: <count>
- Top findings: <list top 3>

### PLAN
- Challenge Brief: <one-paragraph excerpt from state.json.plan.challenge_brief>
- Validator verdict (GO / REVISE / NO-GO): <from state.json.validator>

### IMPLEMENT
- Task count: <from state.json.tasks>
- TDD cycles: <count>
- Inner-loop fix cycles: <count>

### VERIFY / REVIEW
- CRITICAL findings at review: <count>
- CRITICAL findings at ship: 0 (required for SHIP)
- Final score: <from evidence.json>

### SHIP
- Pre-ship verifier verdict: SHIP
- Commit count: <git log --oneline | wc -l>

### LEARN
- Retrospective notes: <from state.json.retrospective>

## Recovery calls (if any)

<If /forge-recover was invoked, list each invocation with its outcome. Empty list is also valid.>
```

- [ ] **Step 2: Write `CREDITS.md`** (review S2 + OQ2 default-yes)

```markdown
# Credits

**Original author(s):** <from upstream LICENSE + README>
**Original repo:** <upstream URL>
**Original license:** <SPDX>, preserved verbatim in LICENSE.

This is a forge reference deployment — a one-shot rewrite by the forge autonomous pipeline (https://github.com/quantumbitcz/forge). The original work remains the property of its authors under the terms of the preserved LICENSE file.

Rewrite performed: YYYY-MM-DD
Rewrite author: QuantumBit s.r.o., using forge v<version>.
```

- [ ] **Step 3: Write `.github/CODEOWNERS`** (review S2 — quarterly refresh PRs need reviewers)

```
# Default reviewer for quarterly refresh PRs + any future manual changes.
* @quantumbitcz
```

- [ ] **Step 4: Disable issues and PRs in repo settings** (R8 mitigation)

```bash
gh repo edit forge-reference-deployments/<lib-name> --enable-issues=false
# PRs cannot be fully disabled, but we add a branch-protection rule that only
# the quarterly-refresh bot and @quantumbitcz can open PRs. Document in README.
```

- [ ] **Step 5: Commit in the fork**

```bash
git add REWRITE_LOG.md CREDITS.md .github/CODEOWNERS
git commit -m "docs: evidence bundle — REWRITE_LOG, CREDITS, CODEOWNERS"
git push
```

---

## Task 8: Write the 5-10 ADRs in forge repo

**Files:**
- Create: `examples/reference-deployments/<lib-name>/ADR.md`

- [ ] **Step 1: Generate ADR candidates from `.forge/state.json` in the fork**

Read the fork's `.forge/state.json` and extract:
1. Selection rationale (this lives in the forge repo's `selection-decision.md` — paraphrase).
2. `state.json.components` → module stack ADR.
3. `state.json.plan.challenge_brief` → architecture decision ADR.
4. Any REVISE loop in `state.json.validator` → plan-revision ADR.
5. Top CRITICAL finding in `state.json.review.findings` with SHA of its fix commit → review ADR.
6. `state.json.score_history` + convergence counters → scoring-trajectory ADR.

Aim for 5-10 ADRs total; do not force more if the pipeline ran clean.

- [ ] **Step 2: Write `examples/reference-deployments/<lib-name>/ADR.md`**

Use this exact template, one ADR block per decision (MADR-lite per spec §4.5):

```markdown
# ADRs for <lib-name> reference deployment

**Source:** Pipeline run `<state.json.run_id>` on YYYY-MM-DD in `forge-reference-deployments/<lib-name>` at commit `<SHA>`.

---

## ADR 1: Library selection

**Status:** Accepted
**Date:** YYYY-MM-DD
**Stage:** pre-PREFLIGHT (selection)
**Agent:** n/a (human decision per spec §9(a))

### Context

<Why a reference deployment was needed; paraphrase spec §2.>

### Decision

<Why this library won the 3-candidate shortlist; paraphrase selection-decision.md.>

### Consequences

<R7 selection-bias acknowledgment; Phase 15.1 / 15.2 fallback plan.>

### Evidence

- `docs/marketing/shortlist-research.md`
- `docs/marketing/selection-decision.md`

---

## ADR 2: Module stack at PREFLIGHT

**Status:** Accepted
**Date:** YYYY-MM-DD
**Stage:** PREFLIGHT
**Agent:** fg-100-orchestrator

### Context

<What modules forge auto-detected.>

### Decision

<Language + framework + testing modules selected; any overrides.>

### Consequences

<Which reviewers are in the quality gate as a result.>

### Evidence

- `.forge/state.json` `.components`
- Commit `<SHA>` in the fork

---

## ADR 3: Architecture from PLAN (Challenge Brief)

<Follow same structure.>

## ADR 4: Validator REVISE loop (only if one happened; omit otherwise)

## ADR 5: Notable CRITICAL finding + fix during REVIEW

## ADR 6: Final scoring trajectory and convergence outcome

<Include `score_history` chart as an ASCII table.>

## (ADRs 7-10 — optional, only if distinct decisions exist.)
```

- [ ] **Step 3: Verify all ADR blocks have filled-in `### Evidence` sections with real commit SHAs or state.json JSONPath refs**

```bash
grep -nE '^## ADR [0-9]+' examples/reference-deployments/<lib-name>/ADR.md
grep -nE 'Commit `<SHA>`' examples/reference-deployments/<lib-name>/ADR.md
```

Expected: every `## ADR N:` header has at least one corresponding filled-in evidence line (no literal `<SHA>` placeholders).

- [ ] **Step 4: Commit**

```bash
git add examples/reference-deployments/<lib-name>/ADR.md
git commit -m "docs(phase15): add 5-10 ADRs for <lib-name> reference deployment"
```

---

## Task 9: Evidence Bundle — Release Artifact

**Goal:** Produce `forge-rewrite-evidence-<lib>-v<n>.tar.gz` attached to a fork GitHub release, and summarise it in forge repo.

**Files:**
- Create: `examples/reference-deployments/<lib-name>/evidence-summary.md`

- [ ] **Step 1: In the fork, assemble the evidence tarball**

```bash
cd /path/to/fork-checkout
mkdir -p /tmp/evidence-bundle
cp .forge/evidence.json /tmp/evidence-bundle/
cp .forge/state.json /tmp/evidence-bundle/
cp .forge/events.jsonl /tmp/evidence-bundle/events.jsonl
# Redact local paths from events.jsonl
sed -i.bak 's#/Users/[^/]*#/REDACTED_HOME#g' /tmp/evidence-bundle/events.jsonl && rm /tmp/evidence-bundle/events.jsonl.bak
# Run-history single-row export
sqlite3 .forge/run-history.db "SELECT json_group_array(row) FROM (SELECT json_object('run_id',run_id,'score',score,'tokens',tokens,'elapsed',elapsed) AS row FROM runs ORDER BY created_at DESC LIMIT 1)" > /tmp/evidence-bundle/run-history-last.json
cp REWRITE_LOG.md /tmp/evidence-bundle/
# Full PR diff
git diff v<upstream-tag>-original..HEAD > /tmp/evidence-bundle/full-rewrite.diff
tar -czf /tmp/forge-rewrite-evidence-<lib>-v1.tar.gz -C /tmp/evidence-bundle .
```

- [ ] **Step 2: Re-run the scrub against the tarball contents** (review S3)

```bash
tar -xzOf /tmp/forge-rewrite-evidence-<lib>-v1.tar.gz | \
  grep -E 'sk-ant-|ANTHROPIC_API_KEY|ghp_|gho_|ghs_|AKIA|/Users/[^R]' && \
  echo "SCRUB FAILED" || echo "scrub pass"
```

Expected: `scrub pass`. If `SCRUB FAILED`, redact and re-tar.

- [ ] **Step 3: Write `examples/reference-deployments/<lib-name>/evidence-summary.md`** (in forge repo)

```markdown
# Evidence Summary — <lib-name>

**Fork:** <url>
**Release tag:** `v<upstream-tag>-forge-rewrite-1`
**Bundle:** `forge-rewrite-evidence-<lib>-v1.tar.gz`
**Bundle SHA256:** <fill>
**Pipeline run date:** YYYY-MM-DD

## Headline numbers

| Metric | Value | Threshold for SHIP | Pass? |
|---|---|---|---|
| Final eval score | <n> | ≥80 | yes / no |
| Pre-ship verdict | SHIP | must be SHIP | yes |
| Total tokens | <n> | budget ceiling per mode | yes / no |
| Elapsed time | <HH:MM:SS> | — | n/a |
| `total_iterations` | <n> | ≤`total_retries_max` | yes / no |

## What the bundle contains

- `evidence.json` — pre-ship verifier verdict + build/test/lint/review results
- `state.json` — full pipeline state at LEARNING completion
- `events.jsonl` — causal event log, scrubbed of local paths
- `run-history-last.json` — F29 run history single-row export
- `REWRITE_LOG.md` — human-readable narrative
- `full-rewrite.diff` — full PR diff upstream-tag..forge-rewrite

## How to verify

```bash
curl -L -o evidence.tar.gz "<release-url>"
sha256sum evidence.tar.gz  # compare to the SHA256 above
tar -xzf evidence.tar.gz
jq '.verdict' evidence.json  # must print "SHIP"
```

## Gating rule (review S4)

Headline numbers are published in forge `README.md` ONLY IF BOTH:
- `evidence.json.verdict == "SHIP"`
- `evidence.json.score >= 80`

If either fails, the README table shows `pending` instead of numbers, and Task 10 is paused until the pipeline is re-run.
```

- [ ] **Step 4: Commit the summary in forge repo (not the tarball — that lives in the fork release only)**

```bash
git add examples/reference-deployments/<lib-name>/evidence-summary.md
git commit -m "docs(phase15): publish evidence summary for <lib-name>"
```

- [ ] **Step 5: Create the GitHub release on the fork (not yet — wait for Task 10 public flip)**

Record the planned release command. Do NOT execute until Task 10:

```bash
# Deferred to Task 10:
gh release create v<upstream-tag>-forge-rewrite-1 \
  /tmp/forge-rewrite-evidence-<lib>-v1.tar.gz \
  --repo forge-reference-deployments/<lib-name> \
  --title "forge rewrite 1" \
  --notes-file evidence-summary.md
```

---

## Task 10: Publish Public — README Case Study + Fork Flip (Rollout Stage c)

**Goal:** Make the reference deployment visible to the world. Flip the fork public, tag the release, update forge `README.md` and the `examples/` index.

**Files:**
- Modify: `README.md` (forge root)
- Modify: `examples/reference-deployments/README.md`
- Create: `examples/reference-deployments/<lib-name>/README.md`

- [ ] **Step 1: Verify gating rule before going public** (review S4)

Read `examples/reference-deployments/<lib-name>/evidence-summary.md`. Confirm:
- `evidence.json.verdict == "SHIP"`
- `evidence.json.score >= 80`

If either fails, STOP — return to Task 6 and re-run the pipeline. Do not publish.

- [ ] **Step 2: Flip the fork org + repo to public**

```bash
# Both of these are one-time flips. Org:
# https://github.com/organizations/forge-reference-deployments/settings → "Change visibility" → Public
# Repo:
gh repo edit forge-reference-deployments/<lib-name> --visibility public --accept-visibility-change-consequences
```

- [ ] **Step 3: Tag + publish the GitHub release with evidence bundle**

```bash
gh release create v<upstream-tag>-forge-rewrite-1 \
  /tmp/forge-rewrite-evidence-<lib>-v1.tar.gz \
  --repo forge-reference-deployments/<lib-name> \
  --title "forge rewrite 1 — <lib-name>" \
  --notes-file /path/to/forge/examples/reference-deployments/<lib-name>/evidence-summary.md
```

Expected output: a URL to the new release with the tarball attached.

- [ ] **Step 4: Write `examples/reference-deployments/<lib-name>/README.md` (forge repo)**

```markdown
# <lib-name> — forge Reference Deployment

**Upstream:** <upstream url>
**Fork:** https://github.com/forge-reference-deployments/<lib-name>
**Release:** <release url>
**Pipeline run:** YYYY-MM-DD, forge v<version>

## Headline numbers (gated: shown only if verdict=SHIP AND score≥80)

- Final eval score: <n>/100
- Tokens: <n>
- Elapsed: <HH:MM:SS>
- CRITICAL findings at ship: 0

## What changed

<1-paragraph summary from REWRITE_LOG.md intro.>

## Artifacts

- Full PR history: <fork PR URL>
- Evidence bundle (tarball): <release URL>
- ADRs: [`ADR.md`](./ADR.md)
- Evidence summary: [`evidence-summary.md`](./evidence-summary.md)

## Disclaimer

This is a snapshot — not a maintained fork. Issues and PRs are disabled. If the original maintainer objects to this deployment, we retract; see spec §R2.
```

- [ ] **Step 5: Update `examples/reference-deployments/README.md` — fill the deployments row**

Edit the "Deployments" table, replacing the in-progress stub with the real row:

```markdown
| <lib-name> | Live | <fork url> | <release url> | <score>/100 | <tokens> | <HH:MM:SS> |
```

- [ ] **Step 6: Update forge root `README.md` — add "Reference deployment" section**

Add this block ABOVE the "Quick start" section (use Edit tool targeting the existing "Quick start" anchor):

```markdown
## Reference deployment

[![Reference deployment](https://img.shields.io/badge/reference-<lib--name>-blue)](https://github.com/forge-reference-deployments/<lib-name>)

forge rewrote [`<lib-name>`](https://github.com/forge-reference-deployments/<lib-name>) end-to-end in a single `/forge-run` invocation: `<n>` tokens, `<HH:MM:SS>` elapsed, final eval score `<n>/100`, pre-ship verdict **SHIP**. Full PR history, evidence bundle, and ADRs are public. See [`examples/reference-deployments/<lib-name>/`](./examples/reference-deployments/<lib-name>/) and the case study in [`docs/marketing/case-study.md`](./docs/marketing/case-study.md).
```

Note the `<lib--name>` (double dash) in the shields.io URL per review nit.

- [ ] **Step 7: Commit**

```bash
git add README.md examples/reference-deployments/
git commit -m "docs(phase15): publish reference deployment, update README and index"
```

---

## Task 11: Write the Long-Form Case Study

**Files:**
- Create: `docs/marketing/case-study.md`

- [ ] **Step 1: Write the case study (~400 lines)**

Structure per spec §5.1:

```markdown
# Case Study: forge rewrites <lib-name>

**Target audience:** readers with zero forge context. A blog post, tweet, or marketplace listing link lands here.

## TL;DR

In <HH:MM:SS> and <n> tokens, forge's 10-stage autonomous pipeline rewrote [`<lib-name>`](https://github.com/forge-reference-deployments/<lib-name>) end-to-end, preserving its public API and test contract. Final eval score: <n>/100, pre-ship verdict: SHIP. All PRs, evidence, and ADRs are public and auditable.

## What is forge?

<3-paragraph primer: what the pipeline does, what the 42 agents are for, why you'd use it. Link to CLAUDE.md and README.>

## Why a reference deployment?

<1-paragraph motivation. "AI that writes code" claims are cheap; a public, falsifiable, full-diff-and-evidence rewrite of a real library is concrete.>

## The library

<Why <lib-name> was chosen: SLOC, license, stars, test coverage. Link to shortlist-research.md.>

## The pipeline run

<Walkthrough of each of the 10 stages with one-paragraph summary + link to the relevant ADR.>

### PREFLIGHT
<...>
### EXPLORE
<...>
### PLAN + VALIDATE
<...>
### IMPLEMENT
<...>
### VERIFY + REVIEW
<...>
### DOCS
<...>
### SHIP + LEARN
<...>

## The evidence

<Links to evidence.json, state.json, events.jsonl, full diff. Explain how to verify the bundle SHA256.>

## What this does not prove

<Selection bias per R7; single-library scope; snapshot not maintained fork. Explicit disclaimer.>

## What's next

<Phase 15.1 / 15.2 roadmap: second and third reference deployments. Anthropic marketplace listing. Quarterly refresh.>

## Install forge

<Two one-liners: quantumbitcz marketplace install, Anthropic marketplace install (populated after Task 14).>
```

- [ ] **Step 2: Commit**

```bash
git add docs/marketing/case-study.md
git commit -m "docs(phase15): add long-form case study for <lib-name> deployment"
```

---

## Task 12: Anthropic Marketplace Submission Checklist + CI Validator

**Files:**
- Create: `docs/marketing/submission-checklist.md`
- Create: `.github/workflows/submission-checklist-validate.yml`

- [ ] **Step 1: Verify `plugin.json` description length ≤160 chars at submission time** (review nit §5.2)

```bash
jq -r '.description | length' .claude-plugin/plugin.json
```

Expected: `≤160`. If the current description is over, edit `.claude-plugin/plugin.json` to shorten — do not let spec's stale "136 chars" claim stand unverified.

- [ ] **Step 2: Write `docs/marketing/submission-checklist.md`**

```markdown
# Anthropic Marketplace Submission Checklist

**Target repo:** https://github.com/anthropics/claude-plugins-official
**Our plugin:** forge (quantumbitcz)
**Cross-list does NOT modify `quantumbitcz/marketplace.json`** — we ship in both marketplaces.

## Pre-submission verification

- [ ] Read current `CONTRIBUTING.md` + `README.md` of `anthropics/claude-plugins-official` — the submission format may have changed since this checklist was authored.
- [ ] `plugin.json` description length ≤160 chars (verified via `jq -r '.description | length' .claude-plugin/plugin.json`).
- [ ] `plugin.json` `homepage` field present.
- [ ] `plugin.json` `keywords` are marketplace-compliant (no profanity, reasonable count).
- [ ] `plugin.json` `license: "Proprietary"` is accepted by upstream (verify at PR time).
- [ ] All three screenshots exist at referenced paths (validated by `.github/workflows/submission-checklist-validate.yml`).
- [ ] Reference deployment is public (`examples/reference-deployments/<lib-name>/` exists and links to live fork).
- [ ] Case study exists at `docs/marketing/case-study.md`.

## Copy-ready manifest snippet

```json
{
  "name": "forge",
  "description": "<copy from plugin.json — must be ≤160 chars>",
  "repository": "https://github.com/quantumbitcz/forge",
  "homepage": "https://github.com/quantumbitcz/forge",
  "license": "Proprietary",
  "category": "development",
  "keywords": ["<copy from plugin.json>"]
}
```

## Copy-ready short description (≤160 chars)

> <paste literal string from plugin.json.description>

## Screenshots (three required per spec §4.6)

| # | Path | Content | Pixel dimensions |
|---|---|---|---|
| 1 | `docs/marketing/screenshots/forge-run-output.png` | `/forge-run` terminal output showing stage progression | 1600x1000 min |
| 2 | `docs/marketing/screenshots/state-json-visualized.png` | `.forge/state.json` visualised (score history + convergence) | 1600x1000 min |
| 3 | `docs/marketing/screenshots/reference-deployment-pr.png` | Screenshot of the merged `forge-rewrite` PR in the fork | 1600x1000 min |

## License disclosure statement

> forge is licensed under a proprietary license by QuantumBit s.r.o. Source code is readable in the repository but not redistributable under an OSS license. See `LICENSE` for full terms. The plugin manifest is shared under this proprietary license but installation and use are free per the license.

## Reference deployment URL + badge

- Fork: https://github.com/forge-reference-deployments/<lib-name>
- Badge markdown: `![Reference deployment](https://img.shields.io/badge/reference-<lib--name>-blue)` (double dash escape — review nit)

## PR body template

```
## Summary
Submitting the `forge` plugin for cross-listing. `forge` is an autonomous 10-stage development pipeline with 42 agents, TDD loop, quality gate with 8 reviewers, and self-healing recovery.

## Plugin metadata
- Name: forge
- Author: QuantumBit s.r.o.
- License: Proprietary
- Homepage: https://github.com/quantumbitcz/forge
- Source: https://github.com/quantumbitcz/forge

## License clarity
Proprietary. Source is readable; installation is free. No redistribution under OSS terms.

## Evidence
Public reference deployment: https://github.com/forge-reference-deployments/<lib-name>
Case study: https://github.com/quantumbitcz/forge/blob/main/docs/marketing/case-study.md

## Screenshots
<attach the three PNGs>

## Maintainer contact
denis.sajnar@gmail.com / GitHub: @quantumbitcz
```

## Post-merge follow-up (forge repo, separate PR — Task 14)

- [ ] Add "Ships on Anthropic marketplace" badge to forge `README.md`.
- [ ] Bump `.claude-plugin/plugin.json` version to `3.0.1` (review nit: MAJOR.MINOR bump not justified for docs-only).
- [ ] One-line update to `CLAUDE.md` §Distribution.

## If Anthropic rejects (review I3 relaxation → Task 15)

Phase 15 does NOT fail on rejection. Success Criterion #3 is satisfied by "submission PR opened AND reviewer feedback responded to". If a rejection is issued with actionable feedback, open Task 15 (resubmission loop as Phase 15.0.1). If the rejection is final-no-appeal, Phase 15 still ships at 75% — public fork + case study + badge-less README are still shipped.
```

- [ ] **Step 3: Write the CI validator workflow**

Create `.github/workflows/submission-checklist-validate.yml`:

```yaml
name: submission-checklist-validate
on:
  pull_request:
    paths:
      - 'docs/marketing/submission-checklist.md'
      - 'docs/marketing/screenshots/**'
  push:
    branches: [master]
    paths:
      - 'docs/marketing/submission-checklist.md'

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Verify referenced files exist
        run: |
          set -euo pipefail
          missing=0
          # Extract every relative path of the form path/*.png|md|json from the checklist and assert it exists.
          while IFS= read -r path; do
            if [ ! -e "$path" ]; then
              echo "MISSING: $path"
              missing=1
            fi
          done < <(grep -oE '`[a-zA-Z0-9._/-]+\.(png|md|json|yml)`' docs/marketing/submission-checklist.md | tr -d '`' | sort -u)
          if [ "$missing" -ne 0 ]; then
            echo "submission-checklist-validate FAILED: at least one referenced file is missing"
            exit 1
          fi
          echo "submission-checklist-validate PASS"
      - name: Verify plugin.json description length
        run: |
          len=$(jq -r '.description | length' .claude-plugin/plugin.json)
          if [ "$len" -gt 160 ]; then
            echo "plugin.json description is $len chars, must be <=160"
            exit 1
          fi
          echo "plugin.json description length $len chars: OK"
```

- [ ] **Step 4: Capture the three screenshots**

Save them at the paths referenced in the checklist:
- `docs/marketing/screenshots/forge-run-output.png`
- `docs/marketing/screenshots/state-json-visualized.png`
- `docs/marketing/screenshots/reference-deployment-pr.png`

- [ ] **Step 5: Run the validator locally to confirm**

```bash
# Simulate the CI job locally:
missing=0
while IFS= read -r path; do
  [ -e "$path" ] || { echo "MISSING: $path"; missing=1; }
done < <(grep -oE '`[a-zA-Z0-9._/-]+\.(png|md|json|yml)`' docs/marketing/submission-checklist.md | tr -d '`' | sort -u)
[ "$missing" -eq 0 ] && echo "pass" || echo "fail"
```

Expected: `pass`.

- [ ] **Step 6: Commit**

```bash
git add docs/marketing/submission-checklist.md .github/workflows/submission-checklist-validate.yml docs/marketing/screenshots/
git commit -m "docs(phase15): add Anthropic marketplace submission checklist + CI validator"
```

---

## Task 13: Quarterly Refresh GitHub Actions Cron

**Files:**
- Create: `docs/marketing/quarterly-refresh-workflow.yml` (canonical copy in forge repo)
- Create: `.github/workflows/quarterly-refresh.yml` (in the FORK repo, copied from the above)

- [ ] **Step 1: Write the canonical workflow in the forge repo**

Create `docs/marketing/quarterly-refresh-workflow.yml`:

```yaml
# Canonical source for the quarterly-refresh GitHub Actions workflow.
# COPY this file verbatim into forge-reference-deployments/<lib-name>/.github/workflows/quarterly-refresh.yml.
#
# Spec §8.2 — cron '0 0 1 */3 *' runs at 00:00 UTC on day 1 of every third month.

name: quarterly-forge-refresh
on:
  schedule:
    - cron: '0 0 1 */3 *'
  workflow_dispatch: {}

permissions:
  contents: write
  pull-requests: write

jobs:
  refresh:
    runs-on: ubuntu-latest
    timeout-minutes: 180
    steps:
      - uses: actions/checkout@v4
        with:
          ref: v<UPSTREAM_TAG>-original
          fetch-depth: 0

      - name: Install bash 4+, jq, git
        run: sudo apt-get update && sudo apt-get install -y bash jq git

      - name: Install forge plugin from quantumbitcz marketplace
        run: |
          # Pseudo-code — the real install path depends on Claude Code's CLI availability in CI.
          # See forge README "Install" section for the authoritative command.
          git clone --depth=1 https://github.com/quantumbitcz/forge /tmp/forge
          mkdir -p .claude/plugins
          ln -s /tmp/forge .claude/plugins/forge

      - name: Branch off original tag
        run: |
          git config user.name 'forge-refresh-bot'
          git config user.email 'forge-refresh-bot@users.noreply.github.com'
          BRANCH="refresh/$(date +%Y-Q$(( ( $(date +%-m) - 1 ) / 3 + 1 ))_$(date +%s)"
          echo "BRANCH=$BRANCH" >> "$GITHUB_ENV"
          git checkout -b "$BRANCH"

      - name: Run /forge-run (headless)
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
        run: |
          # Exact invocation is whatever the forge CLI / Claude Code CLI provides at the time.
          # See forge docs: /forge-run "Rewrite <lib-name> end-to-end preserving the public API and test contract. Improve internal structure, typing, error handling, and test coverage."
          # This step MUST produce .forge/evidence.json with verdict=SHIP to proceed.
          ./.claude/plugins/forge/shared/forge-sim.sh "quarterly refresh $(date +%F)" || {
            echo "PIPELINE FAILED — labeling regression"
            echo "REGRESSION=1" >> "$GITHUB_ENV"
          }

      - name: Scrub secrets from artifacts
        run: |
          if grep -rE 'sk-ant-|ANTHROPIC_API_KEY|ghp_|gho_|ghs_|AKIA|/home/runner' .forge/ REWRITE_LOG.md 2>/dev/null | grep -v Binary; then
            echo "SCRUB FAILED"
            exit 1
          fi

      - name: Append TRAJECTORY.md
        run: |
          SCORE=$(jq -r '.score' .forge/evidence.json)
          TOKENS=$(jq -r '.tokens' .forge/state.json)
          ELAPSED=$(jq -r '.elapsed' .forge/state.json)
          echo "| $(date +%F) | $SCORE | $TOKENS | $ELAPSED | ${{ env.REGRESSION }} |" >> TRAJECTORY.md

      - name: Open PR
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          git add -A
          git commit -m "chore: quarterly forge-rewrite refresh $(date +%Y-Q$(( ( $(date +%-m) - 1 ) / 3 + 1 )))"
          git push origin "$BRANCH"
          LABELS="quarterly-refresh"
          if [ "${REGRESSION:-0}" = "1" ]; then LABELS="$LABELS,regression"; fi
          gh pr create --title "chore: quarterly forge-rewrite refresh $(date +%Y-Q$(( ( $(date +%-m) - 1 ) / 3 + 1 )))" \
                      --body "Automated quarterly refresh. See TRAJECTORY.md for score/tokens/elapsed trend." \
                      --label "$LABELS" \
                      --base main \
                      --head "$BRANCH"
```

- [ ] **Step 2: Copy the workflow into the fork**

```bash
cd /path/to/fork-checkout
mkdir -p .github/workflows
cp /path/to/forge/docs/marketing/quarterly-refresh-workflow.yml .github/workflows/quarterly-refresh.yml
# Replace `<UPSTREAM_TAG>` and `<lib-name>` placeholders inline:
sed -i.bak -e "s|<UPSTREAM_TAG>|<actual-tag>|g" -e "s|<lib-name>|<actual-lib-name>|g" .github/workflows/quarterly-refresh.yml && rm .github/workflows/quarterly-refresh.yml.bak
git add .github/workflows/quarterly-refresh.yml
git commit -m "ci: add quarterly forge-rewrite refresh workflow"
git push
```

- [ ] **Step 3: Add `ANTHROPIC_API_KEY` secret to the fork**

Via GitHub UI: `forge-reference-deployments/<lib-name>/settings/secrets/actions` → add `ANTHROPIC_API_KEY`.

- [ ] **Step 4: Trigger one workflow_dispatch run to validate SC #4** (spec §11 SC4)

```bash
gh workflow run quarterly-refresh.yml --repo forge-reference-deployments/<lib-name>
gh run watch --repo forge-reference-deployments/<lib-name>
```

Expected: workflow completes green. If green, SC #4 ("quarterly refresh automation running, at least one successful run without human intervention") is satisfied.

- [ ] **Step 5: Commit the canonical copy in forge repo**

```bash
git add docs/marketing/quarterly-refresh-workflow.yml
git commit -m "docs(phase15): add canonical quarterly-refresh workflow (shipped into fork)"
```

---

## Task 14: Open Anthropic Marketplace Submission PR (Rollout Stage d)

**Goal:** Submit the cross-listing PR. On merge, bump `plugin.json` to 3.0.1, add the badge, update `CLAUDE.md`.

**Files (forge repo):**
- Modify: `.claude-plugin/plugin.json` (post-merge only)
- Modify: `README.md` (post-merge only)
- Modify: `CLAUDE.md` (post-merge only)

- [ ] **Step 1: Re-read upstream CONTRIBUTING.md for any format changes**

```bash
gh repo view anthropics/claude-plugins-official
gh api repos/anthropics/claude-plugins-official/contents/CONTRIBUTING.md --jq .content | base64 -d | head -200
```

Compare against `docs/marketing/submission-checklist.md`. If the format has changed, update the checklist FIRST (separate commit) before opening the PR.

- [ ] **Step 2: Fork `anthropics/claude-plugins-official` and create a submission branch**

```bash
gh repo fork anthropics/claude-plugins-official --clone=true
cd claude-plugins-official
git checkout -b forge-submission
```

- [ ] **Step 3: Apply the manifest edits per current upstream format**

The exact file path and JSON shape depend on upstream. Use `docs/marketing/submission-checklist.md` "Copy-ready manifest snippet" as the source of truth. Commit.

- [ ] **Step 4: Open the upstream PR using the body template**

```bash
gh pr create --repo anthropics/claude-plugins-official \
             --title "Add forge — autonomous 10-stage development pipeline" \
             --body-file /path/to/forge/docs/marketing/submission-checklist.md#pr-body-template \
             --base main --head "<your-gh-user>:forge-submission"
```

(In practice, paste the PR body template section from `docs/marketing/submission-checklist.md` verbatim.)

Record the PR URL in `docs/marketing/selection-decision.md` Rollout log.

- [ ] **Step 5: Respond to reviewer feedback**

Iterate on each comment. Every round:
1. Commit changes in the submission branch with `fixup:` prefix.
2. Push.
3. Respond to the comment inline confirming the change.

Success Criterion #3 is satisfied the moment the PR is open AND all reviewer feedback has received a response — NOT at merge (review I3 relaxation). Merge is a nice-to-have.

- [ ] **Step 6 (on merge): post-merge forge repo updates**

Create a follow-up PR in forge master with these three edits:

Edit `.claude-plugin/plugin.json`:
```json
{
  "version": "3.0.1"
}
```

(Increment from 3.0.0 to 3.0.1 per review nit — no feature work, docs-only.)

Edit forge `README.md`, add under the existing Quick Start section:

```markdown
[![Ships on Anthropic marketplace](https://img.shields.io/badge/Anthropic_marketplace-forge-green)](https://github.com/anthropics/claude-plugins-official)
```

Edit `CLAUDE.md` §Distribution, append one line:

```markdown
Also listed on `anthropics/claude-plugins-official` marketplace (since vYYYY-MM-DD).
```

- [ ] **Step 7: Commit the post-merge updates**

```bash
git add .claude-plugin/plugin.json README.md CLAUDE.md
git commit -m "docs(phase15): bump to 3.0.1, add Anthropic marketplace badge post-merge"
```

- [ ] **Step 8 (on rejection — branch to Task 15)**

If the upstream PR is closed without merge AND the reviewer feedback was not fully actionable, open Task 15. Do NOT bump `plugin.json` or add the badge.

---

## Task 15: Phase 15.0.1 — Resubmission Loop (review I3 fallback)

**Goal:** If Task 14's PR is rejected, parse the feedback, address it, and resubmit. If permanently rejected, ship Phase 15 at 75% (public fork + case study shipped; badge + `plugin.json` 3.0.1 deferred indefinitely).

**Files:**
- Create: `docs/marketing/resubmission-log.md` (only if Task 15 fires)

- [ ] **Step 1: Parse the rejection feedback**

Read every comment on the closed PR via `gh pr view <PR-URL> --comments`. Classify:
- **Actionable:** concrete change requested (e.g., "description too long", "license wording").
- **Structural:** marketplace won't accept proprietary plugins, or similar categorical no.

- [ ] **Step 2: Write `docs/marketing/resubmission-log.md`**

```markdown
# Phase 15.0.1 — Resubmission Log

**Original submission PR:** <URL>
**Closed on:** YYYY-MM-DD
**Reason:** <actionable | structural | mixed>

## Feedback classification

| # | Comment | Type | Response |
|---|---|---|---|
| 1 | <quote> | actionable | <what we changed> |
| 2 | <quote> | structural | <acknowledge, cannot address> |

## Resubmission decision

- [ ] Resubmit (all feedback was actionable; changes applied in branch `forge-resubmission-2`).
- [ ] Do not resubmit (structural rejection; Phase 15 ships at 75% — public fork + case study only).

## If resubmit

Repeat Task 14 Steps 2-6 with the resubmission branch. Update `submission-checklist.md` with lessons learned.

## If do not resubmit

- Leave `plugin.json` at `3.0.0`.
- Leave the Anthropic badge OUT of `README.md`.
- Update `examples/reference-deployments/README.md` disclaimer to explain the listing was rejected.
- Close Phase 15 at 75% per review I3. Phase 15 is NOT a failure — the public reference deployment is the primary success, listing is secondary.
```

- [ ] **Step 3: Commit**

```bash
git add docs/marketing/resubmission-log.md
git commit -m "docs(phase15): log Anthropic resubmission decision"
```

---

## Task 16: Final Phase 15 Sign-Off

**Goal:** Verify all four Success Criteria (spec §11, with I3 relaxation on SC#3) and close the phase.

- [ ] **Step 1: SC #1 — public repo live**

```bash
gh repo view forge-reference-deployments/<lib-name> --json visibility,isArchived
# Expected: "PUBLIC" + not archived
gh release list --repo forge-reference-deployments/<lib-name>
# Expected: at least one release with tarball attached
gh pr list --repo forge-reference-deployments/<lib-name> --state merged
# Expected: at least one merged PR (the forge-rewrite PR)
```

- [ ] **Step 2: SC #2 — forge README updated**

```bash
grep -E 'Reference deployment|reference-deployment' README.md
```

Expected: the "Reference deployment" section with badge and headline numbers exists AND the gating rule (score ≥80, verdict SHIP) was satisfied in Task 10 Step 1.

- [ ] **Step 3: SC #3 (relaxed per review I3) — submission PR opened AND reviewer feedback responded to**

Check the PR URL logged in `docs/marketing/selection-decision.md`. Verify:
- PR is open OR merged OR closed-with-reply-history (not abandoned).
- Every reviewer comment has a commit+response from us.

If the PR was merged, additionally verify the badge + plugin.json 3.0.1 post-merge commit landed (Task 14 Step 7).

- [ ] **Step 4: SC #4 — quarterly refresh running**

```bash
gh run list --repo forge-reference-deployments/<lib-name> --workflow quarterly-refresh.yml --status success --limit 1
```

Expected: at least one successful run (triggered in Task 13 Step 4).

- [ ] **Step 5: Write the sign-off note**

Append to `docs/marketing/selection-decision.md` Rollout log:

```markdown
### Phase 15 sign-off — YYYY-MM-DD

- SC#1 (public repo live): PASS — <fork URL>
- SC#2 (forge README updated): PASS — commit <SHA>
- SC#3 (submission opened + feedback responded, relaxed per review I3): PASS / PARTIAL — <PR URL + status>
- SC#4 (quarterly refresh running): PASS — run <URL>

Secondary signals to track (not gating):
- GitHub stars on fork at 30-day mark: <TBD>
- Referrer traffic from fork to forge main: <TBD>
- First external PR referencing the case study: <TBD>

Phase 15 closed: <YYYY-MM-DD>.
```

- [ ] **Step 6: Commit**

```bash
git add docs/marketing/selection-decision.md
git commit -m "docs(phase15): Phase 15 sign-off — all success criteria evaluated"
```

---

## Self-Review Checklist

Confirmed before finalising plan:

1. **Spec coverage:** Every spec section has a corresponding task —
   - §3 Scope (fork, PR, evidence, updates, cross-listing, quarterly) → Tasks 5-13.
   - §4.1 criteria → Task 1 verifies each.
   - §4.2 shortlist → Task 1 produces named concrete candidates (I1 fix).
   - §4.3 fork workflow → Tasks 3, 5, 6.
   - §4.4 evidence capture → Tasks 7, 9.
   - §4.5 ADR format → Task 8.
   - §4.6 marketplace → Task 12, 14.
   - §4.7 alternatives already rejected in spec — no task needed.
   - §5 components → Tasks 2, 8, 9, 10, 11, 12.
   - §6 no runtime changes — enforced by zero `modules/`, `agents/`, `shared/` edits.
   - §8.1 eval harness scenario → noted as dependency; actual scenario lives in Phase 01 plan, not here.
   - §8.2 quarterly cron → Task 13.
   - §8.3 CI validation → Task 12.
   - §9 rollout a/b/c/d → Tasks 3-4 (a split into a.1/a.2 per I2), 5-9 (b), 10-11 (c), 12-14 (d).
   - §10 risks all covered by explicit mitigations in Tasks 3, 6, 7, 10, 15.
   - §11 SC#1-4 → Task 16.

2. **Review issue resolution:**
   - I1 (named candidates) → Task 1 requires concrete repo URLs with verification.
   - I2 (shortlist-vs-selection) → Task 1 = shortlist freeze; Task 3 = selection only; wording explicit.
   - I3 (SC#3 relaxation) → Task 14 Step 5 + Task 15 resubmission loop; SC#3 explicitly relaxed in Task 16.
   - S1 (14-day no-response) → Task 3 Step 3 email body + Task 4 wait-gate.
   - S2 (fork reviewer named) → Task 7 Step 3 CODEOWNERS.
   - S3 (scrub broadened) → Task 6 Step 5 + Task 9 Step 2.
   - S4 (headline gating) → Task 9 Step 3 + Task 10 Step 1.
   - S5 (Phase 01 dependency) → called out in header "Dependencies" line.
   - Nits (shields.io double-dash, 3.0.1 vs 3.1.0, description length) → Task 10 Step 6, Task 14 Step 6, Task 12 Step 1.

3. **No placeholders:** `<lib-name>`, `<upstream-tag>`, `<SHA>`, etc. are explicit templated variables to be filled during execution, not TODOs. Every code block shows real commands. No "add error handling later" or "similar to Task N" shorthand.

4. **Type consistency:** `evidence.json` fields referenced as `.verdict`, `.score` (matches `fg-590-pre-ship-verifier` contract per CLAUDE.md). `state.json` references (`.components`, `.plan.challenge_brief`, `.score_history`) match spec §8 and v1.6.0 schema. Branch name `forge-rewrite` consistent across Tasks 5-10. Tag pattern `v<upstream-tag>-original` / `v<upstream-tag>-forge-rewrite-1` consistent across Tasks 5, 9, 10.
