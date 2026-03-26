# ActiveRecord Best Practices

## Overview
ActiveRecord is Ruby on Rails' ORM implementing the Active Record pattern — each model class maps to a database table, each instance to a row. Use it for Rails applications needing rapid development with convention-over-configuration database access. ActiveRecord excels at migrations, associations, validations, and query chaining. Avoid it for complex domain models where the Active Record pattern creates tight coupling between domain logic and persistence (consider a repository pattern with ROM.rb).

## Architecture Patterns

**Model with validations and associations:**
```ruby
class User < ApplicationRecord
  has_many :orders, dependent: :destroy
  has_one :profile, dependent: :destroy

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true, length: { maximum: 255 }

  scope :active, -> { where(active: true) }
  scope :recent, -> { order(created_at: :desc) }
end
```

**Query chaining:**
```ruby
User.active.recent.where("created_at > ?", 1.month.ago).limit(20)
```

**Transactions:**
```ruby
ActiveRecord::Base.transaction do
  order = Order.create!(user: user, total: total)
  order.items.create!(items_params)
  user.update!(last_order_at: Time.current)
end
```

**Anti-pattern — N+1 queries:** Accessing associations in a loop without eager loading triggers a query per iteration. Use `includes`, `preload`, or `eager_load`.

## Configuration

```yaml
# config/database.yml
production:
  adapter: postgresql
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  url: <%= ENV["DATABASE_URL"] %>
```

## Performance

**Eager loading:**
```ruby
# GOOD: 2 queries (users + orders)
users = User.includes(:orders).where(active: true)

# BAD: N+1 queries
users = User.where(active: true)
users.each { |u| puts u.orders.count }
```

**Use `select` for partial loads and `pluck` for single columns.**

**Use `find_each` for batch processing large datasets.**

## Security

ActiveRecord parameterizes queries by default. Never use string interpolation in `where`:
```ruby
# SAFE
User.where("email = ?", email)
User.where(email: email)

# UNSAFE — SQL injection
User.where("email = '#{email}'")
```

## Testing

```ruby
RSpec.describe User do
  it "validates email presence" do
    user = User.new(email: nil)
    expect(user).not_to be_valid
    expect(user.errors[:email]).to include("can't be blank")
  end
end
```

Use FactoryBot for test data. Use `DatabaseCleaner` or transactional tests for isolation.

## Dos
- Use `includes` for eager loading associations — it prevents N+1 queries.
- Use scopes for reusable query conditions — they chain cleanly.
- Use `find_each` for batch processing — it loads records in batches of 1000 by default.
- Use strong parameters in controllers — never pass `params` directly to `create`/`update`.
- Use database-level constraints (unique indexes, foreign keys) alongside model validations.
- Use `dependent: :destroy` or `:nullify` on associations — orphaned records cause data integrity issues.
- Use migrations for all schema changes — never modify production databases manually.

## Don'ts
- Don't use string interpolation in `where` clauses — it enables SQL injection.
- Don't skip eager loading — N+1 queries are the #1 performance problem in Rails apps.
- Don't put business logic in models — use service objects for complex operations.
- Don't use `default_scope` — it applies to all queries and is hard to override, causing surprises.
- Don't use `update_all` without careful scoping — it bypasses validations and callbacks.
- Don't use `find` in loops — use `where(id: ids)` for batch loading.
- Don't ignore `bullet` gem warnings — they detect N+1 queries and unused eager loads.
