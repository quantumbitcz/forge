# Q09: Config Validation Centralization

## Status
DRAFT — 2026-04-13

## Problem Statement

Configuration scored A- (90/100) in the system review. Three issues prevent reaching A+:

1. **No standalone schema validation tool.** PREFLIGHT performs inline config validation, but the checks are scattered across the orchestrator's stage 0 logic. There is no standalone script that can validate `forge-config.md` and `forge.local.md` independently of the pipeline. The `config-validate` skill exists but delegates to PREFLIGHT-like logic without a centralized validator. A developer cannot run `./shared/config-validator.sh /path/to/.claude/` to check their config before invoking the pipeline.

2. **No formal JSON schemas.** Config validation rules are documented in prose across `CLAUDE.md`, `scoring.md`, `convergence-engine.md`, `state-transitions.md`, and mode overlay files. There is no machine-readable schema that enumerates all valid fields, types, ranges, and defaults. This makes it impossible to write exhaustive validation or detect typos in config field names.

3. **No diff-based config change detection.** Convention drift is tracked via whole-file SHA-256 hash comparison. When the retrospective auto-tunes `forge-config.md`, the only detection is "file changed." There is no per-section tracking to know which specific values were modified, making it hard to audit what the retrospective changed versus what the user changed.

## Target
Configuration A- -> A+ (90 -> 97+)

## Detailed Changes

### 1. Centralized Config Validator Script

**New file:** `shared/config-validator.sh`

A standalone bash script that validates forge configuration files and reports errors in a structured format.

#### Interface

```bash
# Validate a project's config files
./shared/config-validator.sh /path/to/project/.claude/

# Validate with verbose output
./shared/config-validator.sh --verbose /path/to/project/.claude/

# Validate and output JSON report
./shared/config-validator.sh --json /path/to/project/.claude/

# Exit codes:
#   0 — all validations passed
#   1 — one or more errors (CRITICAL or ERROR severity)
#   2 — warnings only (no errors)
#   3 — input error (files not found, invalid args)
```

#### Validation Categories

The validator checks both `forge-config.md` and `forge.local.md` in a single invocation.

**Category A: Required fields (forge.local.md)**

| Field | Required | Validation |
|-------|----------|-----------|
| `components.language` | Yes (unless `framework: k8s`) | Must be one of the 15 supported languages or `~` |
| `components.framework` | Yes | Must match a directory in `modules/frameworks/` |
| `components.testing` | Yes (unless `framework: k8s`) | Must match a file in `modules/testing/` |
| `commands.build` | Yes | Non-empty string |
| `commands.test` | Yes | Non-empty string |
| `commands.lint` | Yes | Non-empty string |

**Category B: Range constraints (forge-config.md)**

These constraints are currently documented across multiple files. The validator centralizes them:

| Field | Min | Max | Default | Source Document |
|-------|-----|-----|---------|----------------|
| `scoring.critical_weight` | 10 | - | 20 | scoring.md |
| `scoring.warning_weight` | 1 | - | 5 | scoring.md |
| `scoring.info_weight` | 0 | `< warning_weight` | 2 | scoring.md |
| `scoring.pass_threshold` | 60 | 100 | 80 | scoring.md |
| `scoring.concerns_threshold` | 40 | `< pass_threshold` | 60 | scoring.md |
| `scoring.oscillation_tolerance` | 0 | 20 | 5 | scoring.md |
| `convergence.max_iterations` | 3 | 20 | 15 | scoring.md |
| `convergence.plateau_threshold` | 0 | 10 | 3 | scoring.md |
| `convergence.plateau_patience` | 1 | 5 | 3 | scoring.md |
| `convergence.target_score` | `>= pass_threshold` | 100 | 90 | scoring.md |
| `total_retries_max` | 5 | 30 | 10 | CLAUDE.md |
| `shipping.min_score` | `>= pass_threshold` | 100 | 90 | CLAUDE.md |
| `shipping.evidence_max_age_minutes` | 5 | 60 | 30 | verification-evidence.md |
| `sprint.poll_interval_seconds` | 10 | 120 | 30 | CLAUDE.md |
| `sprint.dependency_timeout_minutes` | 5 | 180 | 60 | CLAUDE.md |
| `tracking.archive_after_days` | 30 (or 0) | 365 | 90 | CLAUDE.md |
| `scope.decomposition_threshold` | 2 | 10 | 3 | CLAUDE.md |
| `automations[].cooldown_minutes` | 1 | - | - | automations.md |
| `model_routing.default_tier` | enum | enum | `standard` | model-routing.md |

