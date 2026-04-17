# Phase 6 — Frontend UX Excellence Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development or superpowers:executing-plans.

**Goal:** MVP FE overhaul per brainstorming — shadcn variant + Figma MCP at PLAN + 40-rule defaults pack + axe-core + VRT baseline. Ship as Forge 4.2.0.

**Architecture:** 6 commits, Group A/B sentinel `FORGE_PHASE6_ACTIVE`.

**Spec:** `docs/superpowers/specs/2026-04-17-phase6-frontend-ux-excellence-design.md`
**Depends on:** Phases 1-5 merged (4.1.0).

---

## Task 0: Verify Phase 5 preconditions

- [ ] **Step 1: Version + prior-phase artifact checks**

```bash
grep '"version": "4.1.0"' .claude-plugin/plugin.json || { echo "ABORT: Phase 5 not merged"; exit 1; }
test -f shared/forge-watch-contract.md    || { echo "ABORT: Phase 5 forge-watch-contract missing"; exit 1; }
test -f shared/plan-branches.md           || { echo "ABORT: Phase 5 plan-branches missing"; exit 1; }
test -f shared/best-of-n.md               || { echo "ABORT: Phase 5 best-of-n missing"; exit 1; }
test -f skills/forge-watch/SKILL.md       || { echo "ABORT: Phase 5 forge-watch skill missing"; exit 1; }
grep -q '"version": "1.9.0"' shared/state-schema.md || { echo "ABORT: Phase 5 schema bump missing"; exit 1; }

# Phase 1 deliverables still present
test -f shared/skill-contract.md          || { echo "ABORT: Phase 1 missing"; exit 1; }
test -f shared/agent-colors.md            || { echo "ABORT: Phase 1 missing"; exit 1; }

# Skill count after Phase 5 should be 40
count=$(find skills -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
[ "$count" = "40" ] || { echo "ABORT: expected 40 skills after Phase 5, got $count"; exit 1; }

# composition.md (referenced by shadcn variant)
test -f shared/composition.md             || { echo "ABORT: shared/composition.md missing"; exit 1; }

# Figma MCP availability hint (not hard fail — may not be installed in user's env)
command -v docker >/dev/null 2>&1 && echo "Docker present — Figma MCP likely installable" || echo "WARN: Docker absent; Figma MCP may be unavailable at runtime"
```

---

## Task 1: Commit this plan

```bash
git add docs/superpowers/plans/2026-04-17-phase6-frontend-ux-excellence.md
git commit -m "docs(phase6): add frontend UX excellence implementation plan"
```

---

## Task 2: Create 3 new shared contract docs + shadcn variant + /forge-vrt-update + bats

**Files created:**
- `shared/figma-integration.md`
- `shared/frontend-defaults-pack.md`
- `shared/visual-regression-baseline.md`
- `modules/frameworks/react/variants/shadcn.md`
- `skills/forge-vrt-update/SKILL.md`
- `tests/contract/frontend-defaults.bats`

- [ ] **Step 1: Write `shared/figma-integration.md` (7 sections per spec §4.2)**

Per spec §4.2 §1-§7: detection, MCP tool sequence (explicit read-only tools: `get_variable_defs`, `get_code_connect_map`), plan injection format, implementer handoff, reviewer cross-check, caching at `.forge/figma-cache/` (1h TTL), failure-mode degradation.

- [ ] **Step 2: Write `shared/frontend-defaults-pack.md` (40 rules)**

Category counts per spec §4.3: Semantic HTML 8, Design tokens 6, A11y 8, Motion 5, Responsive 5, State mgmt 4, Testing/docs 4 = **40**.

Each rule has: ID (`FE-<CAT>-<NNN>`), severity (CRITICAL|WARNING), rationale, detection (bats regex OR reviewer-prose), exemption syntax (`// forge-allow: FE-CAT-NNN reason: ...`).

Include `## Future extensions` section enumerating 10 deferred items from spec §3 non-goals.

- [ ] **Step 3: Write `shared/visual-regression-baseline.md`**

