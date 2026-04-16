# Phase 1 — Skill Surface Consolidation (Design)

**Status:** Draft v2 for review (v1 review applied)
**Date:** 2026-04-16
**Target version:** Forge 3.0.0 (breaking change — SemVer major per §10 rationale)
**Author:** Denis Šajnar (authored with Claude Opus 4.7)
**Phase sequence:** 1 of 7

---

## 1. Goal

Collapse Forge's 41 flat skills into a coherent, contract-enforced surface with uniform flag coverage and read/write signalling. Replace six overlapping recovery commands with a single `/forge-recover` verb. Replace three compression commands with a single `/forge-compress` verb. Enforce a uniform skill contract (`--help`, `--dry-run` where mutating, `--json` where read-only, standard exit codes, `[read-only]`/`[writes]` badges). Enforce an agent frontmatter contract (explicit `ui:` block, cluster-scoped unique colors, tier-sized descriptions, embedded `AskUserQuestion` examples in Tier 1/2 agents).

## 2. Context and motivation

The April 2026 UX audit graded the skill surface **B−** and identified three structural problems:

1. **Recovery sprawl.** `/forge-diagnose`, `/forge-repair-state`, `/forge-reset`, `/forge-resume`, `/forge-rollback` are five commands with overlapping semantics.
2. **Compression discovery gap.** `/forge-compress`, `/forge-caveman`, `/forge-compression-help` are three commands whose relationship is not self-evident.
3. **No uniform contract.** Flag coverage, exit codes, help affordances, read-vs-write signaling are inconsistent across 41 skills.

Additionally:

- **12 agents** lack explicit `ui:` frontmatter (implicit Tier 4 by omission): `fg-101`, `fg-102`, `fg-205`, `fg-210`, `fg-410`, `fg-411`, `fg-412`, `fg-413`, `fg-416`, `fg-417`, `fg-418`, `fg-419`. Two of these (`fg-101`/`fg-102`) are helpers; one (`fg-205`) is the planning critic; one (`fg-210`) is the validator; the other eight are quality-gate reviewers.
- **3 agents** use a non-standard `ui: { tier: N }` shortcut instead of explicit `tasks/ask/plan_mode` keys: `fg-135`, `fg-510`, `fg-515`. Must normalize.
- **Cluster-level color collisions** exist in 4 dispatch clusters (enumerated in §4.6).
- **1 agent** (`fg-205-planning-critic`) carries **no `color:` field at all**.
- **24 `shared/*.md` files** reference deleted skill names today and must be updated during this phase.
- **16 bats files under `tests/unit/skill-execution/`** and **5 under `tests/contract/`** reference deleted skill names and must be updated or deleted.
- Zero concrete `AskUserQuestion` example payloads exist in Tier 1/2 agent `.md` bodies.

No backwards compatibility is required — single-user plugin; BC constraints are counterproductive per user's explicit instruction.

## 3. Non-goals

- **No changes to recovery *logic*.** `fg-100-orchestrator` still owns repair/reset/resume/rollback state transitions. Only the user-facing surface changes.
- **No new runtime agent behaviors.** This phase is pure surface restructuring plus frontmatter-enforcement scaffolding.
  - In particular: `fg-210-validator` is promoted to Tier 2 **by frontmatter and tool declaration only**. The actual REVISE-verdict `AskUserQuestion` behavior remains owned by `fg-100-orchestrator`. Changing the verdict-emission flow is deferred to Phase 4 (escalation taxonomy).
- **No changes to runtime state files** (`state.json`, `events.jsonl`, `caveman-mode`, `check-engine-skipped`). The new `/forge-compress output <mode>` writes the same `.forge/caveman-mode` file the old `/forge-caveman` did.
- **No alias files or deprecation shims.** Old skills are deleted; `DEPRECATIONS.md` documents the removals.
- **Deferred to later phases:**
  - Sub-agent `TaskCreate` visibility → Phase 2
  - Cost streaming → Phase 2
  - Hook failure surfacing → Phase 2
  - Preview-before-apply overlay → Phase 4
  - Editable plan file and escalation taxonomy → Phase 4
  - Changes to agent dispatch logic itself (beyond frontmatter) → Phase 4 or later

## 4. Design

### 4.1 Deletions (7 skill directories, zero aliases)

```
skills/forge-diagnose/          → deleted (functionality → /forge-recover diagnose)
skills/forge-repair-state/      → deleted (functionality → /forge-recover repair)
skills/forge-reset/             → deleted (functionality → /forge-recover reset)
skills/forge-resume/            → deleted (functionality → /forge-recover resume)
skills/forge-rollback/          → deleted (functionality → /forge-recover rollback)
skills/forge-caveman/           → deleted (functionality → /forge-compress output <mode>)
skills/forge-compression-help/  → deleted (functionality → /forge-compress help)
```

`/forge-abort` is **not** deleted — it expresses a distinct intent (graceful stop of an active run) that does not belong under the recovery umbrella.

### 4.2 `/forge-recover` — new consolidated recovery verb

**Invocation:** `/forge-recover [<subcommand>] [flags]`

| Subcommand | Read/Write | Description | Skill-specific flags |
|---|---|---|---|
| `diagnose` *(default)* | read-only | Health check of `state.json`, recovery budget, convergence status, stalled stages. Prints a punch list. | `--json` |
| `repair` | writes | Surgical fixes to `state.json`: counter correction, stale-lock removal, invalid stage repair, WAL recovery. Requires confirmation via `AskUserQuestion` before writing. | `--dry-run` |
| `reset` | writes | Clears pipeline state while preserving cross-run caches (`explore-cache.json`, `plan-cache/`, `code-graph.db`, `trust.json`, `events.jsonl`, `playbook-analytics.json`, `run-history.db`, `playbook-refinements/`, `wiki/`). | `--dry-run` |
| `resume` | writes | Resume from last checkpoint (requires `state.status ∈ {ABORTED, ESCALATED, FAILED}`). | — |
| `rollback` | writes | Revert pipeline commits in the worktree. | `--target <branch>` (default worktree), `--dry-run` |