**Category C: Cross-field constraints**

| Constraint | Rule | Source |
|-----------|------|--------|
| Pass/concerns gap | `pass_threshold - concerns_threshold >= 10` | scoring.md |
| Weight ordering | `warning_weight > info_weight` | scoring.md |
| Target score floor | `convergence.target_score >= scoring.pass_threshold` | scoring.md |
| Shipping score floor | `shipping.min_score >= scoring.pass_threshold` | CLAUDE.md |
| Component path uniqueness | No two components share the same `path:` value | Implicit |
| Test command consistency | `test_gate.command` matches `commands.test` | base-template.md |

**Category D: Command executability (optional, with `--check-commands` flag)**

When `--check-commands` is passed, the validator checks that configured commands are executable:

```bash
# For each command (build, test, lint, format):
#   1. Check if the binary exists (which/command -v)
#   2. Run with --help or --version to verify it responds
#   3. Report CRITICAL if binary missing, WARNING if --help fails
```

This is optional because it requires the project's dependencies to be installed.

**Category E: Unknown field detection**

Any YAML key in `forge-config.md` or `forge.local.md` that does not appear in the schema is flagged as WARNING (potential typo). This catches common errors like `oscillation_toleranec` instead of `oscillation_tolerance`.

#### Output Format

**Human-readable (default):**

```
CRITICAL  forge-config.md  scoring.pass_threshold  Value 50 is below minimum 60
WARNING   forge-config.md  scoring.oscilation_tol   Unknown field (did you mean oscillation_tolerance?)
ERROR     forge.local.md   commands.build           Empty value — build command is required
OK        forge.local.md   components.framework     Value "spring" is valid
```

**JSON (with `--json`):**

```json
{
  "validator_version": "1.0.0",
  "timestamp": "2026-04-13T10:00:00Z",
  "files_checked": ["forge-config.md", "forge.local.md"],
  "results": [
    {
      "severity": "CRITICAL",
      "file": "forge-config.md",
      "field": "scoring.pass_threshold",
      "value": 50,
      "expected": ">= 60",
      "message": "Value 50 is below minimum 60"
    }
  ],
  "summary": {
    "critical": 1,
    "error": 0,
    "warning": 1,
    "ok": 15
  }
}
```

#### Integration with Existing Systems

- **config-validate skill:** Update the skill to invoke `shared/config-validator.sh` instead of inline validation logic.
- **PREFLIGHT:** Orchestrator calls `shared/config-validator.sh --json` at stage 0. If the validator returns exit code 1 (errors), PREFLIGHT logs the errors and uses defaults for invalid fields (existing behavior). If exit code 0 or 2, proceed normally.
- **forge-init:** After generating config files, run `shared/config-validator.sh` to verify the generated config is valid.

### 2. JSON Schemas for Config Files

**New files:**
- `shared/schemas/forge-config-schema.json`
- `shared/schemas/forge-local-schema.json`

These schemas serve as the machine-readable single source of truth for config validation. The validator script (`config-validator.sh`) reads these schemas at runtime.

