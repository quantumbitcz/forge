# mutmut

## Overview

mutmut is the Python mutation testing tool. It modifies Python source files in place (one mutation at a time), runs the test suite, and reports whether tests catch each mutation. Surviving mutants reveal untested code paths, weak assertions, or logic that tests never exercise. mutmut stores results in a SQLite cache (`.mutmut-cache`), enabling incremental re-runs — only unchanged files are re-mutated. Output formats include terminal summary, HTML reports, and JUnit XML for CI ingestion. Configuration lives in `pyproject.toml` under `[tool.mutmut]`.

## Architecture Patterns

### Installation & Setup

```bash
pip install mutmut

# or add to dev dependencies (pyproject.toml)
[project.optional-dependencies]
dev = ["mutmut>=2.4"]
```

**pyproject.toml configuration:**
```toml
[tool.mutmut]
paths_to_mutate = "src/"
backup = false              # don't create .orig files — cache is sufficient
runner = "python -m pytest"
tests_dir = "tests/"
dict_synonyms = ""          # treat these as dict synonyms during mutation
no_progress = false
simple_output = false

# Exclude files not worth mutating
# (use --paths-to-exclude on CLI or filter in CI)
```

**Minimal pyproject.toml for a standard src-layout project:**
```toml
[tool.mutmut]
paths_to_mutate = "src/mypackage/"
tests_dir = "tests/unit/"   # target unit tests only — not integration or e2e
runner = "python -m pytest -x --timeout=10"  # -x = stop on first failure (faster)
backup = false
```

**For projects using pytest with coverage:**
```toml
[tool.mutmut]
paths_to_mutate = "src/"
tests_dir = "tests/unit/"
runner = "python -m pytest --no-header -rN -q"
backup = false
```

### Rule Categories

mutmut applies the following mutation categories to Python source:

| Category | Example mutation | What tests must assert |
|---|---|---|
| Arithmetic | `a + b` → `a - b` | Correct numeric computation |
| Comparison | `x > 0` → `x >= 0`, `==` → `!=` | Boundary conditions and equality |
| Boolean | `True` → `False`, `and` → `or` | Boolean logic and short-circuit |
| String | `"expected"` → `"XX expected XX"` | String return values and messages |
| Keyword | `return x` → `return None` | Return value assertions |
| Number | `42` → `43`, `0` → `1` | Exact numeric value checks |
| Decorator | `@decorator` removed | Decorator side-effect verification |
| None/bool swap | `None` ↔ `""`, `True` ↔ `False` | None-guard and truthiness checks |

### Configuration Patterns

**Scoping mutations to domain logic only:**
```toml
[tool.mutmut]
# Mutate only domain and service layers
paths_to_mutate = "src/myapp/domain/ src/myapp/services/"
tests_dir = "tests/unit/"
runner = "python -m pytest tests/unit/ -x -q --timeout=15"
backup = false
```

**Custom runner with parallel test execution:**
```toml
[tool.mutmut]
paths_to_mutate = "src/"
tests_dir = "tests/"
runner = "python -m pytest -n auto -x -q"   # pytest-xdist parallel
backup = false
```

**Using a wrapper script for test isolation:**
```bash
#!/usr/bin/env bash
# scripts/mutmut-runner.sh — used as runner = "bash scripts/mutmut-runner.sh"
set -e
python -m pytest tests/unit/ -x --timeout=10 -q \
  --ignore=tests/unit/integration/ \
  2>&1
```

### CI Integration

```yaml
# .github/workflows/mutation.yml
- name: Restore mutmut cache
  uses: actions/cache@v4
  with:
    path: .mutmut-cache
    key: mutmut-${{ github.ref }}-${{ hashFiles('src/**/*.py', 'tests/**/*.py') }}
    restore-keys: |
      mutmut-${{ github.ref }}-
      mutmut-

- name: Install dependencies
  run: pip install -e ".[dev]"

- name: Run mutation tests
  run: |
    mutmut run
    mutmut results

- name: Generate mutation report
  if: always()
  run: |
    mutmut html
    mutmut junitxml > reports/mutmut-results.xml

- name: Upload mutation report
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: mutmut-report
    path: html/

- name: Save mutmut cache
  if: always()
  uses: actions/cache/save@v4
  with:
    path: .mutmut-cache
    key: mutmut-${{ github.ref }}-${{ hashFiles('src/**/*.py', 'tests/**/*.py') }}

- name: Check mutation score threshold
  run: |
    SURVIVED=$(mutmut results 2>&1 | grep -c "Survived" || true)
    TOTAL=$(mutmut results 2>&1 | grep -E "^[0-9]+" | wc -l || true)
    echo "Survived: $SURVIVED / $TOTAL mutants"
    # Fail if survival rate > 40% (i.e., kill rate < 60%)
    python -c "
    import subprocess, sys
    result = subprocess.run(['mutmut', 'results'], capture_output=True, text=True)
    survived = result.stdout.count('Survived')
    total = len([l for l in result.stdout.splitlines() if l.strip().startswith(tuple('0123456789'))])
    if total > 0 and survived / total > 0.4:
        print(f'FAIL: mutation kill rate {(1 - survived/total)*100:.1f}% < 60% threshold')
        sys.exit(1)
    print(f'PASS: mutation kill rate {(1 - survived/total)*100:.1f}%')
    "
```

