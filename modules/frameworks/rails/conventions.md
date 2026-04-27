# Rails Framework Conventions

> Support tier: contract-verified

> Framework-specific conventions for Rails 8.x projects (Rails 7.2 also covered). Language idioms are in `modules/languages/ruby.md`.
> Generic testing patterns are in `modules/testing/rspec.md`.
> Composition stack: `variant > rails/testing/rspec.md > rails/conventions.md > ruby.md > persistence/active-record.md > testing/rspec.md`.

## Overview

Rails is a full-stack, convention-over-configuration MVC framework. This module targets **Rails 8.x** (defaults: Solid Queue, Solid Cache, Solid Cable, Propshaft, Importmap, Kamal 2). Rails 7.2 differences are called out inline. Use Rails when:

- The HTTP surface needs a batteries-included story (ORM, auth, jobs, mail, cache, websockets) without assembling extensions
- Server-rendered HTML with progressive enhancement (Hotwire) outpaces a SPA for your team
- The team values "the Rails way" over framework choice — opinionated defaults reduce decision overhead

Prefer Sinatra/Hanami for microservices where you want to assemble a thinner stack. Prefer a Node/Next or Phoenix LiveView stack if you want a different default rendering model.

## Architecture (MVC + Service / Form / Query objects)

| Layer | Responsibility | Dependencies |
|-------|---------------|--------------|
| `app/controllers/` | HTTP handling, strong params, delegate to services, render/redirect | Models, services, policies |
| `app/models/` | ActiveRecord persistence, validations, associations, scopes | DB |
| `app/services/` | Business logic / use cases — one service per verb (`Users::Activate`) | Models, repositories |
| `app/forms/` | Multi-model form objects (`Users::RegistrationForm`) backed by ActiveModel | Models |
| `app/queries/` | Complex read scopes (`Posts::TrendingQuery.new(scope).call`) | ActiveRecord relations |
| `app/policies/` | Pundit/CanCanCan authorization | `current_user`, models |
| `app/jobs/` | ActiveJob background work | Mailers, services |
| `app/mailers/` | ActionMailer with `deliver_later` for outbound mail | Templates |
| `app/components/` (optional) | ViewComponent objects when partials grow stateful | Views |
| `app/javascript/controllers/` | Stimulus controllers (one per Hotwire interaction) | Targets/values |
| `db/migrate/` | Schema changes, gated by `strong_migrations` for zero-downtime | DB |

**Dependency rule:** controllers never own business logic — they parse params, call a service or form object, and render. Models hold persistence rules and validations, **not** workflows that span aggregates. Concerns are for shared behaviour across 3+ models, not as a junk drawer.

## Routing (`config/routes.rb`)

- Use `resources :posts` / `resource :profile` (singular) — restrict with `only:` / `except:` rather than expanding to all 7 actions you don't use
- Nested resources: depth 1 max. Anything deeper hides the parent–child relationship — link via `id` instead
- Constrain dynamic segments: `constraints id: /\d+/`, `constraints subdomain: 'api'`
- Use `direct` and `resolve` for custom polymorphic URL helpers — avoid string interpolation in views
- Mount engines at the routes file boundary (`mount Admin::Engine, at: '/admin'`)
- Keep `routes.rb` < 200 lines — split via `draw(:api_v1)` and `config/routes/api_v1.rb` once it grows

```ruby
Rails.application.routes.draw do
  resources :posts, only: %i[index show create update destroy] do
    resources :comments, only: %i[index create]   # one level deep
  end
  namespace :api do
    namespace :v1 do
      resources :posts, only: %i[index show]
    end
  end
end
```

## ActiveRecord

- One migration per logical change; never edit a migration once it's in main
- Always add an index on foreign keys (`add_reference :posts, :user, index: true, foreign_key: true`)
- Use `strong_migrations` gem in production codebases — it blocks unsafe operations (`remove_column` without `safety_assured`, `add_index` without `algorithm: :concurrently` on Postgres)
- Scopes are first-class: `scope :published, -> { where(published_at: ..Time.current) }` — keep them composable (Arel-friendly, return a Relation)
- `default_scope` is almost always wrong — it's invisible at the call site and breaks `unscoped` expectations
- Callbacks are for invariants (set derived columns, normalize input) — **not** for cross-aggregate side effects (use `after_commit` + ActiveJob, or extract to a service)
- `update_all` and `delete_all` skip callbacks **and** validations — assert in code review that you intend that
- Counter caches: `belongs_to :post, counter_cache: true` + `add_column :posts, :comments_count, :integer, default: 0, null: false`
- Optimistic locking: add `lock_version` column, ActiveRecord raises `StaleObjectError` on conflicting writes

