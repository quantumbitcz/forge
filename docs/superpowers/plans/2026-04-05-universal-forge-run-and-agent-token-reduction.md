# Universal forge-run & Agent Token Reduction — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `/forge-run` a universal entry point with intelligent routing and auto-decomposition of multi-feature requirements, while reducing agent description tokens from ~15.4k to ~1k.

**Architecture:** Three independent workstreams: (1) Intent classification + scope decomposition in forge-run SKILL and orchestrator, with new fg-015-scope-decomposer agent; (2) Visual design preview integration in fg-200-planner using superpowers visual companion; (3) Three-tier agent description compression across all 37 agents.

**Tech Stack:** Markdown agent definitions, YAML frontmatter, bash validation scripts. No build step — documentation-only plugin.

**Spec:** `docs/superpowers/specs/2026-04-05-universal-forge-run-and-agent-token-reduction-design.md`

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `shared/intent-classification.md` | Classification rules, signal definitions, routing table for forge-run |
| `agents/fg-015-scope-decomposer.md` | Agent that decomposes multi-feature requirements into discrete features |

### Modified Files
| File | Change |
|------|--------|
| `skills/forge-run/SKILL.md` | Add intent classification step + scope fast scan between steps 1 and 3 |
| `agents/fg-100-orchestrator.md` | Add post-EXPLORE deep scope check with escalation to fg-015 |
| `agents/fg-200-planner.md` | Add visual design preview section for frontend features |
| `shared/state-schema.md` | Add `decomposition` and `routing` fields, bump version to 1.3.0 |
| `shared/stage-contract.md` | Document auto-decomposition escalation path in EXPLORE and new DECOMPOSE transition |
| `CLAUDE.md` | Document fg-015, config options, routing, visual preview, tier descriptions |
| All 37 `agents/*.md` | Compress descriptions per three-tier strategy |

---

## Task 1: Create `shared/intent-classification.md`

**Files:**
- Create: `shared/intent-classification.md`

- [ ] **Step 1: Write the intent classification reference document**

```markdown
# Intent Classification

Reference document for the intent classification system used by `/forge-run` to auto-route requirements to the correct pipeline mode.

## Classification Table

| Intent | Signals | Confidence Threshold | Route |
|--------|---------|---------------------|-------|
| **bugfix** | "fix", "bug", "broken", "regression", "error", "crash", "404", "500", stack traces, ticket with `bug` label | Any 2+ signals or 1 strong signal (stack trace, error code) | `fg-020-bug-investigator` → `fg-100` bugfix mode |
| **migration** | "upgrade", "migrate", "replace X with Y", "move from X to Y", version numbers in context | Pattern: `{verb} {from} to/with {to}` | `fg-100` migration mode → `fg-160` |
| **bootstrap** | "scaffold", "create new", "start from scratch", "initialize", "new project", empty project root | Any 1+ signal or empty project detection | `fg-100` bootstrap mode → `fg-050` |
| **multi-feature** | 3+ distinct domain nouns joined by conjunctions, enumerated capabilities ("1. X 2. Y 3. Z"), "also add", "plus", "on top of" | 3+ distinct features detected | `fg-015-scope-decomposer` → `fg-090` |
| **vague** | Very short (<10 words with no specifics), very long (>500 words), no acceptance criteria, exploratory language ("something like", "maybe", "could we", "what if") | Qualitative assessment per `routing.vague_threshold` | `fg-010-shaper` → shaped spec → re-enter |
| **single-feature** | Clear, bounded requirement with identifiable scope | Default when no other intent matches | `fg-100-orchestrator` standard mode |

## Classification Priority

When multiple intents match, use this precedence (highest first):
1. Explicit prefix/flag override (always wins)
2. bugfix (specific, actionable)
3. migration (specific pattern)
4. bootstrap (specific or environmental)
5. multi-feature (structural detection)
6. vague (catch-all for unclear)
7. single-feature (default)

## Signal Detection Rules

### Bugfix Signals
- Keywords: fix, bug, broken, regression, error, crash, fail, wrong, incorrect, 404, 500, exception, null, undefined
- Patterns: error codes (`HTTP 4xx/5xx`), stack traces (multi-line with `at` or `File` prefixes), "doesn't work", "stopped working"
- Ticket context: ticket with `bug` label, priority `urgent`/`critical`

### Multi-Feature Signals
- Conjunctions joining distinct domains: "auth AND billing AND notifications"
- Enumerated items: "1. user auth 2. payment processing 3. email notifications"
- Additive language: "also add", "plus", "on top of that", "additionally"
- Domain count: 3+ unrelated bounded contexts in a single requirement

### Vague Signals
- Length extremes: <10 words with no technical specifics, or >500 words of stream-of-consciousness
- Exploratory language: "something like", "maybe we could", "what if", "I'm thinking about"
- Missing specifics: no endpoints, no data models, no user flows, no acceptance criteria
- Threshold levels: `low` (aggressively route to shaper), `medium` (default), `high` (rarely shape)

## Autonomous Mode

- `autonomous: false` (default): Present classification result via AskUserQuestion with structured options (classified intent as recommended, plus "Override: run as standard feature" and "Override: choose mode manually")
- `autonomous: true`: Classify and route without pausing. Log: `[AUTO-ROUTE] Classified as {intent} based on signals: {signal_list}`
```

