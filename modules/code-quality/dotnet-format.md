# dotnet-format

## Overview

C#/VB.NET/F# formatter built into the .NET SDK (available since .NET 6 as `dotnet format`). Reads formatting rules from `.editorconfig` — no separate config file. Enforces whitespace, style, and analyzer diagnostic rules in one pass. Use `--verify-no-changes` in CI to fail on unformatted code without writing. Supports `--include`/`--exclude` filters to scope formatting to specific files or directories. Three sub-commands: `whitespace` (indentation, spacing), `style` (IDE-level code style), `analyzers` (Roslyn analyzer fixes).

## Architecture Patterns

### Installation & Setup

```bash
# dotnet format ships with .NET 6+ SDK — no separate install
dotnet --version   # confirms SDK version

# For .NET 5 and earlier (deprecated — upgrade recommended)
dotnet tool install --global dotnet-format --version 5.*

# Verify
dotnet format --version
```

**`.editorconfig` (project root or solution root):**
```ini
# EditorConfig — https://editorconfig.org
root = true

[*]
indent_style = space
end_of_line = lf
charset = utf-8
trim_trailing_whitespace = true
insert_final_newline = true

[*.{cs,vb}]
indent_size = 4

[*.cs]
# Namespace declarations
csharp_style_namespace_declarations = file_scoped:warning

# Braces
csharp_new_line_before_open_brace = all

# Using directives
dotnet_sort_system_directives_first = true
dotnet_separate_import_directive_groups = false
csharp_using_directive_placement = outside_namespace:warning

# Expression preferences
dotnet_style_prefer_auto_properties = true:suggestion
csharp_style_expression_bodied_methods = when_on_single_line:suggestion
csharp_style_expression_bodied_properties = true:suggestion
csharp_prefer_simple_default_expression = true:suggestion

# Null checks
dotnet_style_null_propagation = true:suggestion
dotnet_style_coalesce_expression = true:suggestion

# var preferences
csharp_style_var_for_built_in_types = false:suggestion
csharp_style_var_when_type_is_apparent = true:suggestion

[*.{json,yaml,yml}]
indent_size = 2

[*.md]
trim_trailing_whitespace = false
```

### Rule Categories

`dotnet format` applies three categories of fixes:

| Sub-command | What It Fixes | Config Source |
|---|---|---|
| `whitespace` | Indentation, spacing, line endings, trailing whitespace | `.editorconfig` whitespace rules |
| `style` | Code style preferences (var usage, expression bodies, using placement) | `.editorconfig` `csharp_style_*` and `dotnet_style_*` |
| `analyzers` | Roslyn analyzer diagnostics with code fixes | `.editorconfig` severity + analyzer packages |

**Severity levels in `.editorconfig`:**
```ini
# silent — no suggestion, no format fix applied
# suggestion — IDE hint, applied by dotnet format style
# warning — compiler warning, applied by dotnet format analyzers
# error — compiler error, always fails build
dotnet_diagnostic.IDE0001.severity = suggestion   # simplify names
dotnet_diagnostic.IDE0003.severity = warning      # remove this. qualification
dotnet_diagnostic.CA1822.severity = warning       # mark member as static
```

### Configuration Patterns

**Scoping to specific projects:**
```bash
# Format a single project
dotnet format ./src/MyApp/MyApp.csproj

# Format the entire solution
dotnet format ./MyApp.sln

# Include only specific files
dotnet format --include src/MyApp/Services/ --include src/MyApp/Controllers/

# Exclude generated code
dotnet format --exclude src/Generated/ --exclude **/*.g.cs
```

**`global.json` — pin SDK version:**
```json
{
  "sdk": {
    "version": "9.0.100",
    "rollForward": "latestPatch"
  }
}
```

**`.editorconfig` hierarchy:** dotnet format reads the nearest `.editorconfig` and walks up to the `root = true` file. Place project-specific overrides in subdirectory `.editorconfig` files.

### CI Integration

```yaml
# .github/workflows/quality.yml
- name: Check .NET formatting
  run: dotnet format --verify-no-changes --verbosity diagnostic
```

