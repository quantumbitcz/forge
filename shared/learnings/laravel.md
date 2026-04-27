---
schema_version: 2
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
items:
  - id: "lv-preempt-001"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.767165Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["security", "laravel"]
    source: "cross-project"
    archived: false
    body_ref: "#lv-preempt-001"
  - id: "lv-preempt-002"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.767165Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["persistence", "laravel"]
    source: "cross-project"
    archived: false
    body_ref: "#lv-preempt-002"
  - id: "lv-preempt-003"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.767165Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["queues", "laravel"]
    source: "cross-project"
    archived: false
    body_ref: "#lv-preempt-003"
  - id: "lv-preempt-004"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.767165Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["configuration", "laravel"]
    source: "cross-project"
    archived: false
    body_ref: "#lv-preempt-004"
  - id: "lv-preempt-005"
    base_confidence: 0.65
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.767165Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["routing", "laravel"]
    source: "cross-project"
    archived: false
    body_ref: "#lv-preempt-005"
  - id: "lv-preempt-006"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.767165Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["migration", "laravel"]
    source: "cross-project"
    archived: false
    body_ref: "#lv-preempt-006"
  - id: "lv-preempt-007"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.767165Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["security", "laravel"]
    source: "cross-project"
    archived: false
    body_ref: "#lv-preempt-007"
  - id: "lv-preempt-008"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.767165Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["persistence", "laravel"]
    source: "cross-project"
    archived: false
    body_ref: "#lv-preempt-008"
  - id: "lv-preempt-009"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.767165Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["security", "laravel"]
    source: "cross-project"
    archived: false
    body_ref: "#lv-preempt-009"
  - id: "lv-preempt-010"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.767165Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["security", "laravel"]
    source: "cross-project"
    archived: false
    body_ref: "#lv-preempt-010"
---
# Cross-Project Learnings: laravel

## PREEMPT items

### LV-PREEMPT-001: Mass assignment via `->fill($request->all())` on models without `$fillable`
<a id="lv-preempt-001"></a>
- **Domain:** security
- **Pattern:** Controllers that pass unfiltered request data to `Model::create($request->all())` / `->fill($request->all())` allow attackers to set arbitrary columns (`is_admin`, `tenant_id`, `email_verified_at`) that the form never exposed. Laravel's `$fillable` allowlist is the only mass-assignment guard; without it (or with `$guarded = []`) every column is writable. Fix: declare `protected $fillable = [...]` listing only the columns safe to mass-assign, and pass `$request->validated()` from a `FormRequest` instead of `$request->all()`. Detect via L1 rule `LV-ARCH-002` (model without explicit `$fillable`) and `LV-SEC-003` (global `unguard()`).
- **Confidence:** HIGH
- **Hit count:** 0

### LV-PREEMPT-002: N+1 from missing eager loads in API resources and Blade loops
<a id="lv-preempt-002"></a>
- **Domain:** persistence
- **Pattern:** `JsonResource::toArray` accesses `$this->author->name` or `$this->tags` without `->with('author', 'tags')` at the query site. The serializer fires one query per row — invisible in dev with 5 rows, catastrophic in prod with 200. Same problem in Blade `@foreach ($posts as $post) {{ $post->author->name }}`. Fix: enable `Model::preventLazyLoading(! app()->isProduction())` in `AppServiceProvider::boot()` so the violation throws `LazyLoadingViolationException` in dev/staging. Always eager-load at the controller, not the model — `Post::with(['author:id,name', 'tags'])->paginate()`. Use `whenLoaded(...)` in resources to gracefully skip unloaded relationships.
- **Confidence:** HIGH
- **Hit count:** 0

### LV-PREEMPT-003: Queue job serialization carries large eager-loaded relations into Redis
<a id="lv-preempt-003"></a>
- **Domain:** queues
- **Pattern:** A job dispatched with `dispatch(new SendInvoice($order))` where `$order` was eager-loaded via `->with(['lineItems', 'customer.addresses', 'payments'])` serializes the entire object graph to Redis. Worker pulls a stale 50KB snapshot, processes it, and operates on data that may have changed since dispatch. `SerializesModels` only stores the model's primary key + class — the trait re-fetches the model from the DB inside the worker. **Discipline:** Pass primary keys (`new SendInvoice($order->id)`) to the job constructor, NOT loaded models, when the data may change between dispatch and execution. Use `SerializesModels` (default on `php artisan make:job`) so any passed model is re-fetched fresh in `handle()`.
- **Confidence:** HIGH
- **Hit count:** 0

### LV-PREEMPT-004: `env()` outside `config/` returns null after `php artisan config:cache`
<a id="lv-preempt-004"></a>
- **Domain:** configuration
- **Pattern:** `env('STRIPE_KEY')` called from `app/Services/StripeClient.php` works in local dev (the `.env` file is loaded). Once `php artisan config:cache` runs in production, the `.env` file is no longer parsed at runtime — only `config/*.php` files reading `env()` at parse time get the values baked in. Code calling `env()` outside `config/` returns `null`, integrations silently fail, and the bug surfaces only after cache regeneration. Fix: every `env()` call lives in `config/services.php` (or another `config/*.php` file). Application code reads `config('services.stripe.key')`. The L1 rule `LV-SEC-002` flags `env()` outside `config/`.
- **Confidence:** HIGH
- **Hit count:** 0

