# F22: AI/ML Pipeline Support Modules

## Status
DRAFT — 2026-04-13 (Forward-Looking)

## Problem Statement

Forge supports 15 languages, 21 frameworks, and 19 test frameworks -- all targeting traditional software development. The AI/ML ecosystem is absent: no modules for model training frameworks (MLflow, W&B, SageMaker), no data pipeline conventions (Airflow, Dagster, dbt), no data version control (DVC), and no ML-specific quality checks. This is a growing gap:

1. **Model versioning:** Teams commit large model files without LFS, embed training configs without reproducibility metadata, and lack convention enforcement for experiment tracking. Forge's check engine has no L1 patterns for these issues.
2. **Data pipeline testing:** Airflow DAGs, dbt models, and Dagster assets are code but follow fundamentally different patterns from application code. Forge's reviewers do not understand DAG structure, idempotency requirements, or data quality assertions.
3. **Experiment reproducibility:** Training scripts without fixed seeds, pinned dependency versions, or logged hyperparameters produce non-reproducible results. No forge agent catches this.
4. **Large file management:** Models and datasets committed to git without LFS or DVC tracking bloat repositories. Forge's security reviewers detect secrets but not large binary files.

Competitive validation: CML (Iterative.ai) provides CI/CD for ML but is CI-specific, not editor-integrated. MLflow and W&B have VS Code extensions but no autonomous pipeline integration. No existing tool combines convention enforcement, quality review, and autonomous pipeline execution for ML projects.

## Proposed Solution

Add two new module layers -- `modules/ml-ops/` for ML operations frameworks and `modules/data-pipelines/` for data transformation and orchestration. Each module follows forge's existing module structure (`conventions.md`, `rules-override.json`, optional `known-deprecations.json`). Four new finding categories (`ML-VERSION`, `ML-REPRO`, `ML-DATA`, `ML-PIPELINE`) integrate with the existing scoring formula. Auto-detection at PREFLIGHT loads modules based on config files and dependency manifests.

## Detailed Design

### Architecture

```
modules/
  ml-ops/
    COMPOSITION.md                  # Layer composition rules
    mlflow/
      conventions.md                # Experiment tracking, model registry, deployment
      rules-override.json           # L1 patterns for MLflow conventions
      known-deprecations.json       # MLflow API deprecations (v2 schema)
    dvc/
      conventions.md                # Data version control, pipeline definitions
      rules-override.json           # L1 patterns for DVC conventions
    wandb/
      conventions.md                # Experiment tracking, sweeps, artifacts
      rules-override.json           # L1 patterns for W&B conventions
    sagemaker/
      conventions.md                # Training jobs, endpoints, pipelines
      rules-override.json           # L1 patterns for SageMaker conventions
      known-deprecations.json       # SageMaker SDK deprecations (v2 schema)
  data-pipelines/
    COMPOSITION.md                  # Layer composition rules
    airflow/
      conventions.md                # DAG conventions, operator patterns, testing
      rules-override.json           # L1 patterns for Airflow conventions
      known-deprecations.json       # Airflow provider deprecations (v2 schema)
    dagster/
      conventions.md                # Asset-based pipeline conventions
      rules-override.json           # L1 patterns for Dagster conventions
    dbt/
      conventions.md                # Data transformation, testing, documentation
      rules-override.json           # L1 patterns for dbt conventions
```

**Composition order** (consistent with `modules/COMPOSITION.md`): ML-ops and data-pipeline modules compose at the same level as other crosscutting modules (database, messaging, caching). Most-specific wins: `ml-ops/mlflow > language > code-quality > generic-layer`.

### Schema / Data Model

#### New Finding Categories

Added to `shared/checks/category-registry.json`:

```json
{
  "ML-VERSION": {
    "description": "Model versioning issue (unversioned model, missing metadata, LFS-absent binary)",
    "agents": ["fg-410-code-reviewer", "fg-412-architecture-reviewer"],
    "wildcard": true,
    "priority": 3,
    "affinity": ["fg-410-code-reviewer"]
  },
  "ML-REPRO": {
    "description": "Experiment reproducibility issue (unfixed seed, missing hyperparameters, unpinned deps)",
    "agents": ["fg-410-code-reviewer"],
    "wildcard": true,
    "priority": 3,
    "affinity": ["fg-410-code-reviewer"]
  },
  "ML-DATA": {
    "description": "Data quality or governance issue (unvalidated schema, missing data tests, PII in dataset)",
    "agents": ["fg-410-code-reviewer", "fg-411-security-reviewer"],
    "wildcard": true,
    "priority": 3,
    "affinity": ["fg-410-code-reviewer"]
  },
  "ML-PIPELINE": {
    "description": "ML/data pipeline issue (untested DAG, non-idempotent task, missing retry config)",
    "agents": ["fg-410-code-reviewer", "fg-412-architecture-reviewer"],
    "wildcard": true,
    "priority": 4,
    "affinity": ["fg-410-code-reviewer"]
  }
}
```

#### L1 Pattern Rules (Representative)

Each module's `rules-override.json` contributes L1 patterns to the check engine. Examples:

**MLflow (`modules/ml-ops/mlflow/rules-override.json`):**

```json
{
  "rules": [
    {
      "id": "ML-REPRO-001",
      "pattern": "mlflow\\.start_run\\(",
      "anti_pattern": "mlflow\\.log_param|mlflow\\.log_params",
      "scope": "file",
      "message": "MLflow run started without logging parameters. Log all hyperparameters for reproducibility.",
      "severity": "WARNING",
      "category": "ML-REPRO",
      "languages": ["python"]
    },
    {
      "id": "ML-VERSION-001",
      "pattern": "mlflow\\.(?:sklearn|pytorch|tensorflow)\\.log_model\\(",
      "anti_pattern": "registered_model_name=",
      "scope": "file",
      "message": "Model logged without registration. Use registered_model_name for versioned model tracking.",
      "severity": "INFO",
      "category": "ML-VERSION",
      "languages": ["python"]
    },
    {
      "id": "ML-REPRO-002",
      "pattern": "(?:random\\.seed|np\\.random\\.seed|torch\\.manual_seed|tf\\.random\\.set_seed)",
      "scope": "file_absent",
      "trigger_pattern": "(?:model\\.fit|model\\.train|trainer\\.train)",
      "message": "Training script without random seed. Set seeds for all random number generators to ensure reproducibility.",
      "severity": "WARNING",
      "category": "ML-REPRO",
      "languages": ["python"]
    }
  ]
}
```

**Airflow (`modules/data-pipelines/airflow/rules-override.json`):**

```json
{
  "rules": [
    {
      "id": "ML-PIPELINE-001",
      "pattern": "PythonOperator\\(",
      "anti_pattern": "retries\\s*=",
      "scope": "file",
      "message": "Airflow PythonOperator without retry configuration. Set retries >= 1 for fault tolerance.",
      "severity": "WARNING",
      "category": "ML-PIPELINE",
      "languages": ["python"]
    },
    {
      "id": "ML-PIPELINE-002",
      "pattern": "DAG\\(",
      "anti_pattern": "catchup\\s*=\\s*False",
      "scope": "file",
      "message": "Airflow DAG without catchup=False. Historical backfills may trigger unexpectedly.",
      "severity": "INFO",
      "category": "ML-PIPELINE",
      "languages": ["python"]
    },
    {
      "id": "ML-PIPELINE-003",
      "pattern": "(?:Variable\\.get|Connection\\.get)\\(",
      "scope": "top_level",
      "message": "Airflow Variable/Connection accessed at module level. Move inside task callable for lazy loading.",
      "severity": "WARNING",
      "category": "ML-PIPELINE",
      "languages": ["python"]
    }
  ]
}
```

**dbt (`modules/data-pipelines/dbt/rules-override.json`):**

```json
{
  "rules": [
    {
      "id": "ML-DATA-001",
      "pattern": "SELECT\\s+\\*",
      "scope": "line",
      "message": "SELECT * in dbt model. Explicitly list columns for schema stability and documentation.",
      "severity": "WARNING",
      "category": "ML-DATA",
      "languages": ["sql"]
    },
    {
      "id": "ML-PIPELINE-010",
      "pattern": "\\.sql$",
      "scope": "filename",
      "check": "dbt_test_exists",
      "message": "dbt model without schema test. Add at minimum a not_null and unique test for primary keys.",
      "severity": "WARNING",
      "category": "ML-PIPELINE"
    }
  ]
}
```