**Full pipeline with scoped checks:**
```yaml
- name: Setup .NET
  uses: actions/setup-dotnet@v4
  with:
    dotnet-version: "9.0.x"

- name: Restore dependencies
  run: dotnet restore

- name: Check whitespace formatting
  run: dotnet format whitespace --verify-no-changes

- name: Check code style
  run: dotnet format style --verify-no-changes

- name: Check analyzer diagnostics
  run: dotnet format analyzers --verify-no-changes --severity warn
```

**Pre-commit hook:**
```bash
#!/usr/bin/env bash
# .git/hooks/pre-commit
staged=$(git diff --cached --name-only --diff-filter=ACM | grep '\.cs$')
if [ -n "$staged" ]; then
  dotnet format --include $staged
  echo "$staged" | xargs git add
fi
```

## Performance

- `dotnet format whitespace` is fast — processes a 500-file project in 5-10 seconds.
- `dotnet format style` and `dotnet format analyzers` are slower — they invoke the Roslyn compiler; 30-120 seconds for large solutions.
- Use `--include` to scope to changed files in CI — avoids full-solution analysis on every PR.
- Separate `whitespace`, `style`, and `analyzers` into parallel CI jobs if the combined runtime exceeds 2 minutes.
- `dotnet format analyzers` requires a full build/restore to resolve analyzer packages — ensure `dotnet restore` runs before it.

## Security

- `dotnet format analyzers` applies Roslyn security analyzers (e.g., `CA2100` for SQL injection, `CA5394` for insecure randomness) as code fixes — review all `analyzers` sub-command changes before committing.
- Pin the .NET SDK version in `global.json` — `dotnet format` behavior can change between SDK versions.
- `.editorconfig` does not execute code — safe for untrusted repo inspection.
- Generated files (`*.g.cs`, `*.Designer.cs`) should be excluded — they are regenerated by scaffolders and do not need manual formatting; reformatting them can break the scaffold relationship.

## Testing

```bash
# Check all formatting without writing (CI mode)
dotnet format --verify-no-changes

# Apply all formatting
dotnet format

# Check only whitespace rules
dotnet format whitespace --verify-no-changes

# Apply only whitespace rules
dotnet format whitespace

# Check style rules
dotnet format style --verify-no-changes

# Apply analyzer fixes (severity warning and above)
dotnet format analyzers --severity warn

# Verbose output (shows each file processed)
dotnet format --verbosity diagnostic

# Scope to a specific project
dotnet format ./src/MyApp/MyApp.csproj --verify-no-changes
```

## Dos

- Use a hierarchical `.editorconfig` with `root = true` at solution root — ensures consistent formatting across all projects in the solution without duplicating rules.
- Run `dotnet format whitespace` separately from `analyzers` in CI — whitespace checks are fast and catch the most common issues; run them first to fail fast.
- Use `--severity warn` with `dotnet format analyzers` — only applies fixes for diagnostics at warning or error severity, avoiding noisy suggestion-level changes.
- Exclude generated files with `--exclude **/*.g.cs` — generated code is rebuilt on every scaffold and should not be manually formatted.
- Pin the .NET SDK version in `global.json` and ensure CI uses the same version as developers — dotnet format output can vary between SDK patch versions.
- Configure `.editorconfig` `csharp_style_namespace_declarations = file_scoped:warning` for .NET 6+ projects — file-scoped namespaces reduce indentation by one level.

## Don'ts

- Don't run `dotnet format` without `--verify-no-changes` in CI — without it, the command exits 0 and writes files, causing a dirty working tree.
- Don't apply `dotnet format analyzers` without reviewing the diff — analyzer fixes can change logic (e.g., `CA1822` marking a method static changes its virtual dispatch behavior).
- Don't configure `.editorconfig` rules at `error` severity for style preferences — error-level IDE rules cause build failures for all developers, not just formatting checks.
- Don't skip the `dotnet restore` step before `dotnet format analyzers` — without restored packages, analyzer packages are missing and the command silently skips analyzer checks.
- Don't mix `dotnet format` with legacy `StyleCop.Analyzers` XML config — `.editorconfig` is the canonical config source; mixing formats causes rule conflicts.
- Don't format `*.Designer.cs` files — they are auto-generated by the Windows Forms/MAUI designer and will be overwritten with their original formatting on the next designer save.