Invocation with no subcommand defaults to `diagnose` (read-only, safe default). Unknown subcommand → exit 1.

**Agent dispatch.** The new `skills/forge-recover/SKILL.md` dispatches the existing agents (no new agents introduced). The orchestrator receives the subcommand name as the `recovery_op` field on its input payload. See §4.10 for the state-schema and orchestrator update this requires.

### 4.3 `/forge-compress` — rewritten consolidated compression verb

**Invocation:** `/forge-compress [<subcommand>] [flags]`

| Subcommand | Read/Write | Description | Skill-specific flags |
|---|---|---|---|
| `agents` | writes | Compress agent `.md` files via terse-rewrite. 30-50% system-prompt reduction. | `--dry-run` |
| `output <mode>` | writes | Set runtime output compression. `mode ∈ {off, lite, full, ultra}`. Writes `.forge/caveman-mode`. | `--dry-run` |
| `status` *(default)* | read-only | Show current agent-compression ratio and output-mode setting. | `--json` |
| `help` | read-only | Reference card (flags, modes, token savings). | `--json` |

Invocation with no subcommand defaults to `status` (read-only, safe default).

### 4.4 Skill contract (`shared/skill-contract.md` — new)

**Every SKILL.md MUST conform:**

1. **Description prefix.** First token of `description:` frontmatter is `[read-only]` or `[writes]`. No other prefix markers permitted. Badge reflects **maximum impact** across all subcommands — skills whose non-default subcommand can write carry `[writes]` even if the default subcommand is read-only. Both `/forge-recover` and `/forge-compress` are therefore `[writes]`.
2. **`## Flags` section** required. Lists every flag with one-line description. `--help` always present.
3. **`## Exit codes` section** required. Either inline or `See shared/skill-contract.md for the standard exit-code table.`
4. **`--help` is mandatory** on every skill. Prints: description → flags → 3 usage examples → exit codes.
5. **`--dry-run` is mandatory on mutating skills.** Implementation: skill sets `FORGE_DRY_RUN=1` env var; orchestrator and agents check this and short-circuit writes.
6. **`--json` is mandatory on read-only skills.** Structured JSON to stdout; suppresses human-readable prose.

**Standard exit codes:**

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | User error (bad args, missing config, unknown subcommand) |
| 2 | Pipeline failure (agent reported FAIL or CONCERNS without override) |
| 3 | Recovery needed (state corruption, locked, or escalated) |
| 4 | Aborted by user (`/forge-abort`, Ctrl+C, or "Abort" chosen in `AskUserQuestion`) |

**Skill categorization:**

Total skills after Phase 1: **35** (41 existing − 7 deleted + 1 net-new = 35; `/forge-compress` is rewritten in place, not a new skill).

**Read-only (15):** `forge-ask`, `forge-codebase-health`, `forge-config-validate`, `forge-graph-debug`, `forge-graph-query`, `forge-graph-status`, `forge-help`, `forge-history`, `forge-insights`, `forge-playbooks`, `forge-profile`, `forge-security-audit`, `forge-status`, `forge-tour`, `forge-verify`.

**Writes (20):** `forge-abort`, `forge-automation`, `forge-bootstrap`, `forge-commit`, `forge-compress`, `forge-config`, `forge-deep-health`, `forge-deploy`, `forge-docs-generate`, `forge-fix`, `forge-graph-init`, `forge-graph-rebuild`, `forge-init`, `forge-migration`, `forge-playbook-refine`, `forge-recover`, `forge-review`, `forge-run`, `forge-shape`, `forge-sprint`.

Reconciliation: 15 + 20 = 35. ✅

### 4.5 Agent frontmatter contract

**Enforced by `tests/contract/ui-frontmatter-consistency.bats` (extended) and a new `tests/contract/skill-contract.bats`:**

1. **Explicit `ui:` block required** with `tasks`, `ask`, and `plan_mode` keys (three booleans). Implicit omission is rejected. The `ui: { tier: N }` shortcut used in `fg-135`, `fg-510`, `fg-515` is normalized to explicit `tasks/ask/plan_mode/` keys matching the target tier's capability set.

   The frontmatter key remains `plan_mode` (not `plan`) to match existing convention in `shared/agent-ui.md` and the 6 Tier 1 agents that already use it.

2. **12 agents** gain explicit `ui:` blocks: `fg-101`, `fg-102`, `fg-205`, `fg-210`, `fg-410`, `fg-411`, `fg-412`, `fg-413`, `fg-416`, `fg-417`, `fg-418`, `fg-419`. All become `ui: { tasks: false, ask: false, plan_mode: false }` (Tier 4) **except** `fg-210` which becomes Tier 2 (see §4.5.3).

3. **`fg-210-validator` promoted from Tier 4 → Tier 2** by frontmatter only:
   - New `ui: { tasks: true, ask: true, plan_mode: false }`
   - `tools:` list extended with `TaskCreate`, `TaskUpdate`, `AskUserQuestion` (satisfies `ui.tasks: true` + `ui.ask: true` tool-agreement assertion already enforced by `tests/contract/ui-frontmatter-consistency.bats`)
   - **No behavioral change in this phase.** Actual REVISE-via-`AskUserQuestion` flow remains owned by `fg-100-orchestrator`; capability declaration is preparatory for Phase 4 migration. Bats test enforces declaration, not usage.

4. **`color:` field required on every agent.** `fg-205-planning-critic` has no `color:` today; it receives one per §4.6.

5. **`color:` uniqueness is cluster-scoped**, not globally unique. Two agents may share a color if and only if they do not appear in the same dispatch cluster (see §4.6 for cluster definitions and the full 42-agent color map). The bats test checks cluster-scoped uniqueness, driven by the cluster table in `shared/agent-colors.md`.

