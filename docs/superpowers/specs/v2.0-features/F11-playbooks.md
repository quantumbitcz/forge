# F11: Playbooks -- Reusable Task Templates with Analytics

## Status
DRAFT -- 2026-04-13

## Problem Statement

Development teams repeat the same categories of tasks: add a REST endpoint, fix a flaky test, add a database migration, implement a webhook handler, extract a service from a monolith. Each type of task follows a predictable pattern with known acceptance criteria, review focus areas, and common pitfalls.

Forge currently has two mechanisms for task customization:
- **Skills** (32): Entry points that route to agents with predefined behavior. Fixed in the plugin -- users cannot define new skills.
- **Mode overlays** (7): Pipeline behavior modifications (standard, bugfix, migration, etc.). Coarse-grained -- they change stage behavior, not task definition.

Neither mechanism allows users to define "how we do X at our company" -- the specific requirement templates, acceptance criteria, review focus areas, and configuration overrides that encode organizational knowledge.

Competitive landscape:
- **Devin** ships playbooks that codify "how we do X" with execution traces and usage analytics. Teams report 60% faster task completion when using playbooks vs. freeform requirements.
- **GitHub Copilot** supports custom agents per organization that encode team-specific workflows.
- **Cursor** has rules files but no task-level templates with parameters.

The gap: Forge has the machinery (skills, modes, convergence, config) but lacks a user-definable abstraction layer that connects "type of task" to "how we execute it."

## Proposed Solution

Introduce playbooks: user-defined task templates stored in `.claude/forge-playbooks/{name}.md` with frontmatter-based configuration, parameter interpolation, and per-playbook analytics tracking. Playbooks feed into the existing `/forge-run` pipeline -- they are not a separate execution path. Built-in playbooks ship with the plugin for common patterns.

## Detailed Design

### Architecture

A playbook is a markdown file with YAML frontmatter that defines: parameters, mode overrides, stage configuration, review focus, and a requirement template. When invoked, the playbook's template is interpolated with parameter values and fed to `/forge-run` as the requirement, with the playbook's configuration overlaid on the project config.

```
User: /forge-run --playbook=add-rest-endpoint entity=Task operations=create,read

  1. Parse playbook file (.claude/forge-playbooks/add-rest-endpoint.md)
  2. Validate required parameters (entity=Task -- OK)
  3. Interpolate template: "Implement a REST API endpoint for Task..."
  4. Overlay playbook config on forge-config.md
  5. Feed interpolated requirement to normal /forge-run pipeline
  6. On completion: update playbook analytics
```

Playbooks do NOT bypass any pipeline stage. They are requirement generation + config overlay, not a separate orchestration path.

#### Component Ownership

| Component | Owner | Responsibility |
|-----------|-------|----------------|
| Playbook parser | fg-100-orchestrator | Parse frontmatter, validate params, interpolate template |
| Playbook config overlay | fg-100-orchestrator | Merge playbook config with project config at PREFLIGHT |
| Analytics tracker | fg-700-retrospective | Update analytics after each playbook run |
| `/forge-playbooks` skill | New skill | List playbooks with stats |
| Auto-suggestion | fg-710-post-run | Suggest playbook usage after runs |
| Built-in playbooks | Plugin distribution | Ship with forge in `shared/playbooks/` |

### Schema / Data Model

#### Playbook File Format

Location: `.claude/forge-playbooks/{name}.md` (project-specific) or `shared/playbooks/{name}.md` (built-in).

Resolution order: project playbooks override built-in playbooks with the same name.

