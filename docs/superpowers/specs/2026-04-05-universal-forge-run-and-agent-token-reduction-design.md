# Universal `/forge-run` with Intelligent Routing & Agent Token Reduction

**Date:** 2026-04-05
**Status:** Draft
**Scope:** Two related enhancements to the forge plugin

---

## 1. Problem Statement

### 1a. Large/Multi-Feature Requirements Stall the Pipeline

When a user runs `/forge-run "Add auth, billing, and notifications"`, the pipeline burns through EXPLORE and PLAN only to discover at VALIDATE that this is 3 separate features. It REVISE-loops, eventually NO-GOs, and the user has to manually split and re-invoke. The sprint orchestrator (`fg-090`) already handles parallel feature execution, but it's only reachable via explicit `--sprint`/`--parallel` flags.

Additionally, users must know which command to use (`/forge-run`, `/forge-fix`, `/forge-shape`, `/forge-sprint`) — the system should figure this out from the input.

### 1b. Agent Description Token Bloat

The 37 forge agents contribute ~15.4k tokens to the system prompt via their `description` fields (with `<example>` blocks). The threshold is 15.0k. These tokens are paid on every conversation turn, whether or not the agent is ever dispatched. Almost all agents are dispatched by explicit name, not by description matching — the rich descriptions are unnecessary overhead.

---

## 2. Universal `/forge-run` with Intelligent Routing

### 2.1 Vision

`/forge-run` becomes the single universal command. The system auto-classifies the input and routes to the correct flow. Explicit prefixes (`bugfix:`, `migrate:`, `bootstrap:`) and flags (`--sprint`, `--spec`) remain as hard overrides but are no longer required. Other entry-point commands (`/forge-fix`, `/forge-shape`, `/forge-sprint`) remain as explicit shortcuts — they are not deprecated.

### 2.2 Intent Classification

Before dispatching any agent, `forge-run` performs lightweight text-based intent classification:

| Intent | Signal Examples | Route |
|--------|----------------|-------|
| **bugfix** | "fix the 404 on /users", error stack traces, "broken", "regression", ticket with `bug` label | `fg-020-bug-investigator` → `fg-100` in bugfix mode |
| **multi-feature** | Multiple distinct domains joined by "and"/"plus", enumerated capabilities, scope implying 4+ stories | `fg-015-scope-decomposer` → `fg-090` sprint |
| **migration** | "upgrade X to Y", "replace X with Y", "migrate from X to Y" | `fg-100` in migration mode → `fg-160` |
| **bootstrap** | "scaffold a new project", "start from scratch", empty project detected | `fg-100` in bootstrap mode → `fg-050` |
| **vague/large** | Very short or very long input, no clear ACs, exploratory language ("something like", "maybe") | `fg-010-shaper` → shaped spec → re-enter `forge-run` |
| **single-feature** | Clear, bounded requirement with identifiable scope | `fg-100-orchestrator` (standard pipeline) |

Classification is a decision tree on requirement text — not an expensive analysis. Explicit mode prefixes and flags act as hard overrides that skip classification entirely.

### 2.3 Autonomous Flag Behavior

- `autonomous: false` (default): Show classification result and ask confirmation before routing. "This looks like a bugfix. Route to bugfix flow?" with override options via `AskUserQuestion`.
- `autonomous: true`: Classify and route without pausing. Log with `[AUTO-ROUTE]` prefix.

### 2.4 Flow Diagram

```
/forge-run "user input"
    |
    +-- Has explicit prefix/flag? --yes--> Use that mode directly
    |
    +-- No override
        |
        v
    Intent Classification (lightweight, text-based)
        |
        +-- bugfix       --> fg-020 (bug investigator) --> fg-100 in bugfix mode
        +-- migration    --> fg-100 in migration mode (dispatches fg-160)
        +-- bootstrap    --> fg-100 in bootstrap mode (dispatches fg-050)
        +-- vague/large  --> fg-010 (shaper) --> shaped spec --> re-enter forge-run
        +-- multi-feature --> fg-015 (decomposer) --> fg-090 (sprint)
        |
        +-- single-feature --> fg-100 (standard pipeline)
                                |
                                v
                          After EXPLORE:
                          Deep scope check
                                |
                                +-- Still single --> continue pipeline
                                +-- Actually multi --> escalate to fg-015 --> fg-090
```

---

## 3. Two-Phase Scope Analysis (Auto-Decomposition)

### 3.1 Phase 1 — Pre-Exploration Fast Scan (in `forge-run` SKILL)

Before dispatching any agent, `forge-run` performs a lightweight text analysis of the requirement:

- **Signal detection**: Multiple distinct domain nouns joined by conjunctions ("auth AND billing AND notifications"), enumerated capabilities, explicit multi-feature language ("also add", "on top of that", "plus")
- **Output**: Either `SINGLE_FEATURE` (proceed normally) or `CANDIDATE_MULTI_FEATURE` with extracted feature candidates
- **On CANDIDATE_MULTI_FEATURE**: Dispatch `fg-015-scope-decomposer`

This catches ~60-70% of oversized requirements for free (no exploration cost).

### 3.2 Phase 2 — Post-Exploration Deep Scan (in `fg-100` orchestrator)

After EXPLORE completes, the orchestrator checks if the codebase reveals cross-domain complexity not obvious from text:

- **Signal detection**: Requirement touches 3+ distinct architectural domains (separate bounded contexts, different API groups, independent data models)
- **Threshold**: Configurable via `scope.decomposition_threshold` (default: 3 domains)
- **On trigger**: Orchestrator pauses, escalates to `fg-015-scope-decomposer`

### 3.3 New Agent: `fg-015-scope-decomposer`

**Purpose**: Takes a multi-feature requirement and decomposes it into discrete, independently-runnable features.

**Flow**:
1. Analyze the requirement text (and exploration notes if available from Phase 2)
2. Extract distinct features with clear boundaries
3. For each feature: title, description, estimated scope (S/M/L), dependencies on other extracted features
4. Run `fg-102-conflict-resolver` logic to determine independence
5. Present decomposition to user via `EnterPlanMode` (or auto-approve if `autonomous: true`)
6. Route to execution:
   - 2+ independent features --> dispatch `fg-090-sprint-orchestrator` with feature list
   - 2+ dependent features --> dispatch `fg-090` with serialization constraints
   - User overrides --> can cherry-pick, reorder, or select a single feature

**Execution routing**:
- Independent features run in parallel via `fg-090` (leverages existing sprint machinery)
- Dependent features get serialized in dependency order via `fg-090` with `serialize` conflict resolution
- User can override: choose parallel sprint, sequential, or cherry-pick which features to run now

### 3.4 Config

```yaml
# forge-config.md
scope:
  auto_decompose: true           # enable/disable auto-decomposition
  decomposition_threshold: 3     # domain count that triggers deep scan
  fast_scan: true                # enable pre-exploration text analysis

routing:
  auto_classify: true            # enable intent classification
  vague_threshold: low           # low = aggressively route to shaper, medium = default, high = rarely shape
```

Note: `vague_threshold` is an LLM classification guideline, not a numeric score. The classifier uses it as a qualitative bar for when to route to the shaper vs proceed with a best-effort single-feature interpretation.

### 3.5 State Schema Addition

New field in `state.json`:

```json
{
  "decomposition": {
    "source": "fast_scan | deep_scan | null",
    "original_requirement": "string",
    "extracted_features": [
      {
        "id": "feat-1",
        "title": "string",
        "description": "string",
        "scope": "S | M | L",
        "depends_on": ["feat-2"]
      }
    ],
    "routing": "parallel | serial | single",
    "user_selection": ["feat-1", "feat-3"]
  }
}
```

---

## 4. Visual Design Preview for Frontend Features

### 4.1 When It Activates

During the PLAN stage (fg-200), when the planner detects a frontend feature:
- `framework:` points to react/vue/svelte/angular/sveltekit/nextjs
- Requirement mentions UI/page/component/layout/dashboard

### 4.2 Integration with Superpowers Visual Companion

Forge reuses the superpowers plugin's visual companion server when available. This follows the same pattern forge uses for MCPs — detect availability, use if present, degrade gracefully.

**Detection**: At PREFLIGHT, check if `~/.claude/plugins/*/skills/brainstorming/visual-companion.md` exists and the corresponding `scripts/start-server.sh` is executable. Store result in `state.json.integrations.visual_companion: true|false`.

```
PLAN stage (fg-200)
    |
    +-- Frontend feature detected?
    |     |
    |     +-- no --> standard text-based plan
    |     |
    |     +-- yes --> Check: superpowers visual companion available?
    |               |
    |               +-- yes --> Start server, generate mockup HTML,
    |               |           present options, read selection
    |               |
    |               +-- no --> Fall back to text descriptions
    |                          of design alternatives
    |
    v
  Plan includes selected design direction as constraint
```

### 4.3 How It Works

1. **Planner detects frontend feature** and generates 2-3 design directions
2. **Forge starts the superpowers server** via `scripts/start-server.sh --project-dir $PROJECT_ROOT` (session stored in `.superpowers/brainstorm/`)
3. **Writes mockup HTML fragments** using superpowers' CSS classes (`.options`, `.cards`, `.mockup`, `.split`)
4. **User views and clicks** to select preferred direction
5. **Forge reads events** from `$STATE_DIR/events`, captures selection
6. **Selection embedded in plan** as design constraint: "User selected Layout B (sidebar navigation with card grid)"
7. **Server stopped** after planning (or kept alive if `fg-320-frontend-polisher` will use it for review)

