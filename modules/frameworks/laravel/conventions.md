# Laravel Framework Conventions
> Support tier: contract-verified
> Framework-specific conventions for Laravel 11.x projects. Language idioms are in `modules/languages/php.md`.
> Generic testing patterns are in `modules/testing/phpunit.md`.
> Composition stack: `variant > laravel/testing/phpunit.md > laravel/conventions.md > php.md > persistence/eloquent-binding > testing/phpunit.md`.

## Overview

Laravel is a batteries-included PHP framework — it ships routing, ORM (Eloquent), queues, mail, validation, auth, scheduling, broadcasting, and a CLI (`artisan`) out of the box. Laravel 11 introduced a streamlined skeleton: configuration moved into `bootstrap/app.php`, the `Kernel` classes were removed, middleware and exception handling are configured fluently, and `routes/console.php` replaces `app/Console/Kernel.php` for scheduling. Use Laravel when:

- You want a productive, full-stack PHP framework with first-class ORM, queue, and mail systems
- The team is comfortable with convention over configuration (service container, facades, ActiveRecord-style models)
- You need a deployable HTTP app behind PHP-FPM / Octane / FrankenPHP

Prefer Symfony when you need a more component-oriented architecture with explicit DI and CQRS-friendly building blocks. Prefer Slim/Lumen when the surface is API-only and you want a microframework. For Laravel API-only services prefer the `api-only` variant in this module.

## Architecture (Controller + Service + Action + FormRequest)

| Layer | Responsibility | Dependencies |
|-------|---------------|--------------|
| `routes/{web,api,console}.php` | URL → controller / action / closure mapping; middleware groups, throttle, route model binding | Controllers, middleware |
| `app/Http/Controllers/*Controller` | HTTP boundary — receive a `FormRequest`, delegate to a service or action, return a response | FormRequests, services, resources |
| `app/Http/Requests/*Request` | Validation + authorization for inbound requests (`rules()`, `authorize()`) | Eloquent (for `exists`/`unique` rules) |
| `app/Http/Resources/*Resource` | JSON serialization (`JsonResource`, `ResourceCollection`) | Eloquent models |
| `app/Services/*Service` | Multi-step business logic, orchestration, transaction boundaries | Models, repositories, jobs |
| `app/Actions/*Action` | Single-purpose use cases (one public method, often `__invoke`) — preferable for thin verbs | Models, services |
| `app/Models/*` | Eloquent models — relationships, scopes, accessors/mutators, casts, observers | None (DB-bound) |
| `app/Jobs/*Job` | Queueable units of work (`ShouldQueue`, `SerializesModels`) | Models, services |
| `app/Events/*Event` + `app/Listeners/*Listener` | Domain event broadcast and reaction | Models |
| `app/Policies/*Policy` | Authorization rules per model — invoked via `Gate`, `authorize()`, `@can` | Models, the authenticated user |
| `app/Providers/*ServiceProvider` | Container bindings, observer registration, route model binding, macros | Container |
| `database/migrations/*` | Schema migrations (`up()`/`down()`) | Schema builder |
| `database/factories/*Factory` | Eloquent factories for tests and seeders | Models, faker |

**Dependency rule:** Controllers do not contain business logic — they validate via a `FormRequest`, delegate to a service or action, and return a response (view, redirect, `JsonResource`, or `Response`). Services own multi-step writes and transaction boundaries. Models own their relationships, scopes, and casts but stay free of HTTP concerns. Cross-module communication uses domain events (`event(...)`) or queued jobs, not direct service-to-controller calls.

## Application Bootstrap (Laravel 11)

The Laravel 11 skeleton replaces `App\Http\Kernel`, `App\Console\Kernel`, and `App\Exceptions\Handler` with fluent configuration in `bootstrap/app.php`:

```php
// bootstrap/app.php
return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__ . '/../routes/web.php',
        api: __DIR__ . '/../routes/api.php',
        commands: __DIR__ . '/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        $middleware->web(append: [HandleInertiaRequests::class]);
        $middleware->alias(['can' => Authorize::class]);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->render(fn (DomainException $e, Request $request) =>
            $request->expectsJson()
                ? response()->json(['error' => $e->getMessage()], 422)
                : null);
    })->create();
```

The schedule lives in `routes/console.php`:

```php
Schedule::command('app:reconcile-billing')->dailyAt('02:00')->onOneServer();
```

Do not resurrect the legacy `Kernel` classes on Laravel 11+ unless migrating an older codebase incrementally.

## Routing