- [ ] **Step 2: Commit**

```bash
git add shared/intent-classification.md
git commit -m "feat: add intent classification reference for universal forge-run routing"
```

---

## Task 2: Create `agents/fg-015-scope-decomposer.md`

**Files:**
- Create: `agents/fg-015-scope-decomposer.md`

- [ ] **Step 1: Write the scope decomposer agent**

```markdown
---
name: fg-015-scope-decomposer
description: |
  Decomposes multi-feature requirements into discrete, independently-runnable features. Routes to sprint orchestrator for parallel or serial execution.

  <example>
  Context: User submits a requirement spanning multiple domains
  user: "Add user authentication, billing system, and email notifications"
  assistant: "I'll decompose this into 3 independent features and dispatch the sprint orchestrator for parallel execution."
  </example>
model: inherit
color: magenta
tools: ['Read', 'Grep', 'Glob', 'Bash', 'Agent', 'AskUserQuestion', 'EnterPlanMode', 'ExitPlanMode', 'TaskCreate', 'TaskUpdate']
ui:
  tasks: true
  ask: true
  plan_mode: true
---

# Scope Decomposer (fg-015)

You decompose multi-feature requirements into discrete, independently-runnable features. You are a coordinator — you analyze scope, not implement code.

**Philosophy:** Apply principles from `shared/agent-philosophy.md` — challenge assumptions, prefer smaller scope, seek the minimal viable decomposition.
**UI contract:** Follow `shared/agent-ui.md` for TaskCreate/TaskUpdate lifecycle, AskUserQuestion structured options, and EnterPlanMode/ExitPlanMode design approval flow. In autonomous mode (`autonomous: true`), auto-approve decomposition and log with `[AUTO]` prefix.

Decompose the following requirement: **$ARGUMENTS**

---

## 1. Identity & Purpose

You sit between `/forge-run` (or the orchestrator's post-EXPLORE scope check) and the sprint orchestrator (`fg-090`). Your job:

1. Take a multi-feature requirement
2. Extract discrete features with clear boundaries
3. Analyze dependencies between features
4. Present the decomposition for approval
5. Route to `fg-090-sprint-orchestrator` for execution

You are dispatched in two scenarios:
- **Fast scan** (from `forge-run` SKILL): Requirement text analysis detected multiple features before exploration
- **Deep scan** (from `fg-100` orchestrator): Post-EXPLORE analysis revealed cross-domain complexity

---

## 2. Input

You receive:
1. **Requirement** — the original multi-feature requirement text
2. **Source** — `fast_scan` or `deep_scan` (determines available context)
3. **Exploration notes** — only if source is `deep_scan` (from Stage 1 notes)
4. **Available MCPs** — comma-separated list of detected integrations
5. **Project config** — framework, language, component structure from `forge.local.md`

---

## 3. Decomposition Process

### 3.1 Feature Extraction

Analyze the requirement and extract distinct features. A feature is distinct when it:
- Has its own bounded context (separate domain models, separate data)
- Can be described with independent acceptance criteria
- Can be implemented and tested without the other features being present
- Would make sense as a standalone `/forge-run` invocation

### 3.2 For Each Feature, Produce

```
Feature {N}: {title}
- Description: {1-2 sentence scope}
- Estimated scope: S / M / L
- Domain: {bounded context or area}
- Dependencies: [list of feature IDs this depends on, or "none"]
- Key signals: {what in the original requirement maps to this feature}
```

### 3.3 Dependency Analysis

For each pair of features, check:
- **Data dependency**: Does feature B need data/schema created by feature A?
- **API dependency**: Does feature B call an API endpoint created by feature A?
- **Shared code**: Do both features need to modify the same files?

If source is `deep_scan` and exploration notes are available, use the file list to detect shared-file conflicts. Otherwise, use domain-level heuristic analysis.

### 3.4 Independence Classification

- **Independent**: No dependencies between features → parallel execution
- **Serial**: Feature B depends on feature A → ordered execution
- **Shared-file conflict**: Both features modify same files → serialize those two, others may parallelize

Dispatch `fg-102-conflict-resolver` if exploration notes include file lists (deep_scan only). Otherwise, use heuristic domain analysis.

---

## 4. Approval

Call `EnterPlanMode` and present the decomposition:

```
## Scope Decomposition

Original requirement: "{original}"

### Extracted Features ({N} total)

{feature list with dependencies}

### Execution Plan

- Parallel group 1: {feature list}
- Serial chain: {feature A → feature B}

### Routing

→ Dispatching fg-090-sprint-orchestrator with {N} features
  - {X} features in parallel
  - {Y} features serialized (dependency: {reason})
```

Call `ExitPlanMode` after presenting.

If `autonomous: true`, skip plan mode — auto-approve and log with `[AUTO]` prefix.

Otherwise, present via `AskUserQuestion` with options:
- **"Proceed with this decomposition"** — dispatch fg-090
- **"Modify features"** — user adjusts scope, re-decompose
- **"Run just feature {N}"** — cherry-pick a single feature for standard fg-100
- **"Run as single feature anyway"** — skip decomposition, send to fg-100 as-is

---

## 5. Dispatch

Based on approval:

### Parallel/Serial → fg-090-sprint-orchestrator

Dispatch `fg-090-sprint-orchestrator` with:

```
Execute these features from decomposed requirement:

Features:
{feature list with titles and descriptions}

Execution order:
{parallel groups and serial chains}

Original requirement: "{original}"
Available MCPs: {mcps}
Source: decomposed (auto-detected from /forge-run)
```

### Single feature cherry-pick → fg-100-orchestrator

Dispatch `fg-100-orchestrator` with the selected feature's description only.

---

## 6. Output

Write decomposition results to orchestrator (via return value):
- Feature count, titles, dependency graph
- Execution routing (parallel/serial/single)
- User's selection (if override)

These are stored in `state.json.decomposition` by the calling context (forge-run SKILL or fg-100 orchestrator).
```

- [ ] **Step 2: Commit**

```bash
git add agents/fg-015-scope-decomposer.md
git commit -m "feat: add fg-015-scope-decomposer agent for multi-feature auto-decomposition"
```

---

## Task 3: Modify `skills/forge-run/SKILL.md` — Universal Routing

**Files:**
- Modify: `skills/forge-run/SKILL.md`

- [ ] **Step 1: Update the skill description in frontmatter**

Replace lines 1-3:
```yaml
---
name: forge-run
description: Universal pipeline entry point. Auto-classifies intent (feature, bugfix, migration, bootstrap, multi-feature) and routes to the correct pipeline mode. Accepts --from=<stage> to resume, --dry-run for analysis only, or --spec <path> for shaped specs.
---
```

- [ ] **Step 2: Update the opening line and restructure instructions**

Replace lines 6-8:
```markdown
# /forge-run — Universal Pipeline Entry Point

You are the universal entry point for the forge pipeline. Your job is to classify the user's intent, detect available integrations, and dispatch the correct agent. You handle routing — not planning, implementation, or review.
```

- [ ] **Step 3: Insert new step 2 (Intent Classification) after Input Parsing (step 1)**

After the existing "Ticket Resolution" section (after line 51) and before "Detect available MCPs" (current step 2), insert a new step:

```markdown
2. **Classify intent**: Unless the user provided an explicit mode prefix (step 1) or flag (`--sprint`, `--parallel`), classify the requirement to determine the correct pipeline mode. Read `shared/intent-classification.md` for the full classification table.

   **Classification order** (first match wins):
   1. Explicit prefix/flag → use that mode directly (skip classification)
   2. Bugfix signals → `Mode: bugfix`
   3. Migration signals → `Mode: migration`
   4. Bootstrap signals (or empty project) → `Mode: bootstrap`
   5. Multi-feature signals (3+ distinct domains) → `Mode: multi-feature`
   6. Vague signals (per `routing.vague_threshold` from forge-config.md, default: `medium`) → `Mode: vague`
   7. Default → `Mode: standard`

   **Read config**: If `routing.auto_classify` is `false` in `forge-config.md`, skip classification entirely and treat as `Mode: standard`.

   **Autonomous mode check**: Read `autonomous` from `forge-config.md` (default: `false`).
   - If `autonomous: false`: Present classification result via AskUserQuestion:
     - Header: "Intent Classification"
     - Question: "This looks like a **{classified_mode}** based on: {signal_summary}. Proceed with this routing?"
     - Options:
       - "{classified_mode} mode" (description: "Route to {target_agent}")
       - "Override: standard feature" (description: "Treat as single feature, route to fg-100")
       - "Override: choose mode" (description: "Let me pick: bugfix / migration / bootstrap / multi-feature / shape first")
   - If `autonomous: true`: Use classified mode directly. Log: `[AUTO-ROUTE] Classified as {mode} based on: {signals}`

   ### Scope Fast Scan (multi-feature detection)

   If classification didn't already detect multi-feature (and `scope.fast_scan` is not `false` in `forge-config.md`), perform a quick text scan for multi-feature signals:
   - 3+ distinct domain nouns joined by "and", "plus", comma-separated
   - Enumerated capabilities ("1. auth 2. billing 3. notifications")
   - Additive language ("also add", "on top of that", "additionally")

   If detected: set `Mode: multi-feature`.
```

- [ ] **Step 4: Renumber existing steps 2-6 to 3-7 and update step 4 (Sprint/Parallel) to include multi-feature routing**

Replace the current step 3 (Sprint/Parallel Mode) content:

```markdown
4. **Route by mode**: Based on the classified mode (or explicit prefix/flag):

   | Mode | Dispatch |
   |------|----------|
   | `--sprint` or `--parallel` flag | `fg-090-sprint-orchestrator` with `$ARGUMENTS` |
   | `multi-feature` | `fg-015-scope-decomposer` with requirement + `Available MCPs: {detected_mcps}` |
   | `vague` | `fg-010-shaper` with requirement. When shaper produces a spec, re-invoke forge-run with `--spec {spec_path}` |
   | `bugfix` | `fg-100-orchestrator` with `Mode: bugfix` + requirement |
   | `migration` | `fg-100-orchestrator` with `Mode: migration` + requirement |
   | `bootstrap` | `fg-100-orchestrator` with `Mode: bootstrap` + requirement |
   | `standard` | `fg-100-orchestrator` with requirement (default) |

   For `multi-feature` mode, dispatch `fg-015-scope-decomposer`:
   > Decompose this multi-feature requirement into independent features:
   >
   > Requirement: `{user_input}`
   >
   > Source: fast_scan
   > Available MCPs: `{detected_mcps}`

   For `vague` mode, dispatch `fg-010-shaper`:
   > Shape this requirement into a structured spec:
   >
   > `{user_input}`

   When the shaper returns a spec path, re-dispatch as:
   > `/forge-run --spec {spec_path}`

   For all other modes, dispatch `fg-100-orchestrator` with the existing prompt format (step 5).
```

