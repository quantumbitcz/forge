---
name: pylint
categories: [linter]
languages: [python]
exclusive_group: python-linter
recommendation_score: 60
detection_files: [.pylintrc, pyproject.toml, setup.cfg]
---

# pylint

## Overview

Deep Python static analyzer with type inference, import graph analysis, and code smell detection. Pylint produces more false positives than ruff but catches semantic issues — unused class attributes, wrong argument types, missing method overrides — that regex-based linters miss. Use pylint on teams that need thorough static analysis beyond formatting and style; pair with ruff for fast feedback and rely on pylint for deeper checks. Many teams migrate from pylint to ruff for speed; retain pylint when its inference-based rules are still catching real bugs.

## Architecture Patterns

### Installation & Setup

```bash
pip install pylint
pylint --version   # e.g., pylint 3.3.x
```

**For type stub support:**
```bash
pip install pylint[spelling]        # optional: spelling checker
pip install pylint-django           # Django-specific plugin
pip install pylint-celery           # Celery-specific plugin
```

### Rule Categories

Pylint uses a `{Letter}{code}` convention:

| Category | Prefix | Examples | Pipeline Severity |
|---|---|---|---|
| Convention | `C` | `C0103` (naming), `C0301` (line too long) | INFO |
| Refactor | `R` | `R0201` (no-self-use), `R0902` (too-many-instance-attributes) | WARNING |
| Warning | `W` | `W0611` (unused-import), `W0613` (unused-argument) | WARNING |
| Error | `E` | `E0102` (class-already-defined), `E1101` (attribute error) | CRITICAL |
| Fatal | `F` | `F0001` (import error blocking analysis) | CRITICAL |

Key high-value rules not covered by ruff:
- `E1101` — accessing attribute on class that may not exist (type inference)
- `W0611` — unused imports with graph-based analysis (catches indirect cases)
- `R0801` — duplicate code blocks across files
- `W0212` — accessing protected member from outside class
- `E0401` — unable to import module (reveals missing deps in CI)

### Configuration Patterns

**`pyproject.toml` (preferred):**
```toml
[tool.pylint.main]
jobs = 4                          # parallel analysis
recursive = true
ignore = ["migrations", ".venv", "node_modules"]
ignore-patterns = [".*\\.generated\\.py"]
load-plugins = ["pylint.extensions.docparams", "pylint.extensions.mccabe"]

[tool.pylint."messages control"]
disable = [
    "C0114",  # missing-module-docstring
    "C0115",  # missing-class-docstring
    "C0116",  # missing-function-docstring
    "R0903",  # too-few-public-methods (common in dataclasses/DTOs)
    "W0107",  # unnecessary-pass (common in abstract methods)
]
enable = ["all"]

[tool.pylint.design]
max-args = 8
max-attributes = 12
max-bool-expr = 5
max-branches = 15
max-locals = 20
max-public-methods = 25
max-returns = 6
min-public-methods = 1

[tool.pylint.format]
max-line-length = 100

[tool.pylint.similarities]
min-similarity-lines = 8         # R0801 duplicate code threshold
ignore-imports = true
```

**`.pylintrc` (alternative, standalone file):**
```ini
[MAIN]
jobs=4
recursive=yes

[MESSAGES CONTROL]
disable=C0114,C0115,C0116,R0903

[FORMAT]
max-line-length=100
```

**Inline suppression:**
```python
class MyConfig:  # pylint: disable=too-few-public-methods
    DEBUG = False

def _internal(x):
    return x._value  # pylint: disable=protected-access -- intentional internal access
```

### CI Integration

```yaml
# .github/workflows/quality.yml
- name: Pylint
  run: |
    pylint src/ --output-format=colorized --fail-under=9.0
  continue-on-error: false

- name: Pylint (JSON for tooling)
  run: pylint src/ --output-format=json2 > pylint-report.json
  if: always()
```

`--fail-under=9.0` fails the build if the score drops below 9.0/10.0. For strict projects, use `--fail-under=10.0`. For gradual adoption, start at `7.0` and raise over sprints.

**GitHub Actions annotation reporter:**
```bash
pip install pylint-github-format
pylint src/ --output-format=pylint_github_format.GithubFormatter
```

## Performance

- Pylint is 10-50x slower than ruff for the same codebase — a 50k-line project may take 30-120s.
- Use `jobs=4` (or match CPU count) for parallel analysis — reduces wall time by ~60% on multi-core machines.
- Run pylint only on changed files in pre-commit hooks: `git diff --name-only HEAD | grep '\.py$' | xargs pylint`
- Exclude `migrations/`, `.venv/`, and test directories from regular runs — separate slower full-project scans to nightly CI.
- `pylint --from-stdin` can lint stdin for IDE integrations without file system overhead.

## Security

Pylint catches security-adjacent issues via inference:

- `W0611` — unused imports pointing to dead code paths (potential stale security logic)
- `E1101` — attribute not found (catches incorrect security API usage patterns)
- `W0212` — protected member access (flags bypassed access controls)
- `R0801` — duplicate code (security logic duplicated incorrectly is a common vulnerability source)

For dedicated security scanning, pair pylint with ruff's `S` (bandit) rules — they complement each other.

## Testing

```bash
# Lint src/ directory
pylint src/

# Lint with score output
pylint src/ --score=y

# List all available messages
pylint --list-msgs

# Show available extensions
pylint --list-extensions

# Check a single file
pylint src/myapp/models.py

# Generate default config
pylint --generate-rcfile > .pylintrc

# Validate current config
pylint --rcfile=pyproject.toml src/ --verbose
```

**Writing pylint plugins:**
```python
# my_plugin.py
from astroid import MANAGER
from pylint.checkers import BaseChecker

class NoTodoChecker(BaseChecker):
    name = "no-todo"
    msgs = {
        "W9001": (
            "TODO comment found: %s",
            "todo-found",
            "Avoid committed TODO comments — use issue tracker instead.",
        )
    }

    def visit_const(self, node):
        if isinstance(node.value, str) and "TODO" in node.value:
            self.add_message("todo-found", node=node, args=(node.value[:50],))


def register(linter):
    linter.register_checker(NoTodoChecker(linter))
```

## Dos

- Use `--fail-under` with a meaningful threshold (≥9.0) — a score without a failure threshold is advisory only.
- Run `jobs=4` or higher — pylint's default single-threaded mode is prohibitively slow on large projects.
- Use `[tool.pylint."messages control"].disable` rather than disabling per-file inline — centralized suppressions are visible in code review.
- Enable `pylint.extensions.mccabe` to enforce cyclomatic complexity limits alongside style checks.
- Pin `pylint-django` or `pylint-celery` versions alongside pylint — mismatched plugins cause false positives on framework-specific patterns.
- Keep pylint score trends in CI as a metric — score drops signal regression before individual rule violations accumulate.

## Don'ts

- Don't `disable=all` then re-enable a few rules — you lose future valuable rules added in upgrades. Start with `enable=all` and disable specific noisy ones.
- Don't run pylint on auto-generated code (migrations, protobuf output, OpenAPI clients) — it produces irrelevant violations and obscures real issues.
- Don't use pylint as a formatter substitute — it does not fix code. Delegate formatting to ruff or black.
- Don't ignore `E0401` (import errors) — they mean pylint could not analyze a module, which silently skips all rules for that module's dependencies.
- Don't suppress entire message categories (`disable=C`) — category-level suppression hides both noisy and genuinely valuable checks.
- Don't skip the `--score=y` flag in developer output — the score provides a high-level signal even when individual violations are filtered.
