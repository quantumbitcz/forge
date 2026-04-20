# Rails + API-Only Variant

> Rails 7.2 / 8.x configured as a JSON API. Extends `modules/frameworks/rails/conventions.md`.
> Use this variant when the Rails app serves JSON to a separate frontend (React, Vue, mobile) and
> never renders ERB / does not need session cookies / CSRF / asset pipeline.

## Skeleton

Generate via `rails new myapp --api` — produces a slim app:

- `ApplicationController` inherits from `ActionController::API` (no view helpers, no CSRF, no flash)
- No `app/views/layouts/application.html.erb`
- No `app/javascript/`, no Propshaft, no Importmap
- `config/application.rb` includes `config.api_only = true` — middleware stack drops cookies, flash, sessions

```ruby
class ApplicationController < ActionController::API
  include ActionController::HttpAuthentication::Token::ControllerMethods
  include Pundit::Authorization

  rescue_from Pundit::NotAuthorizedError, with: :forbidden
  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity

  private

  def forbidden(_) = render json: error('forbidden', status: 403), status: :forbidden
  def not_found(_) = render json: error('not_found', status: 404), status: :not_found
  def unprocessable_entity(e)
    render json: error('validation_failed', detail: e.record.errors.full_messages, status: 422),
           status: :unprocessable_entity
  end
end
```

## Serialization

| Library | Pros | Cons | Use when |
|---------|------|------|----------|
| **Alba** | Fast, simple DSL, Ruby 3-ready, no monkey-patching | Smaller community than fast_jsonapi | **Recommended default** for new APIs |
| `fast_jsonapi` (Netflix, archived) | JSON:API compliant out of the box | Unmaintained; perf gains diminished on Ruby 3 | Existing JSON:API consumers |
| `JBuilder` | Built into Rails, ERB-like | Slow on large payloads, hard to test | Tiny APIs, prototypes |
| Hand-rolled `to_json` | No dependency | Brittle, easy to leak attributes | Avoid past 2 endpoints |

```ruby
# Alba example
class PostResource
  include Alba::Resource
  attributes :id, :title, :body, :published_at
  one :author, resource: AuthorResource
  many :comments, resource: CommentResource

  attribute :word_count do |post|
    post.body.split.size
  end
end

# In controller:
render json: PostResource.new(@post).serialize
```

## Versioning

URL namespace (recommended) — explicit, cacheable, easy to diff in logs:

```ruby
# config/routes.rb
namespace :api do
  namespace :v1 do
    resources :posts, only: %i[index show create update destroy]
  end
  namespace :v2 do
    resources :posts, only: %i[index show]
  end
end
```

Header versioning (`Accept: application/vnd.myapi.v2+json`) is more REST-pure but harder to inspect — pick URL namespacing unless you have a strong reason otherwise.

## Pagination

Use **Pagy** — fastest, lightest, no monkey-patches:

```ruby
class Api::V1::PostsController < ApplicationController
  include Pagy::Backend

  def index
    pagy, posts = pagy(Post.published, items: params[:per_page] || 25, max_items: 100)
    render json: {
      data: PostResource.new(posts).serialize,
      meta: { page: pagy.page, per_page: pagy.items, total: pagy.count, pages: pagy.pages }
    }
  end
end
```

For large datasets, prefer **cursor-based pagination** (use `pagy_keyset` or roll your own) — offset pagination becomes O(N) past page 100.

## Rate limiting

Use **rack-attack** as middleware:

```ruby
# config/initializers/rack_attack.rb
Rack::Attack.throttle('api/ip', limit: 300, period: 5.minutes) { |req| req.ip if req.path.start_with?('/api') }
Rack::Attack.throttle('api/user', limit: 1000, period: 1.hour) do |req|
  req.env['warden']&.user&.id if req.path.start_with?('/api')
end
```

Surface `X-RateLimit-Limit` / `X-RateLimit-Remaining` / `Retry-After` headers from a `before_action` so clients can back off.

## Authentication

| Strategy | Library | When to use |
|----------|---------|-------------|
| JWT | `devise-jwt` (Devise + JWT plugin) | When you already use Devise for web sessions |
| JWT | `Sorcery` + `jwt` gem | Lightweight, no Warden middleware |
| OAuth2 (provider) | `doorkeeper` | When you want to expose OAuth to third-party clients |
| API keys | Hand-rolled `before_action :authenticate_with_token!` | Internal-only APIs |

```ruby
class Api::V1::ApplicationController < ApplicationController
  before_action :authenticate_user!

  def authenticate_user!
    authenticate_with_http_token do |token, _|
      @current_user = User.find_by_authentication_token(token)
    end
    head :unauthorized unless @current_user
  end
end
```

## CORS

```ruby
# config/initializers/cors.rb
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch('ALLOWED_ORIGINS').split(',')
    resource '/api/*',
      headers: :any,
      methods: %i[get post put patch delete options],
      expose: %w[X-RateLimit-Limit X-RateLimit-Remaining]
  end
end
```

Never `origins '*'` for credentialed endpoints — browsers reject it but malicious clients ignore the rule.

## Error envelope

Pick one and stick to it. Two common conventions:

**RFC 7807 problem+json** (recommended):

```json
{
  "type": "https://example.com/probs/validation",
  "title": "Validation failed",
  "status": 422,
  "detail": "Title can't be blank",
  "instance": "/api/v1/posts/42"
}
```

**Custom envelope** (simpler, less interoperable):

```json
{ "error": { "code": "validation_failed", "message": "...", "fields": { "title": ["can't be blank"] } } }
```

Document the envelope in your OpenAPI spec — clients should never have to guess the shape.

## Dos

- Inherit from `ActionController::API` — drops view helpers, CSRF, sessions you don't need
- Use Alba (or fast_jsonapi for JSON:API consumers) for serialization — never hand-roll `to_json` past 2 endpoints
- URL-version your API (`/api/v1/...`) — explicit, cacheable, debuggable
- Use Pagy for pagination — fastest Ruby paginator; cursor-based for high-volume datasets
- Authenticate with `Authorization: Bearer <token>` headers — never query strings (leaked in logs/referers)
- Document with OpenAPI (rswag generates from RSpec request specs)

## Don'ts

- Don't use Devise sessions in API-only mode — use devise-jwt or a token strategy
- Don't return raw `User#to_json` — leaks `password_digest`, `confirmation_token`, internal IDs
- Don't paginate by offset past page ~100 — switch to cursor-based pagination
- Don't allow `origins '*'` for credentialed endpoints — restrict via env var per environment
- Don't return Rails default `<html>` error pages from API routes — always JSON; `rescue_from` the common errors in `ApplicationController`
- Don't ship API tokens that never expire — rotate JWTs (15-min access + 7-day refresh) or set TTL on opaque tokens