- One file per surface: `routes/web.php` (session-cookie auth, CSRF), `routes/api.php` (stateless, prefixed `/api`), `routes/console.php` (artisan + schedule)
- Use route model binding: `Route::get('/users/{user}', [UserController::class, 'show'])` resolves `$user = User::findOrFail($id)` automatically. Customize the key with `getRouteKeyName()`
- Group middleware/prefix at the route level; never duplicate middleware per-route
- Throttle every public endpoint: `Route::middleware('throttle:60,1')` or named limiters via `RateLimiter::for(...)`
- Name every route (`->name('users.show')`) and use `route('users.show', $user)` in controllers, blade, and tests — never hardcode URLs
- Resource routes (`Route::resource('users', UserController::class)`) generate the standard 7 endpoints; use `apiResource` for stateless APIs (drops `create`/`edit`)
- Implicit binding on soft-deleted models requires `->withTrashed()` on the binding or the route returns 404

```php
// routes/api.php
Route::middleware(['auth:sanctum', 'throttle:api'])->group(function (): void {
    Route::apiResource('posts', PostController::class)->scoped(['post' => 'slug']);
});
```

## Eloquent (ORM)

- Prefer Eloquent's expressive query builder over raw `DB::` calls; reach for the query builder when you need GROUP BY / window functions / CTEs
- Always declare `$fillable` (allowlist) **or** `$guarded = []` + global `unguard()` discipline (NOT recommended) — pick one stance per project; `$fillable` is the default in this plugin
- Use casts for typed attributes: `protected $casts = ['settings' => 'array', 'published_at' => 'datetime', 'role' => RoleEnum::class]`
- Define relationships with explicit return types: `public function posts(): HasMany { return $this->hasMany(Post::class); }`
- Use accessors/mutators via `Attribute::make(get: fn ($v) => ucfirst($v))` (Laravel 9+) — not the legacy `getNameAttribute` / `setNameAttribute` methods
- Prevent N+1 with `->with(['posts.tags'])` eager loading at the query site, not in the model. Enable `Model::preventLazyLoading()` in `AppServiceProvider::boot()` for non-prod
- Use `chunk(1000, fn ($rows) => ...)` for large reads; use `lazy()` (cursor-based) when memory is tight
- Use `withCount()` / `loadCount()` for relationship counts instead of separate `->count()` queries
- Soft deletes: `use SoftDeletes; protected $dates = ['deleted_at']` — write queries that consider `withTrashed()` / `onlyTrashed()` semantics
- Observers (`UserObserver`) over inline `static::created(...)` closures — observers are testable and discoverable. Register in `AppServiceProvider`

```php
public function index(): JsonResponse
{
    $posts = Post::query()
        ->with(['author:id,name', 'tags'])
        ->withCount('comments')
        ->latest()
        ->paginate(20);

    return PostResource::collection($posts)->response();
}
```

## Migrations & Schema

- Always pair `up()` and `down()`. A migration without `down()` cannot be rolled back during deploy failures
- One concern per migration file (`add_status_column_to_posts_table.php`); never combine schema + data migrations in the same file
- Zero-downtime patterns:
  - Adding a non-nullable column → 2 migrations: add nullable + backfill data, then alter to non-nullable
  - Renaming a column → 3 migrations: add new column, dual-write + backfill, drop old column. Never `renameColumn` in a single migration on a hot table
  - Dropping a column → release code change first, then the migration in the next deploy
- Use `Schema::table` + `$table->index([...], 'idx_name')` to name indexes — implicit names break across DB engines
- Foreign keys with `->constrained()->cascadeOnDelete()` (Laravel 7+); add explicit indexes on the FK column for query performance
- Prefer `bigIncrements()` / `unsignedBigInteger()` for new tables — `increments()` (`int`) overflows at ~2.1B rows
- Run `php artisan migrate --pretend` in CI to surface destructive operations before production deploys
- For backfills > 100k rows use a queued job (`Schedule::command(...)->onOneServer()`), not the migration body

## Validation (FormRequest)

- One `FormRequest` per controller action — never inline `$request->validate([...])` for anything beyond a single trivial field
- `authorize()` returns `true` only when authorization is genuinely open; otherwise call a `Policy` or check a `Gate`
- Use rule classes (e.g. `Password::min(12)->mixedCase()->numbers()->uncompromised()`) over string DSL when reusable
- Custom rules implement `Illuminate\Contracts\Validation\ValidationRule` (Laravel 10+); the legacy `Rule` interface is deprecated
- `prepareForValidation()` to normalize input before rules run (trim, lowercase emails); `passedValidation()` for downstream side effects
- `messages()` and `attributes()` for human-readable errors

