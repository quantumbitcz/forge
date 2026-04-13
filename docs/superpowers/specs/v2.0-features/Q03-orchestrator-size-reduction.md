# Q03: Orchestrator Size Reduction via Modular Stage Instructions

## Status
DEFERRED — 2026-04-13

**Reason:** User has established that the orchestrator size is acceptable (loads once per run, not per stage). The token cost analysis in this spec conflates context window presence with per-call billing — Claude's prompt caching means the system prompt is cached after the first call, reducing the incremental cost significantly. Additionally, splitting the orchestrator risks behavioral regression since LLMs treat system prompt instructions with higher priority than mid-conversation Read output. This spec is retained for future evaluation if prompt caching economics change, but is NOT scheduled for implementation in v2.0.

**If revisited:** The modular approach is sound architecturally. The key risk is LLM behavioral regression — instructions read via the Read tool during a conversation may carry less weight than system prompt instructions. Any future implementation must include A/B testing against the monolithic orchestrator to verify no quality degradation.

## Problem Statement

`agents/fg-100-orchestrator.md` is 2,365 lines. Because this file IS the system prompt for the orchestrator agent, every line is sent with every API call the orchestrator makes. A typical pipeline run involves 50-100+ tool calls (agent dispatches, state writes, bash commands). That means the full 2,365-line system prompt is transmitted 50-100+ times per run.

**The "loads once per run" counterargument:** The user has previously stated that "fg-100-orchestrator size is fine; loads once per run, not per stage." This is true in the sense that Claude Code loads the agent .md once to initialize the subagent conversation. However, the system prompt is included in the context window for every subsequent API call within that conversation. The context window grows with each turn, and the system prompt is always present at the start. With Claude's pricing model, this means the system prompt tokens are billed on every input. For a run with 80 tool calls at ~6,000 tokens per system prompt, that is ~480,000 input tokens just for the system prompt across the run.

**Current structure analysis:**

| Section | Lines | Line Range | Used When |
|---------|-------|-----------|-----------|
| Frontmatter + Identity (ss1-3) | 77 | 1-77 | Every turn |
| Dispatch Protocol (ss4) | 77 | 79-155 | Every dispatch |
| Argument Parsing (ss5) | 65 | 156-220 | First turn only |
| State Management (ss6) | 66 | 221-286 | State transitions |
| Context Management (ss7) | 61 | 287-347 | Context operations |
| Decision Framework (ss8) | 30 | 348-377 | Decision points |
| Mode Resolution (ss9) | 23 | 378-400 | First turn only |
| Reference Documents (ss10) | 19 | 401-419 | Lookup only |
| Stage 0: PREFLIGHT | 692 | 420-1111 | PREFLIGHT only |
| PREFLIGHT Completion | 13 | 1112-1124 | PREFLIGHT only |
| Stage 1: EXPLORE | 114 | 1125-1238 | EXPLORE only |
| Stage 2: PLAN | 148 | 1239-1386 | PLAN only |
| Stage 3: VALIDATE | 133 | 1387-1519 | VALIDATE only |
| Stage 4: IMPLEMENT | 182 | 1520-1701 | IMPLEMENT only |
| Stage 5: VERIFY | 88 | 1702-1789 | VERIFY only |
| Stage 6: REVIEW | 146 | 1790-1935 | REVIEW only |
| Stage 7: DOCS + Pre-Ship | 115 | 1936-2049 | DOCS/SHIP only |
| Stage 8: SHIP | 163 | 2050-2211 | SHIP only |
| Stage 9: LEARN | 154 | 2212-2365 | LEARN only |

**Key insight:** Sections ss1-ss4 (Identity, Forbidden Actions, Principles, Dispatch Protocol) = ~155 lines are used on virtually every turn. Sections ss5-ss10 (Argument Parsing, State Management, etc.) = ~264 lines are used at specific moments. The 10 stage sections = ~1,948 lines are each used only during their respective stage. At any given point in the pipeline, only ONE stage section is active — the other 9 are dead weight in the context.

## Target

Reduce orchestrator effective token cost by ~60% per run while maintaining identical pipeline behavior.

## Detailed Changes

### 1. Modular Orchestrator Architecture

Split the monolithic orchestrator into a core file and stage-specific instruction files:

```
agents/
  fg-100-orchestrator.md              # Core: ~800 lines (ss1-ss10 + stage dispatch stubs)

shared/orchestrator/
  stage-0-preflight.md                # 692 lines (Stage 0 instructions)
  stage-1-explore.md                  # 114 lines
  stage-2-plan.md                     # 148 lines
  stage-3-validate.md                 # 133 lines
  stage-4-implement.md                # 182 lines
  stage-5-verify.md                   # 88 lines
  stage-6-review.md                   # 146 lines
  stage-7-docs-preship.md             # 115 lines
  stage-8-ship.md                     # 163 lines
  stage-9-learn.md                    # 154 lines
```

