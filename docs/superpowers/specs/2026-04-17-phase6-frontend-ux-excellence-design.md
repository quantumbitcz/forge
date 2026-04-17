# Phase 6 — Frontend UX Excellence (Design)

**Status:** Draft for review
**Date:** 2026-04-17
**Target version:** Forge 4.2.0 (SemVer minor — additive; no breaking changes)
**Author:** Denis Šajnar (authored with Claude Opus 4.7)
**Phase sequence:** 6 of 7
**Depends on:** Phase 5 merged (4.1.0).

---

## 1. Goal

Lift Forge's frontend-development UX to match the 2026 best-of-class baseline set by v0.dev, Lovable, Bolt, Subframe, and Figma MCP. Phase 6 MVP ships four highest-impact deliverables: (1) opt-in shadcn/ui React variant, (2) Figma MCP consumption at PLAN stage (not reactive REVIEW), (3) 40-rule production-grade defaults pack enforced by the frontend reviewer, (4) required `@axe-core/playwright` + visual-regression baseline in preview validation. Remaining FE work (live preview, click-to-edit `/forge-tweak`, variant generation, brand extraction, motion config) deferred to future phases per explicit scope-reduction from brainstorming.

## 2. Context and motivation

The FE research (conducted during Phase 1 audit) surfaced 10 structural gaps in Forge's frontend-development UX:

1. **No shadcn/ui default** — Forge's `modules/frameworks/react/` has no shadcn variant; implementer emits hand-rolled `<div>` components when projects use shadcn.
2. **No Figma MCP at PLAN** — `fg-413-frontend-reviewer` calls `get_design_context` in REVIEW (reactive); by then the implementer has written generic markup.
3. **No Code Connect consumption** — Figma's `Button` → `@/components/ui/button` mapping is ignored; Forge generates generic imports.
4. **No production-grade defaults pack** — 40 rules exist in the research (semantic HTML, tokens, a11y, motion, responsive, state, testing) but aren't codified or enforced.
5. **`@axe-core/playwright` not a required dev dep** — `shared/accessibility-automation.md` mentions axe but doesn't install it.
6. **No VRT baseline** — `shared/visual-verification.md` captures screenshots but doesn't diff against a baseline.
7-10. (Deferred to future phases per brainstorming scope selection.)

Phase 6 MVP addresses gaps 1-6 as four additive deliverables; gaps 7-10 (live preview, click-to-edit, variant generation, brand extraction, motion library config, Storybook prompt references) stay as future work documented in `shared/frontend-defaults-pack.md §Future extensions`.

No backwards compatibility required.

## 3. Non-goals

- **No live preview during IMPLEMENT** (deferred — separate phase).
- **No `/forge-tweak` click-to-edit skill** (deferred).
- **No `/forge-variants` or `/forge-brand-import` skills** (deferred).
- **No `fg-321-ui-variant-generator` or `fg-322-visual-tweak` agents** (deferred).
- **No motion library (Framer Motion / GSAP) config** (deferred to a motion-focused phase).
- **No Storybook `@Story/...` prompt reference syntax** (deferred).
- **No changes to non-React frontend variants** (Vue, Svelte, etc.) — React-first MVP.
- **No Code Connect writeback** from code to Figma (reverse workflow — future phase).

Phase 6 intentionally scoped down per brainstorming. The spec explicitly enumerates the deferred items in `shared/frontend-defaults-pack.md §Future extensions` so they survive as a backlog.

## 4. Design

### 4.1 `modules/frameworks/react/variants/shadcn.md` (new variant)

**Opt-in variant.** Projects using shadcn declare it in `forge.local.md`:

```yaml
components:
  frontend:
    framework: react
    variant: shadcn       # was absent → hand-rolled; now "shadcn" enables variant
```

Variant document structure (~150 lines):