**Large file detection (generic, `modules/ml-ops/rules-override.json`):**

```json
{
  "rules": [
    {
      "id": "ML-VERSION-010",
      "pattern": "\\.(h5|hdf5|pb|pth|pt|onnx|pkl|joblib|safetensors|gguf|bin)$",
      "scope": "filename",
      "check": "git_lfs_tracked",
      "message": "Model file not tracked by Git LFS or DVC. Large binary files should not be committed directly to git.",
      "severity": "CRITICAL",
      "category": "ML-VERSION"
    }
  ]
}
```

#### Auto-Detection Signals

The orchestrator detects ML/data pipeline modules at PREFLIGHT by scanning for config files and dependency declarations:

| Signal File / Pattern | Module Loaded | Confidence |
|---|---|---|
| `mlflow.yml` / `MLproject` / `mlflow` in requirements.txt | `ml-ops/mlflow` | HIGH |
| `.dvc/` directory / `dvc.yaml` / `dvc.lock` | `ml-ops/dvc` | HIGH |
| `wandb/` directory / `wandb` in requirements.txt | `ml-ops/wandb` | HIGH |
| `sagemaker` in requirements.txt / `buildspec.yml` with sagemaker | `ml-ops/sagemaker` | MEDIUM |
| `dags/` directory / `airflow` in requirements.txt / `airflow.cfg` | `data-pipelines/airflow` | HIGH |
| `dagster` in requirements.txt / `dagster.yaml` / `workspace.yaml` | `data-pipelines/dagster` | HIGH |
| `dbt_project.yml` / `profiles.yml` | `data-pipelines/dbt` | HIGH |

### Configuration

In `forge.local.md` (per-project):

```yaml
components:
  language: python
  framework: fastapi
  testing: pytest
  ml_ops: mlflow              # mlflow | dvc | wandb | sagemaker
  data_pipeline: airflow      # airflow | dagster | dbt
```

In `forge-config.md` (plugin-wide defaults):

```yaml
ml_ops:
  enabled: true                       # Master toggle
  auto_detect: true                   # Detect from config files
  large_file_threshold_mb: 100        # Files above this without LFS -> CRITICAL
  experiment_tracking_required: true  # Require experiment tracking in training scripts
  seed_enforcement: true              # Require random seed in training scripts

data_pipelines:
  enabled: true                       # Master toggle
  auto_detect: true                   # Detect from config files
  dag_test_required: true             # DAGs without tests -> WARNING
  idempotency_check: true             # Non-idempotent tasks -> WARNING
```

| Parameter | Type | Default | Range | Description |
|---|---|---|---|---|
| `ml_ops.enabled` | boolean | `true` | -- | Master toggle for ML-ops modules |
| `ml_ops.auto_detect` | boolean | `true` | -- | Auto-detect ML frameworks from project files |
| `ml_ops.large_file_threshold_mb` | integer | `100` | 10-1000 | Threshold for large file detection |
| `ml_ops.experiment_tracking_required` | boolean | `true` | -- | Enforce experiment tracking in training scripts |
| `ml_ops.seed_enforcement` | boolean | `true` | -- | Enforce random seed setting in training scripts |
| `data_pipelines.enabled` | boolean | `true` | -- | Master toggle for data pipeline modules |
| `data_pipelines.auto_detect` | boolean | `true` | -- | Auto-detect data pipeline frameworks |
| `data_pipelines.dag_test_required` | boolean | `true` | -- | Require tests for DAG definitions |
| `data_pipelines.idempotency_check` | boolean | `true` | -- | Flag non-idempotent pipeline tasks |

### Data Flow

#### PREFLIGHT (Auto-Detection)

1. Orchestrator scans project root for signal files (see detection table above)
2. For each detected framework, load the corresponding module's `conventions.md` and `rules-override.json`
3. Record detected modules in `state.json.detected_modules.ml_ops` and `state.json.detected_modules.data_pipelines`
4. If `auto_detect: false`, rely solely on explicit `forge.local.md` component declarations
5. Large file scan: enumerate tracked files matching model extensions, check `.gitattributes` for LFS tracking

#### PLANNING (Convention Awareness)

