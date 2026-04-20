# Rails + ActiveRecord Variant

> Deep ActiveRecord patterns for Rails 7.2 / 8.x. Extends `modules/frameworks/rails/conventions.md`.
> Use this variant focus when the application is data-heavy and persistence is the primary concern
> (analytics dashboards, reporting tools, batch processors).

## Scopes

Scopes are class-level chainable filters that return a Relation:

```ruby
class Post < ApplicationRecord
  scope :published,  -> { where.not(published_at: nil) }
  scope :recent,     ->(days = 7) { where(published_at: days.days.ago..) }
  scope :by_author,  ->(author) { where(author: author) }
end

Post.published.recent(30).by_author(current_user)
```

Rules:
- Scopes always return a Relation (so they chain). If you need a single record, expose a class method instead
- Compose with other scopes — never break out into bare `Post.where(...)` mid-chain
- Scopes that take arguments should default sensibly (so they're chainable without args)

## `default_scope` (don't)

`default_scope` injects a `WHERE` clause into every query for the model — including `count`, `find_by`, `joins` from related models. Pitfalls:

- Hidden filtering: callers don't see `WHERE deleted_at IS NULL` and wonder why their counts disagree with the DB
- `unscoped` is a workaround that propagates everywhere — every query needs awareness of whether to bypass it
- Cross-model joins inherit the default scope, breaking complex aggregations

```ruby
# Don't:
class Post < ApplicationRecord
  default_scope { where(deleted_at: nil) }
end

# Do:
class Post < ApplicationRecord
  scope :active, -> { where(deleted_at: nil) }
end
# Use Post.active everywhere; soft-deleted records are explicit at the call site.
```

## Concerns (shared behaviour)

Concerns extract shared behaviour into modules — but they're a sharp tool. Use only when 3+ models share the behaviour and the behaviour is non-trivial:

```ruby
# app/models/concerns/sluggable.rb
module Sluggable
  extend ActiveSupport::Concern

  included do
    before_validation :generate_slug, on: :create
    validates :slug, presence: true, uniqueness: true
  end

  def to_param = slug

  private

  def generate_slug = self.slug ||= title.parameterize
end

class Post < ApplicationRecord
  include Sluggable
end
```

Anti-pattern: dumping unrelated concerns (`Auditable`, `Notifiable`, `Cacheable`) into one model — concerns become a junk drawer. Each concern should have a single, clearly named responsibility.

## Callback discipline

| Callback | Use for | Don't use for |
|----------|---------|---------------|
| `before_validation` | Normalize input (lowercase email, strip whitespace) | Anything that can fail |
| `before_save` | Set derived columns from other columns on this row | Cross-aggregate writes, network calls |
| `after_save`, `after_create`, `after_update` | Per-row cache invalidation tied to the model | Side effects (use `after_commit`) |
| `after_commit` | Side effects: enqueue ActiveJob, broadcast Turbo Stream, post to webhook | Validations |

Critical: `after_save` runs inside the transaction. If the transaction rolls back (e.g. a parent record fails to save in a `has_many` chain), the side effect already fired. Use `after_commit` for anything that crosses the persistence boundary.

```ruby
class Comment < ApplicationRecord
  belongs_to :post
  after_create_commit -> { NotifyAuthorJob.perform_later(post_id: post_id, comment_id: id) }
end
```

## Query objects

When a scope grows beyond ~5 chained filters, extract to a query object:

```ruby
# app/queries/posts/trending_query.rb
module Posts
  class TrendingQuery
    def initialize(scope = Post.all) = @scope = scope
    def call(window: 24.hours)
      @scope
        .joins(:reactions)
        .where(reactions: { created_at: window.ago.. })
        .group('posts.id')
        .order('COUNT(reactions.id) DESC')
        .limit(20)
    end
  end
end

# Controller:
@posts = Posts::TrendingQuery.new(Post.published).call
```

Benefits: testable in isolation, composable with scopes, named after the use case.

## `includes` vs `preload` vs `eager_load`

| Method | SQL | When to use |
|--------|-----|-------------|
| `preload(:author)` | Two queries (`SELECT * FROM posts; SELECT * FROM users WHERE id IN (...)`) | When you don't filter on the association |
| `eager_load(:author)` | One query with LEFT OUTER JOIN | When you filter on the association (`WHERE authors.role = 'admin'`) |
| `includes(:author)` | Picks `preload` or `eager_load` automatically based on whether the association is referenced in WHERE | Default — let Rails decide |
| `joins(:author)` | INNER JOIN, no eager-loading | When you only need to filter, not load attributes |

```ruby
# N+1 (bad):
Post.all.each { |p| puts p.author.name }   # 1 + N queries

# Eager-loaded (good):
Post.includes(:author).each { |p| puts p.author.name }   # 2 queries
```

## Counter caches

Avoid `posts.comments.count` in the view (a COUNT query per post). Add a counter cache column:

```ruby
class Comment < ApplicationRecord
  belongs_to :post, counter_cache: true
end
# migration: add_column :posts, :comments_count, :integer, default: 0, null: false
```

Now `post.comments_count` is an O(1) attribute read. Counter cache writes happen automatically on `Comment` create/destroy — but `delete_all` and `update_all` skip them.

## Optimistic locking

Add a `lock_version` integer column to detect concurrent writes:

```ruby
# migration: add_column :posts, :lock_version, :integer, default: 0, null: false
post = Post.find(42)
post.title = 'New title'
post.save!     # raises ActiveRecord::StaleObjectError if lock_version changed since load
```

Catch in the controller and re-render the form with a "someone else edited this" message.

## STI (single-table inheritance) caveats

STI stores subclasses in one table with a `type` discriminator column. Useful for closely related types (`Notification` → `EmailNotification`, `SmsNotification`) that share most columns. Pitfalls:

- The `type` column is a string — typos at write time are silent (`type: 'EmailNotificaiton'` saves but never loads back)
- Adding a column for one subtype bloats every row
- Cross-subtype queries are easy (`Notification.where(...)`) but per-subtype indexes get complex

Prefer separate tables (or polymorphic associations) when subtypes diverge significantly.

## Dos

- Use `find_each` for iterating over collections > 1000 rows — batches in groups of 1000 by default
- Wrap multi-record writes in a transaction (`ApplicationRecord.transaction do ... end`); raise to roll back
- Add a DB-level unique index for any uniqueness validator — Rails-level validation is racy under load
- Use `with_lock` for pessimistic locking when you need to serialize access (`post.with_lock { post.publish! }`)
- Prefer `pluck(:id)` over `map(&:id)` when you only need the column — pulls one column instead of full rows
- Use `update_columns` only when you genuinely want to bypass callbacks AND validations AND `updated_at` (e.g. backfilling a denormalized field)
- Define `to_param` to use slugs (`def to_param = slug`) for prettier URLs

## Don'ts

- Don't use `default_scope` — invisible filtering, breaks `count`/`unscoped` semantics, leaks into joins
- Don't put network calls in `before_save`/`after_save` — runs inside the transaction; use `after_commit` + ActiveJob
- Don't use `update_all` without a scope — `Post.update_all(state: 'archived')` archives every post
- Don't `Post.all.each` — loads every row into memory; use `find_each` for batched iteration
- Don't validate associations on both sides (`validates :user, presence: true` on Post AND `validates_associated :posts` on User) — circular validation deadlock
- Don't subclass `ActiveRecord::Base` directly — use `ApplicationRecord` so app-wide concerns have a home
- Don't use callbacks for cross-aggregate workflows — extract to a service object or a saga
