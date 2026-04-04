---
name: black
categories: [formatter]
languages: [python]
exclusive_group: python-formatter
recommendation_score: 70
detection_files: [pyproject.toml, .black, setup.cfg]
---

# black

## Overview

Uncompromising Python code formatter. Black reformats code to a single consistent style with no configuration options beyond `line-length` and `target-version`. The "uncompromising" design is intentional: zero style debates, minimal `.flake8`/`ruff` conflicts, and deterministic output. Black is idempotent — running it twice produces the same result. Use `black --check --diff` in CI to verify formatting without writing. For new projects, pair Black with isort (or ruff's `I` rules) for import ordering; Black does not sort imports.

## Architecture Patterns

### Installation & Setup

```bash
pip install black
# or as a dev dependency
pip install --group dev black
# or with uv
uv tool install black
```

**`pyproject.toml` (preferred config location — avoids proliferating config files):**
```toml
[tool.black]
line-length = 100
target-version = ["py311", "py312"]
include = '\.pyi?$'
extend-exclude = '''
/(
  | migrations
  | \.venv
  | \.git
  | __pycache__
  | build
  | dist
)/
'''
```

**`black.toml` (standalone, if not using `pyproject.toml`):**
```toml
line-length = 100
target-version = ["py311"]
```

Black reads `pyproject.toml` → `black.toml` → `.black` in that precedence order.

### Rule Categories

Black is a formatter, not a linter — it has no rule categories. Configurable behaviors:

| Option | Default | Notes |
|---|---|---|
| `line-length` | `88` | PEP 8 allows 79; Black's 88 is a pragmatic balance |
| `target-version` | auto-detect | Explicit versions enable version-specific syntax rewrites |
| `skip-string-normalization` | `false` | Set `true` only for codebases with deliberate single-quote conventions |
| `skip-magic-trailing-comma` | `false` | Magic trailing comma forces exploded formatting — rarely disable |
| `preview` | `false` | Opt-in to next-version formatting changes before they become default |

### Configuration Patterns

**Excluding generated files via `extend-exclude`:**
```toml
[tool.black]
line-length = 100
target-version = ["py312"]
extend-exclude = '''
/(
  | migrations          # Alembic/Django auto-generated
  | _pb2\.py$           # protobuf generated
  | \.eggs
  | \.tox
)/
'''
```

**Per-file opt-out (use sparingly):**
```python
# fmt: off
MANUAL_TABLE = [
    ["col1",  "col2",  "col3"],
    ["value", "value", "value"],
]
# fmt: on
```

**Inline suppression for a single expression:**
```python
x = [1,2,3]  # fmt: skip
```

### CI Integration

```yaml
# .github/workflows/quality.yml
- name: Black format check
  run: black --check --diff .
```

`--check` exits non-zero if any file would be reformatted. `--diff` shows what would change (useful in PR comments).

**Pre-commit hook (recommended):**
```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/psf/black-pre-commit-mirror
    rev: 24.10.0
    hooks:
      - id: black
        language_version: python3.12
```

Use `black-pre-commit-mirror` (not the main repo) for faster installs — it ships pre-built wheels.

**Makefile target:**
```makefile
.PHONY: format format-check
format:
	black .
format-check:
	black --check --diff .
```

## Performance

- Black formats a typical 10k-line project in under 1 second — no caching needed for most projects.
- For monorepos with many packages, scope Black to changed packages: `black packages/api/ packages/worker/`.
- Black has no incremental mode — it processes all files matching `include` on each run. Use pre-commit's file filtering to limit scope in local dev.
- `--fast` mode skips the second syntax check pass — slightly faster but skips validation that the reformatted code is syntactically valid. Only use in controlled CI environments.

## Security

Black has no security analysis capability — it is purely a formatter. Key points:

- Pin the Black version in `pyproject.toml` and `.pre-commit-config.yaml` — formatting changes between versions can produce spurious diffs on upgrade.
- Black does not execute code during formatting. It parses to an AST and reprints — safe to run on untrusted codebases.
- Verify `extend-exclude` patterns cover `migrations/` — accidentally formatting Django/Alembic migrations can break them if they contain raw SQL with specific whitespace.

## Testing

```bash
# Check all files without writing (CI mode)
black --check --diff .

# Format all files in place
black .

# Format a specific file
black src/myapp/views.py

# Check a single file
black --check src/myapp/views.py

# Show what would change
black --diff src/myapp/views.py

# Format stdin and print to stdout (useful for editor integration)
echo "x=1" | black -

# Verify target version is detected correctly
black --verbose --check src/ 2>&1 | grep "target version"
```

## Dos

- Set `target-version` explicitly in `pyproject.toml` — auto-detection can pick the wrong version in CI environments with multiple Python installations.
- Use `black --check --diff` in CI rather than `black --check` alone — the diff output makes review comments more actionable.
- Pin Black version in both `pyproject.toml` dev dependencies and `.pre-commit-config.yaml` `rev` — Black's output changes between versions.
- Pair Black with ruff's `I` (isort) rules — Black does not order imports; unordered imports cause noisy PRs.
- Use `# fmt: off` / `# fmt: on` sparingly and only for data structures where manual alignment conveys meaning (e.g., alignment matrices, lookup tables).
- Set `line-length` to match your linter (`ruff`/`flake8`) `max-line-length` — mismatches cause linter errors on lines Black considers valid.

## Don'ts

- Don't set `skip-string-normalization = true` without team consensus — it disables Black's single→double quote normalization and breaks the "no debates" contract.
- Don't run `black .` in CI — use `--check` only; auto-formatting commits from CI add noise and obscure real changes.
- Don't add `migrations/` to Black's scope — Django and Alembic migrations contain raw SQL and string patterns that Black reformats in ways that break the migration.
- Don't configure `line-length = 79` to match PEP 8 strictly — Black's default of 88 is calibrated to minimize reformatting; 79 forces aggressive line breaking on modern code.
- Don't skip `black` in pre-commit hooks to "save time" — a single unformatted commit forces a format-only follow-up commit that pollutes `git blame`.
- Don't use Black alongside `autopep8` or `yapf` — running multiple formatters produces conflicts and non-deterministic output.