1. Planner (fg-200) receives ML/data pipeline conventions as part of convention stack
2. Convention files inform the plan: e.g., "when modifying Airflow DAGs, ensure catchup=False and retries are configured"
3. If the requirement involves model training or data pipeline changes, the plan includes ML-specific validation steps

#### REVIEWING (ML-Aware Review)

1. Code reviewer (fg-410) receives ML-specific rules from loaded modules
2. Findings use `ML-*` category codes
3. Large file findings (`ML-VERSION-010`) are surfaced early as CRITICAL
4. Experiment reproducibility findings (`ML-REPRO-*`) are surfaced as WARNING

#### LEARNING (Retrospective)

1. Retrospective (fg-700) includes ML-specific findings in learnings
2. Common patterns (e.g., "team frequently forgets to log MLflow params") become PREEMPT items
3. Learnings stored in `shared/learnings/mlflow.md`, `shared/learnings/airflow.md`, etc.

### Integration Points

| Agent / System | Integration | Change Required |
|---|---|---|
| `fg-100-orchestrator` | Auto-detect ML/data pipeline modules at PREFLIGHT. Load conventions into convention stack. | Add detection logic to PREFLIGHT module loading. |
| `fg-200-planner` | Include ML conventions in plan context when ML modules are active. | No agent change -- conventions loaded via standard composition. |
| `fg-300-implementer` | Follow ML conventions when implementing training scripts, DAGs, or data transforms. | No agent change -- conventions loaded via standard composition. |
| `fg-410-code-reviewer` | Apply `ML-*` finding categories from loaded `rules-override.json`. | No agent change -- rules loaded via standard check engine. |
| `fg-411-security-reviewer` | Detect PII in dataset files, credentials in training configs. | Add `ML-DATA` findings for PII-in-dataset patterns. |
| `fg-412-architecture-reviewer` | Validate ML project structure (separate training/inference/data directories). | Add `ML-VERSION` findings for architectural violations. |
| `shared/checks/engine.sh` | Load `rules-override.json` from `ml-ops/` and `data-pipelines/` modules. | Standard module loading -- no engine changes needed. |
| `shared/checks/category-registry.json` | Add `ML-VERSION`, `ML-REPRO`, `ML-DATA`, `ML-PIPELINE` categories. | Registry update. |
| `shared/scoring.md` | ML categories use standard severity weights (CRITICAL=-20, WARNING=-5, INFO=-2). No special scoring. | Document ML categories in scoring reference. |
| `modules/COMPOSITION.md` | Add `ml-ops` and `data-pipelines` to composition order. | Update composition documentation. |

### Error Handling

| Failure Mode | Behavior | Degradation |
|---|---|---|
| ML framework not detected (false negative) | User can explicitly set `ml_ops:` in `forge.local.md` | Manual configuration available |
| ML framework falsely detected | User can set `ml_ops.auto_detect: false` to disable | Explicit configuration overrides auto-detection |
| Large file check on huge repo | Limit scan to files changed in current branch vs baseline | Bounded scan time |
| Convention file missing for a module | Log WARNING, skip that module's conventions | Other modules unaffected |
| Model extension not in detection list | User adds custom extensions via `ml_ops.model_extensions` config (future) | Extensible by design |
| dbt/Airflow/Dagster not installed locally | Convention checks still run (they are pattern-based, not execution-based). Integration tests flagged as WARNING. | Pattern checks work without installed tools |

## Performance Characteristics

### Module Loading

| Module | Convention File Size | Rules Count | Load Time Impact |
|---|---|---|---|
| mlflow | ~200 lines | 8-12 rules | <10ms |
| dvc | ~150 lines | 5-8 rules | <10ms |
| wandb | ~150 lines | 6-10 rules | <10ms |
| sagemaker | ~250 lines | 10-15 rules | <10ms |
| airflow | ~300 lines | 12-18 rules | <10ms |
| dagster | ~200 lines | 8-12 rules | <10ms |
| dbt | ~250 lines | 10-15 rules | <10ms |

Total convention stack increase: 200-400 lines when both ml-ops and data-pipeline modules are active. Well within the 12-file/component soft cap.

### Large File Detection

| Project Size | Scan Time | Notes |
|---|---|---|
| Small (50 files) | <100ms | Direct `.gitattributes` check |
| Medium (500 files) | <500ms | Filter by extension first, then LFS check |
| Large (5,000 files) | 1-3s | Scoped to changed files only for incremental |

