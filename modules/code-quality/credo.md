---
name: credo
categories: [linter]
languages: [elixir]
exclusive_group: elixir-linter
recommendation_score: 90
detection_files: [.credo.exs]
---

# credo

## Overview

Static code analysis tool for Elixir focused on code consistency, readability, and refactoring opportunities. Runs as `mix credo` and provides checks across design, readability, refactoring, and warning categories. Credo is the standard Elixir static analysis tool — use it alongside `mix dialyzer` (type checking via Dialyxir) for comprehensive coverage. Configuration lives in `.credo.exs`. Credo's strict mode (`--strict`) enables additional checks appropriate for production codebases.

## Architecture Patterns

### Installation & Setup

Add to `mix.exs` as a dev/test dependency:

```elixir
# mix.exs
defp deps do
  [
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    # optional: {:dialyxir, "~> 1.4", only: [:dev], runtime: false}
  ]
end
```

```bash
mix deps.get
mix credo                     # run with default config
mix credo --strict            # include additional checks
mix credo gen.config          # generate .credo.exs at project root
```

### Rule Categories

| Category | What It Checks | Pipeline Severity |
|---|---|---|
| `Credo.Check.Warning` | Unused variables, `IO.inspect` left in, `TODO`/`FIXME` markers, `Kernel.apply/3` misuse | CRITICAL |
| `Credo.Check.Design` | Tagged todo items, modularity (aliases, module attributes) | WARNING |
| `Credo.Check.Readability` | Module doc presence, function names, alias ordering, max line length | WARNING |
| `Credo.Check.Refactor` | Cyclomatic complexity, nested calls, long functions, long parameter lists | WARNING |
| `Credo.Check.Consistency` | `do:` vs `do...end` style, space around operators | INFO |

### Configuration Patterns

`.credo.exs` at the project root:

```elixir
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: [
          "lib/",
          "src/",
          "test/",
          "web/",
          "apps/*/lib/",
          "apps/*/test/"
        ],
        excluded: [
          ~r"/_build/",
          ~r"/deps/",
          ~r"/node_modules/"
        ]
      },
      plugins: [],
      requires: [],
      strict: true,
      parse_timeout: 5000,
      color: true,
      checks: %{
        enabled: [
          # Warning category — keep all enabled
          {Credo.Check.Warning.IoInspect, []},
          {Credo.Check.Warning.UnusedEnumOperation, []},
          {Credo.Check.Warning.UnusedFileOperation, []},
          {Credo.Check.Warning.UnusedKeywordOperation, []},
          {Credo.Check.Warning.UnusedListOperation, []},
          {Credo.Check.Warning.UnusedPathOperation, []},
          {Credo.Check.Warning.UnusedRegexOperation, []},
          {Credo.Check.Warning.UnusedStringOperation, []},
          {Credo.Check.Warning.UnusedTupleOperation, []},

          # Readability
          {Credo.Check.Readability.ModuleDoc, []},
          {Credo.Check.Readability.MaxLineLength, [max_length: 120, ignore_urls: true]},
          {Credo.Check.Readability.FunctionNames, []},

          # Refactor
          {Credo.Check.Refactor.CyclomaticComplexity, [max_complexity: 9]},
          {Credo.Check.Refactor.Nesting, [max_nesting: 3]},
          {Credo.Check.Refactor.LongQuoteBlocks, []},
          {Credo.Check.Refactor.MatchInCondition, []},

          # Design
          {Credo.Check.Design.TagTODO, [exit_status: 0]},  # warn but don't fail on TODOs
          {Credo.Check.Design.TagFIXME, []},
        ],
        disabled: [
          # Disable if team uses consistent do: shorthand
          # {Credo.Check.Readability.PredicateFunctionNames, []},
        ]
      }
    }
  ]
}
```

Inline suppression:
```elixir
# credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
very_long_function_call(argument_one, argument_two, argument_three, argument_four)

# credo:disable-for-this-file Credo.Check.Design.TagTODO
```

### CI Integration

```yaml
# .github/workflows/quality.yml
- name: Run Credo
  run: mix credo --strict --format oneline
  env:
    MIX_ENV: test
```

```yaml
# With JUnit XML output for CI test reporting
- name: Run Credo
  run: mix credo --strict --format json | tee credo-report.json
```

For umbrella apps, run from the root:
```bash
mix credo --strict
```

Credo traverses `apps/*/lib/` automatically when configured in `.credo.exs`.

## Performance

- Credo parses files in parallel — typical Elixir projects (< 200 modules) lint in 1-3s.
- The `parse_timeout` option (default 5000ms) controls per-file parse timeout — increase for very large generated files.
- Exclude `_build/` and `deps/` in `.credo.exs` `files.excluded` — Credo does not analyze them by default but explicit exclusion prevents issues with symlinked paths.
- `mix credo list` shows which checks would run without running the analysis — useful for validating config changes.

## Security

Credo is primarily a code quality tool, not a security scanner. However, these checks are security-adjacent:

- `Credo.Check.Warning.IoInspect` — `IO.inspect/2` left in production code may leak sensitive data (request params, tokens) to stdout/logs.
- `Credo.Check.Warning.ExpensiveEmptyEnumCheck` — performance degradation from inefficient enum ops on untrusted inputs.

For Elixir security analysis, pair Credo with `mix sobelow` (Phoenix security scanner) for SQL injection, XSS, directory traversal, and insecure configuration detection.

## Testing

```bash
# Run all checks
mix credo

# Run strict mode (enables additional checks)
mix credo --strict

# Show suggestions only (no explanations)
mix credo --format oneline

# Show only issues for files changed since last commit
mix credo diff HEAD~1

# Run a single check
mix credo --checks Credo.Check.Warning.IoInspect

# List all available checks
mix credo list

# Explain a check
mix credo explain Credo.Check.Refactor.CyclomaticComplexity

# Validate .credo.exs config
mix credo --config-file .credo.exs
```

## Dos

- Enable `strict: true` in `.credo.exs` rather than passing `--strict` in CI — it makes the strictness level explicit and version-controlled.
- Run `mix credo diff HEAD~1` in pre-commit hooks — it only checks changed files, keeping pre-commit fast while still catching regressions.
- Keep `Credo.Check.Warning.IoInspect` enabled — `IO.inspect` left in production Elixir code is equivalent to debug logging leaking data.
- Configure `Credo.Check.Design.TagTODO` with `exit_status: 0` during development to warn without failing — tighten to default (non-zero exit) before shipping.
- Add `.credo.exs` to version control — team-wide consistency depends on shared configuration.
- Use `mix credo --format json` in CI to emit structured output for dashboards or quality tracking.

## Don'ts

- Don't suppress `Credo.Check.Warning.*` checks — the Warning category flags real bugs (unreturned operation results, left-in debug code).
- Don't disable readability checks globally because existing code violates them — use `credo:disable-for-this-file` for legacy files and enforce for new code.
- Don't use Credo as the only analysis tool — combine with `mix dialyzer` for type checking and `mix sobelow` for security scanning; they cover orthogonal concerns.
- Don't ignore `CyclomaticComplexity` violations in GenServer callbacks — complex callbacks are hard to test and prone to race conditions.
- Don't exclude `test/` from analysis — test code quality matters; `IO.inspect` left in tests leaks to CI logs and `UnusedVariable` hides test logic bugs.