#### forge-config-schema.json (excerpt)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "forge-config-schema",
  "title": "Forge Config Schema",
  "description": "Schema for .claude/forge-config.md YAML frontmatter",
  "type": "object",
  "properties": {
    "scoring": {
      "type": "object",
      "properties": {
        "critical_weight": {
          "type": "integer",
          "minimum": 10,
          "default": 20,
          "description": "Point deduction per CRITICAL finding"
        },
        "warning_weight": {
          "type": "integer",
          "minimum": 1,
          "default": 5,
          "description": "Point deduction per WARNING finding"
        },
        "info_weight": {
          "type": "integer",
          "minimum": 0,
          "default": 2,
          "description": "Point deduction per INFO finding"
        },
        "pass_threshold": {
          "type": "integer",
          "minimum": 60,
          "maximum": 100,
          "default": 80,
          "description": "Minimum score for PASS verdict"
        },
        "concerns_threshold": {
          "type": "integer",
          "minimum": 40,
          "default": 60,
          "description": "Minimum score for CONCERNS verdict"
        },
        "oscillation_tolerance": {
          "type": "integer",
          "minimum": 0,
          "maximum": 20,
          "default": 5,
          "description": "Maximum allowed score regression before escalation"
        }
      },
      "additionalProperties": false
    },
    "convergence": {
      "type": "object",
      "properties": {
        "max_iterations": {
          "type": "integer",
          "minimum": 3,
          "maximum": 20,
          "default": 15
        },
        "plateau_threshold": {
          "type": "integer",
          "minimum": 0,
          "maximum": 10,
          "default": 3
        },
        "plateau_patience": {
          "type": "integer",
          "minimum": 1,
          "maximum": 5,
          "default": 3
        },
        "target_score": {
          "type": "integer",
          "minimum": 60,
          "maximum": 100,
          "default": 90
        }
      },
      "additionalProperties": false
    },
    "total_retries_max": {
      "type": "integer",
      "minimum": 5,
      "maximum": 30,
      "default": 10
    },
    "shipping": {
      "type": "object",
      "properties": {
        "min_score": {
          "type": "integer",
          "minimum": 60,
          "maximum": 100,
          "default": 90
        },
        "evidence_max_age_minutes": {
          "type": "integer",
          "minimum": 5,
          "maximum": 60,
          "default": 30
        }
      }
    }
  },
  "additionalProperties": true
}
```

**Note:** `additionalProperties: true` at the root level allows project-specific extensions. Only known sections have `additionalProperties: false` to catch typos within those sections. The unknown field detection in the validator script handles root-level unknown fields.

#### forge-local-schema.json (excerpt)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "forge-local-schema",
  "title": "Forge Local Schema",
  "description": "Schema for .claude/forge.local.md YAML frontmatter",
  "type": "object",
  "required": ["components", "commands"],
  "properties": {
    "components": {
      "type": "object",
      "required": ["framework"],
      "properties": {
        "language": {
          "type": ["string", "null"],
          "enum": ["kotlin", "java", "typescript", "python", "go", "rust", "swift", "c", "csharp", "ruby", "php", "dart", "elixir", "scala", "cpp", null]
        },
        "framework": {
          "type": "string",
          "description": "Must match a directory in modules/frameworks/"
        },
        "testing": {
          "type": ["string", "null"]
        },
        "variant": { "type": ["string", "null"] },
        "persistence": { "type": ["string", "null"] },
        "web": { "type": ["string", "null"] }
      }
    },
    "commands": {
      "type": "object",
      "required": ["build", "test", "lint"],
      "properties": {
        "build": { "type": "string", "minLength": 1 },
        "test": { "type": "string", "minLength": 1 },
        "lint": { "type": "string", "minLength": 1 },
        "format": { "type": "string" },
        "test_single": { "type": "string" },
        "build_timeout": { "type": "integer", "minimum": 30, "maximum": 600, "default": 120 },
        "test_timeout": { "type": "integer", "minimum": 60, "maximum": 1800, "default": 300 },
        "lint_timeout": { "type": "integer", "minimum": 10, "maximum": 300, "default": 60 }
      }
    }
  }
}
```

#### YAML Parsing Strategy

The validator extracts YAML frontmatter from markdown files and validates against JSON schema:

1. Extract content between `---` delimiters (YAML frontmatter)
2. Parse YAML to JSON using Python (`import yaml, json`)
3. Validate JSON against the appropriate schema using Python `jsonschema` (stdlib-compatible validation if jsonschema not installed, else use it for richer error messages)
4. Apply cross-field constraints that cannot be expressed in JSON Schema