### Token Impact

ML conventions add 200-400 tokens to the convention stack per loaded module. For a project with MLflow + Airflow, this is ~500 additional tokens in the planner and implementer context. Minimal impact relative to existing convention stacks (typically 2,000-5,000 tokens).

## Testing Approach

### Structural Tests

1. **Module structure:** Each module directory contains `conventions.md` and `rules-override.json`
2. **Rules schema:** All `rules-override.json` files validate against the existing rules schema
3. **Category codes:** All rules reference valid categories from `category-registry.json`
4. **Deprecation schema:** All `known-deprecations.json` files validate against v2 schema

### Unit Tests (`tests/unit/ml-ops.bats`)

1. **Auto-detection:** Place signal files in a temp directory, verify correct module detection
2. **Large file detection:** Create a `.pth` file not tracked by LFS, verify `ML-VERSION-010` finding
3. **MLflow rules:** Apply MLflow rules to sample Python file with `mlflow.start_run()` but no `mlflow.log_param()`, verify `ML-REPRO-001` finding
4. **Airflow rules:** Apply Airflow rules to sample DAG without `retries=`, verify `ML-PIPELINE-001` finding
5. **dbt rules:** Apply dbt rules to sample model without tests, verify `ML-PIPELINE` finding
6. **Scoring integration:** Verify `ML-*` findings correctly deduct points using standard formula

### Scenario Tests

1. **Full ML project:** Run `/forge-run --dry-run` on a sample project with MLflow + pytest + DVC. Verify auto-detection, convention loading, and ML-specific findings.
2. **Data pipeline project:** Run `/forge-run --dry-run` on a sample Airflow + dbt project. Verify DAG convention checks and data quality findings.
3. **Mixed project:** Python FastAPI + MLflow + Airflow. Verify all modules compose correctly without conflicts.

## Acceptance Criteria

1. `modules/ml-ops/` contains convention files for MLflow, DVC, W&B, and SageMaker
2. `modules/data-pipelines/` contains convention files for Airflow, Dagster, and dbt
3. Auto-detection at PREFLIGHT correctly identifies ML/data pipeline frameworks from signal files
4. L1 pattern rules in `rules-override.json` produce correct findings for known anti-patterns
5. Large file detection flags model files (>100MB default) not tracked by Git LFS as CRITICAL
6. `ML-VERSION`, `ML-REPRO`, `ML-DATA`, `ML-PIPELINE` categories are registered in `category-registry.json`
7. ML findings integrate with the standard scoring formula (no special treatment)
8. Learnings files exist at `shared/learnings/mlflow.md`, `shared/learnings/airflow.md`, etc.
9. `./tests/validate-plugin.sh` passes with new modules added
10. Convention stack stays within the 12-file/component soft cap when ML modules are loaded
11. `tests/lib/module-lists.bash` MIN counts are updated to reflect new modules

## Migration Path

1. **v2.0.0:** Ship all ML-ops and data-pipeline modules. Auto-detection enabled by default.
2. **v2.0.0:** Add `ml_ops:` and `data_pipelines:` sections to `forge-config-template.md` for Python frameworks (fastapi, django).
3. **v2.0.0:** Add `ML-*` categories to `category-registry.json`.
4. **v2.0.0:** Add learnings files for each new module.
5. **v2.0.0:** Update `CLAUDE.md` module counts and component config documentation.
6. **v2.1.0 (future):** Add Kubeflow, Ray, and Prefect modules based on adoption.
7. **v2.2.0 (future):** Add ML-specific reviewer agent (fg-414-ml-reviewer) for deeper analysis beyond L1 patterns.
8. **No breaking changes:** Existing projects without ML/data pipeline files experience zero behavioral change. Auto-detection adds no overhead for non-ML projects (signal file scan is <10ms).

## Dependencies

**Depends on:**
- Check engine (`shared/checks/engine.sh`) -- loads `rules-override.json` from module directories (existing mechanism)
- Module composition system (`modules/COMPOSITION.md`) -- determines convention loading order
- Auto-detection at PREFLIGHT (same mechanism used for framework/language detection)

**Depended on by:**
- No other F-series features depend on this. Self-contained module addition.
