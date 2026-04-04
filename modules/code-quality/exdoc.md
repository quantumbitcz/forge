---
name: exdoc
categories: [doc-generator]
languages: [elixir]
exclusive_group: elixir-doc-generator
recommendation_score: 90
detection_files: [mix.exs]
---

# exdoc

## Overview

ExDoc is the standard documentation generator for Elixir. Add `ex_doc` to `mix.exs` as a dev dependency and run `mix docs` to generate HTML output. Module documentation is written using `@moduledoc` (module-level), `@doc` (function/macro-level), and `@typedoc` (type-level) module attributes with Markdown content. ExDoc integrates with Livebook so code examples can be run interactively. Published Hex packages are automatically hosted on `hexdocs.pm`.

## Architecture Patterns

### Installation & Setup

```elixir
# mix.exs
defp deps do
  [
    {:ex_doc, "~> 0.34", only: :dev, runtime: false},
    # Optional: earmark_parser is included transitively
  ]
end
```

```bash
mix deps.get
mix docs           # Generates doc/ directory with HTML
mix docs --output docs_output   # Custom output path
```

**`mix.exs` project metadata (appears in generated docs):**
```elixir
def project do
  [
    app: :my_app,
    version: "1.0.0",
    elixir: "~> 1.16",
    description: "A high-performance HTTP client for Elixir",
    source_url: "https://github.com/org/my_app",
    homepage_url: "https://hexdocs.pm/my_app",
    docs: docs()
  ]
end

defp docs do
  [
    main: "MyApp",              # Landing page module
    extras: ["README.md", "CHANGELOG.md", "guides/getting-started.md"],
    groups_for_extras: [
      Guides: ~r/guides\//
    ],
    groups_for_modules: [
      "Core": [MyApp, MyApp.Client, MyApp.Request],
      "Adapters": [MyApp.Adapters.HTTP, MyApp.Adapters.Mock],
      "Internals": ~r/MyApp\.Internal\./
    ],
    filter_modules: fn module, _metadata ->
      # Exclude internal modules from public docs
      not String.contains?(inspect(module), "Internal")
    end,
    formatters: ["html", "epub"]
  ]
end
```

### Rule Categories

| Category | Pattern | Pipeline Severity |
|---|---|---|
| Missing `@moduledoc` | Public module without `@moduledoc` | WARNING |
| `@moduledoc false` on public module | Intentionally hidden public module | INFO |
| Missing `@doc` | Public function without `@doc` | INFO |
| Missing `@typedoc` | Exported type without `@typedoc` | INFO |
| Missing examples | `@doc` without a code example block | INFO |

### Configuration Patterns

**Module documentation:**
```elixir
defmodule MyApp.Client do
  @moduledoc """
  HTTP client with automatic retry and circuit-breaker support.

  ## Usage

      client = MyApp.Client.new(base_url: "https://api.example.com")
      {:ok, %{status: 200, body: body}} = MyApp.Client.get(client, "/users")

  ## Configuration

  See `new/1` for all supported options.

  ## Error Handling

  All functions return `{:ok, response}` or `{:error, reason}` — they never raise.
  See `MyApp.Error` for the full error type hierarchy.
  """
```

**Function documentation:**
```elixir
@doc """
Creates a new client with the given options.

## Options

  * `:base_url` — (required) The base URL for all requests.
  * `:timeout` — Request timeout in milliseconds. Defaults to `5_000`.
  * `:retries` — Number of retry attempts on transient errors. Defaults to `3`.
  * `:adapter` — HTTP adapter module. Defaults to `MyApp.Adapters.HTTP`.

## Examples

    iex> client = MyApp.Client.new(base_url: "https://api.example.com")
    iex> is_struct(client, MyApp.Client)
    true

    iex> MyApp.Client.new([])
    ** (ArgumentError) :base_url is required

## Errors

Returns `{:error, :invalid_url}` if `:base_url` cannot be parsed as a valid URI.
"""
@spec new(keyword()) :: t()
def new(opts) do
```

**Type documentation:**
```elixir
@typedoc """
A parsed HTTP response.

Fields:
  * `status` — HTTP status code (e.g. `200`, `404`).
  * `headers` — Response headers as a list of `{name, value}` tuples.
  * `body` — The decoded response body, or raw binary if not JSON.
"""
@type response :: %{
  status: non_neg_integer(),
  headers: [{String.t(), String.t()}],
  body: term()
}
```

**Livebook integration — run examples in the browser:**
```elixir
@doc """
...
<!-- livebook:{"force_markdown":true} -->

```elixir
# Interactive example
{:ok, pid} = MyApp.start_link([])
```
"""
```

### CI Integration

```yaml
# .github/workflows/docs.yml
- name: Install dependencies
  run: mix deps.get

- name: Generate ExDoc
  run: mix docs

- name: Upload docs artifact
  uses: actions/upload-artifact@v4
  with:
    name: hexdocs
    path: doc/

# Hex.pm publishes docs automatically on `mix hex.publish`
- name: Publish to Hex.pm (on tag)
  if: startsWith(github.ref, 'refs/tags/')
  run: mix hex.publish --yes
  env:
    HEX_API_KEY: ${{ secrets.HEX_API_KEY }}
```

## Performance

- `mix docs` is fast (2-10s) — it parses Markdown and compiles templates, not Elixir bytecode.
- `extras:` with large Markdown files (CHANGELOG, long guides) adds noticeable time. Filter with `filter_modules` to exclude test/internal modules.
- ExDoc caches compiled templates. `mix docs` is effectively incremental between runs.

## Security

- ExDoc generates static HTML — no runtime security surface.
- `@moduledoc false` on a module hides it from docs but does not make it inaccessible — do not rely on doc suppression for security.
- Avoid putting credentials, internal service URLs, or debug tokens in `@doc` examples — they appear on `hexdocs.pm` for published packages.

## Testing

```bash
# Generate HTML docs
mix docs

# Open docs in browser (macOS)
open doc/index.html

# Check docs build in CI (exit code only)
mix docs 2>&1 | tail -5

# Verify doctests pass
mix test --only doctest

# Generate EPUB as well
mix docs --formatter epub
```

## Dos

- Provide `@moduledoc` for every public module — it is the first thing a developer reads when they `h MyApp.Client` in IEx.
- Write `iex>` examples in `@doc` blocks — they double as doctests runnable via `mix test`.
- Use the `docs:` key in `mix.exs` with `groups_for_modules` to organize the API into logical sections.
- Include a `guides/` directory with narrative Markdown files and list them in `extras:` — symbol docs alone are not enough for complex libraries.
- Set `source_url` in `mix.exs` so each documented function links to its source on GitHub.
- Exclude internal modules with `filter_modules` rather than scattering `@moduledoc false` across the codebase.

## Don'ts

- Don't use `@moduledoc false` on modules that have public functions — it hides them from `h` in IEx, frustrating users.
- Don't write `@doc` that duplicates the function signature — describe intent, options, return values, and failure modes.
- Don't skip `@typedoc` on public types — users cannot understand `@spec` annotations without knowing what each type means.
- Don't commit the `doc/` directory — it is generated output; regenerate in CI and deploy the artifact.
- Don't rely on doctests alone for verification — they test happy-path examples, not edge cases. Pair with ExUnit tests.
- Don't use raw HTML in `@moduledoc` — ExDoc renders Markdown; raw HTML is passed through but is fragile across ExDoc versions.
