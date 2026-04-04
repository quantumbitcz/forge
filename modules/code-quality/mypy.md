---
name: mypy
categories: [linter]
languages: [python]
exclusive_group: python-type-checker
recommendation_score: 90
detection_files: [mypy.ini, .mypy.ini, pyproject.toml, setup.cfg]
---

# mypy

## Overview

Static type checker for Python. Mypy reads type annotations and infers types to catch type errors before runtime — wrong argument types, missing attributes, `None` where a value is expected, unreachable code. Use mypy in strict mode for new projects; adopt incrementally on existing codebases using per-module overrides. Mypy is complementary to ruff/pylint — it operates on the type system, not code style or patterns. The `dmypy` daemon makes incremental checks near-instant for local development loops.

## Architecture Patterns

### Installation & Setup

```bash
pip install mypy
mypy --version   # e.g., mypy 1.13.x

# Third-party stubs (install alongside mypy):
pip install types-requests types-PyYAML types-boto3
# Framework stubs:
pip install django-stubs[compatible-mypy] djangorestframework-stubs
pip install sqlalchemy-stubs
```

### Rule Categories

Mypy does not use named rule categories — it reports error codes:

| Code | What It Catches | Pipeline Severity |
|---|---|---|
| `[assignment]` | Assigning incompatible types | CRITICAL |
| `[arg-type]` | Wrong argument type passed to function | CRITICAL |
| `[return-value]` | Return type does not match annotation | CRITICAL |
| `[union-attr]` | Attribute access on potentially `None` value | CRITICAL |
| `[no-untyped-def]` | Function missing type annotations | WARNING |
| `[no-untyped-call]` | Calling untyped function from typed context | WARNING |
| `[import-untyped]` | Importing library without stubs or `py.typed` | INFO |
| `[misc]` | Overloaded function variants, class decorator issues | WARNING |

### Configuration Patterns

**`pyproject.toml` (preferred):**
```toml
[tool.mypy]
python_version = "3.12"
strict = true                     # enables all strictness flags
warn_return_any = true
warn_unused_configs = true
show_error_codes = true
show_column_numbers = true
pretty = true
exclude = [
    "migrations/",
    ".venv/",
    "build/",
]

# Third-party libraries without stubs — silence import errors selectively
[[tool.mypy.overrides]]
module = "some_untyped_library.*"
ignore_missing_imports = true

# Relax rules for test files
[[tool.mypy.overrides]]
module = "tests.*"
disallow_untyped_defs = false
disallow_any_generics = false

# Relax rules for legacy modules during gradual adoption
[[tool.mypy.overrides]]
module = "myapp.legacy.*"
ignore_errors = true
```

**What `strict = true` enables:**
```toml
# Equivalent to strict = true:
disallow_any_generics = true
disallow_subclassing_any = true
disallow_untyped_calls = true
disallow_untyped_defs = true
disallow_incomplete_defs = true
check_untyped_defs = true
disallow_untyped_decorators = true
warn_redundant_casts = true
warn_unused_ignores = true
warn_return_any = true
no_implicit_reexport = true
strict_equality = true
extra_checks = true
```

**`mypy.ini` (alternative):**
```ini
[mypy]
python_version = 3.12
strict = True
show_error_codes = True
exclude = migrations/|\.venv/

[mypy-some_untyped_library.*]
ignore_missing_imports = True
```

**Type annotation patterns:**
```python
from typing import Optional, Union
from collections.abc import Sequence

# Python 3.10+ union syntax (preferred over Optional)
def process(value: str | None = None) -> str:
    if value is None:
        return ""
    return value.upper()

# Debug: reveal_type() is removed at runtime but mypy reports the inferred type
x = some_function()
reveal_type(x)  # mypy: Revealed type is "builtins.str"

# Suppress a specific error with a comment (use sparingly)
result = untyped_api_call()  # type: ignore[no-untyped-call]
```

### CI Integration

```yaml
# .github/workflows/quality.yml
- name: Mypy type check
  run: mypy src/ --no-error-summary --junit-xml=mypy-report.xml

- name: Upload mypy results
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: mypy-report
    path: mypy-report.xml
```

**Pre-commit hook:**
```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/pre-commit/mirrors-mypy
    rev: v1.13.0
    hooks:
      - id: mypy
        additional_dependencies:
          - types-requests
          - django-stubs[compatible-mypy]
```

## Performance

- Cold runs on large codebases take 60-300s — mypy builds a full type graph.
- `dmypy` (mypy daemon) keeps the type graph in memory — incremental checks run in 1-5s:
  ```bash
  dmypy start
  dmypy run -- src/           # first run: ~60s
  dmypy run -- src/           # subsequent: ~2s (cached)
  dmypy stop
  ```
- Use `mypy --cache-dir .mypy_cache` and commit `.mypy_cache` to CI cache layer — halves cold CI run time.
- Run mypy only on changed files locally: `git diff --name-only HEAD | grep '\.py$' | xargs mypy`
- In monorepos, run mypy per package with separate configs rather than across the entire repo — avoids unnecessary cross-package type resolution.

## Security

Mypy's type system catches security-adjacent patterns:

- `[union-attr]` on `Optional` — prevents `None` dereference on values returned from untrusted sources
- `[arg-type]` — catches passing `str` where `bytes` is expected in cryptographic APIs (e.g., `hashlib`)
- `[return-value]` — ensures functions that must return non-`None` on security-critical paths are typed accordingly
- `no_implicit_reexport = true` — prevents accidental exposure of internal APIs through `__init__.py`

## Testing

```bash
# Type check src/ directory
mypy src/

# Check a single file
mypy src/myapp/views.py

# Show what --strict enables
mypy --help | grep strict

# Show inferred type (debugging)
# Add reveal_type(x) to code, then run mypy — it prints the type and removes the call at runtime

# Check without error summary (cleaner CI output)
mypy src/ --no-error-summary

# List all files that would be checked
mypy src/ --list-files

# Generate a stub file for an untyped module
stubgen -m some_module -o stubs/

# Validate stub files
mypy --check-untyped-defs stubs/
```

## Dos

- Start with `strict = true` on new projects — retrofitting strict mode onto an existing codebase is significantly harder.
- Use `[[tool.mypy.overrides]]` per module for gradual adoption — migrate legacy modules incrementally rather than disabling strict mode globally.
- Install `types-*` stub packages for common third-party libraries — `types-requests`, `types-PyYAML`, `types-boto3` cover the majority of unresolved imports.
- Use `dmypy` in local development for fast incremental feedback — integrate into editor LSP where possible.
- Prefer `X | None` over `Optional[X]` in Python 3.10+ code — it reads more naturally and reduces imports.
- Commit `.mypy_cache` directory structure to CI layer cache — reduces cold run time substantially.

## Don'ts

- Don't use `# type: ignore` without an error code — bare `type: ignore` suppresses all errors on that line including future ones. Always use `# type: ignore[specific-code]`.
- Don't set `ignore_errors = true` for entire packages during initial adoption without a deadline to remove it — it becomes permanent.
- Don't rely on mypy alone for runtime validation — mypy checks are erased at runtime. Use Pydantic, attrs validators, or `isinstance` guards for runtime type enforcement.
- Don't disable `warn_unused_ignores = true` — it catches stale `type: ignore` comments that are no longer needed, keeping suppressions minimal.
- Don't skip stub installation for commonly used libraries — `ignore_missing_imports = true` is a last resort, not a default.
- Don't run mypy without `show_error_codes = true` — error codes are required for targeted `type: ignore[code]` suppressions.
