# F18: Next-Task Prediction After Pipeline Completion

## Status
DRAFT — 2026-04-13

## Problem Statement

JetBrains Junie (2025) proactively anticipates what developers need next after completing a task. GitHub Copilot Workspace suggests related follow-up tasks. Cursor proposes "next steps" after code generation. These tools recognize that development is rarely a single discrete action — completing one task reveals the next.

Forge's retrospective (`fg-700`) analyzes what happened in the completed run and extracts learnings. The post-run agent (`fg-710`) captures feedback and creates a recap. Neither agent predicts what the developer should do *next*. The pipeline ends with a summary of what was done, not a forward-looking suggestion of what remains.

**Gap:** After shipping a feature, the developer must mentally enumerate follow-up tasks: "Did I add integration tests? Update the API docs? Check for breaking changes?" This mental enumeration is error-prone and varies by experience level. Forge has the context to predict these follow-up tasks but does not.

**Value:** Predictions reduce the gap between completing work and starting the next task. Even imperfect predictions (50% relevance rate) save the developer the cognitive cost of remembering what comes next.

## Proposed Solution

Enhance `fg-710-post-run` to analyze completed changes and predict likely follow-up tasks using pattern-based rules and (optionally) knowledge graph analysis. Predictions are included in the post-run recap as a "Suggested follow-up tasks" section.

## Detailed Design

### Architecture

```
fg-710-post-run
     |
     +-- Part A: Feedback Capture (existing)
     +-- Part B: Recap Generation (existing)
     +-- Part C: Next-Task Prediction (NEW)
           |
           +-- C.1: Pattern-based predictions
           |     +-- Match changed files against prediction rules
           |     +-- Generate follow-up task descriptions
           |
           +-- C.2: Graph-based predictions (optional, requires Neo4j)
           |     +-- Query code graph for untested callers
           |     +-- Query for downstream consumers of changed APIs
           |
           +-- C.3: Ranking and deduplication
           |     +-- Score predictions by relevance
           |     +-- Deduplicate against already-completed tasks
           |     +-- Limit to max_suggestions
           |
           +-- Output: "Suggested follow-up tasks" in recap
```

### Prediction Rules

**Pattern-based rules** — match file changes against known follow-up patterns:

| Trigger Pattern | Predicted Follow-Up | Confidence | Category |
|---|---|---|---|
| Added REST endpoint (`@GetMapping`, `@PostMapping`, route handler) | "Add integration tests for new endpoint" | HIGH | testing |
| Added REST endpoint | "Update OpenAPI/Swagger specification" | MEDIUM | docs |
| Added REST endpoint | "Add rate limiting to new endpoint" | LOW | security |
| Added DB migration file | "Add corresponding rollback migration" | HIGH | database |
| Added DB migration | "Update seed/fixture data if needed" | MEDIUM | database |
| Changed public API signature | "Update API documentation" | HIGH | docs |
| Changed public API signature | "Check for breaking changes in consumers" | HIGH | compatibility |
| Added new npm/pip/gradle dependency | "Verify license compatibility" | MEDIUM | compliance |
| Added new dependency | "Pin dependency version" | LOW | stability |
| Changed authentication/authorization code | "Review security implications" | HIGH | security |
| Added new UI component | "Add Storybook/design system entry" | MEDIUM | docs |
| Added new UI component | "Add accessibility tests" | MEDIUM | testing |
| Changed shared/core module | "Verify downstream module consumers" | HIGH | compatibility |
| Added new configuration parameter | "Document configuration in README" | MEDIUM | docs |
| Changed error handling pattern | "Update error monitoring/alerting rules" | LOW | observability |
| Added background job/worker | "Add health check endpoint for worker" | MEDIUM | observability |
| Changed database schema | "Update data access documentation" | MEDIUM | docs |
| Added file upload handling | "Add file size/type validation" | HIGH | security |
| Changed caching logic | "Add cache invalidation tests" | HIGH | testing |

**Rule structure:**

```json
{
  "trigger": {
    "file_patterns": ["**/controllers/**", "**/routes/**"],
    "content_patterns": ["@(Get|Post|Put|Delete|Patch)Mapping", "router\\.(get|post|put|delete)"],
    "change_type": "added"
  },
  "prediction": {
    "description": "Add integration tests for new {endpoint_name} endpoint",
    "category": "testing",
    "confidence": "HIGH",
    "priority": 1
  }
}
```

### Graph-Based Predictions

When Neo4j knowledge graph is available, additional predictions are derived from code relationships:

| Graph Query | Predicted Follow-Up | Confidence |
|---|---|---|
| Modified function has callers with no test coverage | "Add tests for callers of {function}: {caller_list}" | HIGH |
| Changed module is imported by N other modules | "Verify {N} downstream consumers of {module}" | MEDIUM |
| Added node is disconnected (no callers/callees) | "Wire new {component} into application graph" | HIGH |
| Modified function's test coverage below threshold | "Improve test coverage for {function} (currently {pct}%)" | MEDIUM |