### 4.4 What Gets Presented

| Decision Type | Example |
|---------------|---------|
| Page layout | Sidebar vs top-nav, single-column vs grid |
| Component design | Card styles, form layouts, table designs |
| Color/theme direction | Minimal vs bold, light-first vs dark-first |
| Responsive strategy | Mobile-first reflow options |
| Interaction pattern | Modal vs inline, wizard vs single-page |

### 4.5 Autonomous Mode

- `autonomous: false`: Present visuals, wait for user selection
- `autonomous: true`: Skip visual preview, planner picks design direction based on codebase conventions and `frontend-design-theory.md` principles. Logs `[AUTO-DESIGN]`.

### 4.6 Config

```yaml
# forge.local.md
frontend_preview:
  enabled: true               # enable visual design preview
  auto_open_browser: true     # auto-open URL in default browser
  keep_alive_for_polish: true # keep server running for fg-320
```

### 4.7 Graceful Degradation

- No superpowers plugin --> text-only design descriptions (already works today)
- Superpowers available but user declines browser --> text-only fallback
- `autonomous: true` --> skip entirely, auto-pick

---

## 5. Agent Description Token Reduction

### 5.1 Root Cause

The 37 forge agents contribute ~15.4k tokens via `description` fields in YAML frontmatter. Each carries 2-3 `<example>` blocks with full Context/user/assistant dialogue. These are loaded into the system prompt at conversation start and paid on every turn.

### 5.2 Key Insight

Almost none of these agents are discovered by description matching. The dispatch chain is fully deterministic:
- Skills dispatch entry-point agents by explicit `subagent_type` name
- The orchestrator dispatches pipeline agents by explicit name
- The quality gate dispatches review agents by explicit name

Rich descriptions with examples are unnecessary overhead for deterministic dispatch.

### 5.3 Three-Tier Description Strategy

**Tier 1 — Entry-point agents (5 agents): Short description + 1 compressed example**

Dispatched by skills, "face" of the pipeline. ~60-80 tokens each.

| Agent | Role |
|-------|------|
| `fg-100-orchestrator` | Main pipeline coordinator |
| `fg-090-sprint-orchestrator` | Parallel feature coordinator |
| `fg-010-shaper` | Pre-pipeline feature shaping |
| `fg-020-bug-investigator` | Bugfix investigation |
| `fg-050-project-bootstrapper` | New project scaffolding |

Format: ~30-40 word description + 1 example (2-3 lines). Remove all but one example, compress remaining.

**Tier 2 — Review agents (10 agents): One-line description, no examples**

Dispatched by `fg-400-quality-gate` by explicit name. ~20-25 tokens each.

Agents: `architecture-reviewer`, `security-reviewer`, `frontend-reviewer`, `frontend-design-reviewer`, `frontend-a11y-reviewer`, `frontend-performance-reviewer`, `backend-performance-reviewer`, `version-compat-reviewer`, `infra-deploy-reviewer`, `docs-consistency-reviewer`.

Format: 1 sentence, ~15-20 words. No examples.

**Tier 3 — Internal pipeline agents (22 agents): Minimal one-line, no examples**

Only dispatched by orchestrator or coordinator agents. ~15-20 tokens each.

Agents: `fg-101-worktree-manager`, `fg-102-conflict-resolver`, `fg-103-cross-repo-coordinator`, `fg-130-docs-discoverer`, `fg-140-deprecation-refresh`, `fg-150-test-bootstrapper`, `fg-160-migration-planner`, `fg-200-planner`, `fg-210-validator`, `fg-250-contract-validator`, `fg-300-implementer`, `fg-310-scaffolder`, `fg-320-frontend-polisher`, `fg-350-docs-generator`, `fg-400-quality-gate`, `fg-500-test-gate`, `fg-600-pr-builder`, `fg-650-preview-validator`, `fg-700-retrospective`, `fg-710-feedback-capture`, `fg-720-recap`, `infra-deploy-verifier`.

Format: 1 short sentence, ~10-15 words. No examples.

### 5.4 Token Budget

| Tier | Count | Tokens/Agent | Total |
|------|-------|-------------|-------|
| Tier 1 (entry-point) | 5 | ~60-80 | ~350 |
| Tier 2 (reviewers) | 10 | ~20-25 | ~225 |
| Tier 3 (internal) | 22 | ~15-20 | ~385 |
| New: fg-015-scope-decomposer | 1 | ~60-80 | ~70 |
| **Total** | **38** | -- | **~1,030** |