```yaml
---
name: add-rest-endpoint
description: Add a new REST API endpoint with tests, validation, and docs
version: "1.0"
mode: standard
parameters:
  - name: entity
    description: The domain entity name (PascalCase)
    type: string
    required: true
    validation: "^[A-Z][a-zA-Z]+$"
  - name: operations
    description: CRUD operations to support
    type: list
    default: [create, read, update, delete]
    allowed_values: [create, read, update, delete, list, search]
  - name: auth
    description: Authentication requirement
    type: enum
    default: required
    allowed_values: [required, optional, none]
  - name: pagination
    description: Enable pagination for list/search operations
    type: boolean
    default: true
stages:
  skip: []
  focus:
    REVIEWING:
      review_agents: [fg-410-code-reviewer, fg-411-security-reviewer, fg-412-architecture-reviewer]
review:
  focus_categories: ["ARCH-*", "SEC-*", "TEST-*", "CONTRACT-*"]
  min_score: 90
scoring:
  critical_weight: 20
  warning_weight: 5
acceptance_criteria:
  - "GIVEN valid {{entity}} data WHEN POST /api/{{entity | kebab-case}}s THEN returns 201 with {{entity}} ID"
  - "GIVEN invalid {{entity}} data WHEN POST /api/{{entity | kebab-case}}s THEN returns 400 with validation errors"
  - "GIVEN authenticated user WHEN GET /api/{{entity | kebab-case}}s/:id THEN returns the {{entity}} with 200"
  - "GIVEN unauthenticated user WHEN any operation on /api/{{entity | kebab-case}}s THEN returns 401"
  - "Integration tests exist for each {{operations}} operation"
  - "OpenAPI spec includes the new {{entity}} endpoints"
tags: [api, backend, rest]
---

## Requirement Template

Implement a REST API endpoint for **{{entity}}** supporting **{{operations | join:", "}}** operations.

### Entity: {{entity}}
- Create the domain entity, repository, service, and controller layers
- Follow the project's existing architectural patterns (check existing controllers for reference)

### Operations
{{#each operations}}
- **{{this}}**: Implement the {{this}} operation with proper validation and error handling
{{/each}}

### Requirements
{{#if (eq auth "required")}}
- All endpoints require authentication via the project's existing auth mechanism
{{else if (eq auth "optional")}}
- Authentication is optional -- unauthenticated users get read-only access
{{/if}}
{{#if pagination}}
- List operations support pagination (offset/limit or cursor-based, matching existing patterns)
{{/if}}
- Input validation covers: required fields, type constraints, business rules
- Error responses follow the project's standard error format
- Integration tests cover happy path and error cases for each operation
- OpenAPI/Swagger spec is updated with the new endpoints
```

#### Frontmatter Schema

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | yes | Unique playbook identifier (kebab-case, matches filename) |
| `description` | string | yes | Human-readable description for `/forge-playbooks` listing |
| `version` | string | no | Playbook version for tracking changes (default: "1.0") |
| `mode` | string | no | Pipeline mode override (default: inherits from project config) |
| `parameters` | array | no | Parameter definitions (empty = no parameters) |
| `parameters[].name` | string | yes | Parameter name (snake_case) |
| `parameters[].description` | string | yes | Human-readable parameter description |
| `parameters[].type` | enum | yes | `string`, `list`, `enum`, `boolean`, `integer` |
| `parameters[].required` | boolean | no | Whether the parameter must be provided (default: false) |
| `parameters[].default` | any | no | Default value if not provided |
| `parameters[].validation` | string | no | Regex pattern for string type validation |
| `parameters[].allowed_values` | array | no | Valid values for enum and list types |
| `stages` | object | no | Stage-level configuration overrides |
| `stages.skip` | string[] | no | Stages to skip (e.g., `["DOCUMENTING"]`) |
| `stages.focus` | object | no | Per-stage configuration (e.g., specific review agents) |
| `review` | object | no | Review configuration overrides |
| `review.focus_categories` | string[] | no | Finding categories to prioritize |
| `review.min_score` | integer | no | Minimum quality score for this playbook |
| `scoring` | object | no | Scoring overrides (same schema as `forge-config.md` scoring) |
| `acceptance_criteria` | string[] | no | Acceptance criteria templates (interpolated with parameters) |
| `tags` | string[] | no | Tags for categorization and auto-suggestion matching |