- [ ] **Step 5: Update the orchestrator dispatch step to be step 5**

The existing step 4 becomes step 5, with the same content but updated numbering. Steps 5-6 become 6-7.

- [ ] **Step 6: Commit**

```bash
git add skills/forge-run/SKILL.md
git commit -m "feat: add intent classification and universal routing to forge-run skill"
```

---

## Task 4: Modify `agents/fg-100-orchestrator.md` — Post-EXPLORE Deep Scope Check

**Files:**
- Modify: `agents/fg-100-orchestrator.md` (after Stage 1: EXPLORE section, before Stage 2: PLAN)

- [ ] **Step 1: Add deep scope check section after EXPLORE stage**

After the EXPLORE stage section (after "Mark Explore as completed.") and before Stage 2: PLAN, insert:

```markdown
### Post-EXPLORE Scope Check (Auto-Decomposition)

After exploration completes (standard mode only — skip for bugfix, migration, bootstrap modes), check if the requirement spans too many architectural domains:

1. **Read config**: Check `scope.auto_decompose` from `forge-config.md` (default: `true`). If `false`, skip this check.

2. **Analyze exploration results**: From stage 1 notes, count distinct architectural domains touched by the requirement:
   - Different bounded contexts (separate domain model packages/directories)
   - Different API groups (separate controller/route namespaces)
   - Independent data models (separate database tables/collections with no FK relationships)
   - Different infrastructure concerns (auth vs. payments vs. notifications)

3. **Threshold check**: If domain count >= `scope.decomposition_threshold` (default: 3 from `forge-config.md`):

   a. Log in stage notes: `"Deep scope check triggered: {domain_count} domains detected (threshold: {threshold}). Domains: {domain_list}"`

   b. Dispatch `fg-015-scope-decomposer`:
   ```
   Decompose this multi-feature requirement into independent features:

   Requirement: {original_requirement}

   Source: deep_scan
   Exploration notes: {summarized stage 1 notes — file paths, domains, patterns}
   Available MCPs: {detected_mcps}
   ```

   c. The scope decomposer will handle user approval and dispatch to `fg-090-sprint-orchestrator`. This orchestrator instance should then **stop execution** — the sprint orchestrator takes over.

   d. Update state: `decomposition.source = "deep_scan"`, store extracted features and routing in `state.json.decomposition`.

   e. Set `story_state` to `"DECOMPOSED"` and return. Do NOT proceed to Stage 2.

4. **If domain count < threshold**: Proceed to Stage 2 (PLAN) as normal.
```

- [ ] **Step 2: Commit**

```bash
git add agents/fg-100-orchestrator.md
git commit -m "feat: add post-EXPLORE deep scope check to orchestrator for auto-decomposition"
```

---

## Task 5: Modify `agents/fg-200-planner.md` — Visual Design Preview

**Files:**
- Modify: `agents/fg-200-planner.md` (add new section after the planning process, before output)

- [ ] **Step 1: Add visual design preview section**

After the "Planning Process" section (section 3) and before the "Output" section, insert:

```markdown
### 3.X Visual Design Preview (Frontend Features)

When the requirement involves frontend UI changes AND the visual companion is available, present design alternatives visually before finalizing the plan.

**Activation conditions** (ALL must be true):
1. The requirement involves frontend UI (component creation, layout changes, page design)
2. The project has a frontend framework configured (`framework:` is react, vue, svelte, angular, sveltekit, or nextjs)
3. `frontend_preview.enabled` is `true` in `forge.local.md` (default: `true`)
4. `autonomous` is `false` in `forge-config.md` (skip visual preview in autonomous mode — pick design based on `shared/frontend-design-theory.md` principles and log `[AUTO-DESIGN]`)
5. The superpowers visual companion is available (check `state.json.integrations.visual_companion`)

**If all conditions met:**

1. **Generate 2-3 design directions** based on the requirement, exploration results, and existing design patterns in the codebase. Each direction should represent a meaningfully different approach (e.g., sidebar vs top-nav, card grid vs table, minimal vs feature-rich).

2. **Start the visual companion server**:
   ```bash
   # Find superpowers plugin path
   SUPERPOWERS_DIR=$(find ~/.claude/plugins -path "*/superpowers/*/skills/brainstorming" -type d | head -1)
   SUPERPOWERS_SCRIPTS="$(dirname "$SUPERPOWERS_DIR")/scripts"

   # Start server
   $SUPERPOWERS_SCRIPTS/start-server.sh --project-dir $PROJECT_ROOT
   ```
   Capture `screen_dir` and `state_dir` from the response.

3. **Write mockup HTML** for each design direction to `screen_dir`. Use content fragments (no full HTML documents). Use superpowers CSS classes:
   - `.options` / `.option` for selectable choices
   - `.cards` / `.card` for visual design cards
   - `.mockup` / `.mockup-body` for wireframe previews
   - `.split` for side-by-side comparison
   - `.mock-nav`, `.mock-sidebar`, `.mock-content` for wireframe blocks

4. **Present to user**: Tell them the URL and ask them to view and select. Read `$STATE_DIR/events` on next turn for click selections.

5. **Capture selection**: Record the user's chosen design direction. Embed it as a plan constraint:
   ```
   ## Design Constraint
   User selected: {Design Direction Name}
   Description: {brief description of chosen approach}
   Key decisions: {layout, color direction, interaction pattern}
   ```

6. **Stop server** (unless `frontend_preview.keep_alive_for_polish` is `true` — keep for fg-320 to reuse).

**If conditions NOT met**: Skip visual preview. Use text-based design alternative descriptions in the Challenge Brief as already done.
```

