# Eval Fixtures

Each fixture is a minimal project directory containing a reproducible bug (for `/forge-fix` suites) or a feature-building starting point (for `/forge-run` suites).

## Fixture Format

```
fixtures/<language>/<task-id>/
  .forge-eval.json       # Metadata (required)
  README.md              # Bug/task description
  src/                   # Source code with intentional bug
  tests/                 # Failing test(s)
  <build-config>         # Language-appropriate build file
```

## .forge-eval.json Schema

```json
{
  "fixture_version": "1.0.0",
  "created": "2026-04-14",
  "language": "python",
  "build_command": "pip install -e .",
  "test_command": "python3 -m pytest tests/ -v",
  "known_failing_tests": ["tests/test_user_lookup.py::test_case_insensitive_lookup"],
  "forge_local_template": {
    "language": "python",
    "testing": "pytest",
    "commands": {
      "build": "pip install -e .",
      "test": "python3 -m pytest tests/ -v",
      "lint": "ruff check src/"
    }
  }
}
```

## Creating New Fixtures

1. Create directory under `fixtures/<language>/<task-id>/`
2. Add source code with an intentional bug
3. Add at least one failing test that validates the fix
4. Add `.forge-eval.json` with metadata
5. Verify: `python3 -m pytest tests/` (or equivalent) should FAIL before fix and PASS after

## Stub Fixtures

Fixtures in this directory are minimal stubs. They contain the metadata and directory structure but may not have full working code. Full fixture repos with git history are too large for the plugin repository.

To populate full fixtures, run the fixture generation script (when available) or manually create the project files following the README in each stub directory.
