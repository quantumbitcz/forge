# Q02: Agent Quality Improvements

## Status
DRAFT — 2026-04-13

## Problem Statement

Agents scored A- (90/100) in the system review. While this is solid overall, six specific problems drag the score down:

1. **6 agents with vague dispatch descriptions:** fg-130, fg-140, fg-150, fg-350, fg-505, fg-650 have descriptions that lack specificity about when they are dispatched. The orchestrator dispatches these agents, so their descriptions must clearly state the dispatch trigger for the LLM to select them reliably.
2. **13 agents with poor/missing error recovery:** Several agents produce messages like "Discovery failed" with no context about what failed, why, or what the user/orchestrator should do. Low error-mention counts correlate with poor failure experience: fg-015 (0 mentions), fg-010 (2), fg-320 (1), fg-412 (1), fg-416 (0), fg-419 (1), fg-420 (1).
3. **Review agents reference agent-defaults.md but do not inline critical constraints:** All 9 review agents reference `shared/agent-defaults.md` (2-3 times each) but require a Read tool call at runtime to access it. The critical output format and token constraints should be inlined.
4. **2 agents missing `model` field:** fg-050-project-bootstrapper and fg-150-test-bootstrapper both have `model: inherit` but this was initially flagged as missing. Verified: they DO have `model: inherit`. This issue is resolved.
5. **Coordinator output is Markdown prose:** fg-400 (quality gate) and fg-500 (test gate) return structured-looking Markdown that the retrospective (fg-700) must parse with custom logic. A machine-parseable JSON block alongside the Markdown would improve reliability.
6. **No tool availability pre-check:** Agents using optional tools (LSP, Context7, Playwright, Neo4j) attempt to use them and fail at runtime rather than checking availability first and adjusting behavior.

## Target

Agents A- (90) --> A+ (97+)

## Detailed Changes

### 1. Vague Description Fixes (6 agents)

Each description must include "Dispatched when..." or "Dispatched by..." trigger language and a concrete scenario.

#### fg-130-docs-discoverer

**Current:**
```
Discovers, classifies, and indexes project documentation into the knowledge graph or fallback JSON index.
```

**Proposed:**
```
Discovers, classifies, and indexes project documentation into the knowledge graph or fallback JSON index. Dispatched by the orchestrator at PREFLIGHT to build the docs index before planning begins. Use to map README, ADR, API spec, and wiki locations.
```

#### fg-140-deprecation-refresh

**Current:**
```
Refreshes known-deprecations JSON files by querying context7 and package registries for newly deprecated APIs.
```

**Proposed:**
```
Refreshes known-deprecations JSON files by querying Context7 and package registries for newly deprecated APIs. Dispatched by the orchestrator at PREFLIGHT when Context7 MCP is available. Skipped gracefully when Context7 is unavailable.
```

#### fg-150-test-bootstrapper

**Current:**
```
Generates baseline test suites for undertested codebases. Prioritizes by risk, generates in batches.
```

**Proposed:**
```
Generates baseline test suites for undertested codebases. Dispatched by the orchestrator at PREFLIGHT when test coverage is below the configured threshold. Prioritizes by risk (recently changed, high-complexity, public API surface), generates in batches.
```

#### fg-350-docs-generator

**Current:**
```
Generates and updates project documentation — README, architecture, ADRs, API specs, onboarding, changelogs, diagrams.
```

**Proposed:**
```
Generates and updates project documentation — README, architecture, ADRs, API specs, onboarding, changelogs, diagrams. Dispatched by the orchestrator at Stage 7 (DOCUMENTING) after implementation and review are complete. Also invoked by /docs-generate skill for on-demand generation.
```

#### fg-505-build-verifier

**Current:**
```
Verifies build and lint pass. Analyzes errors, applies fixes, re-runs. Returns PASS or escalation context.
```

**Proposed:**
```
Verifies build and lint pass after implementation changes. Dispatched by fg-500-test-gate or the orchestrator at Stage 5 (VERIFY) when build or lint commands fail. Analyzes errors, applies targeted fixes, re-runs. Returns PASS verdict or escalation context with structured error details.
```

#### fg-650-preview-validator

**Current:**
```
Validates preview environments after PR creation — smoke tests, Lighthouse, visual regression, Playwright E2E.
```

**Proposed:**
```
Validates preview environments after PR creation. Dispatched by the orchestrator at Stage 8 (SHIP) when preview.enabled is true and a preview URL is available. Runs smoke tests, Lighthouse audits, visual regression, and Playwright E2E against the deployed preview.
```

### 2. Error Message Improvements (13 agents)

Add structured error handling to agents with zero or minimal error coverage. Each agent must have:
- A "## Error Handling" or "## Failure Modes" section
- Specific error messages that include: what failed, why it likely failed, what the orchestrator should do