The validator requires Python 3 (already a prerequisite per `check-prerequisites.sh`). It uses only stdlib modules (`yaml` is commonly available; if not, a minimal YAML-to-dict parser handles the subset of YAML used in forge configs).

### 3. Diff-Based Config Change Detection

**New file:** `shared/config-diff.sh`

Tracks per-section changes to `forge-config.md` across pipeline runs, replacing the whole-file SHA-256 approach with granular section tracking.

#### How It Works

1. **At PREFLIGHT:** Parse `forge-config.md` into sections (top-level YAML keys). Compute SHA-256 hash per section. Store in `.forge/.config-hashes.json`:

```json
{
  "timestamp": "2026-04-13T10:00:00Z",
  "file_hash": "abc123...",
  "sections": {
    "scoring": { "hash": "def456...", "value_snapshot": { "critical_weight": 20, "pass_threshold": 80 } },
    "convergence": { "hash": "ghi789...", "value_snapshot": { "max_iterations": 15, "target_score": 90 } },
    "total_retries_max": { "hash": "jkl012...", "value_snapshot": 10 },
    "shipping": { "hash": "mno345...", "value_snapshot": { "min_score": 90 } }
  }
}
```

2. **At next PREFLIGHT:** Load previous `.config-hashes.json`, compute current section hashes, diff:

```json
{
  "changes": [
    {
      "section": "scoring",
      "field": "pass_threshold",
      "previous": 80,
      "current": 85,
      "changed_by": "unknown"
    }
  ],
  "unchanged_sections": ["convergence", "total_retries_max", "shipping"]
}
```

3. **Attribution:** If the change was made by the retrospective (auto-tuning), the retrospective writes a `<!-- tuned by retrospective: {run_id} -->` comment in `forge-config.md` next to the changed field. The diff tool checks for this comment to attribute changes:

| Attribution | How detected |
|-------------|-------------|
| `retrospective` | `<!-- tuned by retrospective -->` comment present near the field |
| `user` | Field changed, no retrospective comment |
| `forge-init` | Entire file regenerated (all sections changed simultaneously) |

4. **Reporting:** The config diff is included in stage 0 notes for the current run and is available to the retrospective for trend analysis:

```
[INFO] [config-diff] forge-config.md changes since last run:
  - scoring.pass_threshold: 80 -> 85 (changed by: retrospective, run: 2026-04-12)
  - convergence.target_score: 90 -> 95 (changed by: user)
```

#### Integration

- **Retrospective (fg-700):** Reads `.forge/.config-hashes.json` to understand what it previously tuned and what the user overrode. This prevents the retrospective from repeatedly auto-tuning a value the user intentionally changed.
- **Convention drift detection:** Replace the current whole-file SHA-256 check with section-level checks. Agents react only to changes in their relevant sections.
- **`<!-- locked -->` fence interaction:** Sections within `<!-- locked -->` fences are excluded from retrospective auto-tuning (existing behavior). The diff tool marks locked sections as `"locked": true` in the output, confirming they were not changed.

### 4. Config Validation Bats Test

**New file:** `tests/structural/config-schema-validation.bats`

Validates the JSON schemas themselves are complete and consistent.

