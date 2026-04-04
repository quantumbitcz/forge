---
name: coverage-py
categories: [coverage]
languages: [python]
exclusive_group: python-coverage
recommendation_score: 90
detection_files: [.coveragerc, pyproject.toml, setup.cfg]
---

# coverage-py

## Overview

`coverage.py` is the standard Python coverage measurement tool. Run tests through `coverage run -m pytest`, generate reports with `coverage report` / `coverage html`, and enforce minimums with `--fail-under`. Configure via `[tool.coverage]` in `pyproject.toml` (preferred) or `.coveragerc`. Branch coverage catches cases where both sides of conditionals are not exercised. For parallel test runs (`pytest-xdist`), use `coverage combine` to merge `.coverage.*` data files from each worker before reporting.

## Architecture Patterns

### Installation & Setup

```bash
pip install coverage[toml]
# Or with pytest integration:
pip install pytest-cov
```

**pyproject.toml (preferred configuration):**
```toml
[tool.coverage.run]
source = ["src"]
branch = true                       # enable branch coverage
omit = [
    "src/*/migrations/*",
    "src/*/generated/*",
    "tests/*",
    "conftest.py",
    "*/__init__.py",
]
parallel = true                     # append process ID to .coverage file (for xdist)
data_file = ".coverage"

[tool.coverage.report]
show_missing = true
skip_covered = false
skip_empty = true
precision = 2
exclude_lines = [
    "pragma: no cover",
    "def __repr__",
    "def __str__",
    "raise NotImplementedError",
    "if TYPE_CHECKING:",
    "if __name__ == .__main__.:",
    "@(abc\\.)?abstractmethod",
    "\\.\\.\\.",                     # ellipsis in Protocol/abstract stubs
]
fail_under = 80

[tool.coverage.html]
directory = "htmlcov"
title = "Coverage Report"
show_contexts = true

[tool.coverage.xml]
output = "coverage.xml"             # Cobertura format for CI ingestion
```

**pytest-cov integration (avoids separate `coverage run`):**
```toml
# pyproject.toml
[tool.pytest.ini_options]
addopts = "--cov=src --cov-report=term-missing --cov-report=xml --cov-report=html --cov-fail-under=80"
```

### Rule Categories

| Metric | Flag | Notes |
|---|---|---|
| Line coverage | default | Percentage of source lines executed |
| Branch coverage | `branch = true` | Both `True` and `False` branches of conditionals |
| Minimum threshold | `fail_under` | Build fails if coverage drops below value |
| Missing lines | `show_missing` | Print line ranges not covered in terminal report |
| Context tracking | `dynamic_context` | Track which test covered each line |

### Configuration Patterns

**Parallel test runs with pytest-xdist:**
```bash
# Run tests in parallel (each worker writes .coverage.NNNN)
pytest -n auto --cov=src --cov-report=

# Combine after all workers finish
coverage combine

# Then report
coverage report --fail-under=80
coverage html
coverage xml
```

**Dynamic contexts (which test covered which line):**
```toml
[tool.coverage.run]
dynamic_context = "test_function"   # label each line with the test that ran it
```
```bash
coverage html --show-contexts       # HTML report shows which tests cover each line
```

**Suppressing specific lines:**
```python
def platform_specific():  # pragma: no cover
    if sys.platform == "win32":
        return _windows_impl()

# Custom exclude pattern defined in pyproject.toml:
def __repr__(self) -> str:          # covered by exclude_lines pattern
    return f"MyClass({self.value})"
```

### CI Integration

```yaml
# .github/workflows/test.yml
- name: Run tests with coverage
  run: |
    coverage run -m pytest
    coverage report --fail-under=80
    coverage xml

- name: Upload coverage to Codecov
  uses: codecov/codecov-action@v4
  with:
    files: coverage.xml
    fail_ci_if_error: true

- name: Upload HTML report
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: coverage-html
    path: htmlcov/
```

**GitHub PR comment with coverage delta:**
```yaml
- uses: py-cov-action/python-coverage-comment-action@v3
  with:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    MINIMUM_GREEN: 80
    MINIMUM_ORANGE: 70
```

## Performance

- `branch = true` adds ~10-20% overhead vs line-only coverage — still fast enough for most test suites.
- For large test suites (>10 min), use `pytest-xdist` with `parallel = true` — workers write separate `.coverage.*` files, then `coverage combine` merges them.
- `coverage run --source=src` limits instrumentation to the source package — avoids instrumenting site-packages and virtual env overhead.
- `show_contexts = true` in HTML is expensive to render for large test suites — disable in CI unless debugging which test covers what.
- `.coverage` is a SQLite database — concurrent writes without `parallel = true` corrupt it. Always set `parallel = true` when using xdist.

## Security

- `.coverage` SQLite file can contain file paths that reveal project structure — gitignore it.
- `coverage.xml` (Cobertura) contains file paths and line numbers — safe for CI ingestion but should not be public for proprietary code.
- Coverage HTML embeds source lines — do not publish to public-facing hosts for proprietary projects.

## Testing

```bash
# Basic: run pytest through coverage
coverage run -m pytest

# Combined: run, report, and fail if under threshold
coverage run -m pytest && coverage report --fail-under=80

# Generate all report formats
coverage report --show-missing
coverage html
coverage xml

# Parallel: combine after xdist run
pytest -n auto --cov=src --no-header -q
coverage combine && coverage report --fail-under=80

# Show which lines are missing (quick terminal check)
coverage report -m

# Open HTML report
open htmlcov/index.html

# Erase old data before re-run
coverage erase
```

## Dos

- Enable `branch = true` — line coverage misses untaken `else` paths; branch coverage catches them.
- Configure `omit` for migrations, generated code, and `__init__.py` — they inflate denominator without adding meaningful signal.
- Use `fail_under` in `pyproject.toml` so `coverage report` fails the build — do not rely on developers manually checking.
- Use `coverage xml` (Cobertura format) for CI artifact ingestion — it is supported by Codecov, Sonar, and GitHub Actions annotations.
- Set `parallel = true` whenever using `pytest-xdist` — prevents SQLite corruption from concurrent writes.
- Add `exclude_lines` for `TYPE_CHECKING` blocks, abstract methods, and `pragma: no cover` — they add noise to uncovered line counts.

## Don'ts

- Don't commit `.coverage` to version control — it is a binary SQLite file that changes on every run.
- Don't use `pragma: no cover` on business logic paths — it hides real coverage gaps. Reserve it for platform guards and type stubs.
- Don't run `coverage run` without specifying `--source` or configuring `source` in pyproject.toml — without scoping, it instruments the entire Python path including dependencies.
- Don't set `fail_under = 100` for projects with I/O-heavy code, CLI entry points, or OS-specific branches — 100% is unrealistic without meaningless tests.
- Don't generate HTML in CI on every run — it is slow and artifact storage adds up. Generate XML for ingestion and HTML only on failure or scheduled weekly runs.
