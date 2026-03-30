# mix-format

## Overview

Elixir's built-in code formatter, shipped with Mix since Elixir 1.6. Zero external dependencies — `mix format` is always available. Enforces the official Elixir style guide: 2-space indentation, consistent operator spacing, trailing commas in multi-line structures. Configuration via `.formatter.exs` at the project root (or umbrella app root). Use `mix format --check-formatted` in CI to fail on unformatted code without writing. Supports plugins (e.g., `FreedomFormatter`, `Phoenix.LiveView` formatters) for DSL-aware formatting.

## Architecture Patterns

### Installation & Setup

```bash
# mix format ships with Elixir — no separate install
elixir --version   # confirms Elixir (and mix format) is available

# Verify formatter config is valid
mix format --check-formatted
```

**`.formatter.exs` (project root):**
```elixir
[
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib,test}/**/*.{ex,exs}"
  ],
  line_length: 98,
  locals_without_parens: [
    # Custom DSL macros that should not require parentheses
    # Add your project-specific macros here
  ]
]
```

**Umbrella app `.formatter.exs`:**
```elixir
[
  inputs: ["{mix,.formatter}.exs"],
  subdirectories: ["apps/*"]
]
```

Each app in `apps/` has its own `.formatter.exs` with its own `inputs:` and `locals_without_parens:`.

### Rule Categories

`mix format` is not rule-based — it applies a fixed style. Key behaviors:

| Behavior | Description |
|---|---|
| Indentation | 2 spaces, no tabs |
| Line length | Default 98 (configurable via `line_length`) |
| Trailing commas | Added to multi-line lists, maps, function args |
| String concatenation | `<>` spacing normalized |
| Pipe operators | Each pipe on its own line |
| Keyword lists | Consistent spacing around `=>` and `:` |

**Plugin support (`.formatter.exs` with plugins):**
```elixir
[
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib,test}/**/*.{ex,exs}",
    "lib/**/*.html.heex"    # HEEx templates
  ],
  line_length: 98
]
```

### Configuration Patterns

**`locals_without_parens` for custom macros:**
```elixir
# .formatter.exs for Phoenix projects
[
  import_deps: [:ecto, :phoenix],
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib,test}/**/*.{ex,exs}",
    "lib/**/*.html.heex"
  ],
  subdirectories: ["priv/*/migrations"],
  locals_without_parens: [
    # Ecto schema macros
    field: 2,
    field: 3,
    belongs_to: 2,
    belongs_to: 3,
    has_many: 2,
    has_many: 3,
    has_one: 2,
    has_one: 3
  ],
  line_length: 98
]
```

**Import formatter configuration from deps:**
```elixir
[
  import_deps: [:ecto, :ecto_sql, :phoenix],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
```

`import_deps:` pulls `locals_without_parens` from the listed dependency's `.formatter.exs` — no manual duplication of macro lists.

### CI Integration

```yaml
# .github/workflows/quality.yml
- name: Check Elixir formatting
  run: mix format --check-formatted
```

**With cache for dependencies:**
```yaml
- name: Set up Elixir
  uses: erlef/setup-beam@v1
  with:
    elixir-version: "1.17"
    otp-version: "27"

- name: Install dependencies
  run: mix deps.get

- name: Check formatting
  run: mix format --check-formatted
```

**Pre-commit hook via `.pre-commit-config.yaml`:**
```yaml
repos:
  - repo: local
    hooks:
      - id: mix-format
        name: mix format
        entry: mix format
        language: system
        files: \.(ex|exs)$
        pass_filenames: false
```

**Makefile:**
```makefile
.PHONY: format format-check

format:
	mix format

format-check:
	mix format --check-formatted
```

## Performance

- `mix format` on a typical Phoenix app (200 files) completes in under 2 seconds.
- Umbrella apps: each sub-app's formatter runs in sequence — total time scales linearly with app count.
- `--check-formatted` is faster than `mix format` write — it short-circuits on the first unformatted file.
- For large codebases, scope formatting to changed files in pre-commit hooks: `mix format $(git diff --staged --name-only | grep -E '\.exs?$')`.

## Security

mix format has no security analysis capability. Key practices:

- `mix format` does not execute code in the files it formats — safe to run on untrusted source.
- The `.formatter.exs` file is executed as Elixir code (`eval`ed by Mix) — review it for malicious content when pulling from external repos.
- Plugin formatters (e.g., `Phoenix.LiveView.HTMLFormatter`) are Mix dependencies — pin their versions in `mix.lock` and review changelogs on upgrade.

## Testing

```bash
# Check all files without writing (CI mode)
mix format --check-formatted

# Format all files in place
mix format

# Format a specific file
mix format lib/myapp/user.ex

# Dry run (show what would change without writing) — not built-in, use diff
mix format && git diff --stat

# Check a single file
mix format --check-formatted lib/myapp/user.ex

# Verify config is valid
mix format --dry-run 2>&1  # prints file list without formatting

# Debug: see which files are covered by .formatter.exs
mix format --print-applicable-files
```

## Dos

- Use `import_deps:` to pull `locals_without_parens` from framework dependencies — avoids duplicating Phoenix/Ecto macro lists manually.
- Commit `.formatter.exs` to version control — formatting must be reproducible across all developer machines and CI.
- Run `mix format --check-formatted` in CI before tests — formatting failures are fast to catch and should not delay test runs.
- Add `lib/**/*.html.heex` to `inputs:` with the `Phoenix.LiveView.HTMLFormatter` plugin for Phoenix LiveView projects — HEEx templates are not formatted without the plugin.
- Set `line_length: 98` — the default is also 98; making it explicit prevents surprise changes if the Elixir team changes the default.
- Configure your editor to run `mix format` on save — prevents accumulation of formatting fixes in PRs.

## Don'ts

- Don't manually specify `locals_without_parens` for macros that are already covered by `import_deps:` — duplication causes drift when the dep's formatter config changes.
- Don't run `mix format` in CI with write access — use `--check-formatted` only; auto-commits from CI cause history noise.
- Don't exclude `test/` from `inputs:` — test files must be formatted consistently with source files.
- Don't ignore formatting failures in CI because "it's just style" — unformatted Elixir code signals that the developer skipped the pre-commit hook and warrants investigation.
- Don't use mix format plugins without pinning the plugin version — plugin formatting behavior can change between releases.
- Don't add `priv/*/migrations` to `inputs:` without understanding the migration DSL — Ecto migration macros require `locals_without_parens` entries or formatting will add unwanted parentheses.
