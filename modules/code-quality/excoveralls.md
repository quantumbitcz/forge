# excoveralls

## Overview

`excoveralls` is the standard coverage tool for Elixir projects. It wraps Erlang's `:cover` module and integrates with ExUnit to measure line and function coverage during `mix test`. Reports to the terminal, HTML, or Coveralls/Codecov via LCOV. Configure in `mix.exs` under the `coveralls` key. For umbrella projects, use `--umbrella` to aggregate coverage across all child apps. Enforce minimum coverage thresholds with `test_coverage: [minimum_coverage: 80]` or fail CI when coverage drops.

## Architecture Patterns

### Installation & Setup

```elixir
# mix.exs
defp deps do
  [
    {:excoveralls, "~> 0.18", only: :test}
  ]
end

def project do
  [
    app: :my_app,
    version: "0.1.0",
    elixir: "~> 1.16",
    test_coverage: [tool: ExCoveralls],
    preferred_cli_env: [
      coveralls: :test,
      "coveralls.detail": :test,
      "coveralls.post": :test,
      "coveralls.html": :test,
      "coveralls.json": :test,
      "coveralls.lcov": :test
    ]
  ]
end
```

```bash
# Quick terminal summary
MIX_ENV=test mix coveralls

# HTML report
MIX_ENV=test mix coveralls.html

# LCOV for Codecov/Coveralls
MIX_ENV=test mix coveralls.lcov

# JSON format
MIX_ENV=test mix coveralls.json

# Umbrella project
MIX_ENV=test mix coveralls --umbrella
```

### Rule Categories

| Report Type | Command | Use |
|---|---|---|
| Terminal | `mix coveralls` | Quick local check |
| HTML | `mix coveralls.html` | Visual inspection |
| LCOV | `mix coveralls.lcov` | CI ingestion (Codecov) |
| JSON | `mix coveralls.json` | Coveralls.io service |
| Detail | `mix coveralls.detail` | Line-by-line coverage in terminal |

### Configuration Patterns

**`coveralls.json` configuration file:**
```json
{
  "coverage_options": {
    "minimum_coverage": 80,
    "treat_no_relevant_lines_as_covered": true,
    "output_dir": "cover/",
    "template_path": "custom_coverage.html.eex"
  },
  "skip_files": [
    "lib/my_app/repo.ex",
    "lib/my_app/application.ex",
    "lib/my_app_web/telemetry.ex",
    "lib/my_app_web/router.ex",
    "lib/**/migration*.ex",
    "test/",
    "deps/"
  ],
  "groups": [
    {
      "name": "Core",
      "paths": ["lib/my_app/"]
    },
    {
      "name": "Web",
      "paths": ["lib/my_app_web/"]
    }
  ]
}
```

**mix.exs inline configuration:**
```elixir
def project do
  [
    test_coverage: [
      tool: ExCoveralls,
      minimum_coverage: 80,
      output_dir: "cover/"
    ]
  ]
end
```

**Umbrella project — aggregate coverage:**
```bash
# Run from umbrella root
MIX_ENV=test mix coveralls --umbrella

# HTML report for all child apps
MIX_ENV=test mix coveralls.html --umbrella
```

**Excluding files via `coveralls.json`:**
```json
{
  "skip_files": [
    "lib/my_app/application.ex",
    "lib/my_app_web/endpoint.ex",
    "lib/my_app_web/telemetry.ex",
    "lib/my_app_web/gettext.ex",
    "lib/**/migration*.ex",
    "priv/"
  ]
}
```

**Running with specific test paths:**
```bash
# Only test specific module and collect coverage
MIX_ENV=test mix coveralls --include integration
MIX_ENV=test mix test --cover test/my_app/core_test.exs
```

### CI Integration

```yaml
# .github/workflows/test.yml
- name: Set up Elixir
  uses: erlef/setup-beam@v1
  with:
    elixir-version: "1.16"
    otp-version: "26"

- name: Install dependencies
  run: mix deps.get

- name: Run tests with coverage
  run: MIX_ENV=test mix coveralls.lcov
  env:
    MIX_ENV: test

- name: Upload coverage to Codecov
  uses: codecov/codecov-action@v4
  with:
    files: cover/lcov.info
    fail_ci_if_error: true
```

**GitHub PR comment with coverage summary:**
```yaml
- name: Run tests with JSON coverage
  run: MIX_ENV=test mix coveralls.json

- name: Upload to Coveralls
  uses: coverallsapp/github-action@v2
  with:
    file: cover/excoveralls.json
    format: excoveralls
```

## Performance

- `:cover` (Erlang's coverage tool) instruments BEAM bytecode — adds 20-40% to test suite execution time for large projects.
- The `--umbrella` flag runs coverage for all child apps sequentially — parallel runs with `async: true` in ExUnit may cause `:cover` conflicts; disable async if instrumentation errors occur.
- Use `MIX_ENV=test mix test` (without coverage) for the normal development feedback loop — run coverage only in CI or pre-merge.
- HTML report generation is slow for large codebases — generate only LCOV in CI and HTML as a scheduled or on-demand step.
- Coverage data is held in memory by the `:cover` Erlang process — very large test suites (>1000 modules) may cause memory pressure.

## Security

- `cover/` directory output (HTML, JSON, LCOV) contains file paths and line counts — safe for CI artifacts.
- Do not include `cover/` in version control — add `cover/` to `.gitignore`.
- ExCoveralls JSON format posted to Coveralls.io includes repository and commit metadata — review the Coveralls privacy settings for private repositories.
- HTML reports embed source code — do not publish publicly for proprietary Elixir applications.

## Testing

```bash
# Install deps (test env)
MIX_ENV=test mix deps.get

# Run with terminal coverage summary
MIX_ENV=test mix coveralls

# Run with line detail
MIX_ENV=test mix coveralls.detail

# HTML report
MIX_ENV=test mix coveralls.html
open cover/excoveralls.html

# LCOV output
MIX_ENV=test mix coveralls.lcov
cat cover/lcov.info | head -20

# Umbrella
MIX_ENV=test mix coveralls.html --umbrella

# Fail if below minimum
# (enforced via minimum_coverage in coveralls.json or mix.exs)
MIX_ENV=test mix coveralls
```

## Dos

- Configure `minimum_coverage` in `coveralls.json` so `mix coveralls` fails the build when coverage drops — without it, low coverage goes unnoticed.
- Use `mix coveralls.lcov` for CI and upload to Codecov — LCOV is the standard format and provides trend tracking across commits.
- Add `coveralls.json` to version control so all developers and CI use identical exclusion rules.
- Exclude generated files, application entry points (`Application.ex`), router boilerplate, and migration modules from coverage — they inflate the denominator.
- For umbrella projects, always use `--umbrella` to get the aggregate view — per-app coverage misses cross-app integration paths.
- Run `mix coveralls.detail` locally when investigating which specific lines are uncovered — it shows a full annotated source view.

## Don'ts

- Don't set `minimum_coverage: 100` — Phoenix router callbacks, telemetry configuration, and `Application.start/2` are impractical to unit test.
- Don't add `cover/` to version control — HTML and JSON outputs change on every run and are meaningless in git history.
- Don't mix `async: true` ExUnit tests with coverage without testing for `:cover` conflicts first — concurrent test processes can corrupt coverage data for some Erlang/OTP versions.
- Don't use `MIX_ENV=dev mix coveralls` — the coverage tool should only run in `test` environment to avoid loading dev dependencies or configuration.
- Don't skip coverage for business logic modules (contexts, domain modules) by adding them to `skip_files` — reserve exclusions for infrastructure and generated code only.