```bash
@test "forge-config-schema.json is valid JSON Schema" {
  python3 -c "
import json
with open('$PLUGIN_ROOT/shared/schemas/forge-config-schema.json') as f:
    schema = json.load(f)
assert '\$schema' in schema, 'Missing \$schema field'
assert 'properties' in schema, 'Missing properties field'
"
}

@test "forge-config-schema covers all documented scoring constraints" {
  python3 -c "
import json
with open('$PLUGIN_ROOT/shared/schemas/forge-config-schema.json') as f:
    schema = json.load(f)
scoring = schema['properties']['scoring']['properties']
required_fields = ['critical_weight', 'warning_weight', 'info_weight', 'pass_threshold', 'concerns_threshold', 'oscillation_tolerance']
for field in required_fields:
    assert field in scoring, f'Missing scoring field: {field}'
"
}

@test "forge-config-schema covers all documented convergence constraints" {
  python3 -c "
import json
with open('$PLUGIN_ROOT/shared/schemas/forge-config-schema.json') as f:
    schema = json.load(f)
conv = schema['properties']['convergence']['properties']
required_fields = ['max_iterations', 'plateau_threshold', 'plateau_patience', 'target_score']
for field in required_fields:
    assert field in conv, f'Missing convergence field: {field}'
"
}

@test "forge-local-schema.json is valid JSON Schema" {
  python3 -c "
import json
with open('$PLUGIN_ROOT/shared/schemas/forge-local-schema.json') as f:
    schema = json.load(f)
assert '\$schema' in schema
assert 'components' in schema.get('required', [])
assert 'commands' in schema.get('required', [])
"
}

@test "forge-local-schema language enum matches discovered languages" {
  # Verify the language enum in the schema matches actual language modules
  python3 -c "
import json, os
with open('$PLUGIN_ROOT/shared/schemas/forge-local-schema.json') as f:
    schema = json.load(f)
schema_langs = set(schema['properties']['components']['properties']['language'].get('enum', []))
schema_langs.discard(None)  # null is allowed
disk_langs = set()
for f in os.listdir('$PLUGIN_ROOT/modules/languages/'):
    if f.endswith('.md'):
        disk_langs.add(f[:-3])
missing = disk_langs - schema_langs
assert not missing, f'Languages on disk but not in schema: {missing}'
"
}
```

## Testing Approach

1. **Validator functional test:** Create a test config directory with intentionally invalid values. Run `config-validator.sh` and verify it reports the expected errors.

2. **Validator happy path test:** Run `config-validator.sh` against each framework's `forge-config-template.md` and `local-template.md`. All should pass (or produce only warnings for template placeholder values).

3. **Schema completeness test:** The bats tests above verify schemas cover all documented constraints.

4. **Config diff test:** Write a `.config-hashes.json` file, modify a config value, run `config-diff.sh`, verify the diff output identifies the changed section and field.

5. **Integration test:** Run `config-validate` skill end-to-end on a test project with known config issues.

## Acceptance Criteria

- [ ] `shared/config-validator.sh` exists, is executable, and validates both `forge-config.md` and `forge.local.md`
- [ ] Validator checks required fields, range constraints, cross-field constraints, and unknown fields
- [ ] Validator supports `--json` output format and `--check-commands` optional flag
- [ ] Validator exit codes: 0 (pass), 1 (errors), 2 (warnings only), 3 (input error)
- [ ] `shared/schemas/forge-config-schema.json` exists and covers all documented config parameters
- [ ] `shared/schemas/forge-local-schema.json` exists and covers all documented local config parameters
- [ ] Language enum in schema matches discovered languages on disk
- [ ] `shared/config-diff.sh` exists and tracks per-section config changes
- [ ] Config diff attributes changes to retrospective, user, or forge-init
- [ ] Diff output is included in PREFLIGHT stage notes
- [ ] `config-validate` skill updated to use centralized validator
- [ ] `tests/structural/config-schema-validation.bats` exists and passes
- [ ] All existing `validate-plugin.sh` checks continue to pass

## Effort Estimate

Large (5-6 days). The validator script and JSON schemas require careful enumeration of all config fields across multiple source documents.

- JSON schemas: 2 days (enumeration of all fields from scoring.md, convergence-engine.md, CLAUDE.md, automations.md, etc.)
- config-validator.sh: 1.5 days (YAML parsing, schema validation, cross-field checks, output formatting)
- config-diff.sh: 1 day (section parsing, hash comparison, attribution)
- Tests: 0.5 day
- config-validate skill update: 0.5 day
- Integration testing: 0.5 day

## Dependencies

- Requires Python 3 (already a prerequisite)
- The JSON schemas should be reviewed against all source documents to ensure completeness. A gap in the schema means a config field that can be misconfigured without detection.
- Q06 (mode overlay expansion) adds new convergence parameters that must be included in the schema
- The `config-validate` skill update depends on the validator script being ready
- No other Q-series dependencies