6. **Description length per tier:**

   | Tier | Range | Counting rule |
   |---|---|---|
   | 1 | 50–80 words | Count prose words only — exclude YAML structural markers, `<example>` block contents, `<commentary>` contents, and literal code spans. The bats assertion strips XML-like tags and backtick-fenced content before tokenizing on whitespace. |
   | 2 | 20–40 words | Same rule |
   | 3 | 10–20 words | Same rule |
   | 4 | 5–12 words | Same rule |

7. **Tier 1/2 agents (14 total)** must contain a `## User-interaction examples` section with ≥1 valid `AskUserQuestion` JSON payload. Bats test verifies presence via regex. Agents affected:

   **Tier 1 (6):** `fg-010`, `fg-015`, `fg-050`, `fg-090`, `fg-160`, `fg-200`.
   **Tier 2 (7 existing):** `fg-020`, `fg-100`, `fg-103`, `fg-400`, `fg-500`, `fg-600`, `fg-710`.
   **Tier 2 (1 promoted):** `fg-210` (this phase).

   Total: **14 agents** get the examples section.

### 4.6 Agent color palette (`shared/agent-colors.md` — new)

**Cluster definitions** (authoritative — replicated verbatim from `shared/agent-role-hierarchy.md` dispatch-layer tables, then extended with pre-pipeline and impl clusters not formerly clustered):

| Cluster | Members |
|---|---|
| Pre-pipeline | `fg-010`, `fg-015`, `fg-020`, `fg-050`, `fg-090` |
| Orchestrator + helpers | `fg-100`, `fg-101`, `fg-102`, `fg-103` |
| PREFLIGHT | `fg-130`, `fg-135`, `fg-140`, `fg-150` |
| Migration / Planning | `fg-160`, `fg-200`, `fg-205`, `fg-210`, `fg-250` |
| Implement | `fg-300`, `fg-310`, `fg-320`, `fg-350` |
| Review | `fg-400`, `fg-410`, `fg-411`, `fg-412`, `fg-413`, `fg-416`, `fg-417`, `fg-418`, `fg-419` |
| Verify / Test | `fg-500`, `fg-505`, `fg-510`, `fg-515` |
| Ship | `fg-590`, `fg-600`, `fg-610`, `fg-620`, `fg-650` |
| Learn | `fg-700`, `fg-710` |

**Palette (18 hues):** `magenta`, `pink`, `purple`, `orange`, `coral`, `cyan`, `navy`, `teal`, `olive`, `blue`, `crimson`, `yellow`, `green`, `lime`, `red`, `amber`, `brown`, `white`, `gray` — canonical terminal hues with ≥3:1 contrast against common backgrounds. `shared/agent-colors.md` lists hex equivalents.

**Full 42-agent color map** (`fg-205` currently has no color — assigned `crimson` below):

| Agent | Cluster | Old color | New color |
|---|---|---|---|
| `fg-010-shaper` | Pre-pipeline | magenta | magenta |
| `fg-015-scope-decomposer` | Pre-pipeline | magenta | pink |
| `fg-020-bug-investigator` | Pre-pipeline | purple | purple |
| `fg-050-project-bootstrapper` | Pre-pipeline | magenta | orange |
| `fg-090-sprint-orchestrator` | Pre-pipeline | magenta | coral |
| `fg-100-orchestrator` | Orch+helpers | cyan | cyan |
| `fg-101-worktree-manager` | Orch+helpers | gray | gray |
| `fg-102-conflict-resolver` | Orch+helpers | gray | olive |
| `fg-103-cross-repo-coordinator` | Orch+helpers | gray | brown |
| `fg-130-docs-discoverer` | PREFLIGHT | cyan | cyan |
| `fg-135-wiki-generator` | PREFLIGHT | cyan | navy |
| `fg-140-deprecation-refresh` | PREFLIGHT | cyan | teal |
| `fg-150-test-bootstrapper` | PREFLIGHT | cyan | olive |
| `fg-160-migration-planner` | Migration/Plan | orange | orange |
| `fg-200-planner` | Migration/Plan | blue | blue |
| `fg-205-planning-critic` | Migration/Plan | *(none)* | crimson |
| `fg-210-validator` | Migration/Plan | yellow | yellow |
| `fg-250-contract-validator` | Migration/Plan | yellow | amber |
| `fg-300-implementer` | Implement | green | green |
| `fg-310-scaffolder` | Implement | green | lime |
| `fg-320-frontend-polisher` | Implement | magenta | coral |
| `fg-350-docs-generator` | Implement | green | teal |
| `fg-400-quality-gate` | Review | red | red |
| `fg-410-code-reviewer` | Review | cyan | cyan |
| `fg-411-security-reviewer` | Review | red | crimson |
| `fg-412-architecture-reviewer` | Review | cyan | navy |
| `fg-413-frontend-reviewer` | Review | teal | teal |
| `fg-416-performance-reviewer` | Review | yellow | amber |
| `fg-417-dependency-reviewer` | Review | cyan | purple |
| `fg-418-docs-consistency-reviewer` | Review | white | white |
| `fg-419-infra-deploy-reviewer` | Review | green | olive |
| `fg-500-test-gate` | Verify/Test | yellow | yellow |
| `fg-505-build-verifier` | Verify/Test | yellow | brown |
| `fg-510-mutation-analyzer` | Verify/Test | cyan | cyan |
| `fg-515-property-test-generator` | Verify/Test | cyan | pink |
| `fg-590-pre-ship-verifier` | Ship | red | red |
| `fg-600-pr-builder` | Ship | blue | blue |
| `fg-610-infra-deploy-verifier` | Ship | green | green |
| `fg-620-deploy-verifier` | Ship | green | olive |
| `fg-650-preview-validator` | Ship | green | amber |
| `fg-700-retrospective` | Learn | magenta | magenta |
| `fg-710-post-run` | Learn | magenta | pink |