#### Parameter Interpolation

Template syntax uses `{{parameter}}` with optional filters:

| Syntax | Example | Result |
|--------|---------|--------|
| `{{name}}` | `{{entity}}` with entity=Task | `Task` |
| `{{name \| kebab-case}}` | `{{entity \| kebab-case}}` with entity=UserProfile | `user-profile` |
| `{{name \| camelCase}}` | `{{entity \| camelCase}}` with entity=UserProfile | `userProfile` |
| `{{name \| snake_case}}` | `{{entity \| snake_case}}` with entity=UserProfile | `user_profile` |
| `{{name \| UPPER_CASE}}` | `{{entity \| UPPER_CASE}}` with entity=UserProfile | `USER_PROFILE` |
| `{{name \| lower}}` | `{{entity \| lower}}` with entity=Task | `task` |
| `{{name \| plural}}` | `{{entity \| plural}}` with entity=Task | `Tasks` |
| `{{name \| join:", "}}` | `{{operations \| join:", "}}` with operations=[create,read] | `create, read` |
| `{{#each name}}...{{this}}...{{/each}}` | Loop over list parameter | Repeated block per item |
| `{{#if (eq name "value")}}...{{/if}}` | Conditional block | Included if condition true |
| `{{#if name}}...{{/if}}` | Truthiness check | Included if parameter is truthy |

The interpolation engine is intentionally simple -- it handles the patterns above and nothing more. Complex logic belongs in the playbook's prose, not in template syntax.

#### Analytics Schema

`.forge/playbook-analytics.json`:

```json
{
  "schema_version": "1.0.0",
  "playbooks": {
    "add-rest-endpoint": {
      "run_count": 12,
      "success_count": 10,
      "fail_count": 2,
      "avg_score": 91.3,
      "avg_iterations": 4.2,
      "avg_duration_seconds": 420,
      "avg_cost_usd": 0.85,
      "last_used": "2026-04-13T14:00:00Z",
      "parameter_frequency": {
        "entity": { "Task": 3, "User": 2, "Project": 2, "Comment": 1, "other": 4 },
        "operations": { "[create,read,update,delete]": 8, "[create,read]": 3, "other": 1 }
      },
      "common_findings": {
        "SEC-INJECTION": 3,
        "TEST-COVERAGE": 5,
        "CONV-NAMING": 2
      },
      "version_history": [
        { "version": "1.0", "runs": 8, "avg_score": 89.5 },
        { "version": "1.1", "runs": 4, "avg_score": 94.0 }
      ]
    }
  },
  "last_updated": "2026-04-13T14:00:00Z"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `schema_version` | string | Analytics schema version |
| `playbooks` | object | Keyed by playbook name |
| `playbooks.*.run_count` | integer | Total invocations |
| `playbooks.*.success_count` | integer | Runs that reached SHIP |
| `playbooks.*.fail_count` | integer | Runs that failed or aborted |
| `playbooks.*.avg_score` | float | Average final quality score |
| `playbooks.*.avg_iterations` | float | Average convergence iterations |
| `playbooks.*.avg_duration_seconds` | float | Average wall-clock duration |
| `playbooks.*.avg_cost_usd` | float | Average estimated cost |
| `playbooks.*.last_used` | string (ISO 8601) | Most recent invocation |
| `playbooks.*.parameter_frequency` | object | Per-parameter value frequency (top 5 + "other") |
| `playbooks.*.common_findings` | object | Finding categories that recur across runs (count) |
| `playbooks.*.version_history` | array | Per-version run stats |

#### Auto-Suggestion Schema

The post-run agent (`fg-710-post-run`) compares the completed run's requirement against available playbooks. Suggestion data is appended to the run recap:

```json
{
  "playbook_suggestion": {
    "suggested_playbook": "add-rest-endpoint",
    "confidence": "HIGH",
    "match_signals": ["entity pattern detected", "CRUD operations", "REST endpoint"],
    "estimated_savings": "~30% fewer iterations based on playbook history"
  }
}
```

### Configuration

In `forge-config.md`:

```yaml
playbooks:
  enabled: true                      # Master toggle (default: true)
  directory: ".claude/forge-playbooks"  # Playbook directory (default: .claude/forge-playbooks)
  analytics: true                    # Track per-playbook analytics (default: true)
  auto_suggest: true                 # Suggest playbooks after runs (default: true)
  suggestion_confidence_threshold: "MEDIUM"  # Minimum confidence for suggestions (default: MEDIUM)
  builtin_playbooks: true            # Include built-in playbooks from plugin (default: true)
