# Phase 07 — Agent Layer Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the 42-agent population into contract compliance (Tier-4 silent frontmatter, machine-readable `trigger:` on conditional agents) and close four coverage gaps (i18n, migration verification, observability bootstrap, resilience testing) plus a license-compliance split-off, taking the registry to 47 agents with zero dark scoring categories.

**Architecture:** Doc-only plugin changes. Touch agent `.md` frontmatter + bodies, `shared/` reference docs, `shared/checks/category-registry.json`, `forge-config` templates, contract/eval tests, and `CLAUDE.md`. No scripts, no runtime code. Each logical group commits independently so CI bisect stays sharp. No backwards-compatibility shims — consumers update at the same commit (per project policy).

**Tech Stack:** Markdown (agent system prompts), YAML frontmatter, JSON category registry, bats contract tests, YAML eval fixtures.

**Source of truth for tasks:**
- Spec: `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-07-agent-layer-refactor-design.md`
- Review: `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/reviews/2026-04-19-07-agent-layer-refactor-spec-review.md` (APPROVE WITH MINOR — I1/I2/I3 folded into Tasks 13/11/12 respectively)
- CLAUDE.md: `/Users/denissajnar/IdeaProjects/forge/CLAUDE.md` (v3.0.0 architecture)

**Local test execution:** None. Verification runs in CI after push (per user preference "no local tests").

**Final agent count math:** `42 + 5 (fg-155, fg-506, fg-143, fg-555, fg-414) = 47`. `fg-417` is split into `fg-417` (slimmed) + `fg-414` (new); `fg-417` is preserved, not replaced. The migration-verifier is numbered **`fg-506`** (not `fg-505`) because `fg-505-build-verifier` already occupies slot 505.

---

## File Structure

### Agent files touched (23 total)

**UI-frontmatter removal (12 Tier-4 agents — delete the `ui:` block entirely):**

- `agents/fg-101-worktree-manager.md`
- `agents/fg-102-conflict-resolver.md`
- `agents/fg-205-planning-critic.md`
- `agents/fg-410-code-reviewer.md`
- `agents/fg-411-security-reviewer.md`
- `agents/fg-412-architecture-reviewer.md`
- `agents/fg-413-frontend-reviewer.md`
- `agents/fg-416-performance-reviewer.md`
- `agents/fg-417-dependency-reviewer.md`
- `agents/fg-418-docs-consistency-reviewer.md`
- `agents/fg-419-infra-deploy-reviewer.md`
- `agents/fg-510-mutation-analyzer.md`

**`trigger:` additions (5 conditional agents):**

- `agents/fg-320-frontend-polisher.md` — `trigger: frontend_polish.enabled == true && frontend_files_present`
- `agents/fg-515-property-test-generator.md` — `trigger: property_testing.enabled == true`
- `agents/fg-610-infra-deploy-verifier.md` — `trigger: infra_files_present`
- `agents/fg-620-deploy-verifier.md` — `trigger: deployment.strategy != "none"`
- `agents/fg-650-preview-validator.md` — `trigger: preview.url_available == true`

**Split (fg-417 → fg-417 + fg-414):**

- `agents/fg-417-dependency-reviewer.md` — slim to ~180 lines (keep only CVE/outdated/unmaintained/version-compat sections 1, 1a, 2, 2b, 2c, 2d; drop 2e License Compliance).
- `agents/fg-414-license-reviewer.md` — NEW, inherits 2e content plus the new `LICENSE-POLICY-*` categories and fail-open default.

**Slim (fg-413 → fg-416 absorbs Part D):**

- `agents/fg-413-frontend-reviewer.md` — remove sections 17-21 (Bundle Size, Rendering Efficiency, Resource Loading, Network & Data, Performance Finding Categories). Target: ≤400 lines (current 534).
- `agents/fg-416-performance-reviewer.md` — gain a new "Frontend Performance" subsection absorbing the moved content (~60 lines).

**New agents (4, in addition to fg-414 above):**

- `agents/fg-155-i18n-validator.md`
- `agents/fg-506-migration-verifier.md`
- `agents/fg-143-observability-bootstrap.md`
- `agents/fg-555-resilience-tester.md`

### Shared doc files touched

| File | Change |
|---|---|
| `shared/agent-role-hierarchy.md` | Tier tables (Tier-3 gains 4, Tier-4 gains 1); dispatch graph (PREFLIGHT +2, VERIFYING +2, REVIEW +1); **remove duplicate fg-205 row** (footnote ¹ in spec §4.2) |
| `shared/agent-colors.md` | Add 5 rows (fg-155 crimson / fg-143 magenta / fg-506 coral / fg-555 navy / fg-414 lime); update header "42-agent color map" → "47-agent color map" |
| `shared/agent-registry.md` | Add 5 entries |
| `shared/reviewer-boundaries.md` | Update fg-417 (no longer owns license), add fg-414 row, update fg-413 (no longer owns FE perf), update fg-416 (now owns FE perf) |
| `shared/checks/category-registry.json` | Add 14 new categories; re-wire existing `I18N-*` affinity to prefer `fg-155-i18n-validator` |
| `shared/agents.md` | Regenerate Phase 06 registry table |
| `shared/learnings/i18n.md` | NEW |
| `shared/learnings/migration.md` | NEW |
| `shared/learnings/resilience.md` | NEW |
| `shared/learnings/observability.md` | Already exists; ADD an "Agent (fg-143)" section at top |
| `shared/learnings/license-compliance.md` | NEW |
| `CLAUDE.md` | "42 agents" → "47 agents" at lines 23 and 116 (2 occurrences, not 4 as spec §3.1 item 6 claimed) |

### Test files touched

- `tests/contract/ui-frontmatter-consistency.bats` — tighten "every agent has an explicit ui: block" → "every non-Tier-4 agent has ui:; every Tier-4 agent omits ui:"
- `tests/contract/agent-registry.bats` — NEW
- `tests/contract/agent-colors.bats` — NEW
- `tests/lib/module-lists.bash` — bump `MIN_AGENTS` (or equivalent) from 42 → 47
- `evals/scenarios/i18n-hardcoded.yml` — NEW
- `evals/scenarios/migration-no-rollback.yml` — NEW
- `evals/scenarios/resilience-unbounded-retry.yml` — NEW

### Config-template files touched

For every `modules/frameworks/*/forge-config-template.md` that exposes the `agents:` block, append the five new config keys (Task 13 shows the canonical YAML). If a framework template does not yet expose `agents:`, leave it alone — defaults apply from `shared/config-schema.json`.

---

## Task List (15 tasks, ~18 commits)

- Task 1 — Remove `ui:` from 12 Tier-4 agents (1 commit, mechanical)
- Task 2 — Add `trigger:` to 5 conditional agents (1 commit)
- Task 3 — Slim fg-413 and absorb Part D into fg-416 (1 commit)
- Task 4 — Split fg-417 → fg-417 (slimmed) + new fg-414 (1 commit)
- Task 5 — Create fg-155-i18n-validator (agent + learnings) (1 commit)
- Task 6 — Create fg-506-migration-verifier (agent + learnings) (1 commit)
- Task 7 — Create fg-143-observability-bootstrap (agent + learnings amendment) (1 commit)
- Task 8 — Create fg-555-resilience-tester (agent + learnings) (1 commit)
- Task 9 — Create fg-414 learnings file (license-compliance.md) (1 commit — separated from Task 4 so Task 4 is a pure agent split)
- Task 10 — Update `shared/agent-colors.md` (1 commit)
- Task 11 — Update `shared/agent-role-hierarchy.md` including **de-dup of fg-205 row** (resolves review I2) (1 commit)
- Task 12 — Add `shared/trigger-grammar.md` — formal EBNF + evaluator contract (resolves review I3) (1 commit)
- Task 13 — Update `shared/checks/category-registry.json` (14 new categories + rewire I18N affinity) AND append config keys to framework `forge-config-template.md` including the license fail-open default (resolves review I1) (1 commit)
- Task 14 — Update `shared/agent-registry.md`, `shared/reviewer-boundaries.md`, regenerate `shared/agents.md`, bump `CLAUDE.md` counts (1 commit)
- Task 15 — Tighten `ui-frontmatter-consistency.bats`, add `agent-registry.bats`, add `agent-colors.bats`, bump `tests/lib/module-lists.bash`, add 3 eval fixtures (1 commit)

---

## Task 1: Remove `ui:` frontmatter from 12 Tier-4 agents

**Files:**

- Modify: `agents/fg-101-worktree-manager.md`
- Modify: `agents/fg-102-conflict-resolver.md`
- Modify: `agents/fg-205-planning-critic.md`
- Modify: `agents/fg-410-code-reviewer.md`
- Modify: `agents/fg-411-security-reviewer.md`
- Modify: `agents/fg-412-architecture-reviewer.md`
- Modify: `agents/fg-413-frontend-reviewer.md`
- Modify: `agents/fg-416-performance-reviewer.md`
- Modify: `agents/fg-417-dependency-reviewer.md`
- Modify: `agents/fg-418-docs-consistency-reviewer.md`
- Modify: `agents/fg-419-infra-deploy-reviewer.md`
- Modify: `agents/fg-510-mutation-analyzer.md`

- [ ] **Step 1: For each of the 12 agents, delete the `ui:` block from frontmatter**

The block to delete looks like this (exact value may differ; the whole 4-line block goes):

```yaml
ui:
  tasks: false
  ask: false
  plan_mode: false
```

For example, in `agents/fg-410-code-reviewer.md` the file currently reads (lines 14-17):

```yaml
ui:
  tasks: false
  ask: false
  plan_mode: false
```

After: those four lines are gone. The `---` closing fence stays immediately after the last remaining frontmatter key. Do **not** remove the `color:` or `tools:` keys.

Mechanical deletion only. Do not modify agent bodies.

- [ ] **Step 2: Verify locally by eyeballing each file's frontmatter**

Run:

```bash
for f in agents/fg-101-worktree-manager.md agents/fg-102-conflict-resolver.md agents/fg-205-planning-critic.md agents/fg-410-code-reviewer.md agents/fg-411-security-reviewer.md agents/fg-412-architecture-reviewer.md agents/fg-413-frontend-reviewer.md agents/fg-416-performance-reviewer.md agents/fg-417-dependency-reviewer.md agents/fg-418-docs-consistency-reviewer.md agents/fg-419-infra-deploy-reviewer.md agents/fg-510-mutation-analyzer.md; do
  echo "=== $f ==="
  awk '/^---$/{n++} n==1{print} n==2{exit}' "$f"
done
```

Expected: no `ui:` key appears in any of the 12 outputs. `name:`, `description:`, `model:` (if present), `color:`, `tools:` all survive.

- [ ] **Step 3: Commit**

```bash
git add agents/fg-101-worktree-manager.md agents/fg-102-conflict-resolver.md agents/fg-205-planning-critic.md agents/fg-410-code-reviewer.md agents/fg-411-security-reviewer.md agents/fg-412-architecture-reviewer.md agents/fg-413-frontend-reviewer.md agents/fg-416-performance-reviewer.md agents/fg-417-dependency-reviewer.md agents/fg-418-docs-consistency-reviewer.md agents/fg-419-infra-deploy-reviewer.md agents/fg-510-mutation-analyzer.md
git commit -m "refactor(phase07): remove ui: frontmatter from 12 Tier-4 agents"
```

---

## Task 2: Add `trigger:` frontmatter to 5 conditional agents

**Files:**

- Modify: `agents/fg-320-frontend-polisher.md`
- Modify: `agents/fg-515-property-test-generator.md`
- Modify: `agents/fg-610-infra-deploy-verifier.md`
- Modify: `agents/fg-620-deploy-verifier.md`
- Modify: `agents/fg-650-preview-validator.md`

Trigger grammar is defined in Task 12. This task uses the grammar Task 12 will commit; the expressions below are already grammar-compliant.

- [ ] **Step 1: Add `trigger:` key to fg-320-frontend-polisher frontmatter (insert immediately above `ui:` block)**

In `agents/fg-320-frontend-polisher.md`, the frontmatter ends around line 11. Insert this line on the line *before* `ui:`:

```yaml
trigger: config.frontend_polish.enabled == true && state.frontend_files_present == true
```

Resulting frontmatter fragment:

```yaml
color: coral
tools: ['Read', 'Write', 'Edit', 'Grep', 'Glob', 'Bash', 'TaskCreate', 'TaskUpdate']
trigger: config.frontend_polish.enabled == true && state.frontend_files_present == true
ui:
  tasks: true
  ask: false
  plan_mode: false
```

- [ ] **Step 2: Add `trigger:` to fg-515-property-test-generator**

Insert above its `ui:` block:

```yaml
trigger: config.property_testing.enabled == true
```

- [ ] **Step 3: Add `trigger:` to fg-610-infra-deploy-verifier**

Insert above its `ui:` block:

```yaml
trigger: state.infra_files_present == true
```

- [ ] **Step 4: Add `trigger:` to fg-620-deploy-verifier**

Insert above its `ui:` block:

```yaml
trigger: config.deployment.strategy != "none"
```

- [ ] **Step 5: Add `trigger:` to fg-650-preview-validator**

Insert above its `ui:` block:

```yaml
trigger: state.preview.url_available == true
```

- [ ] **Step 6: Commit**

```bash
git add agents/fg-320-frontend-polisher.md agents/fg-515-property-test-generator.md agents/fg-610-infra-deploy-verifier.md agents/fg-620-deploy-verifier.md agents/fg-650-preview-validator.md
git commit -m "refactor(phase07): add machine-readable trigger: to 5 conditional agents"
```

---

## Task 3: Slim fg-413 and absorb Part D into fg-416

**Files:**

- Modify: `agents/fg-413-frontend-reviewer.md` (534 → ≤400 lines)
- Modify: `agents/fg-416-performance-reviewer.md` (146 → ~210 lines)

The section boundaries for `fg-413` were confirmed with `grep '^## '`:

- Sections **17 Bundle Size** (line 379), **18 Rendering Efficiency** (385), **19 Resource Loading** (392), **20 Network & Data** (398), **21 Performance Finding Categories** (404) comprise "Part D — Frontend Performance". Lines 379-419 inclusive (end of section 21, just before E.1 at line 421). That's ~41 lines. Combined with the Part D intro heading (look for `## Part D` or the "Performance" sub-header immediately before section 17) and trailing whitespace/separator lines, the net removal is ~50-60 lines — on target.

- [ ] **Step 1: Cut Part D from fg-413**

In `agents/fg-413-frontend-reviewer.md`, delete all lines from the "Part D" header (the section break right before `## 17. Bundle Size`) through the end of `## 21. Performance Finding Categories` (inclusive) and its trailing blank line. Preserve `## E.1 Screenshot Capture` (line 421) and everything after it.

If there is a `## Part D — Frontend Performance` divider line, delete it too.

Also scrub references to sections 17-21 in any in-file table of contents or intra-doc anchor (e.g., `§17`, `§19`). Use:

```bash
grep -n '§1[789]\|§20\|§21\|#section-1[789]\|#section-2[01]' agents/fg-413-frontend-reviewer.md
```

Fix any matches (either rewrite the reference to point at `fg-416` or delete if no longer relevant).

- [ ] **Step 2: Verify fg-413 is now ≤400 lines**

```bash
wc -l agents/fg-413-frontend-reviewer.md
```

Expected: ≤400 (target 380, hard cap 400).

- [ ] **Step 3: Append "Frontend Performance" subsection to fg-416**

Open `agents/fg-416-performance-reviewer.md`. Append, after the final existing numbered section and before any closing "Constraints" / "Output Format" block, a new top-level section that mirrors what was removed from fg-413:

```markdown
## Frontend Performance (absorbed from fg-413 Part D — Phase 07)

Applies when the reviewer receives frontend files (`.ts{x}`, `.jsx?`, `.vue`, `.svelte`, `.css`).

### FE-PERF-BUNDLE — Bundle size regression

**Detect:** `import * as X` from large libs (lodash, moment), unused imports surviving tree-shake, missing dynamic `import()` on route-level components, third-party deps not in `optimizeDeps` / `external`.

**Severity:** WARNING if delta > 10% of baseline; CRITICAL if > 30% or exceeds `performance_tracking.bundle_budget_kb`.

### FE-PERF-RENDER — Rendering efficiency

**Detect:** unkeyed lists, inline object/array creation in props, `useMemo`/`useCallback` missing on expensive derivations, `useEffect` running every render without deps array, `React.memo` boundary violations, Svelte `{#each}` without `(key)` expression, Vue `v-for` without `:key`, Angular `*ngFor` without `trackBy`.

**Severity:** WARNING (INFO if hot-path evidence is weak).

### FE-PERF-LOAD — Resource loading

**Detect:** `<img>` without `loading="lazy"` below the fold, missing `preconnect`/`dns-prefetch` for third-party origins, blocking `<script>` without `async`/`defer`, `<link rel="stylesheet">` > critical fold, fonts without `font-display: swap`.

**Severity:** WARNING.

### FE-PERF-NETWORK — Network and data

**Detect:** waterfall cascades (serial fetch in `useEffect`), missing HTTP cache headers, over-fetching (GraphQL ask-for-everything), no stale-while-revalidate on paginated reads, absent debounce/throttle on search handlers.

**Severity:** WARNING.

### Finding categories (mapped)

| Code | Severity cap | Owner |
|---|---|---|
| `FE-PERF-BUNDLE` | CRITICAL | fg-416-performance-reviewer |
| `FE-PERF-RENDER` | WARNING | fg-416-performance-reviewer |
| `FE-PERF-LOAD` | WARNING | fg-416-performance-reviewer |
| `FE-PERF-NETWORK` | WARNING | fg-416-performance-reviewer |

Owner change (Phase 07): previously these were emitted by `fg-413-frontend-reviewer`. `fg-413` now delegates performance findings to `fg-416` and focuses on conventions, design system, a11y, and visual regression.
```

- [ ] **Step 4: Commit**

```bash
git add agents/fg-413-frontend-reviewer.md agents/fg-416-performance-reviewer.md
git commit -m "refactor(phase07): slim fg-413 (≤400 lines), move FE perf to fg-416"
```

---

## Task 4: Split fg-417 into fg-417 (slimmed) + fg-414 (new license reviewer)

**Files:**

- Modify: `agents/fg-417-dependency-reviewer.md` (333 → ~180 lines; remove license section and license categories from 2e)
- Create: `agents/fg-414-license-reviewer.md`

- [ ] **Step 1: Remove section 2e from fg-417**

In `agents/fg-417-dependency-reviewer.md`, delete `## 2e. Check 1e: License Compliance (absorbed from fg-420)` (line 112) through the line immediately before `## 3. Check 2: Language Version Feature Usage` (line 122). That's lines 112-121 (10 lines). Leave section 3 intact.

Also scrub references to licenses elsewhere in fg-417:

- Section 1 Identity & Purpose (lines 31-36): if it lists license compliance as an owned duty, remove that bullet.
- Section 8 Output Format (line 267): remove any `License` row from the output table.
- Constraints section near end: remove any "License: *" bullet.

Run to confirm:

```bash
grep -in 'license\|SPDX\|LGPL\|GPL\|copyleft\|LICENSE-' agents/fg-417-dependency-reviewer.md
```

Expected: zero matches after the edit.

- [ ] **Step 2: Verify fg-417 is ≤200 lines**

```bash
wc -l agents/fg-417-dependency-reviewer.md
```

Expected: ≤200 (target 180).

- [ ] **Step 3: Create fg-414-license-reviewer.md**

Create `agents/fg-414-license-reviewer.md` with this content:

````markdown
---
name: fg-414-license-reviewer
description: License compliance reviewer. SPDX audit, copyleft-in-proprietary detection, license-change detection.
model: inherit
color: lime
tools:
  - Read
  - Bash
  - Glob
  - Grep
trigger: always
---

# License Compliance Reviewer (fg-414)

Reviews dependency license declarations (SPDX) for policy compliance. Split out of `fg-417-dependency-reviewer` in Phase 07 because license policy uses a disjoint tool chain (`license-checker`, `reuse`, `licensee`) and disjoint severity calibration (SPDX policy vs CVSS).

**Defaults:** `shared/agent-defaults.md`. **Philosophy:** `shared/agent-philosophy.md`. **Ownership:** `shared/reviewer-boundaries.md`.

Review license data for: **$ARGUMENTS**

---

## 1. Identity & Purpose

Single responsibility: detect license policy violations. Does **not** look at CVEs, outdated-ness, or version compatibility — those stay with `fg-417`.

## 2. Policy resolution order

1. If `config.agents.license_reviewer.policy_file` exists and points at a readable `.forge/license-policy.json`, load it.
2. Else if `config.agents.license_reviewer.embedded_defaults` exists in the resolved config, use it.
3. Else fall back to the baked-in **embedded defaults** (see §3).
4. If the policy file path is set but unreadable AND `config.agents.license_reviewer.fail_open_when_missing == true` (default `true`), emit `LICENSE-UNKNOWN` at WARNING and continue. If `fail_open_when_missing == false`, emit `LICENSE-POLICY-VIOLATION` at CRITICAL and stop.

## 3. Embedded defaults (applied when no policy file found, fail-open mode)

```json
{
  "allow": ["MIT", "Apache-2.0", "BSD-2-Clause", "BSD-3-Clause", "ISC", "Unlicense", "CC0-1.0"],
  "warn":  ["LGPL-2.1+", "LGPL-3.0+", "MPL-2.0"],
  "deny":  ["AGPL-*", "SSPL-*", "Commons-Clause", "BUSL-*"]
}
```

A dependency whose SPDX identifier is on `allow` → no finding. `warn` → `LICENSE-POLICY-VIOLATION` capped at WARNING. `deny` → `LICENSE-POLICY-VIOLATION` CRITICAL. Unrecognised SPDX → `LICENSE-UNKNOWN` WARNING.

## 4. Detection flow

1. Enumerate dependency manifests (`package.json`, `pnpm-lock.yaml`, `pom.xml`, `build.gradle{,.kts}`, `Cargo.toml`, `go.mod`, `requirements.txt`, `Gemfile`, etc.).
2. Shell out to the language-appropriate license extractor (`license-checker --json`, `cargo-about`, `go-licenses`, etc.). On tool missing → emit `LICENSE-UNKNOWN` at WARNING with a `(tool: <name> not installed)` note.
3. For each dependency, map its declared SPDX string to the policy.
4. Detect license *changes* between PR base and HEAD: any dep whose license string changed emits `LICENSE-CHANGE` at WARNING.

## 5. Finding categories

| Code | Severity cap | Description |
|---|---|---|
| `LICENSE-POLICY-VIOLATION` | CRITICAL | Dep on `deny` list (or on `warn` list if strict mode) |
| `LICENSE-UNKNOWN` | WARNING | SPDX not recognised OR extractor missing |
| `LICENSE-CHANGE` | WARNING | Dep's license changed between base and HEAD |

## 6. Output format

Follow `shared/checks/output-format.md`. Include the dep name, version, declared SPDX, and the policy bucket (`allow`/`warn`/`deny`/`unknown`).

## 7. Failure modes

- **No manifests found** → no findings, exit OK.
- **Extractor crash** → one `LICENSE-UNKNOWN` WARNING per affected manifest, with the crash message trimmed to the first 200 chars.
- **Policy file malformed** → one `LICENSE-POLICY-VIOLATION` CRITICAL referencing the parse error, regardless of `fail_open_when_missing`.

## Constraints

- Silent Tier 4: no TaskCreate/TaskUpdate/AskUserQuestion tool usage. Emit findings only.
- No writes (no `Write`/`Edit` tools). Read + shell + glob/grep only.
- Single `affinity` in category registry: `fg-414-license-reviewer`.
````

- [ ] **Step 4: Commit**

```bash
git add agents/fg-417-dependency-reviewer.md agents/fg-414-license-reviewer.md
git commit -m "refactor(phase07): split fg-417 into fg-417 (CVE/compat) + fg-414 (license)"
```

---

## Task 5: Create fg-155-i18n-validator (agent + learnings)

**Files:**

- Create: `agents/fg-155-i18n-validator.md`
- Create: `shared/learnings/i18n.md`

- [ ] **Step 1: Create fg-155-i18n-validator.md**

````markdown
---
name: fg-155-i18n-validator
description: i18n validator. Hardcoded strings, RTL/LTR bleed, locale format drift. PREFLIGHT.
model: inherit
color: crimson
tools: ['Read', 'Glob', 'Grep', 'Bash', 'TaskCreate', 'TaskUpdate']
trigger: config.agents.i18n_validator.enabled == true
ui:
  tasks: true
  ask: false
  plan_mode: false
---

# i18n Validator (fg-155)

Regex-driven scan for internationalisation hazards. PREFLIGHT Tier-3 dispatched unconditionally when `config.agents.i18n_validator.enabled == true` (default `true`; cheap). Owner of `I18N-*` finding categories.

**Defaults:** `shared/agent-defaults.md`. **Philosophy:** `shared/agent-philosophy.md`. **i18n patterns:** `shared/i18n-validation.md`.

Scan for i18n hazards in: **$ARGUMENTS**

---

## 1. Scope

Runs on changed files when dispatched from the inner loop and on the full tree at PREFLIGHT. Honors `.forge/i18n-ignore` (glob file, one pattern per line). Excludes by default: `*.test.*`, `*.spec.*`, `__tests__/**`, `*.stories.*`, `test/**`, `tests/**`, `e2e/**`, `cypress/**`, `*.fixture.*`.

## 2. Detection rules

### I18N-HARDCODED — Hardcoded user-facing string
- JSX/TSX: `>[A-Z][a-zA-Z ,'.!?]{3,}<` in a text node not wrapped by `t(...)`, `FormattedMessage`, `<Trans>`, `useTranslation` hook result.
- Vue: `{{ ... }}` interpolations with raw English literals; `<template>` text not wrapped by `$t(...)`.
- Svelte: `{...}` / plain text not wrapped by `$_(...)` or `_(...)`.
- Backend strings passed directly to response bodies (Spring `ResponseEntity.body("...")`, Express `res.send("...")`) when `response.body` contains English prose.

### I18N-RTL — LTR-unsafe CSS
- `margin-left`, `margin-right`, `padding-left`, `padding-right`, `left:`, `right:`, `border-left`, `border-right`, `text-align: left|right` without corresponding `-inline-start`/`-inline-end` or `direction`-aware logical property.

### I18N-LOCALE — Locale-unaware date/number
- `Date.toLocaleString()` / `toLocaleDateString()` called with no `locale` arg.
- `new Intl.*Format(` with hardcoded `'en-US'`.
- `.toFixed(` for currency (should be `Intl.NumberFormat`).
- Regex `/\$\d+(\.\d{2})?/` for currency (locale-specific).

## 3. Finding output

Follow `shared/checks/output-format.md`. Include the file, line, exact matched text (trimmed to 120 chars), and the rule ID.

## 4. Failure modes

- No frontend/backend text files in diff → no findings, exit OK.
- `.forge/i18n-ignore` present but malformed → one INFO finding (`I18N-CONFIG-ERROR`) and fall back to default excludes.

## Constraints

- No writes. Read/Glob/Grep/Bash only.
- Cap total findings per run at `config.agents.i18n_validator.max_findings_per_run` (default 200) to avoid score-saturation from legacy codebases; emit one INFO `I18N-TRUNCATED` if capped.
````

- [ ] **Step 2: Create shared/learnings/i18n.md**

```markdown
# i18n Learnings

Per-project cumulative learnings for `fg-155-i18n-validator` and downstream consumers (`fg-413-frontend-reviewer` reads these when reviewing FE conventions).

## Discovered patterns

(auto-populated by `fg-700-retrospective`)

## Known false-positive domains

- Test fixtures and storybook stories — excluded by default glob.
- Developer-only admin panels — add to `.forge/i18n-ignore` on a project basis.

## Calibration

| Pattern type | Typical false-positive rate | Mitigation |
|---|---|---|
| JSX text-node heuristic | ~15% | Require 3+ chars + leading uppercase |
| Currency regex | ~5% | Only fire inside `return`/JSX context |
| `margin-left` RTL rule | ~25% | Downgrade to INFO for CSS modules targeting LTR-only app |
```

- [ ] **Step 3: Commit**

```bash
git add agents/fg-155-i18n-validator.md shared/learnings/i18n.md
git commit -m "feat(phase07): add fg-155-i18n-validator (PREFLIGHT Tier-3)"
```

---

## Task 6: Create fg-506-migration-verifier (agent + learnings)

**Files:**

- Create: `agents/fg-506-migration-verifier.md`
- Create: `shared/learnings/migration.md`

Note: the spec's original slot was `fg-505`, which collides with the existing `fg-505-build-verifier`. This task uses `fg-506` per spec §4.3 R1. Do **not** use 505.

- [ ] **Step 1: Create fg-506-migration-verifier.md**

````markdown
---
name: fg-506-migration-verifier
description: Migration verifier. Rollback script, idempotency, data-loss risk. VERIFY (migration mode).
model: inherit
color: coral
tools: ['Read', 'Glob', 'Grep', 'Bash', 'TaskCreate', 'TaskUpdate']
trigger: state.mode == "migration" && config.agents.migration_verifier.enabled == true
ui:
  tasks: true
  ask: false
  plan_mode: false
---

# Migration Verifier (fg-506)

Verifies that the output of `fg-160-migration-planner` + `fg-300-implementer` produces a rollback-safe, idempotent, data-loss-free migration. Dispatched at VERIFYING only in migration mode.

**Defaults:** `shared/agent-defaults.md`. **Philosophy:** `shared/agent-philosophy.md`.

Verify migration: **$ARGUMENTS**

---

## 1. Scope

Runs only when `state.mode == "migration"`. Skips silently in any other mode. Receives the list of migration files (SQL, declarative YAML, code mods) produced during IMPLEMENTING.

## 2. Checks

### MIGRATION-ROLLBACK-MISSING — CRITICAL
For every forward migration file, assert a paired down/rollback file exists *or* the migration tool (Liquibase, Flyway, Alembic, Atlas, Prisma, etc.) supports auto-reversal for every operation used. Flag operations that are inherently non-reversible (e.g., `DROP COLUMN` without schema snapshot) as CRITICAL.

### MIGRATION-NOT-IDEMPOTENT — CRITICAL
Static analysis of SQL: `CREATE TABLE` → require `IF NOT EXISTS`. `CREATE INDEX` → require `IF NOT EXISTS` or idempotent equivalent. `INSERT` of seed data → require `ON CONFLICT DO NOTHING` / `MERGE` / `INSERT ... SELECT WHERE NOT EXISTS`. For code-mod migrations (Rails, Django, TypeORM): require the framework's `reversible do` / `run_python` guard pattern.

### MIGRATION-DATA-LOSS — CRITICAL
Flag any of: `DROP TABLE`, `DROP COLUMN`, `TRUNCATE`, `ALTER COLUMN ... TYPE` where narrowing, `DELETE` without `WHERE`, `UPDATE` without `WHERE`. Each emits CRITICAL unless a backup-snapshot migration sits immediately before it in the same batch.

## 3. Non-goals

- Does NOT run migrations. Static analysis only.
- Does NOT check migration **performance** (long locks, table rewrites) — that is `fg-416`'s concern.

## 4. Output

Follow `shared/checks/output-format.md`. For each finding include the migration filename, line, operation, and the rule.

## Constraints

- `trigger:` gates at-dispatch. If triggered outside migration mode, emit one INFO `MIGRATION-SKIPPED` and exit OK.
- No writes. Read + grep + shell for `diff` only.
````

- [ ] **Step 2: Create shared/learnings/migration.md**

```markdown
# Migration Learnings

Per-project cumulative learnings for `fg-506-migration-verifier` and `fg-160-migration-planner`.

## Discovered patterns

(auto-populated by `fg-700-retrospective`)

## Calibration

| Rule | Default cap | Override path |
|---|---|---|
| `MIGRATION-ROLLBACK-MISSING` | CRITICAL | Lower to WARNING for forward-only projects via `.forge/migration-policy.json` |
| `MIGRATION-DATA-LOSS` | CRITICAL | Cannot be lowered — data loss is always CRITICAL |
| `MIGRATION-NOT-IDEMPOTENT` | CRITICAL | Lower to WARNING only in greenfield (no production snapshot) |
```

- [ ] **Step 3: Commit**

```bash
git add agents/fg-506-migration-verifier.md shared/learnings/migration.md
git commit -m "feat(phase07): add fg-506-migration-verifier (VERIFY, migration mode)"
```

---

## Task 7: Create fg-143-observability-bootstrap (agent + learnings amendment)

**Files:**

- Create: `agents/fg-143-observability-bootstrap.md`
- Modify: `shared/learnings/observability.md` (already exists — prepend an "Agent" header)

- [ ] **Step 1: Create fg-143-observability-bootstrap.md**

````markdown
---
name: fg-143-observability-bootstrap
description: Observability bootstrapper. OTel config, metrics endpoints, structured log baseline. PREFLIGHT.
model: inherit
color: magenta
tools: ['Read', 'Write', 'Edit', 'Glob', 'Grep', 'Bash', 'TaskCreate', 'TaskUpdate']
trigger: config.agents.observability_bootstrap.enabled == true
ui:
  tasks: true
  ask: false
  plan_mode: false
---

# Observability Bootstrap (fg-143)

Ensures the project has minimum-viable observability wiring: OpenTelemetry instrumentation, a `/metrics` (or equivalent) endpoint, and structured logging. PREFLIGHT Tier-3. Write-capable — the only PREFLIGHT agent that mutates the tree.

**Defaults:** `shared/agent-defaults.md`. **Philosophy:** `shared/agent-philosophy.md`. **Patterns:** `shared/observability.md`.

Bootstrap observability for: **$ARGUMENTS**

---

## 1. Safety gate

All writes MUST target `.forge/worktree/` (the pipeline worktree), never the user's main working tree. Before any `Write`/`Edit`, verify `pwd` includes `.forge/worktree/`. If not, emit CRITICAL `OBS-BOOTSTRAP-UNSAFE` and exit without writes.

## 2. Detection

### OBS-MISSING — WARNING
- No `opentelemetry-*` / `@opentelemetry/*` / equivalent dep in any manifest.
- No `/metrics`, `/health`, `/healthz`, `/livez`, or `/readyz` route in the main HTTP surface.
- No structured logger (Pino / Winston / Logback-JSON / structlog / Zap / Logrus).

### OBS-TRACE-INCOMPLETE — INFO
- OTel deps present but no `TracerProvider` / `MeterProvider` wiring in the entrypoint.
- `/metrics` present but not exported by the meter provider.

## 3. Bootstrap actions (only when the project opts in via `config.agents.observability_bootstrap.enabled == true`)

For each gap, generate the smallest plausible stub using the project's language/framework and emit an INFO `OBS-BOOTSTRAP-APPLIED` with the path of the stub file. Do NOT configure exporters — that stays a project decision.

Stub templates: `shared/observability.md` Appendix A.

## 4. Output

Follow `shared/checks/output-format.md`. Include the manifest, endpoint, or entrypoint analysed.

## Constraints

- Write-capable but constrained to `.forge/worktree/`.
- Never overwrite existing observability wiring — only stub when absent.
- No tests, no test edits; `fg-150-test-bootstrapper` owns that seam.
````

- [ ] **Step 2: Prepend an "Agent (fg-143)" header to shared/learnings/observability.md**

The file already exists as a module learnings file. Insert at the very top (before the existing content), using an `Edit` replacing the first line with the new block + the old first line content:

```markdown
# Observability Learnings

## Agent: fg-143-observability-bootstrap (Phase 07)

`fg-143` runs at PREFLIGHT when `config.agents.observability_bootstrap.enabled == true` (default `false`). Categories: `OBS-MISSING`, `OBS-TRACE-INCOMPLETE`, `OBS-BOOTSTRAP-APPLIED`, `OBS-BOOTSTRAP-UNSAFE`.

Write-capable within `.forge/worktree/`. Common calibration:

| Language | Typical OBS-MISSING false-positive rate | Mitigation |
|---|---|---|
| Java/Spring | ~5% (Micrometer implies OTel) | Probe Micrometer registry before flagging |
| Go | ~10% (stdlib `expvar` counts) | Add `expvar` to accepted-patterns list |
| Python | ~15% (Prometheus client sans OTel) | Accept `prometheus_client` as a valid metric surface |

---

<existing file content preserved below this divider>
```

- [ ] **Step 3: Commit**

```bash
git add agents/fg-143-observability-bootstrap.md shared/learnings/observability.md
git commit -m "feat(phase07): add fg-143-observability-bootstrap (PREFLIGHT Tier-3, opt-in)"
```

---

## Task 8: Create fg-555-resilience-tester (agent + learnings)

**Files:**

- Create: `agents/fg-555-resilience-tester.md`
- Create: `shared/learnings/resilience.md`

- [ ] **Step 1: Create fg-555-resilience-tester.md**

````markdown
---
name: fg-555-resilience-tester
description: Resilience tester. Circuit breakers, timeouts, retry policy, chaos smoke. VERIFY.
model: inherit
color: navy
tools: ['Read', 'Glob', 'Grep', 'Bash', 'TaskCreate', 'TaskUpdate']
trigger: config.agents.resilience_testing.enabled == true
ui:
  tasks: true
  ask: false
  plan_mode: false
---

# Resilience Tester (fg-555)

Static scan for resilience anti-patterns plus optional chaos-style smoke probes. Default-OFF because chaos probes flake in CI. VERIFY Tier-3.

**Defaults:** `shared/agent-defaults.md`. **Philosophy:** `shared/agent-philosophy.md`.

Evaluate resilience for: **$ARGUMENTS**

---

## 1. Scope

Runs during VERIFYING only when `config.agents.resilience_testing.enabled == true`. Budget clamp: `config.agents.resilience_testing.max_duration_s` (default 120s).

## 2. Checks

### RESILIENCE-TIMEOUT-UNBOUNDED — CRITICAL (static only)
Outbound HTTP/DB/cache calls that do not pass a timeout. Targets:
- Java: `RestTemplate`/`WebClient` without `.timeout(...)` / `.readTimeout(...)`.
- Go: `http.Client{}` default (no `Timeout` field).
- Python: `requests.get(...)` without `timeout=`.
- Node: `fetch(...)` without `AbortSignal.timeout(...)`.

### RESILIENCE-RETRY-UNBOUNDED — WARNING (static only)
`while(true) { try { … } catch { continue } }` or equivalent; Kotlin coroutine `while(true) { runCatching { ... } }` without `delay()` backoff; unbounded `retry` in `resilience4j` configs.

### RESILIENCE-CIRCUIT-MISSING — WARNING (static only)
Outbound call to a declared downstream (from `state.downstreams`) without a circuit-breaker wrapper. Frameworks: `resilience4j`, `@nestjs/terminus`, `polly`, `gobreaker`, `pybreaker`.

### RESILIENCE-CHAOS-* — WARNING cap (optional, dynamic)
Only when `config.agents.resilience_testing.chaos_enabled == true` AND a chaos harness is configured. Probes: kill a dependency socket, fill a tmpfs, introduce 5s latency. Findings capped at WARNING (CI flake mitigation).

## 3. Output

Follow `shared/checks/output-format.md`. For static rules include file:line. For chaos rules include probe name + observed behaviour.

## Constraints

- Default-OFF. `trigger:` gates dispatch entirely.
- No writes. Read + grep + shell only.
- Dynamic probes gated behind a second opt-in (`chaos_enabled`), default `false`.
````

- [ ] **Step 2: Create shared/learnings/resilience.md**

```markdown
# Resilience Learnings

Per-project cumulative learnings for `fg-555-resilience-tester`.

## Discovered patterns

(auto-populated by `fg-700-retrospective`)

## Calibration

| Rule | Static/Dynamic | Default cap | Notes |
|---|---|---|---|
| `RESILIENCE-TIMEOUT-UNBOUNDED` | Static | CRITICAL | Cheap grep; always on when agent dispatched |
| `RESILIENCE-RETRY-UNBOUNDED` | Static | WARNING | Can be INFO for CLI scripts |
| `RESILIENCE-CIRCUIT-MISSING` | Static | WARNING | Suppress when `state.downstreams` is empty |
| `RESILIENCE-CHAOS-*` | Dynamic | WARNING | Flake-prone; capped per spec §10 R3 |
```

- [ ] **Step 3: Commit**

```bash
git add agents/fg-555-resilience-tester.md shared/learnings/resilience.md
git commit -m "feat(phase07): add fg-555-resilience-tester (VERIFY Tier-3, opt-in)"
```

---

## Task 9: Create fg-414 learnings file (license-compliance.md)

**Files:**

- Create: `shared/learnings/license-compliance.md`

- [ ] **Step 1: Create the file**

```markdown
# License Compliance Learnings

Per-project cumulative learnings for `fg-414-license-reviewer`.

## Discovered patterns

(auto-populated by `fg-700-retrospective`)

## Policy calibration

| SPDX bucket | Default behavior | Override path |
|---|---|---|
| `allow` | No finding | `.forge/license-policy.json` |
| `warn` | `LICENSE-POLICY-VIOLATION` @ WARNING | Promote to CRITICAL via project policy |
| `deny` | `LICENSE-POLICY-VIOLATION` @ CRITICAL | Cannot be lowered without policy edit |
| Unknown SPDX | `LICENSE-UNKNOWN` @ WARNING | Add SPDX to a bucket to silence |

## Common false positives

- Transitive dep declares no SPDX but is on npm registry with a known license → use the `licensee`/`license-checker` fallback heuristic before flagging unknown.
- Dual-licensed deps (`MIT OR Apache-2.0`) → treat as the most permissive match.
```

- [ ] **Step 2: Commit**

```bash
git add shared/learnings/license-compliance.md
git commit -m "docs(phase07): add license-compliance learnings file"
```

---

## Task 10: Update shared/agent-colors.md

**Files:**

- Modify: `shared/agent-colors.md`

- [ ] **Step 1: Rewrite the header line and add cluster rows**

Edit the first sentence of `## 3. Full 42-agent color map` to `## 3. Full 47-agent color map`.

Then add these rows to the end of the table (inside section 3), preserving alphabetical-by-id ordering within each cluster:

- Insert after `fg-140-deprecation-refresh` row:

  ```
  | `fg-143-observability-bootstrap` | PREFLIGHT | *(new)* | magenta |
  ```

- Insert after `fg-150-test-bootstrapper` row:

  ```
  | `fg-155-i18n-validator` | PREFLIGHT | *(new)* | crimson |
  ```

- Insert after `fg-413-frontend-reviewer` row:

  ```
  | `fg-414-license-reviewer` | Review | *(new)* | lime |
  ```

- Insert after `fg-505-build-verifier` row:

  ```
  | `fg-506-migration-verifier` | Verify/Test | *(new)* | coral |
  ```

- Insert after `fg-515-property-test-generator` row:

  ```
  | `fg-555-resilience-tester` | Verify/Test | *(new)* | navy |
  ```

- [ ] **Step 2: Update section 2 cluster-member tables**

In the `## 2. Dispatch clusters` table, append the new members so the `tests/contract/agent-colors.bats` (Task 15) finds them:

- PREFLIGHT row: `fg-130, fg-135, fg-140, fg-143, fg-150, fg-155`
- Review row: `fg-400, fg-410, fg-411, fg-412, fg-413, fg-414, fg-416, fg-417, fg-418, fg-419`
- Verify/Test row: `fg-500, fg-505, fg-506, fg-510, fg-515, fg-555`

- [ ] **Step 3: Commit**

```bash
git add shared/agent-colors.md
git commit -m "docs(phase07): add 5 new agent color assignments (cluster-collision-free)"
```

---

## Task 11: Update shared/agent-role-hierarchy.md — tier tables, dispatch graph, de-dup fg-205

**Resolves review issue I2** (duplicate fg-205 row housekeeping).

**Files:**

- Modify: `shared/agent-role-hierarchy.md`

- [ ] **Step 1: De-dup fg-205**

Check for duplicate `fg-205` row:

```bash
grep -c "fg-205-planning-critic" shared/agent-role-hierarchy.md
```

- If count is 1 (only the legitimate row at line 66 in Tier-4 table), skip to Step 2.
- If count ≥ 2, delete the surplus row. The Tier-4 table row at line 66 (`| \`fg-205-planning-critic\` | Silent adversarial plan reviewer; ... |`) is the canonical one — keep it. Remove any other occurrence in the tier tables.

Record the action in the commit message: "(includes de-dup of duplicate fg-205 row — W7 audit artifact)".

- [ ] **Step 2: Add fg-414 to Tier 4 table**

In the Tier-4 table, insert **after** the `fg-413-frontend-reviewer` row:

```
| `fg-414-license-reviewer` | License compliance review (conditional on always; SPDX policy + change detection) |
```

- [ ] **Step 3: Add 4 new agents to Tier 3 table**

Insert these rows preserving id ordering:

- After `fg-140-deprecation-refresh`:

  ```
  | `fg-143-observability-bootstrap` | Observability bootstrap (conditional) |
  ```

- After `fg-150-test-bootstrapper`:

  ```
  | `fg-155-i18n-validator` | i18n static validation |
  ```

- After `fg-505-build-verifier`:

  ```
  | `fg-506-migration-verifier` | Migration verification (migration mode) |
  ```

- After `fg-515-property-test-generator`:

  ```
  | `fg-555-resilience-tester` | Resilience testing (conditional) |
  ```

- [ ] **Step 4: Update Pipeline Dispatch graph**

In the ```` ``` ```` block starting at line 82, insert lines so the result matches spec §4.3:

Under `PREFLIGHT`, after `fg-140-deprecation-refresh`:

```
  │   ├── fg-143-observability-bootstrap   (conditional: observability_bootstrap.enabled)
```

Under `PREFLIGHT`, after `fg-150-test-bootstrapper`:

```
  │   ├── fg-155-i18n-validator            (conditional: i18n_validator.enabled, default true)
```

Under `VERIFYING`, after `fg-505-build-verifier`:

```
  │   ├── fg-506-migration-verifier        (conditional: mode == "migration")
```

Under `VERIFYING`, after `fg-500-test-gate`:

```
  │   └── fg-555-resilience-tester         (conditional: resilience_testing.enabled)
```

(The existing `└──` ASCII before the new `fg-555` row becomes `├──` — adjust the ASCII characters accordingly.)

- [ ] **Step 5: Update Quality Gate Dispatch graph**

In the `### Quality Gate Dispatch (fg-400-quality-gate)` block (around line 120), insert after `fg-413-frontend-reviewer`:

```
  ├── fg-414-license-reviewer (always)
```

- [ ] **Step 6: Commit**

```bash
git add shared/agent-role-hierarchy.md
git commit -m "docs(phase07): update tier tables + dispatch graph; de-dup fg-205 row"
```

---

## Task 12: Add shared/trigger-grammar.md — formal grammar and evaluator contract

**Resolves review issue I3** (trigger expression grammar not specified).

**Files:**

- Create: `shared/trigger-grammar.md`

- [ ] **Step 1: Create the file**

````markdown
# `trigger:` Expression Grammar

Every agent frontmatter MAY carry a `trigger:` key. The value is a boolean expression evaluated by the dispatcher (`fg-100-orchestrator`) before calling the agent. When the expression evaluates to `false`, the agent is skipped silently and a `DISPATCH-SKIPPED` debug event is emitted to `.forge/events.jsonl`.

## 1. Absence == `always`

An agent with no `trigger:` key is equivalent to `trigger: always`. Phase 08's dispatch-graph generator flags omissions on conditionally-dispatched agents as warnings, but runtime behavior preserves the current "dispatch unconditionally" default.

## 2. Namespaces

Three top-level namespaces are visible to the evaluator:

- `config.*` — effective config after `forge-config.md > forge.local.md > defaults` resolution. Matches the YAML structure in `forge-config-template.md`.
- `state.*` — the subset of `.forge/state.json` that `fg-100-orchestrator` passes to dispatch. Always includes: `mode`, `frontend_files_present` (bool), `infra_files_present` (bool), `preview.url_available` (bool), `downstreams` (array).
- `always` — literal `true`.

Accessing an undefined path evaluates to `null`. Any operator applied to `null` evaluates to `false` (short-circuits safely; no dispatch).

## 3. EBNF

```ebnf
expr       = or ;
or         = and { "||" and } ;
and        = not { "&&" not } ;
not        = [ "!" ] primary ;
primary    = literal
           | path
           | "(" expr ")"
           | comparison ;
comparison = path op rhs ;
op         = "==" | "!=" | ">=" | "<=" | ">" | "<" ;
rhs        = literal | path ;
literal    = boolean | string | number ;
boolean    = "true" | "false" | "always" ;
string     = '"' { any-char-except-quote } '"' ;
number     = digit { digit } [ "." digit { digit } ] ;
path       = identifier { "." identifier } ;
identifier = letter { letter | digit | "_" } ;
```

## 4. Operators

- Equality: `==`, `!=` — strict type and value equality.
- Ordering: `<`, `<=`, `>`, `>=` — numeric only; string compares are a type error → `false`.
- Logical: `&&`, `||`, `!` — short-circuit.
- Parentheses: `(`, `)`.

No arithmetic, no function calls, no regexes, no glob globs. Keep expressions boring on purpose.

## 5. Evaluator

Implemented in-band by `fg-100-orchestrator`. Reference implementation will land in Phase 08 alongside the dispatch-graph generator. Until then, orchestrator prose uses human-language mirrors of the same expressions — the machine-readable `trigger:` field is the source of truth, and Phase 08 generates matching prose.

## 6. Error handling

- Parse error in a `trigger:` → `fg-100-orchestrator` emits CRITICAL `DISPATCH-TRIGGER-PARSE-ERROR`, skips that agent only, and continues the stage.
- Reference to an unknown top-level namespace → WARNING `DISPATCH-TRIGGER-UNKNOWN-NAMESPACE`, expression evaluates `false` (skip).
- Reference to an unknown path inside a known namespace → silent `false` (per §2).

## 7. Canonical examples (used in Phase 07 agents)

| Agent | Expression |
|---|---|
| `fg-155-i18n-validator` | `config.agents.i18n_validator.enabled == true` |
| `fg-143-observability-bootstrap` | `config.agents.observability_bootstrap.enabled == true` |
| `fg-506-migration-verifier` | `state.mode == "migration" && config.agents.migration_verifier.enabled == true` |
| `fg-555-resilience-tester` | `config.agents.resilience_testing.enabled == true` |
| `fg-414-license-reviewer` | `always` |
| `fg-320-frontend-polisher` | `config.frontend_polish.enabled == true && state.frontend_files_present == true` |
| `fg-515-property-test-generator` | `config.property_testing.enabled == true` |
| `fg-610-infra-deploy-verifier` | `state.infra_files_present == true` |
| `fg-620-deploy-verifier` | `config.deployment.strategy != "none"` |
| `fg-650-preview-validator` | `state.preview.url_available == true` |

## 8. Related

- `shared/agent-role-hierarchy.md` — dispatch graph (consumer)
- `shared/agent-ui.md` — UI-tier rules (peer contract)
- `shared/state-schema.md` — `state.*` namespace definitions
- `shared/config-schema.json` — `config.*` namespace definitions
````

- [ ] **Step 2: Commit**

```bash
git add shared/trigger-grammar.md
git commit -m "docs(phase07): add trigger: expression grammar and evaluator contract"
```

---

## Task 13: Update category-registry.json (+14 categories, rewire I18N) AND forge-config templates (incl. license fail-open default)

**Resolves review issue I1** (license fail-open default + embedded-defaults shape wired into config).

**Files:**

- Modify: `shared/checks/category-registry.json`
- Modify: every `modules/frameworks/*/forge-config-template.md`

- [ ] **Step 1: Add 14 new categories to category-registry.json**

Append inside the `"categories": { ... }` object, before the closing `}`. Preserve strict JSON (no comments — the spec §6.1 used JSONC for readability; real registry is strict JSON).

Insert these 14 entries:

```json
    "I18N-RTL": { "description": "LTR-unsafe CSS (missing logical properties)", "agents": ["fg-155-i18n-validator"], "wildcard": false, "priority": 5, "affinity": ["fg-155-i18n-validator", "fg-413-frontend-reviewer"] },
    "I18N-LOCALE": { "description": "Locale-unaware date/number formatting", "agents": ["fg-155-i18n-validator"], "wildcard": false, "priority": 5, "affinity": ["fg-155-i18n-validator"] },
    "MIGRATION-ROLLBACK-MISSING": { "description": "Forward migration lacks rollback pair", "agents": ["fg-506-migration-verifier"], "wildcard": false, "priority": 1, "affinity": ["fg-506-migration-verifier"] },
    "MIGRATION-NOT-IDEMPOTENT": { "description": "Migration is not idempotent (missing IF NOT EXISTS / ON CONFLICT)", "agents": ["fg-506-migration-verifier"], "wildcard": false, "priority": 1, "affinity": ["fg-506-migration-verifier"] },
    "MIGRATION-DATA-LOSS": { "description": "Migration risks data loss (DROP/TRUNCATE without snapshot)", "agents": ["fg-506-migration-verifier"], "wildcard": false, "priority": 1, "affinity": ["fg-506-migration-verifier"] },
    "RESILIENCE-CIRCUIT-MISSING": { "description": "Outbound call lacks circuit-breaker wrapper", "agents": ["fg-555-resilience-tester"], "wildcard": false, "priority": 4, "affinity": ["fg-555-resilience-tester"] },
    "RESILIENCE-TIMEOUT-UNBOUNDED": { "description": "Outbound call has no timeout configured", "agents": ["fg-555-resilience-tester"], "wildcard": false, "priority": 1, "affinity": ["fg-555-resilience-tester"] },
    "RESILIENCE-RETRY-UNBOUNDED": { "description": "Retry loop without bound or backoff", "agents": ["fg-555-resilience-tester"], "wildcard": false, "priority": 4, "affinity": ["fg-555-resilience-tester"] },
    "LICENSE-POLICY-VIOLATION": { "description": "Dependency license violates configured policy", "agents": ["fg-414-license-reviewer"], "wildcard": false, "priority": 1, "affinity": ["fg-414-license-reviewer"] },
    "LICENSE-UNKNOWN": { "description": "Dependency SPDX identifier unknown or extractor missing", "agents": ["fg-414-license-reviewer"], "wildcard": false, "priority": 5, "affinity": ["fg-414-license-reviewer"] },
    "LICENSE-CHANGE": { "description": "Dependency license changed between PR base and HEAD", "agents": ["fg-414-license-reviewer"], "wildcard": false, "priority": 5, "affinity": ["fg-414-license-reviewer"] },
    "OBS-MISSING": { "description": "Observability wiring absent (no OTel / /metrics / structured logger)", "agents": ["fg-143-observability-bootstrap"], "wildcard": false, "priority": 4, "affinity": ["fg-143-observability-bootstrap"] },
    "OBS-TRACE-INCOMPLETE": { "description": "OTel deps present but TracerProvider/MeterProvider wiring absent", "agents": ["fg-143-observability-bootstrap"], "wildcard": false, "priority": 6, "affinity": ["fg-143-observability-bootstrap"] },
    "OBS-BOOTSTRAP-APPLIED": { "description": "Observability stub generated (INFO)", "agents": ["fg-143-observability-bootstrap"], "wildcard": false, "priority": 6, "affinity": ["fg-143-observability-bootstrap"] }
```

Note: the spec §6.1 defined 14 categories; `RESILIENCE-CIRCUIT-MISSING` priority is set to 4 (WARNING-tier) matching spec severity cap. `OBS-BOOTSTRAP-APPLIED` is added (not in spec §6.1 but produced by fg-143) — label it `priority: 6` (INFO, score-irrelevant like SCOUT).

Total post-edit categories: `current + 14`. (Spec said 14 total — matches.)

- [ ] **Step 2: Rewire existing I18N affinity**

Modify the already-present three `I18N-*` entries (around lines 55-58):

Replace the `I18N-HARDCODED` entry with:

```json
    "I18N-HARDCODED": { "description": "Hard-coded user-facing string not using i18n framework", "agents": ["fg-155-i18n-validator"], "wildcard": false, "priority": 5, "affinity": ["fg-155-i18n-validator", "fg-413-frontend-reviewer"] },
```

Replace `I18N-MISSING-KEY`:

```json
    "I18N-MISSING-KEY": { "description": "Translation key present in source locale but missing in target locale", "agents": ["fg-155-i18n-validator"], "wildcard": false, "priority": 5, "affinity": ["fg-155-i18n-validator"] },
```

Replace `I18N-RTL` (remove the old duplicate if its `agents` was `fg-410-code-reviewer`; the new-category block in Step 1 is authoritative — if both exist after Step 1, delete the pre-existing `I18N-RTL` entry).

Replace `I18N-FORMAT`:

```json
    "I18N-FORMAT": { "description": "Hardcoded date/number format instead of locale-aware Intl API", "agents": ["fg-155-i18n-validator"], "wildcard": false, "priority": 5, "affinity": ["fg-155-i18n-validator"] },
```

After this step the 4 I18N entries point at `fg-155-i18n-validator` as primary owner; `fg-413-frontend-reviewer` appears only in `affinity` for `I18N-HARDCODED` (frontend context hint).

- [ ] **Step 3: Validate JSON**

```bash
python3 -m json.tool shared/checks/category-registry.json > /dev/null
```

Expected: exit 0. Any error means a trailing comma or duplicate key.

- [ ] **Step 4: Append agent config block to every framework forge-config-template.md**

For every file matching `modules/frameworks/*/forge-config-template.md`, locate the `agents:` YAML block (or add one if absent — under the top-level config root). Append the following YAML (preserve 2-space indent):

```yaml
agents:
  i18n_validator:
    enabled: true                # cheap regex scan; on by default
    max_findings_per_run: 200    # truncation cap
  observability_bootstrap:
    enabled: false               # opt-in; writes stubs into .forge/worktree/
  migration_verifier:
    enabled: true                # auto-skips outside migration mode
  resilience_testing:
    enabled: false               # opt-in; chaos + flake risk
    max_duration_s: 120
    chaos_enabled: false         # second opt-in for dynamic probes
  license_reviewer:
    policy_file: .forge/license-policy.json    # optional
    fail_open_when_missing: true               # when true, LICENSE-* capped at WARNING when policy file absent
    embedded_defaults:                          # used iff policy_file absent
      allow: ["MIT", "Apache-2.0", "BSD-2-Clause", "BSD-3-Clause", "ISC", "Unlicense", "CC0-1.0"]
      warn:  ["LGPL-2.1+", "LGPL-3.0+", "MPL-2.0"]
      deny:  ["AGPL-*", "SSPL-*", "Commons-Clause", "BUSL-*"]
```

Skip any template that already has an `agents:` block — in that case, merge additively (do not duplicate sub-keys).

For framework templates that do not expose an `agents:` section at all, insert the block before the closing fence of the YAML region.

- [ ] **Step 5: Commit**

```bash
git add shared/checks/category-registry.json modules/frameworks/*/forge-config-template.md
git commit -m "feat(phase07): add 14 new categories + wire 5 agent config blocks (license fail-open default)"
```

---

## Task 14: Update agent-registry.md, reviewer-boundaries.md, regenerate agents.md, bump CLAUDE.md counts

**Files:**

- Modify: `shared/agent-registry.md`
- Modify: `shared/reviewer-boundaries.md`
- Modify: `shared/agents.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add 5 rows to shared/agent-registry.md**

Insert (preserving the existing table's column order — `| agent | tier | ... | cluster | role |`):

- After `fg-140-deprecation-refresh` row: `fg-143-observability-bootstrap | 3 | Yes | PREFLIGHT | Observability bootstrap`
- After `fg-150-test-bootstrapper` row: `fg-155-i18n-validator | 3 | Yes | PREFLIGHT | i18n validator`
- After `fg-413-frontend-reviewer` row: `fg-414-license-reviewer | 4 | No | Review | License compliance`
- After `fg-505-build-verifier` row: `fg-506-migration-verifier | 3 | Yes | Verify/Test | Migration verification`
- After `fg-515-property-test-generator` row: `fg-555-resilience-tester | 3 | Yes | Verify/Test | Resilience testing`

Match the surrounding columns' format exactly.

- [ ] **Step 2: Update shared/reviewer-boundaries.md**

- Update the `fg-413-frontend-reviewer` row's `owns` column: drop "FE performance"; keep "A11y (WCAG 2.2 AA), design system, responsive, dark mode, visual regression".
- Update its `cedes` column: add "→ fg-416 for FE performance".
- Update `fg-416-performance-reviewer` row's `owns` column: add "frontend bundle, render, load, network".
- Update `fg-417-dependency-reviewer` row's `owns` column: drop "license compliance". Add "→ fg-414" to its `cedes` column.
- Add a **new row** for `fg-414-license-reviewer`: owns = "SPDX audit, copyleft in proprietary, license-change detection", cedes = "CVEs (→ fg-417)".
- In the `| Category | Primary | Affinity |` table: update `DEP-*` primary → still `fg-417`; add a new row `LICENSE-* | fg-414 | fg-417`. Update `I18N-*` primary → `fg-155` (with affinity `fg-413 (FE context)`).

- [ ] **Step 3: Regenerate shared/agents.md**

`shared/agents.md` is the Phase 06 regenerated table. Locate the generator (likely `shared/generate-conventions-index.sh` or a Phase 06 script) and run it:

```bash
ls shared/generate-*.sh 2>/dev/null
```

If a generator exists, run it. If it does not (Phase 06 was markdown-only and hand-edited), regenerate by adding the 5 new rows manually in the same table shape:

```
| fg-143-observability-bootstrap | 3 | PREFLIGHT | magenta | Yes | Observability bootstrap |
| fg-155-i18n-validator          | 3 | PREFLIGHT | crimson | Yes | i18n validator |
| fg-414-license-reviewer        | 4 | Review    | lime    | No  | License compliance |
| fg-506-migration-verifier      | 3 | Verify    | coral   | Yes | Migration verification |
| fg-555-resilience-tester       | 3 | Verify    | navy    | Yes | Resilience testing |
```

Insert rows preserving id ordering.

- [ ] **Step 4: Bump CLAUDE.md "42 agents" → "47 agents"**

Two occurrences confirmed by grep:

- Line 23: `Shared core (agents/, shared/, hooks/, skills/) — 42 agents, check engine, ...` → change to `47 agents`.
- Line 116: `## Agents (42 total, \`agents/*.md\`)` → change to `47 total`.

(Spec §3.1 item 6 said "four sites" — actual is two. The plan reconciles this; no other sites need editing.)

Also append to line 122 (Preflight bullet) the new agents: `fg-143-observability-bootstrap (conditional on observability_bootstrap.enabled)` and `fg-155-i18n-validator (conditional on i18n_validator.enabled, default true)`.

Append to line 126 (Verify/Review bullet): `fg-506-migration-verifier (migration mode only)`, `fg-555-resilience-tester (conditional on resilience_testing.enabled)`.

Update the Review (8) list in the same CLAUDE.md Review section: `(8, via quality gate)` → `(9, via quality gate)`, and append `fg-414-license-reviewer`.

- [ ] **Step 5: Commit**

```bash
git add shared/agent-registry.md shared/reviewer-boundaries.md shared/agents.md CLAUDE.md
git commit -m "docs(phase07): regenerate registry + bump CLAUDE.md to 47 agents"
```

---

## Task 15: Tighten contract tests, add registry + colors contract tests, bump module-lists, add 3 eval fixtures

**Files:**

- Modify: `tests/contract/ui-frontmatter-consistency.bats`
- Create: `tests/contract/agent-registry.bats`
- Create: `tests/contract/agent-colors.bats`
- Modify: `tests/lib/module-lists.bash`
- Create: `evals/scenarios/i18n-hardcoded.yml`
- Create: `evals/scenarios/migration-no-rollback.yml`
- Create: `evals/scenarios/resilience-unbounded-retry.yml`

- [ ] **Step 1: Tighten the existing Tier-4 test**

In `tests/contract/ui-frontmatter-consistency.bats` the test at line 149 is `@test "every agent has an explicit ui: block"`. Replace it with two tests:

```bash
@test "non-Tier-4 agents have an explicit ui: block" {
  # Tier-4 agents (silent): must NOT carry ui:
  local tier4=(fg-101 fg-102 fg-205 fg-410 fg-411 fg-412 fg-413 fg-414 fg-416 fg-417 fg-418 fg-419 fg-510)
  for f in "$PLUGIN_ROOT"/agents/fg-*.md; do
    local base
    base="$(basename "$f" .md | cut -c1-6)"
    local is_tier4=0
    for t4 in "${tier4[@]}"; do
      [ "$base" = "$t4" ] && is_tier4=1 && break
    done
    if [ "$is_tier4" -eq 0 ]; then
      grep -q "^ui:" "$f" || { echo "Missing ui: $f"; return 1; }
    fi
  done
}

@test "Tier-4 agents MUST omit ui: frontmatter" {
  local tier4=(fg-101 fg-102 fg-205 fg-410 fg-411 fg-412 fg-413 fg-414 fg-416 fg-417 fg-418 fg-419 fg-510)
  for t4 in "${tier4[@]}"; do
    local f
    f=$(ls "$PLUGIN_ROOT"/agents/${t4}*.md 2>/dev/null | head -1)
    [ -n "$f" ] || { echo "Missing agent file: $t4"; return 1; }
    if awk '/^---$/{n++; next} n==1' "$f" | grep -q "^ui:"; then
      echo "Tier-4 agent has ui: block (must be omitted): $f"
      return 1
    fi
  done
}
```

(The old single test is replaced by these two.)

- [ ] **Step 2: Extend the cluster-color test to know the 3 new cluster members**

Within the same file, in `@test "cluster-scoped color uniqueness holds"` (line 169), update the cluster lists so `agent-colors.bats` (Task 15 Step 4) can be minimal but this test still enforces it too:

```bash
  clusters["preflight"]="fg-130 fg-135 fg-140 fg-143 fg-150 fg-155"
  clusters["review"]="fg-400 fg-410 fg-411 fg-412 fg-413 fg-414 fg-416 fg-417 fg-418 fg-419"
  clusters["verify"]="fg-500 fg-505 fg-506 fg-510 fg-515 fg-555"
```

- [ ] **Step 3: Create tests/contract/agent-registry.bats**

```bash
#!/usr/bin/env bats
# Phase 07 contract: agent registry size, trigger: invariants, category owner existence.

load '../helpers/test-helpers'

AGENTS_DIR="$PLUGIN_ROOT/agents"
REGISTRY="$PLUGIN_ROOT/shared/checks/category-registry.json"

@test "agent registry has exactly 47 agents" {
  local count
  count=$(ls "$AGENTS_DIR"/fg-*.md | wc -l | tr -d ' ')
  [ "$count" -eq 47 ] || { echo "Expected 47 agents, got $count"; return 1; }
}

@test "all conditional agents declare a trigger: key" {
  local conditional=(fg-143 fg-155 fg-320 fg-506 fg-515 fg-555 fg-610 fg-620 fg-650)
  for id in "${conditional[@]}"; do
    local f
    f=$(ls "$AGENTS_DIR"/${id}*.md 2>/dev/null | head -1)
    [ -n "$f" ] || { echo "Missing agent: $id"; return 1; }
    awk '/^---$/{n++; next} n==1' "$f" | grep -q "^trigger:" || {
      echo "Agent $id missing trigger: frontmatter"; return 1;
    }
  done
}

@test "every category.agents[] entry refers to an existing agent file" {
  local agents
  agents=$(python3 -c "
import json, sys
with open('$REGISTRY') as f:
    data = json.load(f)
seen = set()
for code, info in data['categories'].items():
    for a in info.get('agents', []):
        seen.add(a)
for a in sorted(seen):
    print(a)
")
  local bad=0
  while IFS= read -r a; do
    [ -z "$a" ] && continue
    if ! ls "$AGENTS_DIR/${a}.md" >/dev/null 2>&1; then
      echo "category-registry references missing agent: $a"
      bad=1
    fi
  done <<< "$agents"
  [ "$bad" -eq 0 ]
}

@test "every agent with a trigger: key has a syntactically valid expression" {
  # Minimal syntactic check: matches one of the canonical forms.
  # Phase 08 ships a full evaluator; Phase 07 just asserts the string is non-empty and uses only allowed tokens.
  local allowed_re='^(always|[a-z_.]+[[:space:]]*(==|!=|>=|<=|>|<)[[:space:]]*("[^"]*"|true|false|[0-9.]+|[a-z_.]+)([[:space:]]*(&&|\|\|)[[:space:]]*[a-z_.]+[[:space:]]*(==|!=|>=|<=|>|<)[[:space:]]*("[^"]*"|true|false|[0-9.]+|[a-z_.]+))*)$'
  for f in "$AGENTS_DIR"/fg-*.md; do
    local val
    val=$(awk '/^---$/{n++; next} n==1 && /^trigger:/{sub(/^trigger:[[:space:]]*/,""); print; exit}' "$f")
    [ -z "$val" ] && continue
    if ! [[ "$val" =~ $allowed_re ]]; then
      echo "Invalid trigger expression in $f: $val"
      return 1
    fi
  done
}
```

- [ ] **Step 4: Create tests/contract/agent-colors.bats**

```bash
#!/usr/bin/env bats
# Phase 07 contract: cluster-scoped color uniqueness after adding 5 new agents.

load '../helpers/test-helpers'

AGENTS_DIR="$PLUGIN_ROOT/agents"

@test "PREFLIGHT cluster colors are distinct" {
  local colors=""
  for m in fg-130 fg-135 fg-140 fg-143 fg-150 fg-155; do
    local c
    c=$(grep -h "^color:" "$AGENTS_DIR"/${m}*.md 2>/dev/null | head -1 | awk '{print $2}')
    colors="$colors $c"
  done
  local distinct total
  distinct=$(echo "$colors" | tr ' ' '\n' | grep -v '^$' | sort -u | wc -l | tr -d ' ')
  total=$(echo "$colors" | wc -w | tr -d ' ')
  [ "$distinct" = "$total" ] || { echo "PREFLIGHT collision: $colors"; return 1; }
}

@test "Review cluster colors are distinct (9 agents post-phase-07)" {
  local colors=""
  for m in fg-400 fg-410 fg-411 fg-412 fg-413 fg-414 fg-416 fg-417 fg-418 fg-419; do
    local c
    c=$(grep -h "^color:" "$AGENTS_DIR"/${m}*.md 2>/dev/null | head -1 | awk '{print $2}')
    colors="$colors $c"
  done
  local distinct total
  distinct=$(echo "$colors" | tr ' ' '\n' | grep -v '^$' | sort -u | wc -l | tr -d ' ')
  total=$(echo "$colors" | wc -w | tr -d ' ')
  [ "$distinct" = "$total" ] || { echo "Review collision: $colors"; return 1; }
}

@test "Verify/Test cluster colors are distinct (6 agents post-phase-07)" {
  local colors=""
  for m in fg-500 fg-505 fg-506 fg-510 fg-515 fg-555; do
    local c
    c=$(grep -h "^color:" "$AGENTS_DIR"/${m}*.md 2>/dev/null | head -1 | awk '{print $2}')
    colors="$colors $c"
  done
  local distinct total
  distinct=$(echo "$colors" | tr ' ' '\n' | grep -v '^$' | sort -u | wc -l | tr -d ' ')
  total=$(echo "$colors" | wc -w | tr -d ' ')
  [ "$distinct" = "$total" ] || { echo "Verify/Test collision: $colors"; return 1; }
}
```

- [ ] **Step 5: Bump tests/lib/module-lists.bash**

Find the `MIN_AGENTS` (or similar) constant:

```bash
grep -n "AGENT\|42" tests/lib/module-lists.bash 2>&1 | head -5
```

If `MIN_AGENTS=42` exists, change to `MIN_AGENTS=47`. If no such constant exists (the file tracks module counts, not agents), skip this step and note in the commit message that agent count is enforced exclusively by `agent-registry.bats`.

- [ ] **Step 6: Create evals/scenarios/i18n-hardcoded.yml**

```yaml
name: i18n-hardcoded
description: A React component with a hardcoded English string; expect fg-155 to emit I18N-HARDCODED.
fixtures:
  - path: src/components/Welcome.tsx
    content: |
      export function Welcome() {
        return <h1>Hello world, welcome to the app</h1>;
      }
expected:
  findings:
    - agent: fg-155-i18n-validator
      category: I18N-HARDCODED
      path: src/components/Welcome.tsx
      severity_at_least: INFO
```

- [ ] **Step 7: Create evals/scenarios/migration-no-rollback.yml**

```yaml
name: migration-no-rollback
description: A forward-only SQL migration without down script; expect fg-506 to emit MIGRATION-ROLLBACK-MISSING at CRITICAL.
mode: migration
fixtures:
  - path: db/migrations/20260419_add_orders_table.up.sql
    content: |
      CREATE TABLE orders (
        id BIGSERIAL PRIMARY KEY,
        customer_id BIGINT NOT NULL,
        total_cents BIGINT NOT NULL
      );
  # Intentionally missing: db/migrations/20260419_add_orders_table.down.sql
expected:
  findings:
    - agent: fg-506-migration-verifier
      category: MIGRATION-ROLLBACK-MISSING
      severity: CRITICAL
      path: db/migrations/20260419_add_orders_table.up.sql
```

- [ ] **Step 8: Create evals/scenarios/resilience-unbounded-retry.yml**

```yaml
name: resilience-unbounded-retry
description: A Kotlin coroutine with unbounded retry loop; expect fg-555 to emit RESILIENCE-RETRY-UNBOUNDED at WARNING.
config_overrides:
  agents:
    resilience_testing:
      enabled: true
      chaos_enabled: false
fixtures:
  - path: src/main/kotlin/com/example/UpstreamClient.kt
    content: |
      import kotlinx.coroutines.*

      suspend fun callUpstream(): String {
        while (true) {
          runCatching { fetch() }.onSuccess { return it }
          // no delay, no backoff, no attempt cap
        }
      }

      suspend fun fetch(): String = "ok"
expected:
  findings:
    - agent: fg-555-resilience-tester
      category: RESILIENCE-RETRY-UNBOUNDED
      severity_at_least: WARNING
      path: src/main/kotlin/com/example/UpstreamClient.kt
```

- [ ] **Step 9: Gate eval fixtures on Phase 01**

If Phase 01 (evaluation harness) is not yet merged, add a leading comment to each of the three YAML files:

```yaml
# Phase 07 eval fixture. Harness ships in Phase 01. If Phase 01 not merged at CI time,
# the harness will skip this file; re-enable by removing the `skip: true` marker below.
skip: true
```

(Remove `skip: true` in a follow-up commit once Phase 01 merges. Note in commit message.)

- [ ] **Step 10: Commit**

```bash
git add tests/contract/ui-frontmatter-consistency.bats tests/contract/agent-registry.bats tests/contract/agent-colors.bats tests/lib/module-lists.bash evals/scenarios/i18n-hardcoded.yml evals/scenarios/migration-no-rollback.yml evals/scenarios/resilience-unbounded-retry.yml
git commit -m "test(phase07): tighten Tier-4 ui: rule, add registry/colors tests, 3 eval fixtures"
```

- [ ] **Step 11: Push branch and open PR**

```bash
git push -u origin HEAD
gh pr create --title "phase07: agent layer refactor (42 → 47, Tier-4 ui: strict, trigger: formalised)" --body "$(cat <<'EOF'
## Summary

Phase 07 of the A+ roadmap — brings the agent population into contract compliance and closes 4 coverage gaps (+ 1 split-off).

- Removes `ui:` frontmatter from 12 Tier-4 agents.
- Adds machine-readable `trigger:` to 5 conditional agents (+ 4 new agents with triggers).
- Splits `fg-417-dependency-reviewer` → `fg-417` (CVE/compat) + new `fg-414-license-reviewer`.
- Slims `fg-413-frontend-reviewer` (534 → ≤400 lines) by moving frontend-performance section into `fg-416-performance-reviewer`.
- Adds 4 new agents: `fg-155-i18n-validator`, `fg-506-migration-verifier`, `fg-143-observability-bootstrap`, `fg-555-resilience-tester`.
- Adds 14 new scoring categories; re-wires existing `I18N-*` affinity to the new owner.
- Formalises `trigger:` grammar in `shared/trigger-grammar.md`.
- Wires license fail-open default (resolves review I1), de-dups duplicate `fg-205` row (resolves review I2), documents trigger expression grammar (resolves review I3).

Agent count: **42 → 47**. No backwards-compat shims (per project policy).

## Test plan
- [ ] CI runs `tests/contract/ui-frontmatter-consistency.bats` (tightened) — Tier-4 agents must omit `ui:`.
- [ ] CI runs `tests/contract/agent-registry.bats` (new) — 47 agents, trigger keys present, category owners exist, trigger syntax valid.
- [ ] CI runs `tests/contract/agent-colors.bats` (new) — cluster-scoped color uniqueness after additions.
- [ ] CI runs three new eval scenarios (skipped until Phase 01 harness merges): `i18n-hardcoded`, `migration-no-rollback`, `resilience-unbounded-retry`.
- [ ] `./tests/run-all.sh` passes full suite.
- [ ] `ls agents/fg-*.md | wc -l` returns 47.
- [ ] `grep -c "47 agent\|47 total" CLAUDE.md` returns ≥ 2.
EOF
)"
```

---

## Verification checklist (run after all commits)

From spec §11 Success Criteria. Each line is a one-command check that CI runs:

- [ ] `ls agents/fg-*.md | wc -l` → 47
- [ ] `bats tests/contract/ui-frontmatter-consistency.bats` → all green, Tier-4 strict rule enforced
- [ ] `bats tests/contract/agent-registry.bats` → all green
- [ ] `bats tests/contract/agent-colors.bats` → all green
- [ ] `wc -l agents/fg-413-frontend-reviewer.md` → ≤400
- [ ] `wc -l agents/fg-417-dependency-reviewer.md` → ≤200
- [ ] `python3 -m json.tool shared/checks/category-registry.json > /dev/null` → exit 0
- [ ] `grep -c "47" CLAUDE.md | head` → 2 new occurrences visible at lines 23 and 116
- [ ] Every category with non-empty `agents:[]` references an existing agent file (enforced by `agent-registry.bats`)
- [ ] Every conditionally-dispatched agent (fg-143, fg-155, fg-320, fg-506, fg-515, fg-555, fg-610, fg-620, fg-650) has `trigger:` frontmatter (enforced by `agent-registry.bats`)

## Review-issue resolution map

| Review issue | Severity | Resolved in |
|---|---|---|
| I1 — License fail-open default not in config contract | Important | Task 13 Step 4 (config templates) + Task 4 Step 3 (agent §2-3) |
| I2 — Duplicate fg-205 row in agent-role-hierarchy.md | Important | Task 11 Step 1 (explicit de-dup commit step) |
| I3 — trigger: grammar unspecified | Important | Task 12 (new `shared/trigger-grammar.md`) |
| I4 — Eval harness (Phase 01) dependency | Important | Task 15 Step 9 (fixtures ship with `skip: true` until Phase 01 merges) |
| S1 — JSONC vs strict JSON in registry example | Suggestion | Task 13 Step 1 (uses strict JSON) |
| S2 — `model: inherit` verification | Suggestion | Task 4 Step 3 + Tasks 5-8 (all new agents use `model: inherit`; if unsupported, downstream CI breakage is the signal — documented in Task 15) |
| S3 — Squash vs bisect | Suggestion | PR description opts for real-commit history (no squash) per user rollout preference; 15 logical commits preserved |

## Out of scope (explicitly NOT in this plan)

Per spec §3.2:

- Merging `fg-205-planning-critic` into `fg-210-validator` (rejected — two-writer invariant is load-bearing).
- Hook rewrites, check-engine L0/L1 changes, MCP-server changes.
- `fg-400-quality-gate` dispatch batching rules (untouched except for the one new reviewer).
