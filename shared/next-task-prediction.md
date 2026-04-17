# Next-Task Prediction

Predicts follow-up tasks after pipeline completion using pattern-based rules and optional knowledge graph analysis. Predictions are appended to the post-run recap.

## Overview

After shipping a feature, developers must mentally enumerate follow-up tasks: integration tests, API docs, rollback migrations, breaking change checks. This system automates that enumeration by matching changed files against 19 known follow-up patterns and (optionally) querying the code graph for untested callers and downstream consumers.

**Feature flag:** `predictions.enabled` (default: `true`).

## Prediction Rules

19 pattern-based rules match file changes against known follow-up patterns:

| # | Trigger Pattern | Predicted Follow-Up | Confidence | Category |
|---|----------------|---------------------|-----------|----------|
| 1 | Added REST endpoint (`@GetMapping`, `@PostMapping`, route handler) | Add integration tests for new endpoint | HIGH | testing |
| 2 | Added REST endpoint | Update OpenAPI/Swagger specification | MEDIUM | docs |
| 3 | Added REST endpoint | Add rate limiting to new endpoint | LOW | security |
| 4 | Added DB migration file | Add corresponding rollback migration | HIGH | database |
| 5 | Added DB migration | Update seed/fixture data if needed | MEDIUM | database |
| 6 | Changed public API signature | Update API documentation | HIGH | docs |
| 7 | Changed public API signature | Check for breaking changes in consumers | HIGH | compatibility |
| 8 | Added new dependency (npm/pip/gradle) | Verify license compatibility | MEDIUM | compliance |
| 9 | Added new dependency | Pin dependency version | LOW | stability |
| 10 | Changed authentication/authorization code | Review security implications | HIGH | security |
| 11 | Added new UI component | Add Storybook/design system entry | MEDIUM | docs |
| 12 | Added new UI component | Add accessibility tests | MEDIUM | testing |
| 13 | Changed shared/core module | Verify downstream module consumers | HIGH | compatibility |
| 14 | Added new configuration parameter | Document configuration in README | MEDIUM | docs |
| 15 | Changed error handling pattern | Update error monitoring/alerting rules | LOW | observability |
| 16 | Added background job/worker | Add health check endpoint for worker | MEDIUM | observability |
| 17 | Changed database schema | Update data access documentation | MEDIUM | docs |
| 18 | Added file upload handling | Add file size/type validation | HIGH | security |
| 19 | Changed caching logic | Add cache invalidation tests | HIGH | testing |

### Rule Structure

Each rule matches against:
- **File patterns:** Glob patterns on changed file paths (e.g., `**/controllers/**`, `**/routes/**`)
- **Content patterns:** Regex on file content (e.g., `@(Get|Post|Put|Delete|Patch)Mapping`)
- **Change type:** `added`, `modified`, or `deleted`

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

## Graph-Based Predictions

When Neo4j knowledge graph is available (`predictions.graph_predictions: true`), additional predictions are derived from code relationships:

| Graph Query | Predicted Follow-Up | Confidence |
|------------|---------------------|-----------|
| Modified function has callers with no test coverage | Add tests for callers of {function}: {caller_list} | HIGH |
| Changed module is imported by N other modules | Verify {N} downstream consumers of {module} | MEDIUM |
| Added node is disconnected (no callers/callees) | Wire new {component} into application graph | HIGH |
| Modified function's test coverage below threshold | Improve test coverage for {function} (currently {pct}%) | MEDIUM |

Uses existing graph schema from `shared/graph/schema.md`. No new node/edge types required. Graceful skip when Neo4j is unavailable (follows MCP degradation pattern).

## Prediction Output Format

Appended to the post-run recap markdown:

```markdown
## Suggested Follow-Up Tasks

Based on the changes in this run, consider these next steps:

1. **[HIGH] Add integration tests for new `/api/groups` endpoint**
   Category: testing | Trigger: new route handler in `GroupController.kt`
   *Suggested command:* `/forge-run Add integration tests for the groups REST API endpoint`

2. **[HIGH] Update OpenAPI specification for groups endpoint**
   Category: docs | Trigger: new public API endpoint
   *Suggested command:* `/forge-docs-generate --scope api`

3. **[MEDIUM] Verify downstream consumers of `GroupService`**
   Category: compatibility | Trigger: modified shared service used by 3 modules
   *Source: code graph query*
```

Each prediction includes:
- Confidence level (HIGH, MEDIUM, LOW)
- Category (testing, docs, security, database, compatibility, compliance, stability, observability)
- Trigger file that caused the prediction
- Suggested forge command for easy execution

## Prediction Tracking

**Location:** `.forge/predictions.json`

**Lifecycle:**
- Created on first run with predictions enabled
- Appended after each run by `fg-710-post-run`
- Survives `/forge-recover reset`

**Accuracy tracking:** When a subsequent `/forge-run` requirement semantically matches a prediction (compared at PREFLIGHT), the prediction is marked as `acted_on: true` with the matching run ID. Retrospective includes prediction accuracy stats.

**Low accuracy handling:** If `predictions.json` shows <20% acted-on rate after 10+ runs, retrospective flags this and suggests reducing `max_suggestions` or raising `min_confidence` to HIGH. Does not auto-disable.

## Deduplication

Before outputting predictions:
1. Remove predictions for tasks already completed in this run (e.g., if integration tests were written, do not suggest writing them)
2. Deduplicate identical predictions triggered by multiple files
3. Rank by confidence (HIGH first) then by priority
4. Truncate to `max_suggestions`

If all predictions are deduplicated away, include: "No follow-up tasks identified -- changes appear self-contained."

If zero predictions match, omit the section entirely (do not output an empty section).

## Configuration

```yaml
predictions:
  enabled: true               # Enable predictions. Default: true.
  max_suggestions: 5           # Max predictions in recap. Default: 5. Range: 1-15.
  min_confidence: MEDIUM       # Minimum confidence to include. Default: MEDIUM.
  categories: [all]            # Categories to include. Default: all.
  graph_predictions: true      # Use code graph when available. Default: true.
  track_accuracy: true         # Track which predictions are acted on. Default: true.
```

## Data Flow

```
Stage 9 (LEARN)
  fg-710-post-run
    Part A: Feedback Capture (existing)
    Part B: Recap Generation (existing)
    Part C: Pipeline Timeline (existing)
    Part D: Next-Task Prediction (NEW)
      1. Read changed files from state.json
      2. Match against 19 pattern-based rules
      3. Query code graph (if available)
      4. Deduplicate against completed tasks
      5. Rank by confidence, truncate to max_suggestions
      6. Append to recap markdown
      7. Write to .forge/predictions.json
```

## Integration Points

| File | Change |
|------|--------|
| `agents/fg-710-post-run.md` | Add Part D: Next-Task Prediction after Part C |
| `agents/fg-100-orchestrator.md` | At PREFLIGHT, compare new requirement against recent predictions for accuracy tracking |
| `agents/fg-700-retrospective.md` | Include prediction accuracy stats in pipeline report |
| `modules/frameworks/*/forge-config-template.md` | Add `predictions:` section |

## Error Handling

| Failure Mode | Detection | Behavior |
|-------------|-----------|----------|
| No rules match | Zero predictions generated | Omit section entirely |
| Neo4j unavailable | Graph query fails | Skip graph-based predictions, pattern-based still work |
| All predictions completed | Deduplication removes all | Single line: "No follow-up tasks identified" |
| Consistently irrelevant | <20% acted-on rate after 10+ runs | Retrospective flags, suggests raising min_confidence |
