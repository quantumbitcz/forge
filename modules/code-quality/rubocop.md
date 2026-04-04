---
name: rubocop
categories: [linter, formatter]
languages: [ruby]
exclusive_group: ruby-formatter
recommendation_score: 90
detection_files: [.rubocop.yml, .rubocop.yaml]
---

# rubocop

## Overview

Ruby's primary linter and formatter. Enforces the Ruby Style Guide via 400+ cops organized into departments. `rubocop` checks style, layout, and correctness; `rubocop --autocorrect` applies safe fixes in place. Departments: `Layout` (whitespace/indentation), `Lint` (potential bugs), `Metrics` (complexity/length), `Naming` (conventions), `Security` (dangerous patterns), `Style` (idiomatic Ruby). For Rails projects, add `rubocop-rails`; for RSpec, add `rubocop-rspec`. Configuration lives in `.rubocop.yml`.

## Architecture Patterns

### Installation & Setup

```ruby
# Gemfile
group :development, :test do
  gem 'rubocop', '~> 1.70', require: false
  gem 'rubocop-rails', require: false   # for Rails projects
  gem 'rubocop-rspec', require: false   # for RSpec
  gem 'rubocop-performance', require: false
end
```

```bash
bundle install
bundle exec rubocop              # run all cops
bundle exec rubocop --autocorrect # auto-fix safe violations
bundle exec rubocop --only Layout # run only Layout department
```

### Rule Categories

| Department | What It Checks | Pipeline Severity |
|---|---|---|
| `Lint` | Shadowed variables, ambiguous regexp, void conditions, rescue exception | CRITICAL |
| `Security` | Dynamic code execution, `Marshal.load`, `YAML.load` (unsafe) | CRITICAL |
| `Metrics` | Method length, class length, cyclomatic complexity, parameter count | WARNING |
| `Layout` | Indentation, trailing whitespace, blank lines, alignment | WARNING |
| `Naming` | Method, variable, class, constant naming conventions | WARNING |
| `Style` | Frozen string literals, `unless`/`until`, string quotes, hash syntax | INFO |
| `Performance` | `Array#flatten` abuse, `Symbol#to_proc` misuse, `Enumerable#sort` on non-comparable | WARNING |
| `Rails` | `find_each` vs `all.each`, `presence` vs `blank?`, `logger.info` vs `puts` | WARNING |

### Configuration Patterns

`.rubocop.yml` at the project root:

```yaml
# .rubocop.yml
require:
  - rubocop-rails
  - rubocop-rspec
  - rubocop-performance

AllCops:
  NewCops: enable              # opt into new cops immediately
  TargetRubyVersion: 3.3
  Exclude:
    - 'db/schema.rb'
    - 'db/migrate/**/*'        # auto-generated migrations
    - 'node_modules/**/*'
    - 'vendor/**/*'
    - 'bin/**/*'
    - '.git/**/*'

# Layout department
Layout/LineLength:
  Max: 120
  AllowedPatterns:
    - '\A\s*#'  # allow long comments (URLs, etc.)

Layout/MultilineMethodCallIndentation:
  EnforcedStyle: indented

# Metrics department
Metrics/MethodLength:
  Max: 20
  CountAsOne:
    - array
    - hash
    - heredoc

Metrics/ClassLength:
  Max: 200

Metrics/CyclomaticComplexity:
  Max: 10

Metrics/AbcSize:
  Max: 20

# Lint — keep all enabled at error severity
Lint/SuppressedException:
  Enabled: true

Lint/RescueException:
  Enabled: true

# Security
Security/YAMLLoad:
  Enabled: true

Security/MarshalLoad:
  Enabled: true

# Style
Style/FrozenStringLiteralComment:
  EnforcedStyle: always

Style/StringLiterals:
  EnforcedStyle: single_quotes

Style/Documentation:
  Enabled: false   # disable if team doesn't enforce module/class docs

# Rails
Rails/FindEach:
  Enabled: true

Rails/ActiveRecordAliases:
  Enabled: true
```

Per-file overrides (use for specs and migrations):
```yaml
# In .rubocop.yml
RSpec/ExampleLength:
  Max: 30

RSpec/MultipleExpectations:
  Max: 5

# Spec files get relaxed Metrics
Metrics/BlockLength:
  Exclude:
    - 'spec/**/*'
    - 'config/routes.rb'
```