## Strong Parameters

- Always `permit` an explicit allowlist — never `params.permit!` or `params.to_unsafe_h`
- Combine with Pundit `permitted_attributes` to scope params per role: `permitted_attributes(@post)`
- Extract to a private method per controller: `def post_params; params.require(:post).permit(...); end`

```ruby
# Scalars + array of scalars + nested hash + array of hashes
def post_params
  params.require(:post).permit(
    :title, :body,                              # scalars
    tag_ids: [],                                # array of scalar IDs
    metadata: %i[locale source],                # nested hash with fixed keys
    comments_attributes: %i[id body _destroy]   # accepts_nested_attributes_for
  )
end
```

`permit(meta: {})` (with `{}`) accepts an arbitrary hash — use sparingly; you've effectively disabled the whitelist for that key. Prefer enumerating expected keys.

## Views & templating (ERB)

- ERB is the default — Slim/Haml are fine but pick one per project
- Partials: name with leading underscore (`_post.html.erb`), render with `render @posts` (uses `_post.html.erb` per item)
- Use `render collection: @posts, partial: 'post', cached: true` for list rendering — Russian-doll caching slashes render time
- Never put database queries in views — preload in the controller or query object
- Helpers: small, presentational only. Anything stateful belongs in a `ViewComponent` or service

## Asset pipeline (Rails 8 defaults: Propshaft + Importmap)

- **Propshaft** replaces Sprockets in Rails 7+; manages digested asset URLs without preprocessing. JS/CSS bundling is delegated to Importmap or jsbundling/cssbundling
- **Importmap-rails** (default) — no build step, ships ES modules with HTTP/2 multiplexing. Pin via `bin/importmap pin react`. Best for Hotwire-only apps
- **jsbundling-rails** (esbuild/rollup/webpack) — pick when you need npm packages that aren't ESM-friendly, JSX/TSX, or React/Vue
- **cssbundling-rails** (Tailwind/Bootstrap/PostCSS) — alternative to `tailwindcss-rails`; Tailwind users typically pick `tailwindcss-rails` (lighter) unless they need PostCSS plugins
- Migration from Sprockets: remove `sprockets-rails` from Gemfile, drop `app/assets/config/manifest.js`, configure Propshaft via `config.assets.paths`

## Hotwire (Turbo + Stimulus)

- **Turbo Drive** intercepts navigation — full-page loads become XHR + body-swap; preserves JS state. Disable per-link via `data-turbo="false"`
- **Turbo Frames** scope updates to a portion of the page (`<turbo-frame id="post_42">`). Lazy-load with `src=` + spinner
- **Turbo Streams** push partial-page updates (`append`/`prepend`/`replace`/`update`/`remove`/`before`/`after`) over WebSocket (`turbo_stream_from`) or HTTP form responses
- **Stimulus** controllers attach behaviour to data attributes (`data-controller="dropdown"`, `data-action="click->dropdown#toggle"`). One responsibility per controller
- Rails 8 ships **morphing Turbo** as default — DOM diffing instead of full frame swap; preserves form state. Opt-in per stream via `<turbo-stream action="morph">`

See `variants/hotwire.md` for the full lifecycle.

## ActionCable, ActionMailer, ActiveJob

- **ActiveJob queue adapter (Rails 8 default):** `solid_queue` — DB-backed, no Redis required. Set per-job: `class WelcomeEmailJob < ApplicationJob; queue_as :mailers; end`
- **ActiveJob discard:** `discard_on ActiveRecord::RecordNotFound` so deleted records don't dead-letter the queue
- **Retries:** `retry_on Net::OpenTimeout, wait: :polynomially_longer, attempts: 5` — exponential backoff built in
- **ActionMailer:** never call `.deliver_now` in a request path; use `.deliver_later` so outbound SMTP doesn't block the response
- **ActionCable (Rails 8 default):** `solid_cable` adapter (DB-polling). For higher throughput swap to `redis`. Channel auth via `identified_by :current_user` in `ApplicationCable::Connection`
- **Solid Cache (Rails 8 default):** disk-backed cache via SQLite/Postgres — replaces Memcached/Redis for `Rails.cache` defaults