### LV-PREEMPT-005: Implicit route model binding 404s on soft-deleted models
<a id="lv-preempt-005"></a>
- **Domain:** routing
- **Pattern:** A route `Route::get('/posts/{post}', [PostController::class, 'show'])` resolves `$post = Post::findOrFail($id)`. If the `Post` model uses `SoftDeletes`, the implicit binding returns 404 for soft-deleted rows — including admin views that should show deleted content for restoration. Fix: opt into trashed records explicitly per route via `Route::get('/admin/posts/{post}', ...)->withTrashed()` (Laravel 9+), or define a custom resolver in the model: `public function resolveRouteBinding($value, $field = null) { return static::withTrashed()->where(...)->firstOrFail(); }`. Document the convention so admin routes don't silently break when soft-deletes are introduced later.
- **Confidence:** MEDIUM
- **Hit count:** 0

### LV-PREEMPT-006: `dispatchNow()` and other Laravel 8→9 removals break silently on upgrade
<a id="lv-preempt-006"></a>
- **Domain:** migration
- **Pattern:** Codebases that upgraded Laravel 8 → 9 → 10 → 11 over time often retain calls to deprecated APIs that work until they don't: `dispatchNow()` (removed L9, use `dispatchSync()`), `App\Http\Kernel` (removed L11 — middleware/exceptions move to `bootstrap/app.php`), `Mail::send([template], $data, $closure)` (closures aren't queueable, use Mailable classes), `Bus::chain([fn() => ...])` (use invokable Job classes). Detect via the deprecation registry. Most failures are runtime errors that surface only when the specific code path executes — a long-tail of regressions after a Laravel major upgrade. Fix during migration, not post-deploy.
- **Confidence:** HIGH
- **Hit count:** 0

### LV-PREEMPT-007: `Eloquent::unguard()` left enabled in `AppServiceProvider::boot()`
<a id="lv-preempt-007"></a>
- **Domain:** security
- **Pattern:** A developer enables `Eloquent::unguard()` to ease seeding or import, commits it, and forgets to remove it. Every model is now mass-assignable for the entire request lifecycle, including production. Detect via L1 rule `LV-SEC-003`. Fix: remove the call. For seeding, pass attribute arrays explicitly (`User::factory()->create(['is_admin' => true])`) rather than relying on global unguard. For imports, use `Model::withoutEvents(fn () => ...)` for bulk inserts, but never bypass `$fillable`.
- **Confidence:** HIGH
- **Hit count:** 0

### LV-PREEMPT-008: `whereHas` with closures inside loops causes O(N²) queries
<a id="lv-preempt-008"></a>
- **Domain:** persistence
- **Pattern:** Code like `$users->filter(fn ($u) => $u->posts()->where('status', 'published')->exists())` issues one EXISTS subquery per user. With 1000 users, 1000 round trips. Fix: rewrite as a single eager-load + filter: `User::with(['posts' => fn ($q) => $q->where('status', 'published')])->get()->filter(fn ($u) => $u->posts->isNotEmpty())`. Or use `whereHas` at the parent query: `User::whereHas('posts', fn ($q) => $q->where('status', 'published'))->get()`. The latter pushes filtering to the DB in a single query.
- **Confidence:** HIGH
- **Hit count:** 0

### LV-PREEMPT-009: CSRF `$except` exemptions accumulate over time and protect nothing
<a id="lv-preempt-009"></a>
- **Domain:** security
- **Pattern:** Each developer adds one route to `VerifyCsrfToken::$except` to debug a fetch/JSON flow, never removes it. Six months later, a dozen session-cookie-authenticated routes have CSRF disabled. Detect via L1 rule `LV-SEC-005`. Audit rule: every entry in `$except` must use bearer-token auth (Sanctum / Passport) or be a webhook with signature verification — never a route touched by `Auth::user()` via session. In Laravel 11 the exempt list moved to `bootstrap/app.php` `->withMiddleware(fn ($m) => $m->validateCsrfTokens(except: [...]))`; same rule applies.
- **Confidence:** HIGH
- **Hit count:** 0

### LV-PREEMPT-010: Telescope enabled in production exposes every request body and query
<a id="lv-preempt-010"></a>
- **Domain:** security
- **Pattern:** `laravel/telescope` is invaluable in local dev — it captures every request, query, mail, exception, and exposes them via `/telescope`. Shipping it to production with default config exposes secrets, PII, full SQL queries, and authenticated session tokens to anyone who can reach `/telescope`. Even with auth gates, the storage backend retains plaintext request bodies. Fix: install Telescope as `--dev` only (`composer require laravel/telescope --dev`), or guard registration in `TelescopeServiceProvider::register` with `if (! $this->app->environment('local', 'staging')) return;`. Use Pulse for production observability — it ships aggregated, non-sensitive metrics.
- **Confidence:** HIGH
- **Hit count:** 0

## Common Pitfalls
<!-- Populated by retrospective agent -->

## Effective Patterns
<!-- Populated by retrospective agent -->
