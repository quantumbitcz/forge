# Playbooks -- Reusable Task Templates

Playbooks are user-defined task templates that encode "how we do X" as parameterized requirement templates with config overrides. They feed into the existing `/forge run` pipeline -- they are requirement generation + config overlay, not a separate orchestration path.

## Playbook File Format

### Location

- **Project playbooks:** `.claude/forge-admin playbooks/{name}.md`
- **Built-in playbooks:** `shared/playbooks/{name}.md` (shipped with plugin)

Resolution order: project playbooks override built-in playbooks with the same name.

### Structure

A playbook is a markdown file with YAML frontmatter:

```yaml
---
name: my-playbook           # Must match filename (sans .md), kebab-case
description: What this playbook does
version: "1.0"              # Playbook version for analytics tracking
mode: standard              # Pipeline mode override (optional)
parameters:
  - name: entity
    description: The domain entity name
    type: string
    required: true
    validation: "^[A-Z][a-zA-Z]+$"
  - name: operations
    description: Operations to support
    type: list
    default: [create, read, update, delete]
    allowed_values: [create, read, update, delete, list, search]
stages:
  skip: []                  # Stages to skip (safety restriction applies)
  focus:
    REVIEWING:
      review_agents: [fg-410-code-reviewer, fg-411-security-reviewer]
review:
  focus_categories: ["ARCH-*", "SEC-*", "TEST-*"]
  min_score: 90
scoring:
  critical_weight: 20
  warning_weight: 5
acceptance_criteria:
  - "GIVEN valid {{entity}} data WHEN POST /api/{{entity | kebab-case}}s THEN returns 201"
tags: [api, backend]
---

## Requirement Template

Implement a REST API endpoint for **{{entity}}** supporting **{{operations | join:", "}}** operations.
```

### Frontmatter Schema

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | yes | Unique playbook identifier (kebab-case, matches filename) |
| `description` | string | yes | Human-readable description |
| `version` | string | no | Playbook version for tracking (default: "1.0") |
| `mode` | string | no | Pipeline mode override (default: inherits from project config) |
| `parameters` | array | no | Parameter definitions (empty = no parameters) |
| `parameters[].name` | string | yes | Parameter name (snake_case) |
| `parameters[].description` | string | yes | Human-readable parameter description |
| `parameters[].type` | enum | yes | `string`, `list`, `enum`, `boolean`, `integer` |
| `parameters[].required` | boolean | no | Whether parameter must be provided (default: false) |
| `parameters[].default` | any | no | Default value if not provided |
| `parameters[].validation` | string | no | Regex pattern for string type validation |
| `parameters[].allowed_values` | array | no | Valid values for enum and list types |
| `stages` | object | no | Stage-level configuration overrides |
| `stages.skip` | string[] | no | Stages to skip |
| `stages.focus` | object | no | Per-stage configuration (e.g., specific review agents) |
| `review` | object | no | Review configuration overrides |
| `review.focus_categories` | string[] | no | Finding categories to prioritize |
| `review.min_score` | integer | no | Minimum quality score for this playbook |
| `scoring` | object | no | Scoring overrides (same schema as `forge-config.md` scoring) |
| `acceptance_criteria` | string[] | no | Acceptance criteria templates (interpolated with parameters) |
| `tags` | string[] | no | Tags for categorization and auto-suggestion matching |

## Parameter Interpolation

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

The interpolation engine handles the patterns above and nothing more. Complex logic belongs in the playbook's prose, not in template syntax.

## Invocation

```bash
/forge run --playbook=add-rest-endpoint entity=Task operations=create,read
```

### Invocation Flow

1. **PARSE:** Read `.claude/forge-admin playbooks/{name}.md`. If not found, check `shared/playbooks/{name}.md` (built-in). If not found: error `PLAYBOOK_NOT_FOUND`.
2. **VALIDATE PARAMETERS:** Check required params present, type-check values, parse lists, validate against `allowed_values` and `validation` regex, apply defaults.
3. **INTERPOLATE TEMPLATE:** Replace `{{param}}` placeholders, expand `{{#each}}` blocks, evaluate `{{#if}}` conditionals.
4. **INTERPOLATE ACCEPTANCE CRITERIA:** Apply same interpolation to `acceptance_criteria` list.
5. **OVERLAY CONFIG:** Merge `playbook.scoring` over `forge-config.md` scoring, merge `playbook.review` over review settings, merge `playbook.stages` over stage settings. Store overlay source in `state.json`.
6. **DISPATCH /forge run:** Feed interpolated requirement text + merged config to normal pipeline.
7. **ON COMPLETION (LEARN stage):** `fg-700-retrospective` updates `.forge/playbook-analytics.json`. `fg-710-post-run` checks for playbook suggestion opportunity.