**Query patterns use existing graph schema** from `shared/graph/schema.md`. No new node/edge types required.

### Schema / Data Model

**Prediction output** (appended to recap markdown):

```markdown
## Suggested Follow-Up Tasks

Based on the changes in this run, consider these next steps:

1. **[HIGH] Add integration tests for new `/api/groups` endpoint**
   Category: testing | Trigger: new route handler in `GroupController.kt`
   *Suggested command:* `/forge-run Add integration tests for the groups REST API endpoint`

2. **[HIGH] Update OpenAPI specification for groups endpoint**
   Category: docs | Trigger: new public API endpoint
   *Suggested command:* `/docs-generate --scope api`

3. **[MEDIUM] Verify downstream consumers of `GroupService`**
   Category: compatibility | Trigger: modified shared service used by 3 modules
   *Source: code graph query*

4. **[MEDIUM] Add rollback migration for `V202604__add_groups_table.sql`**
   Category: database | Trigger: new migration file added
```

**Prediction tracking** (stored in `.forge/predictions.json`):

```json
{
  "version": "1.0.0",
  "history": [
    {
      "run_id": "story-123",
      "timestamp": "2026-04-13T10:30:00Z",
      "predictions": [
        {
          "id": "pred-001",
          "description": "Add integration tests for /api/groups endpoint",
          "category": "testing",
          "confidence": "HIGH",
          "trigger_file": "src/controllers/GroupController.kt",
          "acted_on": null
        }
      ]
    }
  ]
}
```

**Tracking "acted on":** When a subsequent `/forge-run` requirement semantically matches a prediction (e.g., "add integration tests for groups" matches prediction "Add integration tests for /api/groups endpoint"), the prediction is marked as `acted_on: true` with the matching run ID. This data feeds back to the retrospective for prediction quality analysis.

### Configuration

In `forge-config.md`:

```yaml
# Next-task prediction (v2.0+)
predictions:
  enabled: true               # Enable follow-up task predictions. Default: true.
  max_suggestions: 5           # Max predictions in recap. Default: 5. Range: 1-15.
  min_confidence: MEDIUM       # Minimum confidence to include. Default: MEDIUM. Values: HIGH, MEDIUM, LOW.
  categories: [all]            # Categories to include. Default: all. Or subset: [testing, docs, security]
  graph_predictions: true      # Use code graph for predictions (when available). Default: true.
  track_accuracy: true         # Track which predictions are acted on. Default: true.
```

**PREFLIGHT validation constraints:**

| Parameter | Range | Default | Rationale |
|---|---|---|---|
| `predictions.enabled` | boolean | `true` | Low overhead, default on |
| `predictions.max_suggestions` | 1-15 | 5 | Avoid overwhelming the recap |
| `predictions.min_confidence` | `HIGH`, `MEDIUM`, `LOW` | `MEDIUM` | LOW predictions are often obvious or irrelevant |
| `predictions.graph_predictions` | boolean | `true` | Graceful skip when Neo4j unavailable |

### Data Flow

**Prediction generation (Stage 9 — LEARN):**

1. Post-run agent (`fg-710`) completes Part A (feedback) and Part B (recap)
2. Part C begins: agent reads changed files list from `state.json`
3. For each changed file, match against prediction rules:
   a. Check file path patterns (controller, migration, component, etc.)
   b. Check content patterns (annotations, function signatures, etc.)
   c. Check change type (added, modified, deleted)
4. Generate prediction descriptions with confidence levels
5. If `graph_predictions: true` and Neo4j available:
   a. Query graph for callers of modified functions without tests
   b. Query graph for downstream consumers of changed modules
   c. Add graph-based predictions