```php
class StorePostRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('create', Post::class);
    }

    public function rules(): array
    {
        return [
            'title' => ['required', 'string', 'max:255'],
            'body'  => ['required', 'string'],
            'tags'  => ['array'],
            'tags.*' => ['string', 'exists:tags,name'],
        ];
    }
}
```

## Auth

- Default for SPA + first-party clients: **Sanctum** (cookie or token). Default for OAuth2 server: **Passport**. Use **Breeze** as a starting kit for full-stack scaffolding (Blade, Livewire, Inertia/Vue, Inertia/React)
- Policies (`UserPolicy`) over inline `Gate::define` for model-level permissions. Register via `Gate::policy(...)` or auto-discovery in `AuthServiceProvider`
- `Gate::before(fn ($user, $ability) => $user->isAdmin() ?: null)` for the global "admins can do everything" override — return `null` to defer, never `false`
- Authorize at the controller boundary: `$this->authorize('update', $post)` — every protected action
- `signedRoute` / `temporarySignedRoute` for password-reset / email-verification flows
- `Hash::needsRehash($user->password)` after login to upgrade hashes when bcrypt cost changes

## Queues & Jobs

- Mark slow work as `ShouldQueue`. Implement `SerializesModels` trait so queued models are restored from the DB on dispatch (NOT serialized in full)
- Configure failed jobs: `php artisan queue:failed-table` + `php artisan migrate`. Monitor `failed_jobs` table; retry idempotent failures with `queue:retry`
- Use `Bus::chain([...])` for sequential dependencies, `Bus::batch([...])->then(...)->catch(...)->dispatch()` for fan-out + reconciliation
- Use `dispatchSync(...)` for unit tests; never use the deprecated `dispatchNow()` (removed in Laravel 9)
- Tag long-running jobs with `->onQueue('reports')` and run dedicated workers; never let report generation block transactional work
- Idempotency: every job should be safe to run twice. Use a unique constraint or a "processed at" column to detect re-runs
- Horizon for production queue monitoring (Redis only). Configure `supervisor` / systemd to restart workers; workers must terminate after N jobs to free memory (`--max-jobs=1000`)

## Events, Listeners & Broadcasting

- Domain events (`PostPublished`) are POPOs in `app/Events`; listeners in `app/Listeners`. Auto-register via `EventServiceProvider::$listen`
- Listeners that touch I/O (mail, push, downstream API) implement `ShouldQueue` — they run in the queue worker, not in the request
- Broadcasting (Reverb / Pusher): events implement `ShouldBroadcast` and `broadcastOn()` returns `PrivateChannel(...)` / `PresenceChannel(...)`. Channel auth in `routes/channels.php`
- Model observers (`UserObserver`) for lifecycle hooks (`creating`, `created`, `updating`, `deleted`). Register in `AppServiceProvider::boot()` via `User::observe(UserObserver::class)`. Avoid mixing observers and event listeners for the same model

## Cache, Rate Limiting & Mail

- Cache via `Cache::remember('key', $ttl, fn () => ...)` — never call `Cache::put` + `Cache::get` separately for read-through patterns
- Tag cache for invalidation: `Cache::tags(['users', "user:{$id}"])->put(...)` (Redis / Memcached only)
- Rate limit named limiters in `AppServiceProvider::boot()`:
  ```php
  RateLimiter::for('api', fn (Request $req) =>
      Limit::perMinute(60)->by($req->user()?->id ?: $req->ip())
  );
  ```
- Mailables are classes (`app/Mail/InvoicePaid.php`) that implement `ShouldQueue` for transactional sends. Use markdown mail (`resources/views/mail/...`) for branded templates
- Notifications (`app/Notifications/InvoiceFailed.php`) for multi-channel sends (mail + database + Slack). Notifications wrap mailables and add channel routing

## Artisan Command Design

- Define commands in `app/Console/Commands` with `protected $signature = 'app:reconcile {--dry-run}'` and a meaningful `$description`
- Use the `--dry-run` flag for any command that mutates data; default to dry-run in production-like envs
- Long-running commands: use `--isolated` (Laravel 9+) to lock against concurrent runs of the same command
- Schedule in `routes/console.php` (Laravel 11) — avoid `app/Console/Kernel.php`. Use `->onOneServer()`, `->withoutOverlapping()`, `->runInBackground()`
- Exit codes: `Command::SUCCESS` (0), `Command::FAILURE` (1), `Command::INVALID` (2). Never `return null` — explicit codes drive CI

## Security