**Collision audit** against this table:

- Pre-pipeline: magenta, pink, purple, orange, coral — 5 distinct ✅
- Orch+helpers: cyan, gray, olive, brown — 4 distinct ✅
- PREFLIGHT: cyan, navy, teal, olive — 4 distinct ✅
- Migration/Plan: orange, blue, crimson, yellow, amber — 5 distinct ✅
- Implement: green, lime, coral, teal — 4 distinct ✅
- Review: red, cyan, crimson, navy, teal, amber, purple, white, olive — 9 distinct ✅ (includes `fg-400` red; reviewers' distinct set excludes it where only the 8 fg-41x reviewers run together)
- Verify/Test: yellow, brown, cyan, pink — 4 distinct ✅
- Ship: red, blue, green, olive, amber — 5 distinct ✅
- Learn: magenta, pink — 2 distinct ✅

No intra-cluster collisions. Cross-cluster reuse is intentional and harmless since those agents never render task-dots together.

### 4.7 Rich `AskUserQuestion` patterns (`shared/ask-user-question-patterns.md` — new)

Documents four canonical patterns with copy-paste-ready JSON payloads:

**Pattern 1 — Single-choice with `preview`** (architecture decisions that benefit from visual comparison):
```json
{
  "question": "Which caching strategy should we use?",
  "header": "Cache strategy",
  "multiSelect": false,
  "options": [
    {"label": "In-memory LRU (Recommended)", "description": "Fast, ephemeral.", "preview": "import { LRU } from '...';\nconst c = new LRU({max: 500});"},
    {"label": "Redis", "description": "Persistent, distributed.", "preview": "import Redis from 'ioredis';\nconst r = new Redis(process.env.REDIS_URL);"}
  ]
}
```

**Pattern 2 — Multi-select** (stackable options, triggers Review-your-answers screen):
```json
{
  "question": "Which log levels should emit to stderr?",
  "header": "Log levels",
  "multiSelect": true,
  "options": [
    {"label": "error", "description": "Errors and fatal conditions"},
    {"label": "warn", "description": "Warnings"},
    {"label": "info", "description": "Informational"},
    {"label": "debug", "description": "Verbose diagnostics"}
  ]
}
```

**Pattern 3 — Single-choice with explicit recommendation** (safe-default escalation):
```json
{
  "question": "Build is failing after 3 retry cycles. How should we proceed?",
  "header": "Escalation",
  "multiSelect": false,
  "options": [
    {"label": "Invoke /forge-recover diagnose (Recommended)", "description": "Read-only state analysis."},
    {"label": "Abort this run", "description": "Graceful stop; preserves state for /forge-recover resume."},
    {"label": "Force-continue despite failures", "description": "Mark failures non-blocking (dangerous)."}
  ]
}
```

**Pattern 4 — Free-text via auto "Other"**:
No literal `Other` option — Claude Code's `AskUserQuestion` tool appends it automatically with text input.

**Prohibitions (bats-enforceable by regex):**
- No `Options: (1)...(2)...` plain-text menus in agent `.md` bodies or stage-note templates.
- No yes/no prompts (`Yes|No` labels) when distinct labeled options exist.
- No `AskUserQuestion` payload without `header` field (Claude Code requires ≤12-char chip label).

(The "multi-select when options are not mutually exclusive" rule remains as authoring guidance in the patterns doc, but is **not** bats-enforced — "mutual exclusivity" requires semantic inspection of option labels.)

### 4.8 `/forge-help` — augmented, not replaced

The existing `/forge-help` has a valuable 3-tier *learnability* taxonomy (Essential / Power User / Advanced) and a "Similar Skills — when to use which" section. The rewrite **preserves** both and **adds** two things:

1. **`[read-only]` or `[writes]` badge** inline with each skill entry.
2. A `--json` mode that emits the full decision-tree as structured JSON for external tooling.

Example output shape:

```
Forge skills (35 total)

━━━━━━ Essential (12) ━━━━━━
/forge-run <spec>            [writes]     Full 10-stage pipeline
/forge-fix <bug>             [writes]     Root-cause investigation + fix
/forge-status                [read-only]  Current pipeline state
/forge-help                  [read-only]  This decision tree
...

━━━━━━ Power User (14) ━━━━━━
/forge-recover [subcommand]  [writes]     Diagnose/repair/reset/resume/rollback
/forge-compress [subcommand] [writes]     Agent-prompt or output compression
/forge-review                [writes]     Review changed files with fixes
/forge-insights              [read-only]  Pipeline analytics across runs
...

━━━━━━ Advanced (9) ━━━━━━
/forge-graph-query <cypher>  [read-only]  Neo4j query
/forge-graph-rebuild         [writes]     Full graph rebuild
...

━━━━━━ Similar Skills — when to use which ━━━━━━
  * Health audit:      /forge-codebase-health (read) vs /forge-deep-health (fix)
  * Stuck pipeline:    /forge-recover diagnose (check) vs /forge-recover repair (fix)
  * Compression:       /forge-compress status (check) vs /forge-compress output <mode> (change)
  * Review:            /forge-review (changed files) vs /forge-codebase-health (whole codebase)

Learn more: /forge-tour | /forge-init | /forge-help --json
```

### 4.9 Documentation updates

- `README.md` — skill table rewrite; version string; `[read-only]`/`[writes]` convention note.
- `CLAUDE.md` — skill table rewrite; agent tier section; skill count `41 → 35`; add three new shared docs to the Key Entry Points table (`skill-contract.md`, `agent-colors.md`, `ask-user-question-patterns.md`).
- `shared/agent-ui.md` — rewrite §1 "UI Tiers" to require explicit `ui:` block (remove current "Omitting the `ui:` section entirely means all capabilities are `false`" language); keep `plan_mode` as the plan-key.
- `shared/agent-role-hierarchy.md` — add `fg-205-planning-critic` to the appropriate tier table (currently absent); update `fg-210-validator` row from Tier 4 → Tier 2.
- `shared/state-schema.md` — add `recovery_op` field (string, one of `diagnose|repair|reset|resume|rollback`) to the orchestrator input payload schema.
- `agents/fg-100-orchestrator.md` — add a §N "Recovery op dispatch" section describing the subcommand → existing-agent-flow mapping. No behavioral change; just documents the new input field.
- **27 `shared/` files** containing references to deleted skills: 24 markdown files (`security-audit-trail.md`, `next-task-prediction.md`, `run-history/run-history.md`, `confidence-scoring.md`, `input-compression.md`, `event-log.md`, `automations.md`, `agent-communication.md`, `explore-cache.md`, `recovery/recovery-engine.md`, `flaky-test-management.md`, `plan-cache.md`, `graph/schema.md`, `performance-regression.md`, `playbooks.md`, `background-execution.md`, `learnings/README.md`, `learnings/rule-promotion.md`, `data-classification.md`, `dx-metrics.md`, `visual-verification.md`, `knowledge-base.md`, `state-schema.md`, `output-compression.md`) **plus** 1 SQL migration (`run-history/migrations/001-initial.sql`) **plus** 2 JSON schemas (`schemas/dx-metrics-schema.json`, `schemas/benchmarks-schema.json`). Each is mechanically updated to reference the new command names. The SQL and JSON files require careful per-file edits (not blind sed) since string replacements could affect syntax.
- **17 `skills/*/SKILL.md` files** cross-reference deleted skills and must update: `forge-abort`, `forge-automation`, `forge-bootstrap`, `forge-commit`, `forge-config-validate`, `forge-deploy`, `forge-fix`, `forge-help`, `forge-history`, `forge-init`, `forge-insights`, `forge-migration`, `forge-profile`, `forge-run`, `forge-sprint`, `forge-status`, `forge-tour`.
- **3 top-level documents** contain references to deleted skills: `README.md`, `CLAUDE.md`, `CHANGELOG.md` (the historical 2.8.0 entry references them). These are scrubbed in the same commit as the shared/skills sweep to keep the dangling-reference bats assertion passing from the moment it activates.
- `DEPRECATIONS.md` — append a new `## Removed in 3.0.0` section. Format:

  ```markdown
  ## Removed in 3.0.0

  | Removed | Replacement | Reason |
  |---|---|---|
  | `/forge-diagnose` | `/forge-recover diagnose` | Recovery consolidation |
  | `/forge-repair-state` | `/forge-recover repair` | Recovery consolidation |
  | `/forge-reset` | `/forge-recover reset` | Recovery consolidation |
  | `/forge-resume` | `/forge-recover resume` | Recovery consolidation |
  | `/forge-rollback` | `/forge-recover rollback` | Recovery consolidation |
  | `/forge-caveman` | `/forge-compress output <mode>` | Compression consolidation |
  | `/forge-compression-help` | `/forge-compress help` | Compression consolidation |

  ### Migration
  <example map per removed command>
  ```

  This is a **distinct** section from the existing "Active Deprecations" table (which tracks scheduled-for-removal items). Removed items get their own section.
- `CHANGELOG.md` — 3.0.0 entry summarizing Phase 1.
- `.claude-plugin/plugin.json` — `"version": "2.8.0"` → `"3.0.0"`.
- `.claude-plugin/marketplace.json` — `"metadata.version"` bumped to `3.0.0`.

### 4.10 Hook audit (no-op)

Confirmed by grep of `hooks/`: no hook script references any of the 7 deleted skills. No hook updates required. `§5.4` lists this explicitly for auditability.

### 4.11 Test updates

- **`tests/contract/ui-frontmatter-consistency.bats`** extended with 4 new assertions:
  1. Explicit `ui:` block required (no implicit omission).
  2. Tier-1/2 agent contains `## User-interaction examples` section with ≥1 `AskUserQuestion` JSON block.
  3. `color:` field present on every agent.
  4. Cluster-scoped color uniqueness (driven by cluster table in `shared/agent-colors.md`).
  5. Description word count within tier range (tokenization rule per §4.5.6).
- **`tests/structural/ui-frontmatter-consistency.bats`** (the duplicate): **delete**. Its assertions are subsumed by the contract copy; keeping both has caused drift historically.
- **New `tests/contract/skill-contract.bats`**:
  1. Every SKILL.md `description:` starts with `[read-only]` or `[writes]`.
  2. Every SKILL.md has `## Flags` section.
  3. Every SKILL.md has `## Exit codes` (inline or reference).
  4. Mutating skills list `--dry-run`; read-only list `--json`; all list `--help`.
  5. 35 skill directories exist exactly.
  6. Dangling-reference sweep: grep for deleted skill names across `README.md`, `CLAUDE.md`, `shared/**/*.md`, `skills/**/SKILL.md`, `tests/**/*.bats`, `hooks/**/*.sh`. Any hit fails CI.
- **`tests/unit/skill-execution/forge-compression-help.bats`**: delete (skill no longer exists).
- **`tests/unit/skill-execution/decision-tree-refs.bats`**, **`skill-completeness.bats`**, **`skill-prerequisites.bats`**: update references to deleted skills → new names.
- **`tests/unit/skill-execution/forge-compress-integration.bats`**: update to test new subcommand surface.
- **`tests/unit/caveman-modes.bats`**: rename to `compress-output-modes.bats`; update references.
- **`tests/contract/skill-frontmatter.bats`**, **`explore-cache.bats`**, **`state-schema.bats`**, **`plan-cache.bats`**, **`compression-insights-contract.bats`**: update references.
- **`tests/validate-plugin.sh`**: extend with `[read-only]`/`[writes]` prefix regex; cluster-scoped unique-color sweep.

**Runtime-behavior verification — partial in this phase.** The bats suite enforces *declaration* of `--dry-run`/`--help`/`--json` flags. `forge-recover-integration.bats` verifies that the new SKILL.md advertises all 5 subcommands and the correct per-subcommand flag coverage — a **surface** test, not a live runtime test. True runtime verification (invoking the orchestrator and snapshot-diffing `.forge/`) requires integration fixtures and a live orchestrator mock; that work is **deferred to Phase 2**, which covers observability + hook visibility and is a natural fit for adding live-invocation test fixtures.

**Link-checker.** No existing link-checker in repo. The dangling-reference sweep in `skill-contract.bats` substitutes for one within this phase's scope.

## 5. File manifest (authoritative)

### 5.1 Delete (9 items)

Directories (7):
```
skills/forge-diagnose/
skills/forge-repair-state/
skills/forge-reset/
skills/forge-resume/
skills/forge-rollback/
skills/forge-caveman/
skills/forge-compression-help/
```

Files (2):
```
tests/structural/ui-frontmatter-consistency.bats       # subsumed by contract/ copy
tests/unit/skill-execution/forge-compression-help.bats # skill deleted
```

### 5.2 Create (6 files)

```
skills/forge-recover/SKILL.md
shared/skill-contract.md
shared/agent-colors.md
shared/ask-user-question-patterns.md
tests/contract/skill-contract.bats
tests/unit/skill-execution/forge-recover-integration.bats
```

### 5.3 Rewrite (3 files)

```
skills/forge-compress/SKILL.md                                    # full subcommand surface
skills/forge-help/SKILL.md                                        # augmented taxonomy + badges + --json
tests/unit/caveman-modes.bats → compress-output-modes.bats        # rename + content rewrite
```

### 5.4 Update in place (96 files)

**SKILL.md in-place updates (32 files).** Arithmetic: 41 existing skills − 7 deleted = 34 remaining; of those 2 are full rewrites (`forge-compress`, `forge-help`) listed in §5.3; leaves **32 in-place updates**:

`forge-abort`, `forge-ask`, `forge-automation`, `forge-bootstrap`, `forge-codebase-health`, `forge-commit`, `forge-config`, `forge-config-validate`, `forge-deep-health`, `forge-deploy`, `forge-docs-generate`, `forge-fix`, `forge-graph-debug`, `forge-graph-init`, `forge-graph-query`, `forge-graph-rebuild`, `forge-graph-status`, `forge-history`, `forge-init`, `forge-insights`, `forge-migration`, `forge-playbook-refine`, `forge-playbooks`, `forge-profile`, `forge-review`, `forge-run`, `forge-security-audit`, `forge-shape`, `forge-sprint`, `forge-status`, `forge-tour`, `forge-verify`.

Each is updated for: skill-contract compliance (description badge, Flags section, Exit codes section, flag coverage) AND cross-reference cleanup (removing mentions of deleted skills). Both passes land in the same commit per §9.

**Agent `.md` files** (42 updated for frontmatter contract; 14 additionally get `## User-interaction examples`):

All 42 agents listed in §4.6 color table get the frontmatter pass. The 14 Tier 1/2 additionally get the examples section (subset, same files — counted once).

**Shared file updates — deleted-skill references (27 files):**

24 markdown: `shared/security-audit-trail.md`, `shared/next-task-prediction.md`, `shared/run-history/run-history.md`, `shared/confidence-scoring.md`, `shared/input-compression.md`, `shared/event-log.md`, `shared/automations.md`, `shared/agent-communication.md`, `shared/explore-cache.md`, `shared/recovery/recovery-engine.md`, `shared/flaky-test-management.md`, `shared/plan-cache.md`, `shared/graph/schema.md`, `shared/performance-regression.md`, `shared/playbooks.md`, `shared/background-execution.md`, `shared/learnings/README.md`, `shared/learnings/rule-promotion.md`, `shared/data-classification.md`, `shared/dx-metrics.md`, `shared/visual-verification.md`, `shared/knowledge-base.md`, `shared/state-schema.md`, `shared/output-compression.md`.

1 SQL: `shared/run-history/migrations/001-initial.sql` (careful edit — string replacements inside SQL comments only; no schema change).

2 JSON: `shared/schemas/dx-metrics-schema.json`, `shared/schemas/benchmarks-schema.json` (careful edit — replacements inside `description` fields only; no schema structure change).

**Shared file updates — new content (2 additional files, non-overlapping with the 27 above):**

`shared/agent-ui.md` (remove implicit-omission language), `shared/agent-role-hierarchy.md` (add fg-205, promote fg-210). Note: `shared/state-schema.md` is counted once in the 27 above; its `recovery_op` addition folds into its update pass.

**Skill cross-reference updates (17 SKILL.md files, overlap with the 32 in-place contract updates — done in the same sed pass):**

`forge-abort`, `forge-automation`, `forge-bootstrap`, `forge-commit`, `forge-config-validate`, `forge-deploy`, `forge-fix`, `forge-help`, `forge-history`, `forge-init`, `forge-insights`, `forge-migration`, `forge-profile`, `forge-run`, `forge-sprint`, `forge-status`, `forge-tour`.

**Top-level file scrubbing (3 files, same commit as shared sweep):**

`README.md`, `CLAUDE.md`, `CHANGELOG.md` are scrubbed for deleted-skill references in the sweep commit (same commit as shared updates), so the dangling-reference bats assertion passes from the moment it activates. The separate "top-level docs" commit later in the rollout contains only the *new content* (skill table rewrites, badge convention note, version bump, new 3.0.0 CHANGELOG section) — two-pass editing on the same file across different commits.

**Agent doc update** (1 file):

`agents/fg-100-orchestrator.md` — add §N Recovery op dispatch section.

**Test updates (11 files):**

`tests/contract/ui-frontmatter-consistency.bats` (extend with 5 new assertions), `tests/contract/skill-frontmatter.bats`, `tests/contract/explore-cache.bats`, `tests/contract/state-schema.bats`, `tests/contract/plan-cache.bats`, `tests/contract/compression-insights-contract.bats`, `tests/unit/skill-execution/decision-tree-refs.bats`, `tests/unit/skill-execution/skill-completeness.bats`, `tests/unit/skill-execution/skill-prerequisites.bats`, `tests/unit/skill-execution/forge-compress-integration.bats`, `tests/validate-plugin.sh`.

**Top-level updates (6 files):**

`README.md`, `CLAUDE.md`, `CHANGELOG.md`, `DEPRECATIONS.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`.

**Skill cross-references (~24 SKILL.md files with deleted-skill mentions):**

Overlaps with the 32 SKILL.md in-place contract updates — these get **both** passes in the same commit (contract + cross-reference cleanup). Not double-counted.

### 5.5 File-count arithmetic (exact)

| Category | Count |
|---|---|
| Delete directories | 7 |
| Delete files | 2 |
| Create | 6 |
| Rewrite | 3 |
| SKILL.md in-place updates | 32 |
| Agent `.md` updates | 42 |
| Shared file updates — deleted-skill refs | 27 (24 md + 1 SQL + 2 JSON) |
| Shared file updates — new content | 2 (agent-ui.md, agent-role-hierarchy.md; non-overlapping) |
| Orchestrator `.md` update | 1 |
| Test file updates | 8 |
| Test frontmatter bats extension | 1 |
| validate-plugin.sh extension | 1 |
| Top-level name-swap pass (Commit 5) | 3 (README.md, CLAUDE.md, CHANGELOG.md) |
| Top-level new-content pass (Commit 7) | 5 (README.md, CLAUDE.md, CHANGELOG.md, DEPRECATIONS.md, plugin.json, marketplace.json — two of these files are touched in both passes, counted per operation) |
| **Total file operations across the PR** | **9 + 6 + 3 + 32 + 42 + 27 + 2 + 1 + 8 + 1 + 1 + 3 + 6 = 141 operations** |

(Note: "operations" differ from "unique files" — README.md, CLAUDE.md, CHANGELOG.md are each touched in two distinct commits, so contribute 2 operations but only 1 unique file each.)

## 6. Acceptance criteria

All verified by CI on push; no local test runs permitted.

1. 7 deprecated skill directories removed from `skills/`.
2. `skills/forge-recover/SKILL.md` exists; all 5 subcommands dispatch correctly.
3. `skills/forge-compress/SKILL.md` rewritten; all 4 subcommands dispatch correctly.
4. Every SKILL.md `description:` begins with `[read-only]` or `[writes]`.
5. Every SKILL.md contains `## Flags` and `## Exit codes` sections.
6. Every mutating skill lists `--dry-run`; every read-only skill lists `--json`; every skill lists `--help`.
7. Every agent `.md` contains explicit `ui:` block with `tasks`, `ask`, `plan_mode` keys.
8. No agent uses the `ui: { tier: N }` shortcut (3 agents normalized).
9. `fg-210-validator` carries `ui: { tasks: true, ask: true, plan_mode: false }` and lists `TaskCreate`, `TaskUpdate`, `AskUserQuestion` in `tools:`.
10. Every agent `.md` has a `color:` field (including `fg-205`).
11. Cluster-scoped color uniqueness holds per the table in `shared/agent-colors.md`.
12. Description word count within tier range using the §4.5.6 tokenization rule.
13. 14 Tier 1/2 agent `.md` files contain `## User-interaction examples` with ≥1 valid `AskUserQuestion` JSON block.
14. `shared/skill-contract.md`, `shared/agent-colors.md`, `shared/ask-user-question-patterns.md` exist and reference-check passes.
15. `shared/agent-ui.md` no longer contains the "Omitting the `ui:` section" language.
16. `shared/agent-role-hierarchy.md` lists `fg-205` and places `fg-210` in Tier 2.
17. `shared/state-schema.md` documents the `recovery_op` field.
18. `agents/fg-100-orchestrator.md` contains the Recovery op dispatch section.
19. `/forge-help` output matches the template in §4.8; `/forge-help --json` emits valid JSON.
20. `tests/contract/ui-frontmatter-consistency.bats` contains the 5 new assertions.
21. `tests/contract/skill-contract.bats` created; all assertions pass.
22. `tests/structural/ui-frontmatter-consistency.bats` deleted.
23. `tests/unit/skill-execution/forge-recover-integration.bats` created; verifies SKILL.md advertises 5 subcommands + `--dry-run` on mutating subcommands + `--json` on `diagnose`. **Runtime `--dry-run` verification** (invoking the orchestrator and snapshot-diffing `.forge/`) requires live fixtures and is deferred to Phase 2.
24. 24 `shared/*.md` files have zero references to deleted skill names.
25. All 11 test files updated; dangling-reference sweep in `skill-contract.bats` returns clean.
26. `README.md`, `CLAUDE.md`, `CHANGELOG.md`, `DEPRECATIONS.md` updated per §4.9.
27. `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` version fields set to `3.0.0`.
28. Plugin version is `3.0.0`.
29. CI green on push — no local `./tests/run-all.sh` runs permitted.

## 7. Test strategy

**Static validation (bats, CI-only):**

- Extended `tests/contract/ui-frontmatter-consistency.bats` covers AC #7-13.
- New `tests/contract/skill-contract.bats` covers AC #4-6, #14, #19, #24-25.
- Deletion of `tests/structural/ui-frontmatter-consistency.bats` removes a known drift source.
- `tests/validate-plugin.sh` extension catches structural regressions.

**Integration validation (bats in `tests/unit/skill-execution/`):**

- New `forge-recover-integration.bats` — invokes each subcommand with `--dry-run` and asserts:
  - Exit code 0 on success
  - No writes under `.forge/` (by capturing `.forge/` snapshot before/after)
  - Stdout contains human-readable report
- Extended `forge-compress-integration.bats` — same pattern for new subcommands.
- Existing `forge-run-integration.bats`, `forge-fix-integration.bats`, `forge-review-integration.bats` — re-verified green (reference updates only, no behavior change).

**Per user instruction:** tests are not run locally; CI on push is the source of truth.

## 8. Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Cross-references to deleted skills missed; CI greps catch them but timing varies | Medium | Medium | Dangling-reference sweep in `skill-contract.bats` is exhaustive (shared/, skills/, tests/, hooks/, root .md files) |
| `recovery_op` field addition breaks existing orchestrator JSON parsers | Low | High | `fg-100-orchestrator.md` treats it as optional input; absent → old behavior (reject unknown recovery path) |
| `fg-210` tools list extension triggers model-routing config mismatch | Low | Low | `shared/model-routing.md` routes by tools — TaskCreate/AskUserQuestion are already in the "standard" tier; no routing change needed |
| Description word-count tokenization disagreement between bats and human reading | Low | Low | Rule is explicit in §4.5.6; one unit test in `skill-contract.bats` exercises the tokenizer against a known sample |
| 24 `shared/*.md` updates introduce prose drift in docs that are agent contracts | Medium | Medium | All 24 updates are mechanical name-swap only; no semantic changes. Grep-based sed pass reviewed in PR |
| Color reassignments reduce visual continuity for users with muscle memory | Low | Low | `CHANGELOG.md` entry lists the palette change; `/forge-help` rendering uses descriptive dots, not memorized colors |
| `tests/structural/` deletion is discovered mid-review to contain unique assertions | Low | Low | Plan step "audit both bats files; confirm contract/ subsumes structural/" before deleting |
| 14 `AskUserQuestion` example blocks inflate agent prompt tokens | Medium | Low | ~200 tokens per example × 14 agents ≤ 2800 tokens. Per `shared/output-compression.md` this is <1.5% of agent-prompt budget |
| Rewrite of `forge-help` decision tree loses edge-case information | Low | Medium | §4.8 is augment-not-replace: existing tiered taxonomy and Similar-Skills section preserved |
| Plan-writing step produces tasks that exceed one-PR scope | Medium | Medium | Plan template includes per-commit granularity; if a commit touches >40 files it splits |

## 9. Rollout (one PR, multi-commit; CI gates on merge commit only)

Per-commit order chosen so no intermediate commit leaves the tree in a state the dangling-reference sweep would fail:

1. **Commit 1 — Specs land.** This spec + implementation plan (Phase 1) into `docs/superpowers/`.
2. **Commit 2 — New shared docs + bats + skills created.** `shared/skill-contract.md`, `shared/agent-colors.md`, `shared/ask-user-question-patterns.md`, `skills/forge-recover/SKILL.md`, new bats file, new integration test. Existing tree still references old skills; new files are additive. CI green.
3. **Commit 3 — Frontmatter contract applied.** All 42 agent `.md` updates (explicit `ui:`, unique colors, tier-sized descriptions). `fg-210` promoted. 14 Tier 1/2 agents get examples. `shared/agent-ui.md`, `shared/agent-role-hierarchy.md` updated. Bats assertions now activate; pass. CI green.
4. **Commit 4 — Skill contract applied.** 32 SKILL.md in-place updates (badges, Flags section, Exit codes section, flag coverage). `forge-compress` rewritten. `forge-help` augmented. Bats assertions for skill contract activate; pass. CI green.
5. **Commit 5 — Deletions + dangling-reference sweep.** 7 skill directories deleted. 27 shared file updates (24 md + 1 SQL + 2 JSON). 17 skill cross-reference sed updates (overlap with Commit 4 contract updates — both passes land together). 8 test file updates + 1 bats extension + validate-plugin.sh extension. 3 top-level name-swap scrubs (README.md, CLAUDE.md, CHANGELOG.md — content additions deferred to Commit 7). `tests/structural/ui-frontmatter-consistency.bats` deleted. `tests/unit/caveman-modes.bats` renamed to `compress-output-modes.bats`. Dangling-reference bats sweep activates; passes because ALL references everywhere were scrubbed in this commit. CI green.
6. **Commit 6 — State schema + orchestrator.** `shared/state-schema.md` adds `recovery_op`. `agents/fg-100-orchestrator.md` adds Recovery op dispatch section. CI green.
7. **Commit 7 — Top-level docs.** `README.md`, `CLAUDE.md`, `CHANGELOG.md`, `DEPRECATIONS.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`. Version bumped to 3.0.0. CI green.
8. **Push → CI gate on HEAD → on green, tag `v3.0.0` → release.**

If CI fails on any commit: fix forward in the next commit. Each commit is independently green because the ordering puts additive work before subtractive work.

## 10. Versioning rationale (SemVer major)

This phase is a breaking change (7 skill deletions, no aliases). SemVer rules → major bump. Bump `2.8.0 → 3.0.0` (not `2.9.0`). User's single-user stance would permit `2.9.0` as a deliberate SemVer deviation, but matching SemVer costs nothing and signals breaking change to any future tooling or contributor.

## 11. Open questions

None. All design decisions locked in the brainstorming session preceding this draft (see conversation turn transcript).

## 12. References

- `CLAUDE.md` — canonical architecture reference
- `shared/agent-ui.md` — current UI tier contract (to be revised)
- `shared/agent-role-hierarchy.md` — authoritative tier + cluster definitions
- `shared/output-compression.md` — per-stage verbosity budget (basis for the <1.5% token-bloat claim)
- `shared/state-schema.md` — v1.6.0 state fields (target of `recovery_op` addition)
- April 2026 UX audit (conversation memory)
- User's explicit instruction: "I want to have it all except the backwards compatibility"
- Superpowers `brainstorming` skill contract
- Superpowers `requesting-code-review` skill output (v1 review applied in this revision)