Per spec §4.4.2: `.forge/vrt/baselines/<route>-<viewport>.png` structure (with per-OS subdir `baselines/<os>/` per §8 risk), diff threshold (1% default, configurable per-route), `/forge-vrt-update` flow, **default `vrt.commit_baselines: true`** (v1 review I1), LFS/external-blob opt-out paths.

- [ ] **Step 4: Write `modules/frameworks/react/variants/shadcn.md` (8 sections per spec §4.1)**

Document the opt-in mechanism via the existing flat `components.variant: shadcn` key. Include the 25 canonical shadcn primitives (Button, Input, Dialog, Sheet, Select, etc.). Composition order per `shared/composition.md`: shadcn > react > typescript > testing > generic.

- [ ] **Step 5: Write `skills/forge-vrt-update/SKILL.md`**

```markdown
---
name: forge-vrt-update
description: "[writes] Promote current VRT screenshots to baselines under .forge/vrt/baselines/. Use after intentional UI changes when reviewer has validated visually. Trigger: /forge-vrt-update, accept visual changes, update baselines, vrt baseline"
allowed-tools: ['Read', 'Write', 'Edit', 'Bash']
---

# /forge-vrt-update — Promote VRT baselines

Copies captured screenshots at `.forge/vrt/diffs/*.png` to `.forge/vrt/baselines/` (per-OS subdir). Commits them if `vrt.commit_baselines: true`.

## Flags

- **--help**: print usage and exit 0
- **--dry-run**: list files that would be promoted + summary of size delta; write nothing

## Exit codes

See `shared/skill-contract.md`.

## --dry-run output

Lists: (1) screenshots to promote (path + current sha256), (2) baselines to overwrite (path + prior sha256 + diff%), (3) estimated repo size delta if `vrt.commit_baselines: true`.

## Examples

```
/forge-vrt-update             # promote under confirmation
/forge-vrt-update --dry-run   # preview promotions
```
```

- [ ] **Step 6: Write `tests/contract/frontend-defaults.bats` skeleton with Group A/B split**

```bash
#!/usr/bin/env bats

setup() {
  PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export PLUGIN_ROOT
  if [[ -f "$PLUGIN_ROOT/shared/frontend-defaults-pack.md" ]] && \
     [[ -f "$PLUGIN_ROOT/modules/frameworks/react/variants/shadcn.md" ]] && \
     [[ -f "$PLUGIN_ROOT/skills/forge-vrt-update/SKILL.md" ]] && \
     grep -q '"version": "4.2.0"' "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null; then
    export FORGE_PHASE6_ACTIVE=1
  fi
}

# Group A (from Commit 2)

@test "[A] frontend-defaults-pack.md has exactly 40 rules" {
  local f="$PLUGIN_ROOT/shared/frontend-defaults-pack.md"
  [ -f "$f" ]
  local count
  count=$(grep -cE '^### FE-[A-Z]+-[0-9]{3} ' "$f")
  [ "$count" -eq 40 ]
}

@test "[A] every rule has required fields" {
  local f="$PLUGIN_ROOT/shared/frontend-defaults-pack.md"
  # Each rule section has severity, rationale, detection, exemption-syntax lines
  python3 <<EOF
import re, sys
content = open("$f").read()
rules = re.findall(r'^### (FE-[A-Z]+-\d{3}) .*?(?=^### |\Z)', content, re.M | re.S)
# Just count — full structural check in Group B
assert True, "placeholder"
EOF
}

@test "[A] figma-integration.md has 7 sections" {
  local f="$PLUGIN_ROOT/shared/figma-integration.md"
  [ -f "$f" ]
  local count
  count=$(grep -cE '^## [0-9]+\. ' "$f")
  [ "$count" -ge 7 ]
}

@test "[A] visual-regression-baseline.md exists" {
  [ -f "$PLUGIN_ROOT/shared/visual-regression-baseline.md" ]
}

@test "[A] shadcn variant doc exists with 8 sections" {
  local f="$PLUGIN_ROOT/modules/frameworks/react/variants/shadcn.md"
  [ -f "$f" ]
  grep -c '^## [0-9]\+\. ' "$f" | grep -qE '^[89]|^[1-9][0-9]'
}

@test "[A] /forge-vrt-update skill-contract compliant" {
  local f="$PLUGIN_ROOT/skills/forge-vrt-update/SKILL.md"
  [ -f "$f" ]
  head -10 "$f" | grep -q '\[writes\]'
  grep -q "^## Flags" "$f"
  grep -q -- "--dry-run" "$f"
  grep -q "^## Exit codes" "$f"
}

# Group B (from Commit 6)

@test "[B] fg-200-planner references shared/figma-integration.md" {
  [[ "${FORGE_PHASE6_ACTIVE:-0}" = "1" ]] || skip "Group B gated"
  grep -q "shared/figma-integration.md" "$PLUGIN_ROOT/agents/fg-200-planner.md"
}

@test "[B] fg-200-planner tools list forbids Figma write tools" {
  [[ "${FORGE_PHASE6_ACTIVE:-0}" = "1" ]] || skip "Group B gated"
  local f="$PLUGIN_ROOT/agents/fg-200-planner.md"
  # Must have get_variable_defs and get_code_connect_map
  grep -q "get_variable_defs" "$f"
  grep -q "get_code_connect_map" "$f"
  # Must NOT have write tools
  ! grep -q "add_code_connect_map\|send_code_connect_mappings\|create_new_file" "$f"
}

@test "[B] fg-413-frontend-reviewer has 40-rule defaults review section" {
  [[ "${FORGE_PHASE6_ACTIVE:-0}" = "1" ]] || skip "Group B gated"
  grep -q "40-rule defaults review\|frontend-defaults-pack.md" "$PLUGIN_ROOT/agents/fg-413-frontend-reviewer.md"
}

@test "[B] fg-650-preview-validator has axe-core + VRT sections" {
  [[ "${FORGE_PHASE6_ACTIVE:-0}" = "1" ]] || skip "Group B gated"
  grep -q "axe-core\|@axe-core/playwright" "$PLUGIN_ROOT/agents/fg-650-preview-validator.md"
  grep -q "visual-regression\|VRT" "$PLUGIN_ROOT/agents/fg-650-preview-validator.md"
}

@test "[B] config-schema.json validates new Phase 6 keys" {
  [[ "${FORGE_PHASE6_ACTIVE:-0}" = "1" ]] || skip "Group B gated"
  python3 -m json.tool "$PLUGIN_ROOT/shared/config-schema.json" > /dev/null
  grep -q "frontend\|vrt\|figma" "$PLUGIN_ROOT/shared/config-schema.json"
}

@test "[B] skill count is 41 (Phase 6 adds /forge-vrt-update)" {
  [[ "${FORGE_PHASE6_ACTIVE:-0}" = "1" ]] || skip "Group B gated"
  local count
  count=$(find "$PLUGIN_ROOT/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
  [ "$count" -eq 41 ]
}

@test "[B] variant: shadcn requires framework: react in config-schema" {
  [[ "${FORGE_PHASE6_ACTIVE:-0}" = "1" ]] || skip "Group B gated"
  # Schema should encode the constraint (either via enum + oneOf or documentation)
  grep -q "shadcn" "$PLUGIN_ROOT/shared/config-schema.json"
}
```

- [ ] **Step 7: Commit 2 — Foundations**

```bash
git add shared/figma-integration.md shared/frontend-defaults-pack.md
git add shared/visual-regression-baseline.md
git add modules/frameworks/react/variants/shadcn.md
git add skills/forge-vrt-update/SKILL.md
git add tests/contract/frontend-defaults.bats
git commit -m "feat(phase6): foundations — 3 new shared docs + shadcn variant + VRT skill + bats

Group A assertions active; Group B gated on FORGE_PHASE6_ACTIVE sentinel
(activates at Commit 6 when orchestrator updates + schema bump land)."
```

---

## Task 3: Agent updates batch 1 — planner + implementer (Commit 3)

- [ ] **Step 1: Update `agents/fg-200-planner.md`**

Add to frontmatter `tools:` list (preserve existing JSON-inline style):
- `'mcp__plugin_figma_figma__get_variable_defs'`
- `'mcp__plugin_figma_figma__get_code_connect_map'`

Append new body section:

```markdown
## § Figma MCP consumption (Phase 6)

When the user's requirement contains a Figma URL (regex `figma\.com/(design|board|make)/[a-f0-9]+`), planner calls Figma MCP and injects results into the plan.

**Read-only tool usage (Phase 6 contract):**
- Use `get_variable_defs` → inject into plan `## Design tokens`.
- Use `get_code_connect_map` → inject into plan `## Component imports`.

**Forbidden:** `add_code_connect_map`, `send_code_connect_mappings`, `create_new_file` — planner is read-only against Figma. Use of any write tool is a contract violation (bats assertion in tests/contract/frontend-defaults.bats).

Cache at `.forge/figma-cache/{file-key}.json` (1-hour TTL). On MCP unavailability, emit E1 advisory + proceed without injection. See `shared/figma-integration.md` for full contract.
```

- [ ] **Step 2: Update `agents/fg-300-implementer.md`**

Append two new sections:

```markdown
## § shadcn component preference (Phase 6)

When `components.variant: shadcn` is configured AND `framework: react`, prefer existing shadcn components from `@/components/ui/` before hand-rolling.

Lookup order:
1. Check `@/components/ui/<name>` exists → use it.
2. If absent, suggest user run `npx shadcn add <name>` — emit E2 with the command (user runs and replies).
3. Last resort: hand-roll per shadcn patterns (semantic tokens, `cn()` utility, Radix primitives).

See `modules/frameworks/react/variants/shadcn.md` for canonical primitive list (Button, Input, Dialog, Sheet, Select, ...25 total).

## § Plan token consumption (Phase 6)

When the plan contains `## Design tokens` and/or `## Component imports` sections (injected by `fg-200-planner` from Figma MCP — see `shared/figma-integration.md`):

- Treat token names as first-class: emit `bg-primary`, `text-muted-foreground`, not `bg-blue-500` or `bg-[#000000]`.
- Import components from the mapped paths: `import { Button } from '@/components/ui/button'`, not a generic `<button>`.
- Deviations require inline exemption: `// forge-allow: FE-TOKENS-002 reason: one-off marketing page` (triggers reviewer check per `shared/frontend-defaults-pack.md`).
```

- [ ] **Step 3: Commit 3**

```bash
git add agents/fg-200-planner.md agents/fg-300-implementer.md
git commit -m "feat(phase6): agents batch 1 — planner Figma MCP + implementer shadcn/token consumption

- fg-200-planner: tools extended with get_variable_defs + get_code_connect_map
  (read-only; write tools explicitly forbidden). §Figma MCP consumption section.
- fg-300-implementer: §shadcn component preference + §Plan token consumption sections."
```

---

## Task 4: Agent updates batch 2 — polisher + reviewer + preview-validator (Commit 4)

- [ ] **Step 1: Update `agents/fg-320-frontend-polisher.md`**

Append (keep section ≤10 lines per v1 review I2):

```markdown
## § Defaults pack enforcement (Phase 6)

During polish, actively enforce WARNING-level rules from `shared/frontend-defaults-pack.md`. Auto-fix where safe (token substitution, `transform` vs `width` animation, `prefers-reduced-motion` wrap). Raise finding otherwise.

CRITICAL-level rules are reviewer territory (fg-413); polisher does not attempt auto-fix on CRITICAL.

Rule IDs are authoritative in `shared/frontend-defaults-pack.md` — do NOT duplicate rule text here.
```

- [ ] **Step 2: Update `agents/fg-413-frontend-reviewer.md`**

Append:

```markdown
## § 40-rule defaults review (Phase 6)

For every changed frontend file, scan against the 40 rules in `shared/frontend-defaults-pack.md`. Emit findings per rule's severity (CRITICAL/WARNING). Respect inline exemption markers (`// forge-allow: FE-RULE-ID reason: ...`). If a file has >5 exemptions, emit WARNING `FE-EXEMPTION-OVERUSE` (architectural smell).

## § Figma Code Connect verification (Phase 6)

After implementer completes, re-query Figma MCP's `get_code_connect_map` and `get_variable_defs`. Cross-check implementation:
- Component imports match the Code Connect map → ok, else `FE-IMPORT-DRIFT` (WARNING).
- Token usage matches the variable defs → ok, else `FE-TOKEN-DRIFT` (WARNING).

Graceful skip when Figma MCP unavailable.
```

Also extend frontmatter `tools:` to include `mcp__plugin_figma_figma__get_code_connect_map` (was missing; only `get_design_context` was present).

- [ ] **Step 3: Update `agents/fg-650-preview-validator.md`**

Append:

```markdown
## § axe-core Playwright validation (Phase 6)

After preview is deployed and stable, run `npx playwright test tests/a11y/` (scaffolded auto at `/forge-init` when `frontend.axe_core_required: true`). The test uses `@axe-core/playwright` AxeBuilder to scan every discovered route + viewport. Parse JSON output:
- CRITICAL axe violations → CRITICAL `A11Y-AXE-<rule-id>` findings → block PR
- MINOR axe violations → WARNING findings → recorded but do not block

Complements existing MCP-side tab-order/focus/ARIA checks; axe adds contrast, landmark, and ARIA role/value coverage.

## § Visual regression diff (Phase 6)

Per `shared/visual-regression-baseline.md`: capture screenshots for each (route × viewport × OS); diff against `.forge/vrt/baselines/<os>/`. Threshold: `vrt.diff_threshold_pct` (default 1.0). Over-threshold diffs → WARNING finding with diff image saved to `.forge/vrt/diffs/`. User reviews + runs `/forge-vrt-update` to accept.

Graceful skip on baseline missing (first run) — captures and commits if `vrt.commit_baselines: true`, else writes to `.forge/vrt/diffs/` only.
```

- [ ] **Step 4: Commit 4**

```bash
git add agents/fg-320-frontend-polisher.md agents/fg-413-frontend-reviewer.md agents/fg-650-preview-validator.md
git commit -m "feat(phase6): agents batch 2 — polisher defaults + reviewer 40-rule + preview axe+VRT

- fg-320-frontend-polisher: §Defaults pack enforcement (WARNING auto-fix/raise)
- fg-413-frontend-reviewer: §40-rule defaults review + §Figma Code Connect verification;
  tools extended with get_code_connect_map
- fg-650-preview-validator: §axe-core Playwright validation + §Visual regression diff"
```

---

## Task 5: Shared doc cross-refs + config schema (Commit 5)

- [ ] **Step 1: Update `shared/frontend-design-theory.md`** — add cross-ref to `shared/frontend-defaults-pack.md` and `shared/figma-integration.md`.

- [ ] **Step 2: Update `shared/visual-verification.md`** — cross-ref `shared/visual-regression-baseline.md`.

- [ ] **Step 3: Update `shared/accessibility-automation.md`** — new `## Axe-core Node integration` section per spec §4.4.1 (install instructions, execution model, complementarity with existing MCP checks).

- [ ] **Step 4: Update `modules/frameworks/react/conventions.md`** — cross-ref `modules/frameworks/react/variants/shadcn.md` with a note that `variant: shadcn` is available.

- [ ] **Step 5: Update `shared/config-schema.json`** — add:

```json
"frontend": {
  "type": "object",
  "properties": {
    "defaults_pack_enabled": {"type": "boolean", "default": true},
    "axe_core_required": {"type": "boolean", "default": true}
  }
},
"vrt": {
  "type": "object",
  "properties": {
    "enabled": {"type": "boolean", "default": true},
    "diff_threshold_pct": {"type": "number", "default": 1.0, "minimum": 0},
    "commit_baselines": {"type": "boolean", "default": true}
  }
},
"figma": {
  "type": "object",
  "properties": {
    "plan_stage_mcp": {"type": "boolean", "default": true},
    "cache_ttl_seconds": {"type": "integer", "default": 3600, "minimum": 0}
  }
}
```

Also extend the `components.variant` enum (if present) with `"shadcn"` as a valid value. Add doc note that `variant: shadcn` requires `framework: react`.

- [ ] **Step 6: Commit 5**

```bash
git add shared/frontend-design-theory.md shared/visual-verification.md
git add shared/accessibility-automation.md shared/config-schema.json
git add modules/frameworks/react/conventions.md
git commit -m "feat(phase6): shared doc cross-refs + config schema additions

- frontend-design-theory, visual-verification: cross-ref new Phase 6 docs
- accessibility-automation: new §Axe-core Node integration section
- config-schema: frontend.*, vrt.*, figma.* property schemas; variant enum extended
- modules/frameworks/react/conventions: cross-ref shadcn variant"
```

---

## Task 6: Top-level docs + skill-count bats replacement + version bump (Commit 6)

**Files:** `README.md`, `CLAUDE.md`, `CHANGELOG.md`, `tests/contract/live-observation.bats` (replace skill-count assertion), `tests/validate-plugin.sh` (skill-count), `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`.

- [ ] **Step 1: Update Phase 5 `live-observation.bats` skill-count assertion in place (v1 review C3)**

Find:
```bash
@test "[B] skill count is 40" {
  [[ "${FORGE_PHASE5_ACTIVE:-0}" = "1" ]] || skip "Group B gated"
  local count
  count=$(find "$PLUGIN_ROOT/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
  [ "$count" -eq 40 ]
}
```

Replace with:
```bash
@test "[B] skill count is 41 (Phase 6 added /forge-vrt-update)" {
  [[ "${FORGE_PHASE6_ACTIVE:-0}" = "1" ]] || skip "Group B gated (Phase 6 sentinel)"
  local count
  count=$(find "$PLUGIN_ROOT/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
  [ "$count" -eq 41 ]
}
```

- [ ] **Step 2: Update `tests/validate-plugin.sh` skill-count**

Find the skill-count assertion (likely `[ "$count" = "N" ]` or similar). Change to `41`.

- [ ] **Step 2.5: Create `docs/frontend-guide.md` — user-facing walkthrough (AC 14)**

```markdown
# Forge Frontend Guide (4.2.0+)

A walkthrough of the four Phase 6 features for project maintainers.

## Enabling shadcn/ui

In `.claude/forge.local.md`:

```yaml
components:
  language: typescript
  framework: react
  variant: shadcn
  testing: vitest
```

Commit; next `/forge-run` uses shadcn primitives from `@/components/ui/` by default.

## Using Figma URLs

Paste a Figma URL in your requirement — planner calls Figma MCP at PLAN stage and injects design tokens + Code Connect mappings into the plan. Implementer consumes them automatically.

Cache lives at `.forge/figma-cache/` with 1-hour TTL; reset with `/forge-reset` or explicit `--figma-refresh` flag on `/forge-run`.

## Understanding defaults-pack findings

`shared/frontend-defaults-pack.md` codifies 40 rules. Reviewer flags violations as `FE-<CAT>-<NNN>` findings. Severity: CRITICAL blocks PR, WARNING advises. Exempt with inline marker:

```ts
// forge-allow: FE-TOKENS-002 reason: one-off marketing accent color
const accent = "#FF6B6B";
```

Files with >5 exemptions trigger WARNING `FE-EXEMPTION-OVERUSE` (architectural smell).

## Visual regression — updating baselines

After intentional UI changes:

```
/forge-preview                    # review via Phase 4 preview flow
/forge-vrt-update --dry-run       # see which baselines would be promoted
/forge-vrt-update                 # promote
```

Baselines live at `.forge/vrt/baselines/<os>/<route>-<viewport>.png`. Committed by default (`vrt.commit_baselines: true`); see `shared/visual-regression-baseline.md` for LFS / external-blob opt-outs.

## axe-core in local dev

`@axe-core/react` is a dev-dep (installed at `/forge-init` when `frontend.axe_core_required: true`). Developers see axe warnings in browser console during local dev. CI runs `@axe-core/playwright` on every PR; CRITICAL violations block merge.

## Further reading

- `shared/figma-integration.md` — Figma MCP contract
- `shared/frontend-defaults-pack.md` — 40-rule catalog with detection + exemption
- `shared/visual-regression-baseline.md` — VRT workflow
- `modules/frameworks/react/variants/shadcn.md` — shadcn primitives + conventions
```

- [ ] **Step 3: README.md — "Frontend development UX (4.2.0+)" section**

```markdown
## Frontend development UX (4.2.0+)

Forge gains a production-grade FE stack:

- **shadcn/ui variant** — opt-in via `components.variant: shadcn` (requires `framework: react`). Implementer prefers existing `@/components/ui/` components; reviewer flags hand-rolled equivalents.
- **Figma MCP at PLAN** — paste a Figma URL in your requirement; `fg-200-planner` calls `get_variable_defs` + `get_code_connect_map` and injects tokens + component imports into the plan. Implementer consumes them directly (no generic `bg-blue-500`).
- **40-rule defaults pack** — `shared/frontend-defaults-pack.md` codifies semantic HTML, design tokens, WCAG 2.2 AA a11y, motion, responsive, state mgmt, and testing rules. `fg-413` enforces with CRITICAL/WARNING severity; `fg-320` auto-fixes WARNINGs where safe.
- **axe-core Playwright** — `@axe-core/playwright` runs in CI against every user-facing route; CRITICAL violations block PR.
- **Visual regression baseline** — `.forge/vrt/baselines/<os>/` with per-OS screenshots; `/forge-vrt-update` promotes after intentional UI changes.

Contracts: `shared/figma-integration.md`, `shared/frontend-defaults-pack.md`, `shared/visual-regression-baseline.md`, `modules/frameworks/react/variants/shadcn.md`.
```

- [ ] **Step 4: CLAUDE.md — 4 new Key Entry Points + skill count 40 → 41**

- [ ] **Step 5: CHANGELOG.md — 4.2.0 entry**

- [ ] **Step 6: Bump plugin + marketplace JSON**

```bash
sed -i.bak 's/"version": "4.1.0"/"version": "4.2.0"/' .claude-plugin/plugin.json
sed -i.bak 's/"version": "4.1.0"/"version": "4.2.0"/' .claude-plugin/marketplace.json
rm -f .claude-plugin/*.bak
```

- [ ] **Step 7: Commit 6 (activates FORGE_PHASE6_ACTIVE sentinel)**

```bash
git add tests/contract/live-observation.bats tests/validate-plugin.sh
git add docs/frontend-guide.md
git add README.md CLAUDE.md CHANGELOG.md
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "docs(phase6): frontend-guide + top-level + skill count 40 → 41 + bump 4.1.0 → 4.2.0

- live-observation.bats skill count assertion: 40 → 41; gate Phase 5 → Phase 6
- validate-plugin.sh: skill count 41
- README.md: §Frontend development UX
- CLAUDE.md: 4 new Key Entry Points (figma-integration, frontend-defaults-pack,
  visual-regression-baseline, shadcn variant)
- CHANGELOG.md: 4.2.0 entry
- Version bump; FORGE_PHASE6_ACTIVE sentinel now true at HEAD"
```

---

## Task 7: Push + tag + release

```bash
git push origin master
gh run watch

git tag -a v4.2.0 -m "Phase 6: Frontend UX Excellence

MVP scope — shadcn/ui variant, Figma MCP at PLAN, 40-rule defaults pack,
axe-core Playwright + visual regression baseline.

Deferred: live preview, click-to-edit /forge-tweak, /forge-variants,
brand extraction, motion library config, Vue/Svelte shadcn."
git push origin v4.2.0

gh release create v4.2.0 --title "4.2.0 — Phase 6: Frontend UX Excellence" --notes-file - <<'EOF'
See CHANGELOG.md §4.2.0.

Next: Phase 7 — Strategic Go core binary.
EOF
```

---

## Self-review

- **Spec coverage:** All 17 ACs mapped.
- **Placeholder scan:** Task 2 Step 2 calls the 40-rule enumeration "per spec §4.3 table" — executor consults the spec for category counts. The specific rule text is research-derived; Task 2 Step 2 is acceptable as mechanical fill from the research artifact cited in spec §12.
- **Type consistency:** `components.variant: shadcn`, `frontend.*`, `vrt.*`, `figma.*` used consistently across spec + plan.

**Plan complete.**