- **Mass assignment:** Always set `$fillable` (allowlist) on every model. Never call `Model::unguard()` globally — it disables the protection for the entire request lifecycle
- **CSRF:** Automatic on `web` routes via `VerifyCsrfToken`. Exempt only when the endpoint authenticates via token (Sanctum personal access token / Passport bearer), never for session-cookie-authenticated routes
- **Authorization:** Every state-changing route must call `$this->authorize(...)` or sit behind the `can:` middleware
- **`env()` outside config:** `env('FOO')` returns `null` once `php artisan config:cache` has run because the env file is no longer loaded. Read `config('services.foo')` everywhere outside `config/`
- **SQL injection:** Eloquent and the query builder bind all parameters. Never interpolate variables into `DB::raw('... ' . $value . ' ...')`; pass bindings as the second argument to `whereRaw` / `selectRaw`
- **Signed URLs:** Use `URL::signedRoute(...)` for one-shot links (download, password reset). Verify with `signed` middleware
- **File uploads:** Validate via `mimes:` (extension) AND `mimetypes:` (sniffed). Store with `Storage::putFileAs(...)` and use `secure_filename`-equivalent sanitization
- **Headers:** Use `secure-headers`-style middleware (CSP, HSTS, X-Frame-Options) — Laravel does not ship them by default

## Performance

- N+1 detection: enable `Model::preventLazyLoading()` in non-prod inside `AppServiceProvider::boot()`. Will throw `LazyLoadingViolationException` when an unloaded relationship is accessed
- `DB::enableQueryLog()` in tests to assert on query count: `assertSame(1, count(DB::getQueryLog()))`
- Eager load with field selection to reduce row size: `->with('author:id,name')` instead of `->with('author')`
- Cache aggressively for read-heavy lists: `Cache::remember("posts:trending:{$page}", 60, ...)`. Invalidate via tags on writes
- Pagination: every list endpoint uses `paginate()` or `cursorPaginate()`. `cursorPaginate` for unbounded feeds (no count query)
- Octane / FrankenPHP for hot-path APIs — but watch state leaks across requests (singletons that hold per-request data)
- Avoid `whereHas('relation', fn ($q) => ...)` in tight loops — it issues an exists subquery per row. Prefer eager loading + filtering in PHP for known-bounded sets

## Error Handling