#### Agents requiring error handling additions:

| Agent | Lines | Error Mentions | Required Changes |
|-------|-------|---------------|-----------------|
| `fg-015-scope-decomposer` | 197 | 0 | Add failure mode: requirement unparseable, decomposition produces 0 stories, decomposition exceeds sprint capacity. Return structured error to orchestrator. |
| `fg-010-shaper` | 378 | 2 | Add failure mode: user provides empty input, shaping session times out, user rejects all shaped specs. |
| `fg-130-docs-discoverer` | 467 | 4 | Replace generic "Discovery failed" with: "Documentation discovery failed: {reason}. Searched {N} directories. {N} files matched but {N} were unreadable. The docs index will be empty — planning proceeds without documentation context." |
| `fg-135-wiki-generator` | 238 | 5 | Add failure mode: codebase too large to analyze within token budget, wiki directory write fails. |
| `fg-140-deprecation-refresh` | 266 | 5 | Add failure mode: Context7 unavailable (graceful skip), all registries unreachable, JSON write fails. |
| `fg-200-planner` | 483 | 4 | Add failure mode: requirement too vague after explore (redirect to shaper), plan exceeds iteration budget, challenge brief missing. |
| `fg-250-contract-validator` | 286 | 4 | Add failure mode: no contracts found, contract format unrecognized, validation tool unavailable. |
| `fg-320-frontend-polisher` | 216 | 1 | Add failure modes: no frontend files in scope, design tokens missing, visual verification unavailable. Report as INFO findings rather than hard failures. |
| `fg-350-docs-generator` | 307 | 4 | Add failure mode: no documentation config, target directory not writable, doc type unsupported. |
| `fg-412-architecture-reviewer` | 157 | 1 | Add failure mode: codebase too small for architecture review (report 0 findings, not error), module boundaries undetectable. |
| `fg-416-backend-performance-reviewer` | 100 | 0 | Add failure mode: no backend code in scope (skip with INFO), profiling data unavailable, benchmark baseline missing. |
| `fg-419-infra-deploy-reviewer` | 144 | 1 | Add failure mode: no infrastructure files in scope (skip with INFO), Docker unavailable, k8s config unreadable. |
| `fg-420-dependency-reviewer` | 172 | 1 | Add failure mode: no dependency manifests found (skip with INFO), registry unreachable, advisory database unavailable. |

#### Error message template for all agents:

```markdown
## Failure Modes

| Condition | Severity | Response |
|-----------|----------|----------|
| [Specific condition] | ERROR | Report to orchestrator: "[Agent ID]: [What failed] — [Why] — [Suggested action]" |
| [Scope empty] | INFO | Report: "[Agent ID]: No files in scope for [review type]. Skipping with 0 findings." |
| [Optional tool unavailable] | INFO | Report: "[Agent ID]: [Tool] unavailable. Running in degraded mode — [what is skipped]." |
```

### 3. Inline Critical agent-defaults.md Sections into Review Agents

The 9 review agents (fg-410 through fg-420) reference `shared/agent-defaults.md` for output format and constraints. Instead of requiring a Read tool call, inline these two critical sections directly into each reviewer:

#### Sections to inline:

**Output format block** (from `shared/checks/output-format.md`, referenced by agent-defaults):
```
file:line | CATEGORY-ID | SEVERITY | description | suggested_fix
```

**Token constraints:**
```
- Output: max 2,000 tokens
- Dispatch prompt: max 2,000 tokens
- Findings: max 50 per reviewer invocation
```

**Which agents get the inline:** All 9 review agents:
- `fg-410-code-reviewer`
- `fg-411-security-reviewer`
- `fg-412-architecture-reviewer`
- `fg-413-frontend-reviewer`
- `fg-416-backend-performance-reviewer`
- `fg-417-version-compat-reviewer`
- `fg-418-docs-consistency-reviewer`
- `fg-419-infra-deploy-reviewer`
- `fg-420-dependency-reviewer`

**Token cost analysis:** Adding ~10 lines to each of 9 agents = ~90 lines total. These agents are dispatched as subagents (their .md is the system prompt), so these 10 lines are sent once per dispatch. This replaces a Read tool call that would fetch the entire agent-defaults.md (larger). Net token savings: positive.

**Keep the reference:** Retain the reference to `shared/agent-defaults.md` for completeness, but mark it as "See agent-defaults.md for full constraints. Critical constraints inlined below for efficiency."

### 4. Structured Output for Coordinators

**DEFERRED TO Q10.** The full structured output design for coordinators (fg-400, fg-500, fg-700) is specified in Q10-coordinator-structured-output.md using the `<!-- FORGE_STRUCTURED_OUTPUT -->` standard. Q02 does NOT define its own format — Q10 is the single source of truth for this concern. Q02's scope is limited to items 1-3 (descriptions, error messages, reviewer inlines) and item 5 (tool pre-check pattern).