- [ ] **Step 2: Commit**

```bash
git add agents/fg-200-planner.md
git commit -m "feat: add visual design preview for frontend features in planner"
```

---

## Task 6: Modify `shared/state-schema.md` — Add Decomposition Fields

**Files:**
- Modify: `shared/state-schema.md`

- [ ] **Step 1: Bump version from 1.2.0 to 1.3.0**

Find and replace the version reference (appears in schema section).

- [ ] **Step 2: Add decomposition and routing fields to state.json schema**

In the state.json schema section, add after the existing `graph` field:

```markdown
### `decomposition` (object, optional)

Present when auto-decomposition was triggered. Null otherwise.

```json
{
  "decomposition": {
    "source": "fast_scan | deep_scan",
    "original_requirement": "string — the original user input before decomposition",
    "extracted_features": [
      {
        "id": "feat-1",
        "title": "string",
        "description": "string",
        "scope": "S | M | L",
        "domain": "string — bounded context or area",
        "depends_on": ["feat-2"]
      }
    ],
    "routing": "parallel | serial | single",
    "user_selection": ["feat-1", "feat-3"],
    "classified_intent": "bugfix | migration | bootstrap | multi-feature | vague | standard",
    "classification_signals": ["signal1", "signal2"]
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `source` | string | How decomposition was triggered: `fast_scan` (pre-explore text analysis) or `deep_scan` (post-explore domain analysis) |
| `original_requirement` | string | The original requirement text before decomposition |
| `extracted_features` | array | List of extracted features with metadata |
| `routing` | string | How features will be executed: `parallel`, `serial`, or `single` (cherry-picked) |
| `user_selection` | array | Feature IDs the user chose to execute (may be subset) |
| `classified_intent` | string | The intent classification result from forge-run |
| `classification_signals` | array | Signals that triggered the classification |
```

- [ ] **Step 3: Add `integrations.visual_companion` field**

In the `integrations` section of the schema, add:

```markdown
| `visual_companion` | boolean | Whether the superpowers visual companion server is available. Detected at PREFLIGHT by checking for `~/.claude/plugins/*/skills/brainstorming/visual-companion.md`. |
```

- [ ] **Step 4: Document the new `DECOMPOSED` story_state**

In the story_state values section, add:

```markdown
| `DECOMPOSED` | Requirement was decomposed into multiple features; sprint orchestrator taking over |
```

- [ ] **Step 5: Commit**

```bash
git add shared/state-schema.md
git commit -m "feat: add decomposition fields and visual_companion integration to state schema v1.3.0"
```

---

## Task 7: Modify `shared/stage-contract.md` — Document Decomposition Path

**Files:**
- Modify: `shared/stage-contract.md`

- [ ] **Step 1: Add decomposition escalation to Stage 1 EXPLORE exit conditions**

In the Stage 1 EXPLORE section, update the exit condition to add:

```markdown
**Exit condition:** Exploration results summarized and available for the planner. OR: auto-decomposition triggered (domain count >= `scope.decomposition_threshold`) — orchestrator dispatches `fg-015-scope-decomposer` and transitions to `DECOMPOSED` state instead of PLANNING.
```

- [ ] **Step 2: Add DECOMPOSED transition documentation**

After the Stage 1 section, add:

```markdown
### Decomposition Transition (EXPLORING → DECOMPOSED)

**Trigger:** Post-EXPLORE deep scope check detects requirement touches >= `scope.decomposition_threshold` (default: 3) distinct architectural domains.

**Actions:**
1. Orchestrator dispatches `fg-015-scope-decomposer` with exploration notes
2. Scope decomposer extracts features, analyzes dependencies, presents decomposition
3. On approval: dispatches `fg-090-sprint-orchestrator` with feature list
4. The current orchestrator instance stops — sprint orchestrator takes over with per-feature fg-100 instances

**State:** `story_state` set to `DECOMPOSED`. Decomposition details stored in `state.json.decomposition`.

**Note:** This transition only occurs in standard mode. Bugfix, migration, and bootstrap modes skip the scope check.
```

- [ ] **Step 3: Add `DECOMPOSED` to the story_state list in the Stage Overview table**

Update the stage overview to note this as a possible transition from Stage 1.

- [ ] **Step 4: Commit**

```bash
git add shared/stage-contract.md
git commit -m "feat: document auto-decomposition escalation path in stage contract"
```

---

## Task 8: Compress Tier 1 Agent Descriptions (5 entry-point agents)

**Files:**
- Modify: `agents/fg-100-orchestrator.md` (lines 3-18)
- Modify: `agents/fg-090-sprint-orchestrator.md` (lines 3-22)
- Modify: `agents/fg-010-shaper.md` (lines 3-16)
- Modify: `agents/fg-020-bug-investigator.md` (lines 3-10)
- Modify: `agents/fg-050-project-bootstrapper.md` (lines 3-29)

Strategy: Keep description + 1 compressed example. Remove extra examples and commentary blocks.

- [ ] **Step 1: Compress fg-100-orchestrator description**

Replace the description field (keep everything else in frontmatter unchanged):

```yaml
description: |
  Autonomous pipeline orchestrator — coordinates the 10-stage development lifecycle.
  Reads forge.local.md for config. Dispatches fg-* agents per stage. Manages .forge/ state for recovery.

  <example>
  Context: Developer wants to implement a feature
  user: "Implement plan comment feature"
  assistant: "I'll dispatch the pipeline orchestrator to handle the full development lifecycle."
  </example>
```

- [ ] **Step 2: Compress fg-090-sprint-orchestrator description**

Replace the description field:

```yaml
description: |
  Sprint-level orchestrator — decomposes a sprint into independent features and dispatches parallel fg-100 pipeline instances. Supports Linear cycles and manual feature lists.

  <example>
  Context: User provides manual feature list
  user: "/forge-run --parallel 'Add user avatars' 'Fix checkout flow' 'Add export CSV'"
  assistant: "I'll dispatch the sprint orchestrator to analyze these 3 features for independence and execute them in parallel where safe."
  </example>
```

- [ ] **Step 3: Compress fg-010-shaper description**

Replace the description field:

```yaml
description: |
  Interactive feature shaping agent — refines vague requirements into structured specs with epics, stories, and acceptance criteria.

  <example>
  Context: User has a vague idea for a feature
  user: "/forge-shape I want users to share their plans"
  assistant: "I'll dispatch the shaper to collaboratively refine this into a structured spec with stories and acceptance criteria."
  </example>
```

- [ ] **Step 4: fg-020-bug-investigator description — already compact**

This agent already has only 1 example. Just trim the description slightly:

```yaml
description: |
  Bug investigation and reproduction agent — pulls context from ticket sources, explores fault area, attempts automated reproduction via failing test. Dispatched at Stage 1-2 in bugfix mode.

  <example>
  Context: User reports a bug
  user: "/forge-fix Users get 404 on group endpoint"
  assistant: "I'll dispatch the bug investigator to trace the error and write a failing test."
  </example>
```

- [ ] **Step 5: Compress fg-050-project-bootstrapper description**

Replace the description field (remove 2 of 3 examples, remove commentary):

```yaml
description: |
  Scaffolds new projects with production-grade structure, architecture patterns, CI/CD, and tooling. Supports Gradle, Maven, npm/bun, Cargo, Go modules, and more.

  <example>
  Context: Developer wants to start a new microservice from scratch
  user: "bootstrap: Kotlin Spring Boot REST API with PostgreSQL"
  assistant: "I'll scaffold a Kotlin Spring Boot project with hexagonal architecture, Gradle composite builds, Flyway migrations, and Docker support."
  </example>
```

- [ ] **Step 6: Run validation**

```bash
./tests/validate-plugin.sh
```

Expected: All 51 checks pass (agent name matches filename, frontmatter structure valid).

- [ ] **Step 7: Commit**

```bash
git add agents/fg-100-orchestrator.md agents/fg-090-sprint-orchestrator.md agents/fg-010-shaper.md agents/fg-020-bug-investigator.md agents/fg-050-project-bootstrapper.md
git commit -m "chore: compress Tier 1 agent descriptions (entry-point agents, keep 1 example)"
```

---

## Task 9: Compress Tier 2 Agent Descriptions (10 review agents)

**Files:**
- Modify: `agents/architecture-reviewer.md`
- Modify: `agents/security-reviewer.md`
- Modify: `agents/frontend-reviewer.md`
- Modify: `agents/frontend-design-reviewer.md`
- Modify: `agents/frontend-a11y-reviewer.md`
- Modify: `agents/frontend-performance-reviewer.md`
- Modify: `agents/backend-performance-reviewer.md`
- Modify: `agents/version-compat-reviewer.md`
- Modify: `agents/infra-deploy-reviewer.md`
- Modify: `agents/docs-consistency-reviewer.md`

Strategy: Single-line description, no examples. These are dispatched by fg-400-quality-gate by explicit name.

- [ ] **Step 1: Compress all 10 reviewer descriptions**

Replace each agent's description field with a single line (no pipe `|`, no examples):

**architecture-reviewer.md:**
```yaml
description: Reviews code for architecture pattern compliance (hexagonal, clean, layered, MVC, microservices, modular monolith).
```

**security-reviewer.md:**
```yaml
description: Reviews code for security vulnerabilities — OWASP Top 10, auth gaps, injection, secrets exposure, dependency CVEs.
```

**frontend-reviewer.md:**
```yaml
description: Reviews frontend code for conventions, accessibility, and framework-specific patterns across React, Svelte, Vue, Angular.
```

**frontend-design-reviewer.md:**
```yaml
description: Evaluates frontend for design quality, design system compliance, visual coherence, responsive behavior, and dark mode.
```

**frontend-a11y-reviewer.md:**
```yaml
description: Performs deep WCAG 2.2 AA accessibility audits — contrast, ARIA, keyboard nav, focus management, touch targets.
```

**frontend-performance-reviewer.md:**
```yaml
description: Reviews frontend code for performance issues — bundle size, rendering efficiency, lazy loading, resource optimization.
```

**backend-performance-reviewer.md:**
```yaml
description: Reviews backend code for performance issues — N+1 queries, missing indexes, connection pools, caching, concurrency.
```

**version-compat-reviewer.md:**
```yaml
description: Analyzes dependency tree for version conflicts, language feature compatibility, and runtime API removals.
```

**infra-deploy-reviewer.md:**
```yaml
description: Reviews Helm charts, K8s manifests, Terraform, and Dockerfiles for security, reliability, and observability.
```

**docs-consistency-reviewer.md:**
```yaml
description: Reviews code for consistency with documented decisions, constraints, and existing documentation. Reports DOC-* findings.
```

- [ ] **Step 2: Run validation**

```bash
./tests/validate-plugin.sh
```

Expected: All 51 checks pass.

- [ ] **Step 3: Commit**

```bash
git add agents/architecture-reviewer.md agents/security-reviewer.md agents/frontend-reviewer.md agents/frontend-design-reviewer.md agents/frontend-a11y-reviewer.md agents/frontend-performance-reviewer.md agents/backend-performance-reviewer.md agents/version-compat-reviewer.md agents/infra-deploy-reviewer.md agents/docs-consistency-reviewer.md
git commit -m "chore: compress Tier 2 agent descriptions (reviewers, single-line, no examples)"
```

---

## Task 10: Compress Tier 3 Agent Descriptions (22 internal agents)

**Files:**
- Modify all 22 internal pipeline agent files

Strategy: Minimal single-line description, no examples. These are only dispatched by the orchestrator or other coordinator agents by explicit name.

- [ ] **Step 1: Compress all 22 internal agent descriptions**

Replace each agent's description field:

**fg-101-worktree-manager.md:**
```yaml
description: Manages git worktree lifecycle — creation, cleanup, branch naming, and stale detection.
```

**fg-102-conflict-resolver.md:**
```yaml
description: Analyzes file and symbol-level conflicts between tasks or features. Produces parallel groups and serial chains.
```

**fg-103-cross-repo-coordinator.md:**
```yaml
description: Coordinates cross-repo operations — worktree creation, lock ordering, PR linking, and timeout management.
```

**fg-130-docs-discoverer.md:**
```yaml
description: Discovers, classifies, and indexes project documentation into the knowledge graph or fallback JSON index.
```

**fg-140-deprecation-refresh.md:**
```yaml
description: Refreshes known-deprecations JSON files by querying context7 and package registries for newly deprecated APIs.
```

**fg-150-test-bootstrapper.md:**
```yaml
description: Generates baseline test suites for undertested codebases. Prioritizes by risk, generates in batches.
```

**fg-160-migration-planner.md:**
```yaml
description: Plans and orchestrates multi-phase library migrations and major upgrades with per-batch rollback.
```

**fg-200-planner.md:**
```yaml
description: Decomposes a requirement into a risk-assessed implementation plan with stories, tasks, and parallel groups.
```

**fg-210-validator.md:**
```yaml
description: Validates implementation plans across 7 perspectives. Produces GO/REVISE/NO-GO verdict.
```

**fg-250-contract-validator.md:**
```yaml
description: Detects breaking changes in shared API contracts (OpenAPI, Protobuf, GraphQL) between producer and consumer repos.
```

**fg-300-implementer.md:**
```yaml
description: TDD implementation agent — writes tests first (RED), implements to pass (GREEN), refactors.
```

**fg-310-scaffolder.md:**
```yaml
description: Generates boilerplate files with correct structure, types, imports, and TODO markers. Never implements business logic.
```

**fg-320-frontend-polisher.md:**
```yaml
description: Creative visual polish agent — animations, micro-interactions, spatial composition, depth, responsive polish, dark mode.
```

**fg-350-docs-generator.md:**
```yaml
description: Generates and updates project documentation — README, architecture, ADRs, API specs, onboarding, changelogs, diagrams.
```

**fg-400-quality-gate.md:**
```yaml
description: Multi-batch quality coordinator — dispatches reviewers, deduplicates findings, scores, determines GO/CONCERNS/FAIL verdict.
```

**fg-500-test-gate.md:**
```yaml
description: Test execution and analysis coordinator — runs test suite, dispatches coverage and quality analysis agents.
```

**fg-600-pr-builder.md:**
```yaml
description: Creates feature branch, stages logical commits, opens PR with quality gate results. No AI attribution.
```

**fg-650-preview-validator.md:**
```yaml
description: Validates preview environments after PR creation — smoke tests, Lighthouse, visual regression, Playwright E2E.
```

**fg-700-retrospective.md:**
```yaml
description: Post-pipeline learning agent — extracts PREEMPT/PATTERN/TUNING learnings, auto-tunes config, tracks trends.
```

**fg-710-feedback-capture.md:**
```yaml
description: Records user corrections and rejections as structured feedback. Proposes convention rules after 3+ similar corrections.
```

**fg-720-recap.md:**
```yaml
description: Creates a human-readable markdown recap of the pipeline run for PR descriptions and team updates.
```

**infra-deploy-verifier.md:**
```yaml
description: Verifies infrastructure deployments — static validation, container builds, optional local cluster tests.
```

- [ ] **Step 2: Run validation**

```bash
./tests/validate-plugin.sh
```

Expected: All 51 checks pass.

- [ ] **Step 3: Commit**

```bash
git add agents/fg-101-worktree-manager.md agents/fg-102-conflict-resolver.md agents/fg-103-cross-repo-coordinator.md agents/fg-130-docs-discoverer.md agents/fg-140-deprecation-refresh.md agents/fg-150-test-bootstrapper.md agents/fg-160-migration-planner.md agents/fg-200-planner.md agents/fg-210-validator.md agents/fg-250-contract-validator.md agents/fg-300-implementer.md agents/fg-310-scaffolder.md agents/fg-320-frontend-polisher.md agents/fg-350-docs-generator.md agents/fg-400-quality-gate.md agents/fg-500-test-gate.md agents/fg-600-pr-builder.md agents/fg-650-preview-validator.md agents/fg-700-retrospective.md agents/fg-710-feedback-capture.md agents/fg-720-recap.md agents/infra-deploy-verifier.md
git commit -m "chore: compress Tier 3 agent descriptions (internal agents, minimal single-line)"
```

---

## Task 11: Update `CLAUDE.md`

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add fg-015-scope-decomposer to agent list**

In the "Agents (37 total)" section, update count to 38 and add fg-015 to Pre-pipeline agents:

```markdown
### Agents (38 total, in `agents/*.md`)

**Pipeline agents** (`fg-{NNN}-{role}` naming):
- Pre-pipeline: `fg-010-shaper`, `fg-015-scope-decomposer`, `fg-020-bug-investigator`, `fg-050-project-bootstrapper`
```

- [ ] **Step 2: Add fg-015 to agent UI tier list**

Add to Tier 1:
```markdown
- Agent UI tiers: Tier 1 (tasks+ask+plan_mode): shaper, scope-decomposer, planner, migration planner, bootstrapper, sprint orchestrator.
```

- [ ] **Step 3: Add intent classification and routing documentation**

In the "Key entry points" table, add:

```markdown
| Intent classification | `shared/intent-classification.md` (routing rules, signal definitions)   |
```

In the "Key conventions" section, add under "Skills":

```markdown
- **Universal routing:** `/forge-run` auto-classifies intent (bugfix/migration/bootstrap/multi-feature/vague/standard) and routes to the correct agent. Explicit prefixes and flags override classification. Config: `routing.auto_classify`, `routing.vague_threshold` in `forge-config.md`. See `shared/intent-classification.md`.
- **Auto-decomposition:** Multi-feature requirements detected via fast scan (text analysis) or deep scan (post-EXPLORE domain analysis). Triggers `fg-015-scope-decomposer` → `fg-090-sprint-orchestrator`. Config: `scope.auto_decompose`, `scope.decomposition_threshold`, `scope.fast_scan` in `forge-config.md`.
- **Visual design preview:** Frontend features optionally present design alternatives via superpowers visual companion during PLAN stage. Config: `frontend_preview.enabled`, `frontend_preview.auto_open_browser`, `frontend_preview.keep_alive_for_polish` in `forge.local.md`.
```

- [ ] **Step 4: Add description tiering note**

In the "Agent file rules" section, add:

```markdown
- **Description tiering:** Agent descriptions use a three-tier compression strategy to minimize system prompt token usage (~1k vs ~15.4k). Tier 1 (entry-point, 5 agents): short description + 1 example. Tier 2 (reviewers, 10 agents): single-line, no examples. Tier 3 (internal, 23 agents): minimal single-line, no examples. Full agent capability is in the `.md` body (loaded at dispatch time), not the description.
```

- [ ] **Step 5: Update state schema version reference**

Update any references to state schema version from 1.2.0 to 1.3.0.

- [ ] **Step 6: Add new PREFLIGHT constraints**

In the "PREFLIGHT constraints" section, add:

```markdown
- Scope: `scope.decomposition_threshold` 2-10 (default: 3). Routing: `routing.vague_threshold` low/medium/high (default: medium).
```

- [ ] **Step 7: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for fg-015, universal routing, visual preview, description tiering"
```

---

## Task 12: Run Full Validation

**Files:** None (read-only verification)

- [ ] **Step 1: Run structural validation**

```bash
./tests/validate-plugin.sh
```

Expected: All checks pass. Specifically verify:
- Agent count now 38 (37 existing + fg-015)
- All agent `name` fields match filenames
- All frontmatter is valid YAML
- No broken references

- [ ] **Step 2: Run full test suite**

```bash
./tests/run-all.sh
```

Expected: All tests pass. If any MIN_* guards fail due to the new agent, update `tests/lib/module-lists.bash` accordingly.

- [ ] **Step 3: Verify agent description token reduction**

Quick manual check — count total words across all agent descriptions:

```bash
for f in agents/*.md; do awk '/^---$/{c++} c==1{print} c==2{exit}' "$f" | grep -A100 'description:' | grep -v 'model:\|color:\|tools:\|ui:\|---' | head -20; done | wc -w
```

Expected: ~300-400 words total (down from ~3,000+).

- [ ] **Step 4: Commit any fixes**

If validation caught issues, fix and commit:

```bash
git add -A
git commit -m "fix: address validation findings after universal routing and token reduction"
```