Inline suppression:
```ruby
# rubocop:disable Security/Open
file = open(config_path) # config_path is from application config, not user input
# rubocop:enable Security/Open

hash = { key: value } # rubocop:disable Style/HashSyntax
```

Generate a baseline for gradual adoption:
```bash
bundle exec rubocop --auto-gen-config
# generates .rubocop_todo.yml with all existing violations
```

### CI Integration

```yaml
# .github/workflows/quality.yml
- name: Run RuboCop
  run: bundle exec rubocop --format github --no-color
```

`--format github` emits GitHub Actions workflow commands for inline PR annotations.

```yaml
# Output formats for different CI systems
bundle exec rubocop --format json | tee rubocop-report.json    # machine-readable
bundle exec rubocop --format html --out rubocop.html           # HTML report
```

## Performance

- RuboCop parallelizes analysis with `--parallel` (default on Ruby 2.6+). Enable explicitly for large codebases: `rubocop --parallel`.
- Result cache (`.rubocop_cache/`) stores results per file content hash — incremental runs skip unchanged files. Cache is automatically invalidated on config change.
- Disable expensive cops for local development: `rubocop --except Metrics` then enable Metrics in CI only.
- For monorepos, run RuboCop with `--force-exclusion` to respect `Exclude` patterns regardless of invocation path.
- `--display-only-offenses` skips the summary table for faster output parsing in CI.

## Security

The `Security` department catches dangerous Ruby patterns:

- `Security/YAMLLoad` — `YAML.load` deserializes arbitrary Ruby objects; use `YAML.safe_load` instead.
- `Security/MarshalLoad` — `Marshal.load` can execute arbitrary code from untrusted input.
- `Security/Open` — `Kernel#open` with user-controlled strings enables command injection via `|pipe` syntax.
- `Security/IoMethods` — `IO.read(path)` and similar with dynamic paths.
- Dynamic string execution (Kernel `binding` patterns) — flagged by the `Security/Eval` cop.

For web applications, complement RuboCop with `brakeman` (Rails-specific security scanner) which understands request data flow and taint tracking.

## Testing

```bash
# Run all cops
bundle exec rubocop

# Auto-correct safe violations
bundle exec rubocop --autocorrect

# Auto-correct including unsafe fixes (review diffs!)
bundle exec rubocop --autocorrect-all

# Run specific department
bundle exec rubocop --only Lint,Security

# Run on specific files
bundle exec rubocop app/models/user.rb spec/models/user_spec.rb

# Show enabled cops and their config
bundle exec rubocop --show-cops

# Check config file validity
bundle exec rubocop --no-lint

# Generate todo baseline
bundle exec rubocop --auto-gen-config

# Lint only changed files vs main branch
bundle exec rubocop $(git diff --name-only origin/main | grep '\.rb$')
```

## Dos

- Use `NewCops: enable` in `AllCops` — new cops default to `Pending` status; opt-in immediately rather than getting surprised on version upgrades.
- Run `rubocop --auto-gen-config` when onboarding existing codebases — it generates `.rubocop_todo.yml` that whitelists current violations, enabling fail-on-new-violations immediately.
- Enable `rubocop-rails` and `rubocop-rspec` for Rails projects — they add 100+ cops specific to Rails idioms and RSpec patterns that the base gem misses.
- Configure `Metrics/MethodLength` with `CountAsOne: [array, hash, heredoc]` — data literals inflate method length counts without indicating complexity.
- Use `--format github` in GitHub Actions CI for inline PR annotations showing exact line violations.
- Pin rubocop and its extensions to specific patch versions in the Gemfile — minor updates regularly introduce new failing cops.

## Don'ts

- Don't commit `.rubocop_todo.yml` with hundreds of disabled cops as a permanent baseline — it defeats the purpose. Use it only to bootstrap adoption, then resolve violations progressively.
- Don't disable `Lint` and `Security` departments — they flag real bugs and dangerous patterns, not style preferences.
- Don't run `--autocorrect-all` in CI — it modifies files mid-pipeline and creates commits that don't reflect developer intent. Use only locally.
- Don't ignore `Metrics/CyclomaticComplexity` — Ruby's duck typing and lack of compiler checks make complex methods especially risky.
- Don't disable `Style/FrozenStringLiteralComment` — unfrozen string literals create unnecessary object allocations and can cause subtle mutation bugs.
- Don't exclude `spec/` from all cops — test code quality matters; `Lint` violations in specs hide real test logic bugs.