### Config Overlay Resolution

```
playbook overrides > forge-config.md values > plugin defaults
```

The overlay is scoped to the current run. It does not modify `forge-config.md` on disk. The orchestrator records the overlay in `state.json`:

```json
{
  "playbook": {
    "name": "add-rest-endpoint",
    "version": "1.0",
    "parameters": { "entity": "Task", "operations": ["create", "read"] },
    "config_overrides": {
      "review.focus_categories": ["ARCH-*", "SEC-*", "TEST-*"],
      "review.min_score": 90
    }
  }
}
```

## Discovery

`/forge-admin playbooks` lists all available playbooks (project + built-in) with:
- Name and description
- Run count, average score, last used date (from analytics)
- Parameter list with types and defaults

## Analytics Tracking

Per-playbook analytics are stored in `.forge/playbook-analytics.json`. Updated by `fg-700-retrospective` after each playbook run. Schema: `shared/schemas/playbook-analytics-schema.json`.

Tracked metrics per playbook:
- `run_count`, `success_count`, `fail_count`
- `avg_score`, `avg_iterations`, `avg_duration_seconds`, `avg_cost_usd`
- `last_used` (ISO 8601)
- `parameter_frequency` (top 5 values + "other" per parameter)
- `common_findings` (recurring finding categories with counts)
- `version_history` (per-version run stats)

## Auto-Suggestion

After a non-playbook pipeline run, `fg-710-post-run` compares the completed run's requirement against available playbooks using:
- Tag matching (requirement keywords vs playbook tags)
- Description matching (fuzzy match)
- Template keyword matching (extracted nouns)
- AC pattern matching (implied acceptance criteria patterns)

Scoring: >= 10 = HIGH, >= 5 = MEDIUM, >= 2 = LOW. Suggestions below `playbooks.suggestion_confidence_threshold` (config, default MEDIUM) are suppressed.

Suggestion data is appended to the run recap:

```json
{
  "playbook_suggestion": {
    "suggested_playbook": "add-rest-endpoint",
    "confidence": "HIGH",
    "match_signals": ["tag match: rest", "description match", "3 AC patterns match"],
    "estimated_savings": "~30% fewer iterations based on playbook history"
  }
}
```

## Safety Constraints

### Stage Skip Restrictions

`stages.skip` MUST NOT include `VERIFYING`, `REVIEWING`, or `SHIPPING`. These are safety-critical stages. Attempting to skip them produces a CRITICAL validation error and the playbook is rejected at PREFLIGHT.

### Scoring Override Validation

Playbook `scoring` overrides are validated against PREFLIGHT constraints:
- `critical_weight >= 10`
- `warning_weight >= 1`
- `warning_weight > info_weight`
- `info_weight >= 0`

Playbooks cannot weaken scoring below project minimums.

### Review Score Validation

Playbook `review.min_score` must be >= project's `pass_threshold`. If lower, PREFLIGHT uses the project's `pass_threshold` as the minimum and logs a WARNING.

## Configuration

In `forge-config.md`:

```yaml
playbooks:
  enabled: true                           # Master toggle (default: true)
  directory: ".claude/forge-admin playbooks"    # Playbook directory (default: .claude/forge-admin playbooks)
  suggestion_confidence_threshold: MEDIUM # Minimum confidence for suggestions (LOW/MEDIUM/HIGH)
```

## Built-In Playbooks

The plugin ships with playbooks in `shared/playbooks/`. Available when `playbooks.enabled: true` (default). Teams can override any built-in by creating a file with the same name in `.claude/forge-admin playbooks/`.

| Playbook | Description | Key Parameters |
|----------|-------------|----------------|
| `add-rest-endpoint` | Add a REST API endpoint with tests, validation, docs | `entity`, `operations`, `auth`, `pagination` |
| `fix-flaky-test` | Investigate and fix a flaky test | `test_name`, `test_file`, `flaky_behavior` |
| `add-db-migration` | Add a database migration with rollback | `entity`, `change_type`, `target_db` |
| `implement-webhook` | Implement a webhook handler with validation | `direction`, `event_type`, `payload_format` |
| `refactor-extract-service` | Extract a service from existing code | `source_class`, `target_service`, `extraction_type` |

## Error Handling