```

Constraints enforced at PREFLIGHT:
- `directory` must be a valid path relative to project root.
- `suggestion_confidence_threshold` must be one of `LOW`, `MEDIUM`, `HIGH`.
- Playbook `name` must match its filename (sans `.md`), same rule as agent frontmatter.
- Playbook `stages.skip` values must be valid stage names.
- Playbook `stages.skip` MUST NOT include `VERIFYING`, `REVIEWING`, or `SHIPPING` — these are safety-critical stages. Attempting to skip them produces a CRITICAL validation error and the playbook is rejected.
- Playbook `review.min_score` must be >= project's `pass_threshold`.
- Playbook `scoring` overrides are validated against PREFLIGHT constraints: `critical_weight >= 10`, `warning_weight >= 1 > info_weight >= 0`. Playbooks cannot weaken scoring below project minimums.

### Data Flow

#### Invocation Flow

```
/forge-run --playbook=add-rest-endpoint entity=Task operations=create,read,list

  1. PARSE: Read .claude/forge-playbooks/add-rest-endpoint.md
     - If not found: check shared/playbooks/add-rest-endpoint.md (built-in)
     - If not found: error PLAYBOOK_NOT_FOUND

  2. VALIDATE PARAMETERS:
     - Required params present: entity=Task (OK)
     - Type check: entity is string matching ^[A-Z][a-zA-Z]+$ (OK)
     - List parse: operations="create,read,list" -> ["create", "read", "list"]
     - Allowed values: all in [create,read,update,delete,list,search] (OK)
     - Apply defaults: auth="required", pagination=true

  3. INTERPOLATE TEMPLATE:
     - Replace {{entity}} -> Task
     - Replace {{operations | join:", "}} -> create, read, list
     - Expand {{#each operations}} blocks
     - Evaluate {{#if}} conditionals
     - Result: fully interpolated requirement text

  4. INTERPOLATE ACCEPTANCE CRITERIA:
     - Apply same interpolation to acceptance_criteria list
     - Result: concrete ACs with parameter values filled in
     - If F05 (living specs) active: register ACs in spec registry

  5. OVERLAY CONFIG:
     - Merge playbook.scoring over forge-config.md scoring
     - Merge playbook.review over forge-config.md review settings
     - Merge playbook.stages over forge-config.md stage settings
     - Store overlay source in state.json: playbook_name, playbook_version

  6. DISPATCH /forge-run:
     - requirement = interpolated template text
     - config = merged config
     - Pipeline proceeds as normal through all 10 stages

  7. ON COMPLETION (LEARN stage):
     - fg-700-retrospective updates playbook-analytics.json
     - fg-710-post-run checks for playbook suggestion opportunity
```

#### Config Overlay Resolution

When a playbook specifies config overrides, they are merged with project config using this precedence:

```
playbook overrides > forge-config.md values > plugin defaults
```

The overlay is scoped to the current run. It does not modify `forge-config.md` on disk. The orchestrator records the overlay in `state.json`:

```json
{
  "playbook": {
    "name": "add-rest-endpoint",
    "version": "1.0",
    "parameters": { "entity": "Task", "operations": ["create", "read", "list"] },
    "config_overrides": {
      "review.focus_categories": ["ARCH-*", "SEC-*", "TEST-*", "CONTRACT-*"],
      "review.min_score": 90
    }
  }
}
```

#### Auto-Suggestion Algorithm

After a pipeline run completes without a playbook, `fg-710-post-run` checks for matching playbooks:

```
FUNCTION suggest_playbook(requirement, available_playbooks):
  candidates = []

  FOR playbook in available_playbooks:
    score = 0
    signals = []

    # Tag matching: compare requirement keywords against playbook tags
    FOR tag in playbook.tags:
      IF tag appears in requirement (case-insensitive):
        score += 3
        signals.append("tag match: " + tag)

    # Description matching: fuzzy match against playbook description
    IF fuzzy_match(requirement, playbook.description) > 0.6:
      score += 5
      signals.append("description match")

    # Template keyword matching: extract nouns from template, match against requirement
    template_keywords = extract_keywords(playbook.template)
    matching_keywords = intersection(template_keywords, extract_keywords(requirement))
    score += len(matching_keywords) * 1
    IF len(matching_keywords) > 2:
      signals.append("{N} template keywords match")

    # AC pattern matching: check if requirement's implied ACs match playbook ACs
    IF playbook.acceptance_criteria:
      ac_patterns = extract_patterns(playbook.acceptance_criteria)
      # Patterns like "REST endpoint", "CRUD", "validation", "integration tests"
      matching_patterns = intersection(ac_patterns, extract_patterns(requirement))
      score += len(matching_patterns) * 2
      IF len(matching_patterns) > 1:
        signals.append("{N} AC patterns match")

    IF score > 0:
      candidates.append({playbook, score, signals})

  # Sort by score descending
  candidates.sort(by=score, descending=true)

  IF candidates[0].score >= 10:
    confidence = "HIGH"
  ELIF candidates[0].score >= 5:
    confidence = "MEDIUM"
  ELIF candidates[0].score >= 2:
    confidence = "LOW"
  ELSE:
    RETURN null  # No suggestion

  IF confidence < config.suggestion_confidence_threshold:
    RETURN null

  RETURN {
    suggested_playbook: candidates[0].playbook.name,
    confidence: confidence,
    match_signals: candidates[0].signals,
    estimated_savings: compute_savings_estimate(candidates[0].playbook)
  }
```

### Built-In Playbook Catalog

The plugin ships with playbooks in `shared/playbooks/`. These are available when `builtin_playbooks: true` (default).

| Playbook | Description | Parameters |
|----------|-------------|------------|
| `add-rest-endpoint` | Add a REST API endpoint with full CRUD | `entity`, `operations`, `auth`, `pagination` |
| `fix-flaky-test` | Investigate and fix a flaky test | `test_name`, `test_file`, `flaky_behavior` |
| `add-db-migration` | Add a database schema migration | `entity`, `change_type` (add_table, add_column, rename, drop), `target_db` |
| `implement-webhook` | Implement an incoming or outgoing webhook handler | `direction` (incoming, outgoing), `event_type`, `payload_format` |
| `refactor-extract-service` | Extract a service from existing code | `source_class`, `target_service`, `extraction_type` (interface, module, microservice) |
| `add-auth-endpoint` | Add authentication/authorization to an endpoint or module | `auth_type` (jwt, oauth2, api_key), `scope`, `resource` |
| `add-event-handler` | Implement an async event handler (message queue consumer) | `event_name`, `source_queue`, `idempotency` |

Each built-in playbook follows the same frontmatter schema as user-defined playbooks. Teams can override built-ins by creating a file with the same name in `.claude/forge-playbooks/`.

### Integration Points

| System | Integration | Direction |
|--------|-------------|-----------|
| `/forge-run` | Playbook parsed and interpolated at entry | Read |
| fg-100-orchestrator | Config overlay applied at PREFLIGHT | Read |
| fg-200-planner | Receives interpolated requirement (transparent) | Consumer |
| fg-700-retrospective | Updates playbook analytics | Write |
| fg-710-post-run | Auto-suggestion after non-playbook runs | Read |
| F05 living specs | Playbook ACs registered in spec registry | Write |
| `forge-config.md` | Playbook scoring/review overrides merged | Read |
| `/forge-playbooks` skill | Lists playbooks with analytics | Read |
| `/forge-shape` | Can produce a spec that maps to a playbook pattern | Read |

### Error Handling

| Scenario | Behavior |
|----------|----------|
| Playbook file not found (project or built-in) | Error: `PLAYBOOK_NOT_FOUND`. List available playbooks. |
| Required parameter not provided | Error: `PLAYBOOK_PARAM_MISSING`. List missing params with descriptions. |
| Parameter fails validation (regex, allowed_values, type) | Error: `PLAYBOOK_PARAM_INVALID`. Show constraint and provided value. |
| Playbook frontmatter is invalid YAML | Error: `PLAYBOOK_PARSE_ERROR`. Show YAML error location. |
| Playbook `name` does not match filename | WARNING at PREFLIGHT. Use filename as the canonical name. |
| Playbook `stages.skip` contains invalid stage name | WARNING at PREFLIGHT. Ignore invalid skip entry. |
| Playbook `review.min_score` < project `pass_threshold` | WARNING at PREFLIGHT. Use project `pass_threshold` as minimum. |
| Template interpolation produces empty result | Error: `PLAYBOOK_TEMPLATE_EMPTY`. Check parameters and conditionals. |
| Analytics file corrupt (invalid JSON) | Rebuild from empty state. Log WARNING. Historical analytics lost. |
| Two playbooks with same name in project and built-in dirs | Project playbook wins. Log INFO: "Overriding built-in playbook: {name}". |

## Performance Characteristics

- **Parsing overhead**: Playbook frontmatter parsing and template interpolation add <100ms to pipeline startup. Negligible.
- **Analytics write**: One JSON file write at LEARN stage. <10ms.
- **Auto-suggestion**: Keyword extraction and matching across 10-20 playbooks takes <500ms. No LLM call.
- **No additional LLM cost**: Playbooks generate a requirement string that feeds into the normal pipeline. The interpolated requirement may be slightly longer than a freeform one (more structured), adding ~200-500 tokens to the initial prompt. This is offset by clearer requirements reducing convergence iterations.
- **Analytics file size**: ~2KB per playbook with 50 runs of analytics. At 20 playbooks: ~40KB.

## Testing Approach

### Structural Tests

1. All built-in playbooks in `shared/playbooks/` have valid frontmatter (name matches filename, required fields present).
2. All built-in playbooks have at least 3 acceptance criteria.
3. `playbook-analytics.json` schema version field is present in the schema definition.

### Unit Tests

1. **Parameter parsing**: Given CLI args `entity=Task operations=create,read`, parse into typed parameter map. Test: missing required, invalid type, regex failure, list parsing.
2. **Template interpolation**: Given a template with `{{entity}}`, `{{operations | join}}`, `{{#each}}`, `{{#if}}`, verify correct output. Test: missing optional param uses default, missing required param errors.
3. **Config overlay**: Given playbook scoring overrides and project config, verify merged config has playbook values taking precedence.
4. **Analytics update**: Given existing analytics with 10 runs and a new run result, verify updated averages and counts.
5. **Auto-suggestion**: Given a requirement "Add a REST endpoint for users with CRUD" and available playbooks, verify `add-rest-endpoint` is suggested with HIGH confidence.

### Contract Tests

1. Interpolated requirement text from a playbook is accepted by `/forge-run` without errors.
2. Config overlay from a playbook produces valid merged config per PREFLIGHT validation.
3. Analytics JSON written by retrospective is readable by `/forge-playbooks`.

### Scenario Tests

1. **Happy path**: Invoke `--playbook=add-rest-endpoint entity=Task`. Pipeline completes. Analytics updated. Verify the requirement fed to the planner contains "Task" and the review focused on the specified categories.
2. **Parameter validation**: Invoke `--playbook=add-rest-endpoint entity=task` (lowercase). Expect `PLAYBOOK_PARAM_INVALID` because validation requires PascalCase.
3. **Built-in override**: Create `.claude/forge-playbooks/add-rest-endpoint.md` with custom template. Invoke. Verify the custom template is used, not the built-in.
4. **Auto-suggestion**: Run `/forge-run "Add REST API for Comments with create and read"` without playbook. Verify post-run suggests `add-rest-endpoint` playbook.
5. **No match**: Run `/forge-run "Optimize database query performance"`. Verify no playbook suggestion (no matching tags/keywords).

## Acceptance Criteria

- [AC-001] GIVEN a playbook `add-rest-endpoint` with required parameter `entity` WHEN `/forge-run --playbook=add-rest-endpoint entity=Task` is invoked THEN the pipeline receives an interpolated requirement containing "Task" and the playbook's config overrides are applied.
- [AC-002] GIVEN a playbook with parameter `operations` of type list with `allowed_values: [create,read,update,delete,list,search]` WHEN `operations=create,read,deploy` is provided THEN the invocation fails with `PLAYBOOK_PARAM_INVALID` citing "deploy" as not in allowed values.
- [AC-003] GIVEN a completed playbook run WHEN the retrospective executes THEN `.forge/playbook-analytics.json` is updated with incremented `run_count`, updated averages for score/iterations/duration/cost, and the current timestamp as `last_used`.
- [AC-004] GIVEN `/forge-playbooks` is invoked WHEN 3 playbooks exist (2 project, 1 built-in) with analytics THEN all 3 are listed with their description, run count, average score, and last used date.
- [AC-005] GIVEN a completed non-playbook run with requirement "Add REST API for Users with CRUD operations" WHEN post-run analysis executes THEN the run recap includes a playbook suggestion for `add-rest-endpoint` with confidence >= MEDIUM and relevant match signals.
- [AC-006] GIVEN `playbooks.auto_suggest: false` WHEN a pipeline run completes THEN no playbook suggestion appears in the run recap.
- [AC-007] GIVEN a project playbook and a built-in playbook with the same name WHEN the playbook is invoked THEN the project playbook is used and an INFO log notes the override.
- [AC-008] GIVEN a playbook with `acceptance_criteria` templates and F05 (living specs) is active WHEN the playbook is invoked THEN the interpolated acceptance criteria are registered in `.forge/specs/index.json` with AC-NNN identifiers.

## Migration Path

1. **v2.0.0**: Ship with `playbooks.enabled: true` by default. Include 7 built-in playbooks. Analytics tracking active from first use.
2. **v2.0.x**: Gather analytics from early adopters. Refine built-in playbook templates based on common findings patterns.
3. **v2.1.0**: Add `/forge-playbook-create` skill that generates a playbook from a completed pipeline run's requirement and configuration (reverse engineering a template from a successful run).
4. **v2.2.0**: Consider team-shared playbook repository (git submodule or registry) for organizations with multiple projects.

## Dependencies

| Dependency | Type | Required? |
|------------|------|-----------|
| `/forge-run` CLI argument parsing | Existing skill modification | Yes |
| fg-100-orchestrator config overlay logic | Agent modification | Yes |
| fg-700-retrospective analytics writing | Agent modification | Yes |
| fg-710-post-run auto-suggestion | Agent modification | Yes |
| `/forge-playbooks` (new skill) | New skill | Yes |
| `shared/playbooks/` directory (new) | New plugin directory | Yes |
| F05 living specs (AC registration) | Feature dependency | No (graceful: ACs not registered if F05 inactive) |
| YAML frontmatter parser | Existing capability | Yes (already used by agent frontmatter) |
