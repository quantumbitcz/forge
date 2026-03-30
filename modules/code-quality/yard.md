# yard

## Overview

YARD (Yardoc) is the standard Ruby documentation generator. Install with `gem install yard` or add to the `Gemfile`. Document using `@param`, `@return`, `@example`, `@raise`, `@see`, `@note`, and other tags in `/** */`-style or `#`-prefixed comment blocks. Configure default options in `.yardopts`. Run `yard doc` to generate HTML and `yard server` for a local browsable doc server.

## Architecture Patterns

### Installation & Setup

```ruby
# Gemfile
group :development do
  gem 'yard', '~> 0.9'
  gem 'redcarpet'   # Markdown rendering (optional, enables GitHub Flavored Markdown)
  gem 'yard-rspec'  # Auto-link RSpec examples (optional)
end
```

```bash
bundle exec yard doc    # Generate docs to doc/ directory
bundle exec yard server # Start local server at http://localhost:8808
bundle exec yard stats  # Show documentation coverage statistics
```

**`.yardopts` (project-wide YARD configuration):**
```
--output-dir docs/api
--markup markdown
--markup-provider redcarpet
--no-private
--protected
--title "MyGem API Documentation"
lib/**/*.rb
- README.md
- CHANGELOG.md
```

### Rule Categories

| Category | Pattern | Pipeline Severity |
|---|---|---|
| Undocumented public method | Public method without YARD comment | WARNING |
| Missing `@param` | Method with parameters but no `@param` tags | WARNING |
| Missing `@return` | Non-void method without `@return` | INFO |
| Missing type annotation | `@param` or `@return` without type in `[Type]` | INFO |
| Undocumented class | Public class without description comment | WARNING |

### Configuration Patterns

**Standard YARD comment structure:**
```ruby
# Fetches a paginated list of users from the remote API.
#
# @param page [Integer] the 1-based page number to retrieve (must be > 0).
# @param per_page [Integer] the number of records per page (1..100). Defaults to 20.
# @param filters [Hash{Symbol => Object}] optional key-value filters to apply.
# @option filters [String] :status filter by user status ("active" or "suspended").
# @option filters [Integer] :org_id restrict results to a specific organisation.
#
# @return [Array<User>] the users on the requested page.
# @return [Array] empty array if the page is beyond the last page.
#
# @raise [AuthError] if the current session token is expired.
# @raise [RateLimitError] if too many requests have been made.
#
# @example Fetch the first page of active users
#   users = client.list_users(page: 1, filters: { status: "active" })
#   puts users.map(&:name)
#
# @see UserFilter for available filter keys
# @since 2.0
#
def list_users(page:, per_page: 20, filters: {})
```

**Module and class documentation:**
```ruby
# Encapsulates authentication logic for the API client.
#
# @note This class is thread-safe. A single instance can be shared across threads.
# @see TokenRefresher for background token renewal
module MyGem
  # Represents an authenticated API session.
  #
  # @example Creating a session
  #   session = MyGem::Session.new(token: ENV["API_TOKEN"])
  #   session.valid? #=> true
  class Session
```

**Type annotations:**
```ruby
# @param ids [Array<Integer>, Set<Integer>] a collection of user IDs.
# @return [Hash{Integer => User}] map from ID to user (missing IDs omitted).
# @return [nil] if the connection is unavailable.
def find_users_by_ids(ids)
```

**Custom YARD tags (`.yardopts` or `yard_ext.rb`):**
```ruby
YARD::Tags::Library.define_tag("Complexity", :complexity)

# @complexity O(n log n) where n is the number of records
def sort_records(records)
```

### CI Integration

```yaml
# .github/workflows/docs.yml
- name: Install dependencies
  run: bundle install

- name: Generate YARD docs
  run: bundle exec yard doc --fail-on-warning

- name: Check documentation coverage
  run: |
    bundle exec yard stats --list-undoc 2>&1
    COVERAGE=$(bundle exec yard stats 2>&1 | grep "% documented" | awk '{print $1}' | tr -d '%')
    [ "$COVERAGE" -ge 80 ] || (echo "Doc coverage below 80%: $COVERAGE%" && exit 1)

- name: Upload docs
  uses: actions/upload-artifact@v4
  with:
    name: yard-docs
    path: docs/api/
```

## Performance

- YARD parses Ruby source files — fast for most gems (2-15s). Large Rails apps with thousands of files take longer; scope with explicit file globs in `.yardopts`.
- `yard server --reload` watches for file changes during development — no need to re-run `yard doc` manually.
- YARD caches parsed files in `.yardoc/`. Incremental runs only reparse changed files — commit `.yardoc/` to version control to speed up CI or add it to `.gitignore` and regenerate.
- Run `yard stats` frequently — it is near-instant and shows coverage without regenerating HTML.

## Security

- YARD generates static HTML — no runtime security surface.
- `--no-private` (default) excludes private methods. Use `--protected` to include protected methods for internal teams.
- Avoid documenting internal credentials, API keys, or environment-specific URLs in `@example` blocks.

## Testing

```bash
# Generate docs
bundle exec yard doc

# Start local doc server
bundle exec yard server

# Show coverage statistics
bundle exec yard stats

# List undocumented methods
bundle exec yard stats --list-undoc

# Fail on any YARD warning
bundle exec yard doc --fail-on-warning

# Generate with Markdown support
bundle exec yard doc --markup markdown
```

## Dos

- Configure `.yardopts` at the repo root to standardize options — avoids different outputs across machines.
- Include `[Type]` annotations on all `@param` and `@return` tags — YARD renders them as highlighted type badges.
- Use `@option` sub-tags for `Hash` parameters that accept keyword-style arguments.
- Run `yard stats --list-undoc` in CI and gate on a minimum coverage threshold (80%+ for libraries).
- Add `--fail-on-warning` in CI to catch broken tag references and malformed type syntax.
- Use `@example` blocks with realistic, runnable code snippets — they are the most useful part of method docs.

## Don'ts

- Don't skip `@raise` tags — undocumented exceptions are the leading source of surprise failures for gem consumers.
- Don't use bare `# comment` without YARD tags for complex methods — YARD renders free-form text but tags provide structured lookup.
- Don't commit `doc/` generated output — publish to GitHub Pages or RubyGems.org from CI.
- Don't ignore `yard stats` output — a gem with < 50% documented public methods is effectively undocumented for users.
- Don't use `@return [void]` for methods that actually return meaningful values — document the actual return type.
- Don't write `@param name [String]` without describing the parameter's purpose — the type alone is insufficient.