```ruby
class NotifyAuthorJob < ApplicationJob
  queue_as :default
  retry_on Net::OpenTimeout, wait: :polynomially_longer, attempts: 5
  discard_on ActiveRecord::RecordNotFound          # post deleted while job queued

  def perform(post_id:)
    post = Post.find(post_id)
    AuthorMailer.with(post: post).new_comment.deliver_now    # OK in a job
  end
end

# In a controller, dispatch async:
NotifyAuthorJob.perform_later(post_id: @post.id)
```

## Authorization (Pundit)

- One policy per resource: `app/policies/post_policy.rb` with `index?`, `show?`, `create?`, `update?`, `destroy?`
- Enforce in controllers via `authorize @post` and `policy_scope(Post)`; raise `Pundit::NotAuthorizedError` on violation
- Verify policy enforcement in tests via `verify_authorized` and `verify_policy_scoped` after-action hooks
- Role modeling: prefer simple boolean columns (`admin?`) over Rolify until you have 4+ roles

```ruby
class PostPolicy < ApplicationPolicy
  def show?    = record.published? || owner?
  def update?  = owner? || user.admin?
  def destroy? = user.admin?

  class Scope < Scope
    def resolve
      return scope.all if user.admin?
      scope.where('published_at IS NOT NULL OR author_id = ?', user.id)
    end
  end

  private def owner? = record.author_id == user.id
end

class PostsController < ApplicationController
  after_action :verify_authorized, except: :index
  after_action :verify_policy_scoped, only: :index

  def index = (@posts = policy_scope(Post))
  def show  = (authorize(@post = Post.find(params[:id])))
end
```

## I18n

- All user-facing strings go through `I18n.t('key')` / `t('.scoped_key')` — never hardcode in views or models
- Locale files live in `config/locales/{en,fr,...}.yml` — namespace by controller / model (`activerecord.errors.models.user`)
- Pluralization: use `I18n.t('apples', count: n)` with `one`/`other` keys
- Set `I18n.fallbacks` so missing keys fall through to `:en` rather than raise
- Date/number/currency: `l(date, format: :long)`, `number_to_currency(amount, locale: :de)`

## Security

- Strong parameters everywhere — no `params.permit!`
- CSRF: `protect_from_forgery with: :exception` on `ApplicationController` (default); API controllers use token auth and skip with `skip_before_action :verify_authenticity_token, only: %i[create update destroy]`
- Session store: `cookie_store` (signed + encrypted) for most apps; `redis_store` only when sessions are too large for cookies
- Encrypted credentials: `bin/rails credentials:edit` — `Rails.application.credentials.dig(:stripe, :secret_key)`. Never commit `master.key`
- ActiveRecord encryption (Rails 7+): `encrypts :ssn, deterministic: true` for searchable encrypted columns
- Set `config.force_ssl = true` in production; HSTS preload via `config.ssl_options`
- Never `html_safe` user-controlled strings — use `sanitize` with a strict allowlist instead

## Generators & engines

- `bin/rails g resource Post title:string body:text` scaffolds model + migration + controller + routes — useful for the first cut, but always review and prune
- Skip what you don't need: `bin/rails g model Post --no-test-framework` if you write specs by hand
- Customize generator defaults in `config/application.rb` so every team member generates consistent code:

```ruby
config.generators do |g|
  g.test_framework    :rspec, fixture: false
  g.factory_bot       dir: 'spec/factories'
  g.skip_collision_check true
  g.helper            false
  g.assets            false
  g.view_specs        false
end
```

- **Engines** (`bin/rails plugin new admin --mountable`) for modular monoliths — `isolate_namespace Admin` keeps models/controllers under `Admin::` and routes scoped under `mount Admin::Engine, at: '/admin'`
- See `variants/engine.md` for engine-based architecture

## Testing

Defers to `testing/rspec.md`. Rails 8 defaults to **Minitest**; this module recommends **RSpec** (rspec-rails 7+) for community gem ecosystem (Capybara, factory_bot, shoulda-matchers, vcr) — convert via `bin/rails generate rspec:install`.

## TDD Flow

```
generate skeleton -> write specs (RED) -> implement (GREEN) -> refactor
```

