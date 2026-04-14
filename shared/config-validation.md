# Config Validation

Centralized validation for `forge-config.md` and `forge.local.md`. Replaces scattered inline checks with a standalone validator backed by JSON schemas.

## Architecture

```
shared/config-validator.sh          Standalone CLI validator
shared/config-diff.sh               Per-section change tracking
shared/schemas/
  forge-config-schema.json          JSON Schema for forge-config.md
  forge-local-schema.json           JSON Schema for forge.local.md
```

The validator is the single source of truth for config constraints. All consumers (PREFLIGHT, `config-validate` skill, `forge-init`) delegate to it.

## Validator Usage

```bash
# Validate a project
./shared/config-validator.sh /path/to/project

# Verbose (show OK results too)
./shared/config-validator.sh --verbose /path/to/project

# JSON output
./shared/config-validator.sh --json /path/to/project

# Check command executability
./shared/config-validator.sh --check-commands /path/to/project
```

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All validations passed |
| 1 | One or more CRITICAL or ERROR findings |
| 2 | Warnings only (no errors) |
| 3 | Input error (files not found, invalid arguments) |

## Validation Categories

### Category A: Required Fields (forge.local.md)

| Field | Required | Validation |
|-------|----------|-----------|
| `components.language` | Yes (unless `framework: k8s`) | Must be one of the 15 supported languages or null |
| `components.framework` | Yes | Must match a directory in `modules/frameworks/` |
| `components.testing` | Recommended | Must match a file in `modules/testing/` |
| `commands.build` | Yes | Non-empty string |
| `commands.test` | Yes | Non-empty string |
| `commands.lint` | Yes | Non-empty string |

### Category B: Range Constraints (forge-config.md)

| Field | Min | Max | Default | Source |
|-------|-----|-----|---------|--------|
| `scoring.critical_weight` | 10 | — | 20 | scoring.md |
| `scoring.warning_weight` | 1 | — | 5 | scoring.md |
| `scoring.info_weight` | 0 | < warning_weight | 2 | scoring.md |
| `scoring.pass_threshold` | 60 | 100 | 80 | scoring.md |
| `scoring.concerns_threshold` | 40 | < pass_threshold | 60 | scoring.md |
| `scoring.oscillation_tolerance` | 0 | 20 | 5 | scoring.md |
| `convergence.max_iterations` | 3 | 20 | 15 | scoring.md |
| `convergence.plateau_threshold` | 0 | 10 | 3 | scoring.md |
| `convergence.plateau_patience` | 1 | 5 | 3 | scoring.md |
| `convergence.target_score` | >= pass_threshold | 100 | 90 | scoring.md |
| `total_retries_max` | 5 | 30 | 10 | CLAUDE.md |
| `shipping.min_score` | >= pass_threshold | 100 | 90 | CLAUDE.md |
| `shipping.evidence_max_age_minutes` | 5 | 60 | 30 | verification-evidence.md |
| `sprint.poll_interval_seconds` | 10 | 120 | 30 | CLAUDE.md |
| `sprint.dependency_timeout_minutes` | 5 | 180 | 60 | CLAUDE.md |
| `tracking.archive_after_days` | 30 (or 0) | 365 | 90 | CLAUDE.md |
| `scope.decomposition_threshold` | 2 | 10 | 3 | CLAUDE.md |
| `routing.vague_threshold` | enum | enum | medium | CLAUDE.md |
| `model_routing.default_tier` | enum | enum | standard | model-routing.md |
| `infra.max_verification_tier` | 1 | 5 | 3 | CLAUDE.md |
| `preview.max_fix_loops` | 1 | 10 | 3 | CLAUDE.md |
| `cost_alerting.budget_ceiling_tokens` | 0 or 10000 | — | 2000000 | cost-alerting.sh |
| `context_guard.condensation_threshold` | 5000 | 100000 | 30000 | context-guard.sh |
| `context_guard.critical_threshold` | > condensation_threshold | — | 50000 | context-guard.sh |
| `context_guard.max_condensation_triggers` | 1 | 20 | 5 | context-guard.sh |

### Category B2: Boolean Constraints

| Field | Default | Source |
|-------|---------|--------|
| `cost_alerting.enabled` | `true` | cost-alerting.sh |
| `context_guard.enabled` | `true` | context-guard.sh |

### Category B3: Array/Enum Constraints

| Field | Valid Values | Default | Source |
|-------|-------------|---------|--------|
| `cost_alerting.alert_thresholds` | Array of 3 ascending floats in (0.0, 1.0) | `[0.50, 0.75, 0.90]` | cost-alerting.sh |
| `cost_alerting.per_stage_limits` | `"auto"` or object with 10 stage keys | `"auto"` | cost-alerting.sh |

### Category C: Cross-Field Constraints