6. Deduplicate: remove predictions for tasks already completed in this run
   (e.g., if integration tests were already written, don't suggest writing them)
7. Rank by confidence (HIGH first) then by priority
8. Truncate to `max_suggestions`
9. Append to recap markdown as "Suggested Follow-Up Tasks" section
10. Write predictions to `.forge/predictions.json` for accuracy tracking

**Accuracy tracking (subsequent runs):**

1. At PREFLIGHT of a new run, read the requirement text
2. Compare against recent predictions in `.forge/predictions.json`
3. If semantic match found: mark prediction as `acted_on: true`
4. Retrospective includes prediction accuracy stats in its report

### Integration Points

| File | Change |
|---|---|
| `agents/fg-710-post-run.md` | Add Part C: Next-Task Prediction. New section after Part B. |
| `agents/fg-100-orchestrator.md` | At PREFLIGHT, compare new requirement against recent predictions for accuracy tracking. |
| `agents/fg-700-retrospective.md` | Include prediction accuracy stats in pipeline report. |
| `shared/state-schema.md` | Document `.forge/predictions.json` schema and lifecycle. |
| `modules/frameworks/*/forge-config-template.md` | Add `predictions:` section. |

### Error Handling

**Failure mode 1: No prediction rules match.**
- Detection: Zero predictions generated after scanning all changed files
- Behavior: Omit "Suggested Follow-Up Tasks" section from recap entirely. Do not include an empty section.

**Failure mode 2: Neo4j unavailable for graph predictions.**
- Detection: Graph query fails or Neo4j not configured
- Behavior: Skip graph-based predictions. Pattern-based predictions still work. This follows existing MCP degradation pattern.

**Failure mode 3: All predictions are already completed.**
- Detection: Deduplication removes all candidates
- Behavior: Include a single line in recap: "No follow-up tasks identified — changes appear self-contained." This is a positive signal.

**Failure mode 4: Predictions are consistently irrelevant.**
- Detection: `predictions.json` shows <20% acted-on rate after 10+ runs
- Behavior: Retrospective flags this and suggests reducing `max_suggestions` or raising `min_confidence` to HIGH. Does not auto-disable.

## Performance Characteristics

**Prediction generation:**

| Step | Token Cost | Wall-Clock Time |
|---|---|---|
| Read changed files list | 0 (from state.json) | <1ms |
| Pattern matching | 200-500 tokens | 50-200ms (regex + content checks) |
| Graph queries (if enabled) | 100-300 tokens | 500ms-2s (Neo4j round-trips) |
| Rank and format | 100-200 tokens | <50ms |
| Write to predictions.json | 0 | 5ms |
| **Total** | **400-1,000 tokens** | **555ms-2.3s** |

**Accuracy tracking:**

| Step | Token Cost | Notes |
|---|---|---|
| Read predictions.json | 0 | File read |
| Semantic comparison | 100-200 tokens | Compare requirement vs prediction text |
| **Total** | **100-200 tokens** | Runs once at PREFLIGHT |

Negligible overhead relative to the full pipeline cost.

## Testing Approach

### Structural Tests (`tests/structural/`)

1. **Agent update:** `fg-710-post-run.md` contains "Part C" and "Next-Task Prediction"
2. **Config template:** All `forge-config-template.md` files include `predictions:` section

### Unit Tests (`tests/unit/`)

1. **`next-task-prediction.bats`:**
   - New REST endpoint triggers "add integration tests" prediction
   - New migration triggers "add rollback migration" prediction
   - Changed public API triggers "check breaking changes" prediction
   - Deduplication removes predictions for already-completed tasks
   - `max_suggestions` limits output count
   - `min_confidence: HIGH` excludes MEDIUM and LOW predictions
   - Config disabled: `predictions.enabled: false` omits section entirely
   - No matching patterns: section omitted (not empty)

2. **`prediction-tracking.bats`:**
   - Prediction marked as acted_on when subsequent run matches
   - Non-matching runs do not mark predictions
   - Accuracy stats computed correctly

## Acceptance Criteria

1. Post-run recap includes "Suggested Follow-Up Tasks" section when predictions exist
2. Predictions are generated from pattern-based rules matching changed files
3. Graph-based predictions enhance results when Neo4j is available
4. Predictions are ranked by confidence and capped at `max_suggestions`
5. Already-completed tasks are deduplicated from predictions
6. Prediction accuracy is tracked across runs in `.forge/predictions.json`
7. Retrospective reports prediction accuracy statistics
8. Section is omitted entirely when no predictions exist (not displayed empty)
9. Feature can be disabled via `predictions.enabled: false`
10. Each prediction includes a suggested forge command for easy execution

## Migration Path

**From v1.20.1 to v2.0:**

1. **Zero breaking changes.** Part C is additive to the post-run agent's existing Part A + Part B.
2. **Post-run agent update:** New section C appended. Existing feedback capture and recap unchanged.
3. **Config:** `predictions.enabled: true` by default. Low overhead justifies default-on.
4. **New file:** `.forge/predictions.json` created on first run with predictions enabled.
5. **No new agents or categories.** Predictions are presented in the recap, not as findings.

## Dependencies

**This feature depends on:**
- `fg-710-post-run` Part B recap generation (predictions appended to recap)
- `state.json` changed files list (already tracked by orchestrator)
- Neo4j knowledge graph (optional, for graph-based predictions; graceful degradation)

**Other features that benefit from this:**
- F12 (Spec Inference): prediction tracking data reveals which bug investigation areas need better coverage
- F19 (DX Metrics): prediction relevance rate becomes a DX metric
- Sprint orchestration: predictions can feed into sprint backlog for multi-feature runs