- Exception rendering goes through `bootstrap/app.php` `withExceptions(...)` (Laravel 11). Map domain exceptions to HTTP responses there
- Define a domain base exception (`App\Exceptions\AppException`) with `code` and `status` properties; concrete classes (`PostNotPublishableException`) extend it
- Never `catch (\Throwable $e) { /* swallow */ }` — at minimum log + rethrow. Use the dedicated `report($e)` helper for logged-but-handled errors
- API responses use a consistent envelope: `{"message": "...", "errors": {...}}` (matches Laravel's default `ValidationException` format)
- Never expose stack traces in production: `APP_DEBUG=false` in production envs; verify with `php artisan about`

## API Design

- Versioning via URL prefix: `Route::prefix('v1')->group(...)` — separate `routes/api/v1.php` files for large APIs
- JSON via `JsonResource` / `ResourceCollection`; never return raw `Model::all()->toJson()` — it leaks columns
- Pagination: include `links`, `meta` blocks (default in `ResourceCollection`); use `cursorPaginate` for unbounded feeds
- Rate limiting per-route via named limiters; surface `X-RateLimit-*` headers (Laravel does this by default for `throttle` middleware)
- Idempotency for write endpoints: accept `Idempotency-Key` header, persist (key, hash(body), response) for 24h, replay on collision

## Code Quality

- Follow PSR-12 and Laravel's own conventions (Pint config: `laravel`)
- Run `./vendor/bin/pint` (or `pint --test` in CI) for formatting
- Static analysis: PHPStan / Larastan at level 6+ for new code; level 5 for legacy
- One class per file; PSR-4 autoloading. Filename matches class name
- Methods ≤ 40 lines; controllers ≤ 200 lines; nesting ≤ 3 levels
- Type-hint every parameter and return type. PHP 8.1+ for `readonly` properties on DTOs
- No `dd()` / `dump()` / `var_dump()` in committed code — block via lint rule

## Testing

- PHPUnit 10+ (or Pest). Per-test database isolation via `RefreshDatabase` (truncate + re-migrate per test) or `DatabaseTransactions` (rollback per test — faster, requires SQLite/Postgres transactional DDL)
- Feature tests via `$this->get(...)`, `$this->postJson(...)`; unit tests for services / actions in isolation
- See `modules/frameworks/laravel/testing/phpunit.md` for the full fixture pattern, factories, and fakes

## TDD Flow

```
scaffold -> write failing tests (RED) -> implement (GREEN) -> refactor
```

1. **Scaffold:** controller + FormRequest + service stub + policy + factory + resource
2. **RED:** feature test through `$this->postJson(...)` asserting status + JSON shape; unit test for service in isolation
3. **GREEN:** minimum code to satisfy the assertions — start with the controller wiring, fill in the service
4. **Refactor:** extract collaborators, tighten validation rules, run `pint --test` + `phpstan analyse` — tests must still pass

## Logging and Monitoring

- `Log::info(...)` / `Log::error(...)` — backed by Monolog. Configure channels in `config/logging.php`
- JSON output in production via the `json` formatter; include request_id (set in middleware), user_id, route
- Never log secrets, passwords, full request bodies, or PII. Use `Log::withContext([...])` to add scoped fields
- Health endpoint: Laravel 11 ships `/up` by default (configured in `withRouting(health: '/up')`). Add a richer `/healthz` for DB / Redis / S3 reachability checks if needed
- Telescope for local debugging only (NEVER in production — exposes request bodies, queries, mail). Pulse for production observability dashboards

## Boy Scout Rule

Improve touched code if: safe, small (<10 lines), local (same file), convention-aligned.
NOT in scope: refactoring unrelated controllers, schema changes, fixing pre-existing bugs.

## Dos and Don'ts

### Do
- Use Laravel 11's `bootstrap/app.php` configuration — do not resurrect `App\Http\Kernel` on new projects
- Declare `$fillable` (allowlist) on every Eloquent model; never rely on `$guarded = []` plus discipline
- Read configuration via `config('services.foo')`, not `env('FOO')`, outside the `config/` directory
- Use `FormRequest` classes for all non-trivial validation; keep `authorize()` honest (call a Policy / Gate)
- Eager-load relationships at the query site (`->with([...])`) and enable `Model::preventLazyLoading()` in non-prod
- Use queued mailables / notifications (`ShouldQueue`) for transactional email and push — never block the request
- Authorize state-changing routes with `$this->authorize(...)` or the `can:` middleware
- Pair every migration `up()` with a real `down()` body — never leave it as `pass` / empty
- Use named routes (`->name(...)`) and `route(...)` everywhere — never hardcode URLs
- Use `JsonResource` / `ResourceCollection` for API responses; never `return Model::all()`
- Use observers for model lifecycle hooks; register them in `AppServiceProvider::boot()`
- Run `php artisan config:cache && php artisan route:cache` in production deploys; verify locally that `env()` is not used outside `config/`
- Use `Sanctum` for SPA + first-party clients; `Passport` for OAuth2 server scenarios
- Schedule via `routes/console.php` (Laravel 11) with `->onOneServer()` for cron-safe single execution
- Use `cursorPaginate()` for unbounded feeds and large datasets — avoid the count query

### Don't
- Don't call `env(...)` outside `config/` files — it returns `null` once `php artisan config:cache` runs
- Don't use `Eloquent::unguard()` globally — it nullifies mass-assignment protection for the entire request
- Don't use `$request->validate(...)` inline for anything beyond one trivial field — promote to a `FormRequest`
- Don't expose `Model::query()->get()` or raw collections directly from controllers; serialize via `JsonResource`
- Don't `csrf` exempt session-cookie-authenticated routes; only token-authenticated endpoints qualify
- Don't use `dispatchNow(...)` — it was removed in Laravel 9; use `dispatchSync(...)` for synchronous dispatch
- Don't use `Mail::send(['template'], $data, $closure)` — closures aren't queueable; use Mailable classes
- Don't import `Illuminate\Support\Facades\Input` — it was removed in Laravel 6; inject `Request` instead
- Don't string-concat into `DB::raw(...)` / `whereRaw(...)` — use bindings (`whereRaw('col = ?', [$value])`)
- Don't `static::created(fn ($model) => ...)` inside the model — use an Observer for testability and discoverability
- Don't combine schema + data changes in the same migration — separate files, separate deploys
- Don't run Telescope in production — it captures every request body, query, mail, and exposes them via `/telescope`
- Don't return raw `dump()` / `dd()` / `var_dump()` from controllers; use logging or the debug bar
- Don't bind to `$request->all()` for `Model::create(...)` without `$fillable` — exposes mass-assignment vulnerabilities
- Don't access soft-deleted models via implicit route binding without `->withTrashed()` — silently 404s confuse callers