## Performance

- mutmut runs tests once per mutant sequentially by default — a project with 500 mutants and a 2s test suite takes ~17 minutes. Use `-x` (stop-on-first-failure) in the runner command to abort early per mutant.
- Cache `.mutmut-cache` in CI — mutmut skips already-tested mutants for unchanged source lines on re-runs (incremental mode is automatic via the cache).
- Scope `paths_to_mutate` tightly: mutating only domain/service layers reduces mutant count by 50-70% vs full `src/`.
- Use `--timeout=N` in the pytest runner command — hung mutants block the queue; 2-3× your slowest unit test is a safe ceiling.
- `pytest-xdist` (`-n auto`) parallel mode works with mutmut's runner — reduces per-mutant test time for suites with many independent tests.
- Run mutmut in a separate CI job (not blocking PR merge) until a stable baseline is established — nightly jobs work well initially.

## Security

- mutmut modifies source files in place during a run and restores them immediately after — a crash mid-run can leave a file mutated. Always run in a clean checkout (CI) or commit your work before running locally.
- `.mutmut-cache` is a SQLite file containing mutant source snippets and test results — treat as an internal development artifact. Do not commit to version control (add to `.gitignore`).
- The test runner command in `pyproject.toml` executes arbitrary shell commands — ensure no sensitive environment variables are needed by the runner script.

## Testing

```bash
# Run all mutations
mutmut run

# Run for a specific file only
mutmut run --paths-to-mutate src/mypackage/domain.py

# Show results summary
mutmut results

# Show details for a specific surviving mutant (ID from results)
mutmut show 42

# Apply mutant to inspect it manually
mutmut apply 42
# (remember to restore afterwards)
mutmut reset

# Generate HTML report (creates html/ directory)
mutmut html
open html/index.html

# Generate JUnit XML for CI ingestion
mutmut junitxml > mutmut-results.xml

# Re-run only surviving/timeout mutants from a previous run
mutmut run --rerun-all
```

## Dos

- Add `.mutmut-cache` to `.gitignore` — the cache is local/CI state, not source code.
- Use `-x` (fail-fast) in the pytest runner command inside `pyproject.toml` — mutmut exits the test run as soon as one test fails, which is all it needs to kill a mutant.
- Cache `.mutmut-cache` in CI keyed by a hash of source and test files — incremental re-runs skip already-tested mutants and are dramatically faster.
- Scope `paths_to_mutate` to `src/` domain/service subdirectories — avoid mutating `__init__.py` files, CLI entry points, and configuration modules.
- Use `mutmut show <id>` to inspect surviving mutants individually before writing new tests — understand what logic gap the mutant exposes rather than writing tests to kill it blindly.
- Set `tests_dir` explicitly to unit tests — including integration or e2e tests in the runner multiplies per-mutant time by their slowness.

## Don'ts

- Don't run `mutmut run` without a test timeout in the runner command — a mutant that causes an infinite loop will block the entire run indefinitely.
- Don't mutate generated code (Pydantic model validators auto-generated by tools, migration files, OpenAPI-generated clients) — surviving mutants there are noise.
- Don't commit `.mutmut-cache` — it contains absolute path references and differs across machines.
- Don't use `backup = true` — it creates `.orig` files next to every mutated file and pollutes the workspace; the cache is sufficient for recovery.
- Don't treat mutation score as a substitute for coverage — a file with 100% line coverage can still have surviving mutants if assertions don't verify computed values.
- Don't set a mutation threshold gate on the first run without measuring the baseline — the initial kill rate on an untested project can be under 30%; establish a baseline, fix gaps, then introduce the gate.