### 2. Core Orchestrator Content (~800 lines)

The core file retains:
- **Frontmatter** (19 lines)
- **ss1 Identity & Purpose** (12 lines)
- **ss2 Forbidden Actions** (29 lines)
- **ss3 Pipeline Principles** (6 lines)
- **ss4 Dispatch Protocol** (77 lines) — used every dispatch
- **ss5 Argument Parsing** (65 lines) — used at start but referenced for --from
- **ss6 State Management** (66 lines) — used at every transition
- **ss7 Context Management** (61 lines) — used for context operations
- **ss8 Decision Framework** (30 lines) — used at decision points
- **ss9 Mode Resolution** (23 lines) — used at start, referenced for mode checks
- **ss10 Reference Documents** (19 lines) — lookup table
- **Stage dispatch stubs** (~40 lines) — one paragraph per stage explaining: "Read `shared/orchestrator/stage-N-{name}.md` for detailed instructions, then execute."

Total core: ~447 lines of current content + ~40 lines of stage stubs = ~487 lines. Round up to ~500-550 with formatting.

However, to be conservative and avoid behavioral regressions, we should also keep:
- **PREFLIGHT Completion** transition logic (13 lines) — this is a critical state transition
- **Stage transition guards** — the first ~5 lines of each stage that handle state transitions

Conservative core estimate: **~650-800 lines**.

### 3. Stage Instruction Files

Each file in `shared/orchestrator/` contains the detailed instructions for one stage. Format:

```markdown
# Stage N: STAGE_NAME — Detailed Instructions

> This file is read by fg-100-orchestrator when entering STAGE_NAME.
> It is not a standalone agent — it extends the orchestrator's context for this stage.

[Full stage instructions, exactly as they exist today in the monolithic file]
```

The orchestrator reads the relevant file with the Read tool when entering each stage:

```
When entering Stage 0 (PREFLIGHT):
  1. Read shared/orchestrator/stage-0-preflight.md
  2. Execute the instructions from that file
  3. On stage completion, the file contents leave the active context naturally
```

### 4. Token Savings Calculation

**Current cost per run (monolithic):**
- System prompt: ~2,365 lines ~= 6,000 tokens
- Typical tool calls per run: ~80
- System prompt sent with each: 6,000 x 80 = 480,000 input tokens just for system prompt

**Proposed cost per run (modular):**
- Core system prompt: ~700 lines ~= 1,800 tokens
- Core sent with each tool call: 1,800 x 80 = 144,000 input tokens for system prompt
- Stage files read on-demand: ~200 lines avg = ~500 tokens per stage
- Stage files in conversation context: ~500 tokens x ~10 tool calls per stage x 10 stages = 50,000 tokens
- But stage file context accumulates — later stages have earlier stage files in history

**Realistic savings model:**
- The Read tool adds the stage file content to the conversation history. It does NOT leave the context.
- After reading all 10 stage files across a full run, the conversation history will contain all ~1,948 lines of stage content.
- However, the savings come from the EARLY stages: during PREFLIGHT (which dominates tool calls), only stage-0's content is in context, not stages 1-9.
- A typical run's tool call distribution is heavily front-loaded: PREFLIGHT ~20 calls, IMPLEMENT ~15, VERIFY/REVIEW ~15, other stages ~5 each.

**Conservative savings estimate:**
- PREFLIGHT (20 calls): saves (6,000 - 1,800 - 500) x 20 = 74,000 tokens (only stage-0 loaded)
- EXPLORE (5 calls): saves (6,000 - 1,800 - 1,000) x 5 = 16,000 tokens (stages 0-1 loaded)
- PLAN (8 calls): saves (6,000 - 1,800 - 1,500) x 8 = 21,600 tokens
- Later stages: diminishing savings as conversation history grows
- **Total estimated savings: ~35-45% of system-prompt token cost**

This is less than the ideal 60% because conversation history accumulates. But it is still significant: ~150,000-200,000 fewer input tokens per run.

### 5. On-Demand Read Pattern

Add this dispatcher to the core orchestrator, replacing each stage's full content:

```markdown
## Stage Execution Pattern

When the state machine transitions to a new stage:

1. **Read stage instructions:** `Read shared/orchestrator/stage-{N}-{name}.md`
2. **Execute:** Follow the instructions from the read file
3. **Transition:** Use the state machine to move to the next stage
4. **Do NOT re-read** the same stage file if still in that stage — the content is in your conversation history

### Stage Dispatch Map

| State | Stage File | Description |
|-------|-----------|-------------|
| PREFLIGHT | `shared/orchestrator/stage-0-preflight.md` | Config, conventions, worktree, integrations |
| EXPLORING | `shared/orchestrator/stage-1-explore.md` | Codebase analysis, explore cache |
| PLANNING | `shared/orchestrator/stage-2-plan.md` | Plan creation, Linear sync |
| VALIDATING | `shared/orchestrator/stage-3-validate.md` | Plan validation, challenge brief |
| IMPLEMENTING | `shared/orchestrator/stage-4-implement.md` | TDD implementation, scaffolding |
| VERIFYING | `shared/orchestrator/stage-5-verify.md` | Build, test, quality checks |
| REVIEWING | `shared/orchestrator/stage-6-review.md` | Review batches, convergence |
| DOCUMENTING | `shared/orchestrator/stage-7-docs-preship.md` | Documentation, pre-ship verification |
| SHIPPING | `shared/orchestrator/stage-8-ship.md` | PR creation, preview, feedback |
| LEARNING | `shared/orchestrator/stage-9-learn.md` | Retrospective, cleanup, report |
```

### 6. Migration Path

1. **Phase 1 — Create stage files:** Extract stage content into `shared/orchestrator/stage-*.md`. The monolithic file remains unchanged. Both exist in parallel.
2. **Phase 2 — Add dispatch stubs:** Add the stage dispatch map to the core orchestrator. The monolithic file still has full content (stubs are additive).
3. **Phase 3 — Remove stage content from core:** Remove the detailed stage instructions from the monolithic file, leaving only the dispatch stubs. This is the breaking change.
4. **Phase 4 — Validate:** Run all orchestrator-related tests. Run a dry-run pipeline to verify stage instructions load correctly.

### 7. Fallback Plan

If the modular approach causes behavioral regressions (agents not following stage instructions because they were read mid-conversation rather than in the system prompt):

1. **Quick revert:** Restore the monolithic file from git history (`git checkout HEAD~1 -- agents/fg-100-orchestrator.md`)
2. **Stage files preserved:** The `shared/orchestrator/` files remain useful as documentation even if not used at runtime
3. **Hybrid approach:** Keep the most critical stage (PREFLIGHT, 692 lines) in the core and only externalize smaller stages

### 8. Addressing the "Loads Once" Argument

To be transparent: the user's prior feedback that "orchestrator size is fine" is a valid perspective. The orchestrator loads once per run as a subagent. The question is whether the 2,365-line system prompt being in every API call's context is a material cost concern.

**Arguments for splitting:**
- ~150,000-200,000 fewer input tokens per run (conservative estimate)
- At Claude's pricing, this is $0.45-0.60 savings per run (Opus at $15/M input)
- Over 100 runs, that is $45-60 of pure token waste
- Faster API responses (smaller context = faster processing)
- Better separation of concerns (stage logic is independently reviewable)

**Arguments against splitting:**
- Additional complexity (10 new files to maintain)
- Read tool calls add latency (~100ms per Read)
- Risk of behavioral regression if the LLM treats Read content differently than system prompt
- The user has explicitly stated the current size is acceptable

**Recommendation:** Proceed with the split but treat Phase 3 (removing content from core) as gated on successful dry-run validation. If the dry-run shows behavioral differences, stop at Phase 2 (where both monolithic and modular coexist).

## Testing Approach

1. **Structural tests:** New `tests/contract/orchestrator-modular.bats`:
   - All 10 stage files exist in `shared/orchestrator/`
   - Core orchestrator references all 10 stage files
   - Stage files contain expected section headers
   - No stage content duplicated between core and stage files
   - Combined line count of stage files matches original stage content (~1,948 lines +/- 10%)

2. **Existing tests:** All tests in `tests/contract/orchestrator-state-machine.bats` must pass unchanged. State machine logic stays in the core.

3. **Dry-run validation:** Run `forge-run --dry-run "Test requirement"` and verify state transitions match the monolithic orchestrator's behavior.

## Acceptance Criteria

- [ ] Core orchestrator reduced to ~650-800 lines (from 2,365)
- [ ] 10 stage instruction files created in `shared/orchestrator/`
- [ ] Stage dispatch map in core orchestrator references all 10 files
- [ ] All existing orchestrator tests pass unchanged
- [ ] New structural tests validate modular consistency
- [ ] Dry-run pipeline produces identical state transitions
- [ ] Fallback to monolithic file documented and achievable in one git command
- [ ] CLAUDE.md updated with new file paths for stage instructions

## Effort Estimate

**M** (Medium) — Mechanical extraction (copy-paste into files), stub creation, test writing. The content does not change, only its location. Estimated: 3-4 hours.

## Dependencies

- None. This is an internal refactoring with no external API changes.
- Should be done AFTER Q01 and Q02 to avoid merge conflicts with agent description changes.
- The `shared/orchestrator/` directory must be added to CLAUDE.md's key entry points table.