**Current: ~15,400 tokens --> Projected: ~1,030 tokens. Reduction: ~93%.**

### 5.5 Example Transformations

**Tier 1 (before --> after):**

```yaml
# BEFORE (~150 tokens)
description: |
  Autonomous pipeline orchestrator -- coordinates the 10-stage development lifecycle.
  Reads forge.local.md for project-specific config. Dispatches fg-* agents per stage.
  Manages .forge/ state for recovery. Only pauses when risk exceeds threshold or max retries exhausted.

  <example>
  Context: Developer wants to implement a feature
  user: "Implement plan comment feature"
  assistant: "I'll dispatch the pipeline orchestrator to handle the full development lifecycle."
  </example>

  <example>
  Context: A previous run was interrupted
  user: "Resume the pipeline"
  assistant: "I'll dispatch the orchestrator to check for saved state and resume."
  </example>

# AFTER (~50 tokens)
description: |
  Autonomous pipeline orchestrator -- coordinates the 10-stage development lifecycle.
  Reads forge.local.md for config. Dispatches fg-* agents per stage. Manages .forge/ state for recovery.

  <example>
  Context: Developer wants to implement a feature
  user: "Implement plan comment feature"
  assistant: "I'll dispatch the pipeline orchestrator to handle the full development lifecycle."
  </example>
```

**Tier 2 (before --> after):**

```yaml
# BEFORE (~200 tokens with examples)
description: |
  Detects the project's architecture pattern and reviews code for compliance.
  Supports hexagonal/ports-and-adapters, clean architecture, layered/N-tier, MVC,
  microservices, and modular monolith. ...
  <example>...</example>

# AFTER (~25 tokens)
description: Reviews code for architecture pattern compliance (hexagonal, clean, layered, MVC, microservices, modular monolith).
```

**Tier 3 (before --> after):**

```yaml
# BEFORE (~250 tokens with 3 examples)
description: |
  TDD implementation agent -- writes tests first (RED), implements to pass (GREEN),
  refactors. Follows SOLID, idiomatic code, and project conventions. ...
  <example>...</example>
  <example>...</example>
  <example>...</example>

# AFTER (~20 tokens)
description: TDD implementation agent -- writes tests first (RED), implements to pass (GREEN), refactors.
```

### 5.6 What Is NOT Changed

- Agent system prompts (body of `.md` files) -- unchanged, loaded at dispatch time
- `tools`, `ui`, `color`, `model` frontmatter fields -- unchanged
- Agent capabilities -- identical, only system-prompt-visible description compressed
- Dispatch mechanism -- unchanged, all by explicit name

---

## 6. New Files & Modified Files

### New Files

| File | Purpose |
|------|---------|
| `agents/fg-015-scope-decomposer.md` | New agent: decomposes multi-feature requirements |
| `shared/intent-classification.md` | Classification rules and signal definitions |

### Modified Files

| File | Change |
|------|--------|
| `skills/forge-run/SKILL.md` | Add intent classification step (2.2), scope fast-scan (3.1), visual preview routing |
| `agents/fg-100-orchestrator.md` | Add post-EXPLORE deep scope check (3.2), escalation to fg-015 |
| `agents/fg-090-sprint-orchestrator.md` | Accept feature list from fg-015 (same format as --parallel input) |
| `agents/fg-200-planner.md` | Add visual design preview step for frontend features (4.2-4.3) |
| `shared/state-schema.md` | Add `decomposition` field (3.5), bump version |
| `shared/stage-contract.md` | Document auto-decomposition escalation path |
| All 37 `agents/*.md` | Compress descriptions per tier (5.3) |
| `CLAUDE.md` | Document new agent, config options, routing behavior |
| `tests/lib/module-lists.bash` | Bump MIN_AGENTS count for fg-015 |

### Config Additions

```yaml
# forge-config.md additions
scope:
  auto_decompose: true
  decomposition_threshold: 3
  fast_scan: true

routing:
  auto_classify: true
  vague_threshold: medium

# forge.local.md additions
frontend_preview:
  enabled: true
  auto_open_browser: true
  keep_alive_for_polish: true
```

---

## 7. PREFLIGHT Constraints (New)

| Parameter | Range | Default |
|-----------|-------|---------|
| `scope.decomposition_threshold` | 2-10 | 3 |
| `routing.vague_threshold` | low / medium / high | medium |

---

## 8. Out of Scope

- Changes to `/forge-fix`, `/forge-shape`, `/forge-sprint` — they remain as-is
- Modifications to the superpowers visual companion server itself — forge uses it as-is
- Changes to agent system prompt bodies (only frontmatter descriptions change)
- New MCP integrations
