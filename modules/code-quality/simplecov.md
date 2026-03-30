# simplecov

## Overview

SimpleCov is the standard Ruby coverage tool. It wraps Ruby's built-in `Coverage` module and provides configurable formatters, groups, filters, and threshold enforcement. Configuration goes in `spec_helper.rb` (RSpec) or `test_helper.rb` (Minitest) — SimpleCov must be started before any application code is `require`d. `SimpleCov.minimum_coverage 80` fails the process with a non-zero exit code when coverage drops below the threshold. Multiple test suite runs can be merged with `SimpleCov.use_merging true`.

## Architecture Patterns

### Installation & Setup

```ruby
# Gemfile
group :test do
  gem "simplecov", require: false
  gem "simplecov-lcov", require: false   # LCOV formatter for CI
end
```

**RSpec setup (`spec/spec_helper.rb` — must be first lines):**
```ruby
require "simplecov"
require "simplecov-lcov"

SimpleCov::Formatter::LcovFormatter.config do |config|
  config.report_with_single_file = true
  config.single_report_path = "coverage/lcov.info"
end

SimpleCov.start do
  add_filter "/spec/"
  add_filter "/test/"
  add_filter "/config/"
  add_filter "/db/"
  add_filter "/vendor/"

  add_group "Models",      "app/models"
  add_group "Controllers", "app/controllers"
  add_group "Services",    "app/services"
  add_group "Jobs",        "app/jobs"
  add_group "Mailers",     "app/mailers"
  add_group "Helpers",     "app/helpers"
  add_group "Lib",         "lib/"

  enable_coverage :branch           # enable branch coverage (Ruby 2.5+)
  primary_coverage :branch          # use branch as the primary metric

  minimum_coverage line: 80, branch: 70
  minimum_coverage_by_file line: 70 # per-file minimum

  track_files "app/**/*.rb"         # include untested files in denominator
  track_files "lib/**/*.rb"
end
```

**Minitest setup (`test/test_helper.rb`):**
```ruby
require "simplecov"
SimpleCov.start "rails" do
  add_filter "/test/"
  minimum_coverage 80
end
```

**Rails preset:**
```ruby
SimpleCov.start "rails" do
  # The "rails" preset auto-filters: test/, spec/, config/, db/
  # Add custom filters on top:
  add_filter "app/channels/application_cable/"
  minimum_coverage 80
end
```

### Rule Categories

| Metric | Configuration | Notes |
|---|---|---|
| Line coverage | `minimum_coverage line: N` | Default metric |
| Branch coverage | `enable_coverage :branch` + `minimum_coverage branch: N` | Ruby 2.5+ |
| Per-file minimum | `minimum_coverage_by_file N` | Catches low-coverage new files |
| Untracked files | `track_files "app/**/*.rb"` | Includes files with zero tests |

### Configuration Patterns

**Custom filters for common exclusions:**
```ruby
SimpleCov.start do
  # Filter by regex
  add_filter /\.rb\z/ do |src_file|
    src_file.filename.include?("_spec.rb") ||
    src_file.filename.include?("/concerns/") ||   # if concerns are pure mixins
    src_file.filename.match?(/app\/admin\//)      # ActiveAdmin generated views
  end

  # Filter generated code (e.g., Jbuilder views, serializers)
  add_filter "app/views/"
end
```

**Merging parallel test runs:**
```ruby
SimpleCov.start do
  use_merging true
  merge_timeout 7200  # keep results for 2 hours
end
```

```bash
# Run RSpec and Minitest in parallel:
bundle exec rspec &
bundle exec rails test &
wait

# SimpleCov automatically merges via the .resultset.json file
# The final coverage report reflects all runs
```

**LCOV formatter for Codecov:**
```ruby
SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new([
  SimpleCov::Formatter::HTMLFormatter,
  SimpleCov::Formatter::LcovFormatter
])
```

### CI Integration

```yaml
# .github/workflows/test.yml
- name: Run RSpec with coverage
  run: bundle exec rspec

- name: Upload coverage to Codecov
  uses: codecov/codecov-action@v4
  with:
    files: coverage/lcov.info
    fail_ci_if_error: true

- name: Upload HTML coverage
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: coverage-html
    path: coverage/
```

**Failing on low coverage (SimpleCov handles exit code):**
```yaml
- name: Run tests
  run: bundle exec rspec
  # SimpleCov exits with non-zero if minimum_coverage is not met
  # No extra step needed — the test step itself fails
```

## Performance

- SimpleCov adds 5-15% overhead to test suite execution — acceptable for CI, noticeable on suites running > 5 minutes.
- Use `SimpleCov.at_exit` guard to ensure results are written even if tests crash — SimpleCov registers an `at_exit` hook automatically, but some test runners may bypass it.
- `track_files` adds overhead for large apps with many untested files — it must stat every matched file even if not loaded.
- HTML report generation is slow for large Rails apps (>2000 files) — use `SimpleCov::Formatter::LcovFormatter` only in CI and generate HTML as a scheduled report.
- `.resultset.json` (used for merging) grows large in long-running CI — set `merge_timeout` to a reasonable value (2-4 hours) to prevent stale data accumulation.

## Security

- `coverage/` directory output contains HTML with embedded source — gitignore it; do not publish publicly for proprietary apps.
- `.resultset.json` contains fully qualified file paths and coverage data — gitignore it.
- SimpleCov does not transmit data externally — it is entirely local. The `simplecov-lcov` gem adds LCOV export only, no upload.

## Testing

```bash
# Run RSpec with coverage
bundle exec rspec

# Run with specific formatter
COVERAGE=true bundle exec rspec

# Open HTML report
open coverage/index.html

# Check minimum manually (verbose output)
bundle exec rspec --format progress

# Minitest
bundle exec rails test

# Merge multiple runs (verify .resultset.json exists)
ls -lh .resultset.json
```

## Dos

- Start SimpleCov before `require "rails_helper"` or any application code — coverage misses files loaded before instrumentation starts.
- Enable `enable_coverage :branch` and set `primary_coverage :branch` for accurate coverage — line coverage alone misses unexecuted conditional branches.
- Use `track_files "app/**/*.rb"` to include untested files in the denominator — without it, files with zero tests are invisible to SimpleCov.
- Set `minimum_coverage_by_file` alongside global minimum to catch individual files with 0% coverage hidden by a passing global average.
- Use the `MultiFormatter` with both HTML and LCOV so developers get human-readable reports and CI gets machine-parseable LCOV for Codecov.
- Add `coverage/` and `.resultset.json` to `.gitignore` — they change on every run.

## Don'ts

- Don't put `SimpleCov.start` after `require "rails_helper"` — Rails eager-loads application code, making SimpleCov miss those files entirely.
- Don't use `add_filter "/app/"` on a Rails app — it filters out all application code and produces misleading 100% coverage on nothing.
- Don't set `minimum_coverage 100` — initializers, ApplicationRecord, ApplicationController, and mailer layouts are impractical to unit test.
- Don't rely on SimpleCov alone for branch coverage — run mutation testing (e.g., mutant) periodically to find tests that pass but don't actually verify behavior.
- Don't add `simplecov` to the `development` group — it slows down Rails boot time and instruments code on every request in development.