- §1 When to use (React projects with shadcn/ui + Tailwind + Radix)
- §2 Component preference order: (a) use existing shadcn component from `@/components/ui/<name>`; (b) if absent, suggest `npx shadcn add <name>`; (c) last resort — hand-roll per shadcn patterns
- §3 Import conventions (`@/components/ui/button`, `@/lib/utils` for `cn()`)
- §4 Token conventions: CSS variables per shadcn `globals.css`; semantic tokens (`bg-primary`, `text-muted-foreground`) only; no raw hex in components
- §5 Implementer rules: when adding buttons/inputs/dialogs/etc., check `@/components/ui/` first; list the 25 canonical shadcn primitives (Button, Input, Dialog, Sheet, Select, etc.)
- §6 Frontend-polisher rules: respect existing shadcn tokens; never introduce new CSS vars; use `cn()` for conditional classes
- §7 Frontend-reviewer rules: flag hand-rolled components when a shadcn equivalent exists in `@/components/ui/`; flag raw hex colors (`bg-[#FF0000]`) when a semantic token applies
- §8 Testing: Storybook stories for any new shadcn-wrapper; `@axe-core/playwright` required for rendered routes

**Composition order** (per existing Forge module-resolution algorithm in `shared/composition.md`): `shadcn variant > react framework > typescript language > testing > generic layers`. Shadcn's rules take precedence when active.

### 4.2 Figma MCP consumption at PLAN — `shared/figma-integration.md` (new)

**`fg-200-planner.md` extension:** when the user's requirement contains a Figma URL (pattern `figma\.com/(design|board|make)/[a-f0-9]+`), planner calls Figma MCP with two tool invocations:

1. **`get_variable_defs`** — returns the project's design tokens (colors, spacing, typography, shadows, radius) as semantic names. Planner injects into plan as `## Design tokens` section.
2. **`get_code_connect_map`** — returns component → code-import mappings (e.g., `Figma Button` → `@/components/ui/button`). Planner injects as `## Component imports` section.

**Contract doc `shared/figma-integration.md`:**

- §1 Detection (URL regex + user explicit `--figma-url` override flag on `/forge-run`)
- §2 MCP tool call sequence (graceful skip if Figma MCP unavailable)
- §3 Plan injection format (two new sections in the plan markdown)
- §4 Implementer handoff: implementer reads plan `## Design tokens` + `## Component imports`; treats token names as first-class citizens (uses `bg-primary`, not `bg-blue-500`; imports from mapped paths)
- §5 Frontend-reviewer cross-check: after implementation, reviewer re-queries MCP + confirms implementation used the canonical token names / imports. Flags drift as `FE-TOKEN-DRIFT` or `FE-IMPORT-DRIFT` finding (WARNING severity).
- §6 Caching: MCP responses cached to `.forge/figma-cache/{file-key}.json` (1-hour TTL); avoids redundant MCP calls across stages.
- §7 Failure modes (MCP down, no Figma URL, invalid node-id — all degrade gracefully with a single stage note, pipeline continues)

### 4.3 `shared/frontend-defaults-pack.md` (new — the 40 rules)

40 rules grouped by category. Each rule:
- ID: `FE-<CAT>-<NNN>` (e.g., `FE-A11Y-015`)
- Rule statement (one sentence, testable)
- Severity (CRITICAL / WARNING)
- Rationale (one paragraph)
- Detection (bats-enforceable or reviewer-enforced)
- Exemption mechanism (`// forge-allow: FE-A11Y-015 reason: ...` inline marker)

**Categories (counts):**

| Category | Count | Severity mix |
|---|---|---|
| Semantic HTML | 8 | 2 CRITICAL, 6 WARNING |
| Design tokens | 6 | 4 WARNING, 2 CRITICAL (raw-hex ban) |
| Accessibility (WCAG 2.2 AA) | 8 | 6 CRITICAL, 2 WARNING |
| Motion | 5 | 5 WARNING |
| Responsive | 5 | 2 CRITICAL (320px overflow, touch target), 3 WARNING |
| State management | 4 | 4 WARNING |
| Testing & docs | 4 | 2 CRITICAL (no Storybook story for new component), 2 WARNING |

