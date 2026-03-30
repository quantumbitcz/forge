# ruff

## Overview

Rust-based Python linter and formatter that replaces flake8, isort, pyupgrade, pydocstyle, and black in a single tool. 10-100x faster than the tools it replaces. `ruff check` enforces code quality via 50+ rule categories; `ruff format` applies opinionated formatting (black-compatible by default). Use ruff as the primary linter/formatter for any new Python project. For teams on existing codebases using flake8 + black + isort, ruff is a drop-in replacement with a one-pass migration script.

## Architecture Patterns

### Installation & Setup

```bash
# Project dependency (recommended)
pip install ruff
# or with uv (faster)
uv tool install ruff

# Verify
ruff --version   # e.g., ruff 0.9.x
```

### Configuration Patterns

**pyproject.toml is the preferred config location:**
```toml
[tool.ruff]
target-version = "py312"
line-length = 100
exclude = [
    ".git",
    "__pycache__",
    "*.egg-info",
    "dist",
    "build",
    ".venv",
    "migrations",  # auto-generated Django/Alembic migrations
]

[tool.ruff.lint]
select = [
    "E",   # pycodestyle errors
    "W",   # pycodestyle warnings
    "F",   # pyflakes (undefined names, unused imports)
    "I",   # isort (import ordering)
    "N",   # pep8-naming
    "UP",  # pyupgrade (modernize syntax)
    "B",   # flake8-bugbear (likely bugs)
    "C4",  # flake8-comprehensions
    "S",   # bandit (security)
    "ANN", # flake8-annotations (type annotation coverage)
    "D",   # pydocstyle (docstring conventions)
    "RUF", # ruff-specific rules
]
ignore = [
    "D100",   # missing docstring in public module
    "D104",   # missing docstring in public package
    "ANN101", # missing type annotation for `self`
    "S101",   # use of assert (common in tests)
]

[tool.ruff.lint.per-file-ignores]
"tests/**/*.py" = ["S101", "ANN", "D"]
"migrations/*.py" = ["E501"]  # auto-generated lines may be long

[tool.ruff.lint.isort]
known-first-party = ["myapp"]
force-sort-within-sections = true

[tool.ruff.lint.pydocstyle]
convention = "google"  # or "numpy", "pep257"

[tool.ruff.format]
quote-style = "double"
indent-style = "space"
docstring-code-format = true
```

Alternatively, use `ruff.toml` at the project root for ruff-only config without embedding in `pyproject.toml`.

### Rule Categories

| Prefix | Source Tool | What It Checks | Pipeline Severity |
|---|---|---|---|
| `F` | pyflakes | Undefined names, unused imports, redefined builtins | CRITICAL |
| `E` / `W` | pycodestyle | PEP 8 style: indentation, whitespace, line length | WARNING |
| `I` | isort | Import order, grouping, blanks between sections | WARNING |
| `B` | flake8-bugbear | Mutable default args, bare `except`, loop variable leaks | CRITICAL |
| `S` | bandit | Hardcoded secrets, unsafe deserialization, shell injection | CRITICAL |
| `UP` | pyupgrade | f-strings, `dict()` → `{}`, `Optional[X]` → `X | None` | INFO |
| `ANN` | flake8-annotations | Missing type annotations on public functions | WARNING |
| `D` | pydocstyle | Missing/malformed docstrings | INFO |
| `N` | pep8-naming | Class/function/variable naming conventions | WARNING |
| `RUF` | ruff-native | Ambiguous variable names, mutable class variables | WARNING |

### CI Integration

```yaml
# .github/workflows/quality.yml
- name: Ruff lint
  run: ruff check . --output-format=github

- name: Ruff format check
  run: ruff format --check .
```

`--output-format=github` emits GitHub Actions annotations on PR diffs. Exit code 1 if violations found.

**Pre-commit hook (recommended):**
```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.9.0
    hooks:
      - id: ruff
        args: [--fix, --exit-non-zero-on-fix]
      - id: ruff-format
```

**With `uv` in CI:**
```yaml
- name: Install uv
  uses: astral-sh/setup-uv@v5
- name: Ruff check
  run: uvx ruff check . --output-format=github
```

## Performance

- Ruff runs in ~0.1s on most projects — a 100k-line codebase lints in under 1 second.
- File-based caching (`.ruff_cache/`) skips unchanged files — incremental CI runs are near-instant.
- Replaces 5+ tools in one pass: flake8, isort, pyupgrade, pydocstyle, and some bandit rules. Eliminates inter-tool coordination and ordering issues.
- `ruff check --fix` applies safe auto-fixes in one pass; `--unsafe-fixes` enables destructive fixes (review before committing).

## Security

The `S` (bandit) rule set catches common Python security issues:

- `S105` / `S106` — hardcoded passwords and secrets in source code
- `S301` / `S302` — unsafe deserialization of untrusted binary data formats
- `S324` — use of insecure hash functions (`md5`, `sha1` without `usedforsecurity=False`)
- `S603` / `S604` — subprocess calls with `shell=True` — allows shell injection via unsanitized input
- `S701` — Jinja2 templates with `autoescape=False`

Enable all `S` rules and only suppress specific ones with justification:
```python
result = subprocess.run(cmd, shell=True)  # noqa: S603 -- cmd is fully controlled, no user input
```

## Testing

```bash
# Lint all Python files and show violations
ruff check .

# Lint and auto-fix safe issues in place
ruff check . --fix

# Format all files
ruff format .

# Format check only (no writes) — for CI
ruff format --check .

# Show what would be fixed without applying
ruff check . --diff

# Check a single file
ruff check src/myapp/views.py

# Show rule documentation for a specific code
ruff rule B006

# List all enabled rules for current config
ruff check --show-settings | grep -A2 "enabled_rules"
```

## Dos

- Pin ruff version in `pyproject.toml` dev dependencies and in `.pre-commit-config.yaml` `rev` — rules change between versions and new violations appear on upgrades.
- Start with a broad `select` and gradually narrow `ignore` per file via `per-file-ignores` rather than disabling rules globally.
- Use `ruff check --fix` as the pre-commit hook — it fixes safe issues automatically and reduces friction for developers.
- Enable `B` (bugbear) rules from day one — mutable default arguments (`B006`) and bare `except` (`B001`) are real bugs, not style.
- Use `UP` rules to keep syntax modern — auto-upgrade `Optional[X]` to `X | None`, f-strings from `.format()`, etc.
- Specify `target-version` matching your Python runtime — version-gated upgrade rules only fire when the feature is available.

## Don'ts

- Don't disable the entire `S` (security) rule set — cherry-pick specific suppressions per file with `# noqa: S{code}` and a comment explaining why.
- Don't add `migrations/` to the global `exclude` without also adding the directory to `per-file-ignores` for `E501` — migrations are auto-generated but should still be checked for security patterns.
- Don't run ruff without `--fix` in local dev hooks — silent check-only hooks slow developers down without preventing CI failures.
- Don't skip `ruff format` in favor of running black alongside ruff — they have near-identical output but running both wastes time and can conflict on edge cases.
- Don't ignore `F401` (unused imports) globally — it hides real code quality issues. Instead, use `__all__` in `__init__.py` files to mark intentional re-exports.
- Don't commit `.ruff_cache/` to version control — add it to `.gitignore`.
