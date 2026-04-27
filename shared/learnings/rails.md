---
schema_version: 2
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
items:
  - id: "ra-preempt-001"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.795418Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["persistence", "rails"]
    source: "cross-project"
    archived: false
    body_ref: "ra-preempt-001"
  - id: "ra-preempt-002"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.795418Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["security", "rails"]
    source: "cross-project"
    archived: false
    body_ref: "ra-preempt-002"
  - id: "ra-preempt-003"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.795418Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["architecture", "rails"]
    source: "cross-project"
    archived: false
    body_ref: "ra-preempt-003"
  - id: "ra-preempt-004"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.795418Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["persistence", "rails"]
    source: "cross-project"
    archived: false
    body_ref: "ra-preempt-004"
  - id: "ra-preempt-005"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.795418Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["architecture", "rails"]
    source: "cross-project"
    archived: false
    body_ref: "ra-preempt-005"
  - id: "ra-preempt-006"
    base_confidence: 0.65
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.795418Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["architecture", "rails"]
    source: "cross-project"
    archived: false
    body_ref: "ra-preempt-006"
  - id: "ra-preempt-007"
    base_confidence: 0.65
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.795418Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["persistence", "rails"]
    source: "cross-project"
    archived: false
    body_ref: "ra-preempt-007"
  - id: "ra-preempt-008"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.795418Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["persistence", "rails"]
    source: "cross-project"
    archived: false
    body_ref: "ra-preempt-008"
  - id: "ra-preempt-009"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.795418Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["performance", "rails"]
    source: "cross-project"
    archived: false
    body_ref: "ra-preempt-009"
  - id: "ra-preempt-010"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.795418Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["persistence", "rails"]
    source: "cross-project"
    archived: false
    body_ref: "ra-preempt-010"
---
# Cross-Project Learnings: rails

## PREEMPT items

### RA-PREEMPT-001: N+1 queries from missing `includes` in views and serializers
<a id="ra-preempt-001"></a>
- **Domain:** persistence
- **Pattern:** ERB templates that iterate `<% @posts.each do |p| %><%= p.author.name %><% end %>` or JSON serializers walking `post.comments.map(&:user)` trigger one query per row when associations default to `lazy`. Add `.includes(:author, comments: :user)` in the controller — or, for a specialized read, build a query object that pre-joins. Detect with the **bullet** gem in development (`Bullet.alert = true`) or the **n_plus_one_control** gem in CI to fail builds when N+1 patterns appear inside loops. RuboCop-performance also flags some patterns. The L1 rule `RA-PERF-003` catches the simple `.all.each do` form.
- **Confidence:** HIGH
- **Hit count:** 0

### RA-PREEMPT-002: `params.permit!` / `params.to_unsafe_h` bypass — mass-assignment vulnerability
<a id="ra-preempt-002"></a>
- **Domain:** security
- **Pattern:** Strong parameters exist to prevent attackers from setting columns the form never exposed (e.g. `is_admin`, `account_id`). `params.permit!` whitelists everything; `params.to_unsafe_h` returns the unfiltered hash. Both forms appear during debugging ("just let it through to see what breaks") and survive into commits. Audit rule: every controller action that calls `.create`/`.update` must funnel through a `*_params` private method that does `params.require(:resource).permit(...)`. Caught by L1 rules `RA-SEC-001` and `RA-SEC-002`.
- **Confidence:** HIGH
- **Hit count:** 0

### RA-PREEMPT-003: Callback hell — fat models with cascading `after_save` chains
<a id="ra-preempt-003"></a>
- **Domain:** architecture
- **Pattern:** A model accumulates `after_save :send_notification`, `after_save :update_search_index`, `after_save :recompute_counters`, `after_save :enqueue_webhook` until the act of saving a record triggers an unpredictable cascade. Symptoms: tests get slow (every `create` does 5 things), seeders fail in surprising ways (callbacks fire), `update_columns` is needed everywhere just to skip them, and rolled-back transactions still send notifications because the `after_save` already fired. Rules: callbacks are for invariants (set derived columns, normalize input). Side effects belong in `after_commit` + ActiveJob, or extract to a service object. Five+ callbacks on a single model is a code smell — pause and refactor.
- **Confidence:** HIGH
- **Hit count:** 0

### RA-PREEMPT-004: `update_all` / `delete_all` silently skip validations and callbacks
<a id="ra-preempt-004"></a>
- **Domain:** persistence
- **Pattern:** `Order.where(state: 'pending').update_all(state: 'cancelled')` is fast and intentional in some cases — but it bypasses `validates`, `before_save`, `after_save`, `after_commit`, counter caches, paper_trail audit logging, and any other model-layer hook. Discovered in production via "why is the audit log empty for these 10k records?" or "why didn't the search index update?" Fix: confirm in code review that you intend to skip callbacks. If you don't, iterate with `find_each(&:cancel!)` or extract to a job. Caught by L1 rule `RA-PERF-001`.
- **Confidence:** HIGH
- **Hit count:** 0