1. **Generate:** model + migration + controller stubs via `bin/rails g`
2. **RED:** write request specs (`spec/requests/posts_spec.rb`) for the HTTP contract; model spec for invariants
3. **GREEN:** implement service/form, wire controller to it, run `bundle exec rspec --fail-fast`
4. **Refactor:** extract query objects when scopes get complex; promote view helpers to ViewComponents; run RuboCop

## Logging and Monitoring

- `Rails.logger` is configured per-env in `config/environments/`. Production: tagged logger with `request_id` (built-in)
- Log levels: ERROR (action needed), WARN (degraded), INFO (business events), DEBUG (dev only)
- Lograge or `rails-semantic_logger` for structured JSON logs in production
- Health endpoint: Rails 7.1+ ships `/up` (liveness) — supplement with `/health/db` (DB ping) and `/health/cache` if you have downstream readiness gates
- Never log credentials/tokens/PII — configure `config.filter_parameters += [:password, :ssn, :credit_card]`

## Boy Scout Rule

Improve touched code if: safe, small (<10 lines), local (same file), convention-aligned.
NOT in scope: refactoring unrelated controllers, schema changes, fixing pre-existing bugs.

## Dos

- Use `bin/rails` (not `rails`) — pinned to the project's bundle, never the system gem
- Strong parameters with explicit `permit` — one allowlist per resource
- Add an index to every foreign key (`add_reference ..., index: true, foreign_key: true`)
- Use `includes`/`preload`/`eager_load` to prevent N+1 — assert in tests with `Bullet` or `n_plus_one_control`
- Prefer `find_each` (batched) over `all.each` for large collections
- Use `deliver_later` for mailers in request paths — `deliver_now` only in jobs and tests
- Wrap multi-step writes in a transaction (`ApplicationRecord.transaction do ... end`) — rollback on `raise`
- Use `strong_migrations` to prevent zero-downtime hazards (`remove_column`, blocking `add_index`)
- Pin gems with the **major** version in `Gemfile` (`gem 'rails', '~> 8.0'`) — let `bundle update` handle patches
- Use `Rails.application.credentials` for secrets — never `ENV['STRIPE_KEY']` for secret values (env vars leak in process listings); env is fine for non-secret config
- Authorize every controller action with Pundit (`authorize @resource`); use `after_action :verify_authorized` in `ApplicationController` to fail loudly if missed
- Use service objects (`Users::Activate.call(user)`) for business workflows; controllers should be < 50 lines
- Prefer `head :ok` / `head :no_content` over `render plain: ''` for empty responses
- Use `bin/rails db:migrate` followed by `bin/rails db:rollback` locally before pushing — catches non-reversible migrations early

## Don'ts

- Don't use `params.permit!` or `params.to_unsafe_h` — defeats the strong-parameters whitelist (CRITICAL: mass-assignment vulnerability)
- Don't put business logic in callbacks (`after_save :notify_team`) — they fire on `update_columns`, fixtures, and seeders, leading to surprise side effects. Use `after_commit` + ActiveJob, or extract to a service
- Don't use `default_scope` — invisible filtering breaks `unscoped` expectations and confuses `count` semantics
- Don't `update_all` / `delete_all` without confirming you want to skip validations and callbacks
- Don't interpolate into `where("name = '#{params[:name]}'")` — use `where(name: params[:name])` (parameterized) — SQL injection
- Don't use `find_by_sql` with interpolation — use `sanitize_sql_array(['... ?', value])` if you must
- Don't call `.deliver_now` in controllers — blocks the request thread on SMTP
- Don't share models across engines via `Admin::User = ::User` — extract to a separate gem if cross-engine sharing is unavoidable
- Don't subclass `ActiveRecord::Base` directly — use `ApplicationRecord` so you can add app-wide concerns
- Don't use `before_filter` — it was removed in Rails 5.1; use `before_action`
- Don't ship `config.consider_all_requests_local = true` to production — it leaks stack traces
- Don't put `secrets.yml` in the repo — use `bin/rails credentials:edit` (Rails 5.2+) or env vars for secrets
- Don't use `request.referer` for redirects — use `redirect_back(fallback_location: root_path)`; bare `request.referer` is `nil`-prone and a CRLF-injection vector
- Don't use `rescue Exception` — catch `StandardError` (the Rails default) so you don't trap `SystemExit`/`Interrupt`
- Don't run `bin/rails db:migrate:reset` against shared environments — it drops the DB