**Sample rules (illustrative — full list in the document):**

- `FE-SEMANTIC-001` CRITICAL: `<button>` for actions, `<a href>` for navigation. Never `<div onClick>`.
- `FE-A11Y-011` CRITICAL: Every form input has programmatic `<label for>` or `aria-labelledby`.
- `FE-TOKENS-002` CRITICAL: No raw hex color literals in components (`bg-[#FF0000]`) — must use token.
- `FE-MOTION-024` WARNING: Only animate `transform` and `opacity`; never `width`/`height`/`top`/`left`.
- `FE-TEST-038` CRITICAL: Every new component has a Storybook story (or an exemption marker explaining why).

**Enforcement:**

- **`fg-413-frontend-reviewer.md`** extended (§4.4) — loads `shared/frontend-defaults-pack.md`, scans changed files against each rule, emits findings with rule ID + severity + fix suggestion.
- **`fg-320-frontend-polisher.md`** (§4.5) — actively enforces WARNING-level rules during polish (auto-fix where safe; raise finding otherwise).
- **`tests/contract/frontend-defaults.bats`** asserts the rules file is well-formed (40 rules, all have ID/severity/rationale/detection fields) and loadable.

### 4.4 `@axe-core/playwright` required dev dep + VRT baseline

#### 4.4.1 Required dev dep

`shared/accessibility-automation.md` extension:

- Add explicit install step: `pnpm add -D @axe-core/playwright @axe-core/react` (or npm/yarn equivalents per project's package manager detected at PREFLIGHT).
- `fg-650-preview-validator.md` extended — dispatches `@axe-core/playwright` against every new user-facing route via Playwright MCP. CRITICAL violations block PR.
- `@axe-core/react` added to dev deps — enables runtime console warnings during local dev.

#### 4.4.2 Visual regression baseline — `shared/visual-regression-baseline.md` (new)

Chromatic-equivalent baseline model without the SaaS:

- `.forge/vrt/baselines/<route>-<viewport>.png` — committed baseline screenshots per route per breakpoint (mobile/tablet/desktop).
- `fg-650-preview-validator.md` captures fresh screenshots at the same set; diffs against baseline via pixelmatch-like comparison (Python Pillow diff or `odiff`-like npm dep).
- Threshold: 1% pixel diff default; configurable per-route in `.forge/vrt/config.yaml`.
- Diff > threshold → WARNING finding with diff image saved to `.forge/vrt/diffs/`; user reviews + regenerates baseline via new `/forge-vrt-update` skill (adds 41st skill; skill count 40 → 41).
- Baselines gitignored by default (too large); project can opt in to committing them via `vrt.commit_baselines: true` config.

#### 4.4.3 `/forge-vrt-update` (new skill)

`[writes]` — promotes current screenshots to baselines. Used after intentional UI changes when reviewer has validated visually.

Flags: `--help`, `--dry-run`, per skill-contract.

### 4.5 Frontend agent updates

**`fg-200-planner.md`:**
- New `## § Figma MCP consumption` section — detect URL, call MCP, inject into plan. Details in `shared/figma-integration.md §2-3`.

**`fg-300-implementer.md`:**
- New `## § shadcn component preference` section — when `components.frontend.variant: shadcn` is configured, check `@/components/ui/` before hand-rolling. Reference the variant doc.
- New `## § Plan token consumption` section — read plan's `## Design tokens` + `## Component imports` sections; treat as first-class inputs.

**`fg-320-frontend-polisher.md`:**
- New `## § Defaults pack enforcement` section — active enforcement of WARNING-level rules during polish.
- Cross-references `shared/frontend-defaults-pack.md`.

**`fg-413-frontend-reviewer.md`:**
- New `## § 40-rule defaults review` section — loads the pack, scans, emits findings.
- Existing `mcp__plugin_figma_figma__get_design_context` call extended with `get_code_connect_map` call.

**`fg-650-preview-validator.md`:**
- New `## § axe-core Playwright validation` section.
- New `## § Visual regression diff` section.
- Cross-references to `shared/accessibility-automation.md` + `shared/visual-regression-baseline.md`.

### 4.6 Documentation updates

- `README.md` — new "Frontend development UX (4.2.0+)" section.
- `CLAUDE.md` — 4 new Key Entry Points: `modules/frameworks/react/variants/shadcn.md`, `shared/figma-integration.md`, `shared/frontend-defaults-pack.md`, `shared/visual-regression-baseline.md`. Skill count `40 → 41`.
- `CHANGELOG.md` — 4.2.0 entry.
- `docs/frontend-guide.md` (new) — user-facing walkthrough: configuring shadcn variant, using Figma URLs, understanding defaults-pack findings, updating VRT baselines.
- `shared/frontend-design-theory.md` — cross-reference new defaults pack + Figma integration.
- `shared/visual-verification.md` — cross-reference VRT baseline.
- `shared/accessibility-automation.md` — install instructions for @axe-core deps.
- `.claude-plugin/plugin.json`, `marketplace.json` — `4.1.0 → 4.2.0`.

### 4.7 Configuration additions

`forge.local.md`:

```yaml
components:
  frontend:
    framework: react
    variant: shadcn       # NEW — existing `variant:` key; `shadcn` is new valid value

frontend:
  defaults_pack_enabled: true    # NEW — master switch
  axe_core_required: true        # NEW — install @axe-core deps at /forge-init

vrt:
  enabled: true                  # NEW — visual regression enabled
  diff_threshold_pct: 1.0        # NEW — percent pixel diff to flag
  commit_baselines: false        # NEW — opt-in baseline commits

figma:
  plan_stage_mcp: true           # NEW — enable MCP calls at PLAN
  cache_ttl_seconds: 3600        # NEW — Figma cache TTL
```

`shared/config-schema.json` schemas for all new keys.

### 4.8 Deferred item tracking — `shared/frontend-defaults-pack.md §Future extensions`

Appendix listing scope-deferred items with one-line justification:

- Live preview during IMPLEMENT
- `/forge-tweak` click-to-edit skill
- `/forge-variants` 3-take generation skill
- `/forge-brand-import` URL-scrape brand extraction
- Motion library variant (Framer Motion / GSAP)
- Storybook `@Story/...` prompt reference
- Vue / Svelte / Solid shadcn-equivalents
- Code Connect reverse writeback
- Multi-viewport parallel polish
- Auto-revision history

## 5. File manifest

### 5.1 Delete

None.

### 5.2 Create (7 files)

```
modules/frameworks/react/variants/shadcn.md
shared/figma-integration.md
shared/frontend-defaults-pack.md
shared/visual-regression-baseline.md
skills/forge-vrt-update/SKILL.md
docs/frontend-guide.md
tests/contract/frontend-defaults.bats
```

### 5.3 Update in place (17 files)

- **Agents (5):** `fg-200-planner`, `fg-300-implementer`, `fg-320-frontend-polisher`, `fg-413-frontend-reviewer`, `fg-650-preview-validator`.
- **Shared (4):** `frontend-design-theory.md`, `visual-verification.md`, `accessibility-automation.md`, `config-schema.json`.
- **Framework module (1):** `modules/frameworks/react/conventions.md` — cross-ref shadcn variant.
- **Top-level (6):** `README.md`, `CLAUDE.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `tests/validate-plugin.sh` (skill-count assertion 40 → 41).
- **Skill count bump (1):** Phase 5's skill count assertion in `live-observation.bats` needs to note 40 baseline; Phase 6 adds 1 skill → 41. Update `tests/contract/live-observation.bats` Group B skill-count assertion to handle either value based on detection, OR make the Phase 5 assertion exactly 40 and add a new Phase 6 assertion for 41. Cleanest: Phase 6 adds a new assertion in `tests/contract/frontend-defaults.bats` for count=41; Phase 5's existing assertion stays at 40 but gated on `FORGE_PHASE5_ACTIVE && ! FORGE_PHASE6_ACTIVE`.

### 5.4 File-count arithmetic

| Category | Count |
|---|---|
| Creations | 7 |
| Agent updates | 5 |
| Shared doc updates | 4 |
| Framework module update | 1 |
| Top-level + CI | 6 |
| **Total unique files** | **23** |

## 6. Acceptance criteria

All verified by CI on push.

1. `modules/frameworks/react/variants/shadcn.md` exists with 8 sections per §4.1.
2. `shared/figma-integration.md` exists with 7 sections per §4.2.
3. `shared/frontend-defaults-pack.md` exists with 40 rules (exactly); each rule has ID / severity / rationale / detection / exemption-syntax fields.
4. `shared/visual-regression-baseline.md` exists; documents `.forge/vrt/` layout + diff threshold + `/forge-vrt-update` flow.
5. `skills/forge-vrt-update/SKILL.md` exists with Phase 1 skill-contract compliance.
6. `agents/fg-200-planner.md` has `## § Figma MCP consumption` section referencing `shared/figma-integration.md`.
7. `agents/fg-300-implementer.md` has `## § shadcn component preference` + `## § Plan token consumption` sections.
8. `agents/fg-320-frontend-polisher.md` has `## § Defaults pack enforcement` section.
9. `agents/fg-413-frontend-reviewer.md` has `## § 40-rule defaults review` section + extended Figma MCP calls (now includes `get_code_connect_map`).
10. `agents/fg-650-preview-validator.md` has `## § axe-core Playwright validation` + `## § Visual regression diff` sections.
11. `shared/config-schema.json` validates `components.frontend.variant: shadcn`, `frontend.*`, `vrt.*`, `figma.*` keys.
12. `tests/contract/frontend-defaults.bats` passes: 40-rule count assertion; rule-format assertion; cross-references resolve.
13. `tests/validate-plugin.sh` skill-count assertion bumped to accept 41 post-Phase-6.
14. `README.md`, `CLAUDE.md`, `CHANGELOG.md`, `docs/frontend-guide.md` (new) all present and updated.
15. `shared/frontend-design-theory.md`, `visual-verification.md`, `accessibility-automation.md` cross-reference new files.
16. `.claude-plugin/plugin.json` + `marketplace.json` set to `4.2.0`.
17. CI green on push.

## 7. Test strategy

**Static (bats):**
- New `tests/contract/frontend-defaults.bats` — 40-rule assertion, format check, reference resolution.
- Existing `tests/contract/ui-frontmatter-consistency.bats` — auto-picks up agent changes.
- Existing `tests/contract/skill-contract.bats` — auto-picks up `/forge-vrt-update`.
- Extension to `tests/validate-plugin.sh` — skill-count 41.

**Cross-file (Group B gated on `FORGE_PHASE6_ACTIVE` sentinel):**
- Agent `## §` section presence checks (per AC 6-10).
- Config schema schema-validates new keys (ajv-like check via python3 jsonschema).

**Runtime:** No new runtime tests in Phase 6; FE changes are contract-doc + agent-prose. Runtime validation of actual frontend output is deferred to the Playwright-integration layer which is Phase 6-external.

Per user: no local runs.

## 8. Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Figma MCP unavailable at PLAN causes pipeline failure | Medium | Medium | `fg-200-planner` degrades gracefully — if MCP call fails, emits E1 advisory + proceeds without token/import injection. Implementer then uses conventions without specific Figma context |
| shadcn variant is too opinionated for some React projects | Low | Low | Variant is opt-in; absent from config → current behavior unchanged |
| 40 rules create noisy reviewer findings on legitimate code | Medium | Medium | Exemption mechanism (inline `// forge-allow: FE-RULE-ID reason: ...` markers); reviewer counts exemptions per-file; flags if >5 exemptions (architectural smell) |
| VRT baselines drift against legitimate redesigns | High | Low | `/forge-vrt-update` skill + per-route threshold config; reviewer recommends baseline update when WARNING count is high |
| `@axe-core/playwright` + `@axe-core/react` install adds dev deps to all frontend projects | Low | Low | Config `frontend.axe_core_required: false` disables auto-install for projects that already have alternative a11y tooling |
| Figma cache stale across sessions | Low | Low | 1-hour TTL + cache-bust on explicit `--figma-refresh` flag |
| 40 rules hard-coded in markdown drift from actual reviewer scan code | Medium | Medium | `tests/contract/frontend-defaults.bats` asserts every rule ID in the markdown is matched by a reviewer-prose reference in `fg-413-frontend-reviewer.md` |
| Code Connect map empty for projects without Figma integration | Low | Low | MCP call returns empty map → planner skips injection silently |
| shadcn variant doc drifts from upstream shadcn/ui CLI | Medium | Low | Variant doc cites shadcn/ui v4+ (2026-03 CLI); quarterly refresh documented in `shared/frontend-defaults-pack.md §Future extensions` |
| VRT pixel-diff on macOS vs Linux CI renders differently (font hinting) | High | Medium | Baselines generated per-OS (`.forge/vrt/baselines/<os>/<route>-<viewport>.png`); reviewer flags cross-OS diffs separately |
| Skill count assertion drift across phases | Low | Low | Test `tests/validate-plugin.sh` uses a variable `PHASE_{N}_SKILL_COUNT` that each phase updates |

## 9. Rollout

1. **Commit 1 — Specs land.** This spec + plan.
2. **Commit 2 — Foundations.** 3 new shared docs (`figma-integration.md`, `frontend-defaults-pack.md`, `visual-regression-baseline.md`) + shadcn variant doc + `forge-vrt-update` SKILL.md + `frontend-defaults.bats` skeleton. Group A active. CI green.
3. **Commit 3 — Agent updates batch 1 (planner + implementer).** `fg-200-planner` Figma MCP section; `fg-300-implementer` shadcn + plan-token sections. CI green.
4. **Commit 4 — Agent updates batch 2 (polisher + reviewer + preview-validator).** Defaults pack enforcement + axe-core + VRT sections. CI green.
5. **Commit 5 — Shared doc cross-refs + config schema.** `frontend-design-theory.md`, `visual-verification.md`, `accessibility-automation.md`, `config-schema.json`, `modules/frameworks/react/conventions.md`. CI green.
6. **Commit 6 — User guide + top-level docs + version bump + sentinel.** README, CLAUDE.md, CHANGELOG, `docs/frontend-guide.md`, `validate-plugin.sh` skill-count, plugin.json, marketplace.json → 4.2.0. `FORGE_PHASE6_ACTIVE=1` sentinel activates Group B. CI green.
7. **Push → CI → tag `v4.2.0` → release.**

## 10. Versioning rationale

Purely additive. Opt-in variant; new optional config keys; new skill (not replacing anything); new contract docs. No existing behavior changes unless user opts in. `4.1.0 → 4.2.0`.

## 11. Open questions

None. All scope decisions locked in brainstorming.

## 12. References

- Phase 1-5 specs (same directory).
- FE research (conducted during Phase 1 audit; synthesized 20 patterns + 10 gaps + 40 rules).
- `shared/frontend-design-theory.md` — existing design theory (pre-Phase-6); Phase 6 extends.
- `shared/visual-verification.md` — existing Playwright MCP usage; Phase 6 adds VRT baseline layer.
- `shared/accessibility-automation.md` — existing axe references; Phase 6 mandates install.
- shadcn/ui v4 CLI (2026-03); Figma MCP (`get_variable_defs`, `get_code_connect_map`).
- User instruction: "I initially meant the UI and UX for FE development can you do the research as well?"