### RA-PREEMPT-005: Fat controllers — 10+ action methods or business logic inline
<a id="ra-preempt-005"></a>
- **Domain:** architecture
- **Pattern:** A controller grows past `index/show/new/create/edit/update/destroy` into custom verbs (`activate`, `archive`, `merge`, `transfer`) and business logic creeps inline. Symptoms: actions exceed 40 lines, multiple service calls per action, controller spec setup blocks longer than the test. Fix: split via nested resources (`resources :users do; member { post :activate }; end` → `Users::ActivationsController#create`) and move workflows to service objects (`Users::Activate.call(user)`) that return a result object with `.success?` / `.error`. Caught loosely by L1 rule `RA-ARCH-001`.
- **Confidence:** HIGH
- **Hit count:** 0

### RA-PREEMPT-006: Service objects without a return contract — boolean / nil / raise mixed
<a id="ra-preempt-006"></a>
- **Domain:** architecture
- **Pattern:** Half the services return `true`/`false`, a third return the saved record, and the rest raise on failure. Callers can't tell what to expect — every site hand-rolls `if result` vs `begin; rescue` vs `result.persisted?`. Convention: every service returns a Result object (`Result.success(value)` / `Result.failure(error)`) or nothing at all (raises on failure, returns void). Pick one shape and use it across the app. The `dry-monads` Result type or a 20-line custom `Result` struct works; consistency matters more than the choice.
- **Confidence:** MEDIUM
- **Hit count:** 0

### RA-PREEMPT-007: Polymorphic associations break referential integrity at the DB level
<a id="ra-preempt-007"></a>
- **Domain:** persistence
- **Pattern:** `belongs_to :commentable, polymorphic: true` stores `commentable_id` + `commentable_type` (a string). The DB cannot enforce a foreign key on `commentable_id` because it points to multiple tables. Stale references (`commentable_type='Post', commentable_id=1234` after the post was deleted) accumulate silently. Mitigations: (1) use composite indexes `[commentable_type, commentable_id]`; (2) clean up in `before_destroy` on each parent (`has_many :comments, as: :commentable, dependent: :destroy`); (3) consider concrete tables (`PostComment`, `VideoComment`) when there are only 2-3 polymorphic targets and the discriminator column is the primary join condition.
- **Confidence:** MEDIUM
- **Hit count:** 0

### RA-PREEMPT-008: `default_scope` invisibility — `User.count` disagrees with `SELECT COUNT(*) FROM users`
<a id="ra-preempt-008"></a>
- **Domain:** persistence
- **Pattern:** `class User < AR::Base; default_scope { where(deleted_at: nil) }; end` filters every query — including `count`, `sum`, joins from related models, and `find` (which silently raises RecordNotFound for soft-deleted rows). Callers don't see the filter at the call site; database admins counting rows in a console get different answers from the app. Fix: replace with an explicit scope (`scope :active, -> { where(deleted_at: nil) }`) and call it where needed. Soft-delete becomes visible at every use site. Caught by L1 rule `RA-ARCH-002`.
- **Confidence:** HIGH
- **Hit count:** 0

### RA-PREEMPT-009: `deliver_now` in controllers — request blocked on SMTP latency
<a id="ra-preempt-009"></a>
- **Domain:** performance
- **Pattern:** `WelcomeMailer.with(user: user).welcome_email.deliver_now` inside a `create` action blocks the response on outbound SMTP — typically 200ms to 2s. Worse, if the SMTP server is degraded the request times out. Replace every `deliver_now` in controllers with `deliver_later` so ActiveJob (solid_queue on Rails 8) handles delivery async with retries. `deliver_now` is appropriate only inside ActiveJob jobs (the mailer IS the unit of work) and tests (`assert_emails`). Caught by L1 rule `RA-PERF-002`.
- **Confidence:** HIGH
- **Hit count:** 0

### RA-PREEMPT-010: Forgotten `pessimistic_locking` causing race conditions in increment/decrement workflows
<a id="ra-preempt-010"></a>
- **Domain:** persistence
- **Pattern:** `def withdraw(amount); user.update!(balance: user.balance - amount); end` — two concurrent requests both read the same `balance`, both subtract `amount`, both write back. The DB doesn't notice — only the second write wins, but the first's "I subtracted" effect is lost. Symptoms: account balances drift, inventory counts go negative, rate limits leak. Fix: wrap in `User.transaction { user.lock!; user.update!(balance: user.balance - amount); }` for pessimistic locking, or add a `lock_version` column and rescue `ActiveRecord::StaleObjectError` for optimistic locking. For pure counters, use atomic `increment_counter`/`decrement_counter` (single SQL `UPDATE ... SET balance = balance - ?`).
- **Confidence:** HIGH
- **Hit count:** 0

## Common Pitfalls
<!-- Populated by retrospective agent -->

## Effective Patterns
<!-- Populated by retrospective agent -->