| Scenario | Error Code | Behavior |
|----------|------------|----------|
| Playbook file not found | `PLAYBOOK_NOT_FOUND` | List available playbooks |
| Required parameter missing | `PLAYBOOK_PARAM_MISSING` | List missing params with descriptions |
| Parameter fails validation | `PLAYBOOK_PARAM_INVALID` | Show constraint and provided value |
| Invalid YAML frontmatter | `PLAYBOOK_PARSE_ERROR` | Show YAML error location |
| Name does not match filename | WARNING | Use filename as canonical name |
| Invalid stage in `stages.skip` | WARNING | Ignore invalid skip entry |
| `review.min_score` < `pass_threshold` | WARNING | Use project `pass_threshold` as minimum |
| Template interpolation produces empty result | `PLAYBOOK_TEMPLATE_EMPTY` | Check parameters and conditionals |
| Analytics file corrupt | WARNING | Rebuild from empty state, historical analytics lost |
| Same name in project and built-in dirs | INFO | Project playbook wins |

## Integration Points

| System | Integration | Direction |
|--------|-------------|-----------|
| `/forge run` | Playbook parsed and interpolated at entry | Read |
| `fg-100-orchestrator` | Config overlay applied at PREFLIGHT | Read |
| `fg-200-planner` | Receives interpolated requirement (transparent) | Consumer |
| `fg-700-retrospective` | Updates playbook analytics | Write |
| `fg-710-post-run` | Auto-suggestion after non-playbook runs | Read |
| `forge-config.md` | Playbook scoring/review overrides merged | Read |
| `/forge-admin playbooks` skill | Lists playbooks with analytics | Read |

## Component Ownership

| Component | Owner | Responsibility |
|-----------|-------|----------------|
| Playbook parser | `fg-100-orchestrator` | Parse frontmatter, validate params, interpolate template |
| Config overlay | `fg-100-orchestrator` | Merge playbook config with project config at PREFLIGHT |
| Analytics tracker | `fg-700-retrospective` | Update analytics after each playbook run |
| `/forge-admin playbooks` skill | Skill | List playbooks with stats |
| Auto-suggestion | `fg-710-post-run` | Suggest playbook usage after runs |
| Built-in playbooks | Plugin distribution | Ship with forge in `shared/playbooks/` |

## Self-Improvement

Playbooks improve over time based on pipeline run outcomes. The retrospective agent (`fg-700`) analyzes each playbook run and generates refinement proposals.

### How It Works

1. After each run using a playbook, the retrospective computes refinement suggestions
2. Suggestions accumulate in `run-history.db` (`playbook_runs.refinement_suggestions`)
3. When 3+ runs of the same playbook exist, suggestions are aggregated
4. Proposals with sufficient agreement (default 66%) become `ready`
5. Ready proposals are written to `.forge/playbook-refinements/{playbook_id}.json`

### Refinement Categories

| Category | What It Detects | What It Proposes |
|----------|----------------|------------------|
| Scoring gap | Runs consistently below `pass_threshold` | Acceptance criteria addressing top deduction categories |
| Stage focus | Non-focused stages consuming >25% wall time | Adding stage to `stages_focus` |
| Acceptance gap | Finding categories not covered by criteria | New acceptance criterion |
| Parameter default | Same parameter value in 80%+ of runs | Updated default value |

### Philosophy

**Make the code meet the bar, never move the bar to meet the code.**

Refinements always push quality up — adding preventive criteria, fixing blind spots, improving focus. They never lower thresholds, suppress findings, or remove safety stages.

### Applying Refinements

**Manual (default):** Review and apply via `/forge-admin refine [playbook_id]`

**Auto-apply (opt-in):** Set `playbooks.auto_refine: true` in `forge-config.md`. Only HIGH confidence proposals are auto-applied (max 2 per run). Changes are logged with `[AUTO-REFINE]` marker.

**Rollback:** If a refined playbook's next run scores >10 points below the pre-refinement average, changes are automatically reverted and logged with `[REFINE-ROLLBACK]`.

### File Locations

- Proposals: `.forge/playbook-refinements/{playbook_id}.json` (survives `/forge-admin recover reset`)
- Schema: `shared/schemas/playbook-refinement-schema.json`
- Analytics: `.forge/playbook-analytics.json` (version history for rollback)

### Configuration

```yaml
playbooks:
  auto_refine: false              # Auto-apply HIGH confidence refinements
  refine_min_runs: 3              # Minimum runs before proposing
  refine_agreement: 0.66          # Agreement threshold (0.5-1.0)
  max_auto_refines_per_run: 2     # Cap on automatic changes
  rollback_threshold: 10          # Score regression triggering rollback
  max_rollbacks_before_reject: 2  # Permanent rejection after N rollbacks
```

### Auto-Apply File Rules

Auto-apply only modifies project-level playbooks in `.claude/forge-admin playbooks/`. If a built-in playbook (in `shared/playbooks/`) has refinement proposals, auto-apply first copies it to `.claude/forge-admin playbooks/` (creating a project override), then applies refinements to the project copy. The plugin directory is never modified.