### 5. Tool Availability Pre-Check Pattern

Define a standard pre-check pattern for agents using optional tools. Add to `shared/agent-defaults.md` as a new section:

#### Pattern:

```markdown
## Optional Tool Pre-Check

Before first use of an optional tool, verify availability:

1. **Context7:** Attempt `mcp__plugin_context7_context7__resolve-library-id` with a known library.
   - Success: mark `context7_available = true`
   - Failure: mark `context7_available = false`, log INFO: "Context7 unavailable — skipping documentation lookups"

2. **Playwright:** Attempt `mcp__plugin_playwright_playwright__browser_tabs`.
   - Success: mark `playwright_available = true`
   - Failure: mark `playwright_available = false`, log INFO: "Playwright unavailable — skipping visual verification"

3. **Neo4j:** Attempt neo4j-mcp health check query.
   - Success: mark `neo4j_available = true`
   - Failure: mark `neo4j_available = false`, log INFO: "Neo4j unavailable — using fallback index"

4. **LSP:** Check `lsp.enabled` in forge-config.md and verify LSP server process.
   - Available: use LSP for type checking and references
   - Unavailable: fall back to grep/glob, log INFO: "LSP unavailable — using text-based analysis"
```

**Agents that need this pattern:**

| Agent | Optional Tools | Current Behavior | Required Change |
|-------|---------------|-----------------|-----------------|
| `fg-100-orchestrator` | Neo4j, Context7 | Checks at PREFLIGHT | Already handled — no change needed |
| `fg-130-docs-discoverer` | Neo4j | Attempts graph write, fails | Add pre-check, skip graph indexing if unavailable |
| `fg-140-deprecation-refresh` | Context7 | Listed in tools, may fail | Add pre-check at start, skip Context7 queries if unavailable |
| `fg-200-planner` | Neo4j | Queries graph for context | Add pre-check, fall back to explore cache |
| `fg-350-docs-generator` | Context7 | Queries for latest docs | Add pre-check, skip doc freshness verification |
| `fg-417-version-compat-reviewer` | Context7 | Queries for version info | Add pre-check, rely on known-deprecations.json only |
| `fg-650-preview-validator` | Playwright | Core dependency | Add pre-check, return INFO finding if Playwright unavailable |
| `fg-610-infra-deploy-verifier` | Docker, kubectl | Tiers depend on tools | Already has tier-based skipping — verify pre-check is explicit |

### 6. Description Quality Bats Test

Add `tests/contract/agent-description-quality.bats`:

```bash
@test "agent-descriptions: all pipeline agents (fg-1xx through fg-7xx) have descriptions >= 60 chars"
@test "agent-descriptions: all dispatch agents contain 'Dispatched' or 'dispatched' in description"
@test "agent-descriptions: tier 1 agents have example blocks in description"
@test "agent-descriptions: all agents have model field in frontmatter"
@test "agent-descriptions: no agent description is a single generic sentence"
@test "agent-descriptions: review agents (fg-41x, fg-42x) inline output format"
@test "agent-descriptions: coordinators (fg-400, fg-500) document JSON output block"
```

Estimated: 7-10 test cases.

## Testing Approach

1. Run new `tests/contract/agent-description-quality.bats` — all tests must pass
2. Run existing `tests/contract/agent-frontmatter.bats` — no regressions
3. Run existing `tests/contract/tier1-description-examples.bats` — no regressions
4. Run existing `tests/contract/agent-tools-consistency.bats` — verify tool lists unchanged
5. Verify coordinator JSON output by grep for `GATE_JSON` in fg-400 and fg-500

## Acceptance Criteria

- [ ] All 6 vague descriptions replaced with specific dispatch trigger descriptions
- [ ] All 13 agents with poor error handling have structured Failure Modes sections
- [ ] All 9 review agents inline output format and token constraints (adds ~10 lines each)
- [ ] fg-400, fg-500, fg-700 document structured JSON output blocks
- [ ] Tool availability pre-check pattern documented in agent-defaults.md
- [ ] 6+ agents updated with explicit pre-check logic for optional tools
- [ ] `tests/contract/agent-description-quality.bats` passes with 7+ test cases
- [ ] All existing agent tests continue to pass

## Effort Estimate

**L** (Large) — 6 description rewrites, 13 error handling additions, 9 reviewer inlines, 3 coordinator output schemas, tool pre-check pattern. Estimated: 5-7 hours.

## Dependencies

- Should be done AFTER Q01 (skill quality) — skills trigger agents, so skills should be clean first.
- Coordinator JSON output (change 4) affects Q04 test design — tests can validate JSON structure.