| Constraint | Rule | Source |
|-----------|------|--------|
| Pass/concerns gap | `pass_threshold - concerns_threshold >= 10` | scoring.md |
| Weight ordering | `warning_weight > info_weight` | scoring.md |
| Target score floor | `convergence.target_score >= scoring.pass_threshold` | scoring.md |
| Shipping score floor | `shipping.min_score >= scoring.pass_threshold` | CLAUDE.md |
| Context guard threshold ordering | `context_guard.critical_threshold > context_guard.condensation_threshold` | context-guard.sh |

### Category D: Command Executability (optional)

When `--check-commands` is passed, the validator checks that configured commands are executable:
- Extracts the first word (binary name) from each command
- Checks if the binary exists (`command -v` for PATH, file existence for `./` paths)
- Reports CRITICAL if binary missing, WARNING if not executable

### Category E: Unknown Field Detection

Top-level YAML keys in `forge-config.md` that do not appear in the schema are flagged as WARNING. Simple prefix matching suggests close alternatives for likely typos.

### Framework-Component Compatibility

- `framework: k8s` expects `language: null`
- `framework: go-stdlib` expects `language: go`
- `framework: embedded` expects `language: c` or `language: cpp`

## Severity Levels

| Severity | Meaning | Effect |
|----------|---------|--------|
| CRITICAL | Configuration prevents pipeline operation | Exit code 1, pipeline should not start |
| ERROR | Configuration violates a documented constraint | Exit code 1, pipeline may malfunction |
| WARNING | Configuration is unusual or may indicate a mistake | Exit code 2, pipeline uses defaults |
| OK | Field passes validation | Exit code 0 (informational) |

## JSON Schemas

### forge-config-schema.json

Covers all forge-config.md parameters including:
- Core: `scoring`, `convergence`, `total_retries_max`, `shipping`
- Sprint: `sprint`, `tracking`, `scope`, `routing`
- Features: `model_routing`, `quality_gate`, `mutation_testing`, `visual_verification`
- Integrations: `lsp`, `observability`, `data_classification`, `graph`, `linear`
- UI: `frontend_polish`, `preview`, `infra`, `autonomous`
- v2.0 additions: `confidence`, `test_history`, `condensation`, `check_engine`, `code_graph`, `living_specs`, `events`, `playbooks`

Root-level `additionalProperties: true` allows project-specific extensions. Known sections use `additionalProperties: false` to catch typos within structured sections.

### forge-local-schema.json

Covers all forge.local.md parameters including:
- Required: `components` (with `framework`), `commands` (with `build`, `test`, `lint`)
- Components: all 15 languages, 21 frameworks, 19 testing frameworks
- Crosscutting: `database`, `migrations`, `api_protocol`, `messaging`, `caching`, `search`, `storage`, `auth`, `observability`, `build_system`, `ci`, `container`, `orchestrator`, `documentation`, `code_quality`
- File references: `conventions_file`, `conventions_variant`, `conventions_testing`, `conventions_web`, `conventions_persistence`, `language_file`, `preempt_file`, `config_file`

## Config Diff Usage

```bash
# Print human-readable diff
./shared/config-diff.sh /path/to/project

# Save snapshot without diffing
./shared/config-diff.sh --snapshot /path/to/project

# JSON diff output
./shared/config-diff.sh --json /path/to/project
```

### How Section Tracking Works

1. At PREFLIGHT, `config-diff.sh` parses `forge-config.md` into top-level sections
2. SHA-256 hash computed per section, stored in `.forge/config-hashes.json`
3. On next run, previous hashes are loaded, current hashes computed, delta reported
4. Field-level diff within changed sections identifies exactly what changed

### Change Attribution

| Attribution | How Detected |
|-------------|-------------|
| `retrospective` | `<!-- tuned by retrospective -->` comment present near the field |
| `user` | Field changed, no retrospective comment |
| `forge-init` | Entire file regenerated (all sections changed simultaneously) |

### Integration Points

- **Orchestrator (PREFLIGHT)**: Calls `config-diff.sh --json` and includes in stage notes
- **Retrospective (fg-700)**: Reads `.forge/config-hashes.json` to understand what it previously tuned vs user overrides
- **Convention drift**: Agents check section-level changes instead of whole-file hashes

## Integration Flow

```
forge-init generates config
       |
       v
config-validator.sh validates generated config
       |
       v
config-diff.sh --snapshot saves initial hashes
       |
       v
/forge-run starts pipeline
       |
       v
PREFLIGHT: config-validator.sh --json validates
PREFLIGHT: config-diff.sh --json reports changes
       |
       v
Pipeline runs...
       |
       v
Retrospective auto-tunes forge-config.md
       |
       v
Next run: config-diff.sh detects retrospective changes
```

## Dependencies

- Python 3 (already a prerequisite per `check-prerequisites.sh`)
- No external Python packages (uses inline YAML parser, not PyYAML)
- `shared/platform.sh` for cross-platform helpers
