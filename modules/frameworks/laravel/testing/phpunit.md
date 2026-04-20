# Laravel + PHPUnit Testing Patterns

> Laravel-specific PHPUnit patterns. Extends `modules/testing/phpunit.md`.
> Generic PHPUnit conventions (data providers, mocks, attributes) are not repeated here.

## Test Layout

```
tests/
  TestCase.php                 # extends Illuminate\Foundation\Testing\TestCase
  Feature/                     # HTTP / multi-component flows
    Auth/
      LoginTest.php
    Posts/
      CreatePostTest.php
      ListPostsTest.php
  Unit/                        # No app boot; isolated services / value objects
    Services/
      BillingReconcilerTest.php
    Money/
      MoneyTest.php
  Fixtures/                    # Static JSON, XML, fixtures
phpunit.xml
```

`Feature` tests boot the application, use the request lifecycle, and hit the database. `Unit` tests should NOT boot Laravel — they instantiate the SUT directly with mocked collaborators, and are an order of magnitude faster.

## Database Isolation Strategies

| Trait | How it works | Speed | Caveats |
|---|---|---|---|
| `RefreshDatabase` | Migrate + truncate per test | Slowest | Safest, works for any DB |
| `DatabaseTransactions` | Wrap each test in a transaction, rollback at teardown | Fast | Requires transactional DDL — Postgres/SQLite OK, MySQL needs InnoDB and does NOT support DDL inside the transaction |
| `DatabaseMigrations` | Re-run migrations per test | Slowest | Use only when schema mutations are part of the test |

**Default for new projects: `RefreshDatabase` with the `--using-in-memory-database=true` config option (`config/database.php` + `phpunit.xml`).** SQLite in-memory is fast enough for most suites and avoids the MySQL DDL caveat.

```php
namespace Tests\Feature\Posts;

use App\Models\Post;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class CreatePostTest extends TestCase
{
    use RefreshDatabase;

    public function test_authenticated_user_can_create_a_post(): void
    {
        $user = User::factory()->create();

        $response = $this->actingAs($user)->postJson('/api/posts', [
            'title' => 'Hello',
            'body'  => 'World',
        ]);

        $response->assertCreated()
            ->assertJsonStructure(['data' => ['id', 'slug', 'title', 'links' => ['self']]]);

        $this->assertDatabaseHas('posts', ['title' => 'Hello', 'author_id' => $user->id]);
    }
}
```

## `actingAs` and Auth Guards

```php
$this->actingAs($user);                    // default web guard
$this->actingAs($user, 'sanctum');         // explicit guard
Sanctum::actingAs($user, ['post:write']);  // Sanctum with scoped abilities
```

For tests that exercise the full token flow (issuing + revoking), call the auth endpoints directly:

```php
$response = $this->postJson('/api/login', ['email' => $user->email, 'password' => 'secret']);
$token = $response->json('token');

$this->withHeader('Authorization', "Bearer {$token}")
     ->getJson('/api/posts')
     ->assertOk();
```

## HTTP Testing Assertions

```php
$response->assertOk();                       // 200
$response->assertCreated();                  // 201
$response->assertNoContent();                // 204
$response->assertNotFound();                 // 404
$response->assertForbidden();                // 403
$response->assertUnauthorized();             // 401
$response->assertUnprocessable();            // 422
$response->assertStatus(418);                // explicit

$response->assertJsonStructure([
    'data' => [
        '*' => ['id', 'title', 'author' => ['id', 'name']],
    ],
    'meta',
    'links',
]);

$response->assertJsonPath('data.0.title', 'Hello');
$response->assertJsonCount(20, 'data');
$response->assertJsonValidationErrors(['email', 'password']);
$response->assertJsonMissingValidationErrors(['name']);
$response->assertExactJson([...]);            // strict — every key matched
```

`assertJsonStructure` validates SHAPE; `assertJsonPath` / `assertExactJson` validate VALUES. Use both — shape catches refactor regressions, values catch data bugs.

## Factories

Define factories with `state()` for variants and `has()` / `for()` for relationships:

```php
namespace Database\Factories;

use App\Models\Post;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

class PostFactory extends Factory
{
    protected $model = Post::class;

    public function definition(): array
    {
        return [
            'title'        => $this->faker->sentence(6),
            'slug'         => $this->faker->slug(),
            'body'         => $this->faker->paragraphs(3, true),
            'status'       => 'draft',
            'published_at' => null,
            'author_id'    => User::factory(),
        ];
    }

    public function published(): self
    {
        return $this->state([
            'status'       => 'published',
            'published_at' => now()->subDay(),
        ]);
    }
}
```

```php
$user = User::factory()->create();
$post = Post::factory()->published()->for($user, 'author')->create();
$comments = Comment::factory(5)->for($post)->create();

// Single SQL round trip via createMany
Post::factory()->count(100)->published()->for($user, 'author')->create();
```

For model-level relationships use `has()`:

```php
$user = User::factory()
    ->has(Post::factory()->count(3)->published(), 'posts')
    ->has(Comment::factory()->count(10), 'comments')
    ->create();
```

Avoid raw `User::create([...])` in tests — factories make tests resilient to schema changes.

## Mockery and Container Bindings

Three patterns, in order of preference:

**1. Bind a fake into the container (preferred for service-layer collaborators):**

```php
$this->mock(StripeClient::class, function ($mock) {
    $mock->shouldReceive('charge')->once()->andReturn(['id' => 'ch_123']);
});

$this->postJson('/api/checkout', [...])->assertOk();
```

`$this->mock(...)` replaces the binding only for the duration of the test.

**2. `Mockery::mock(...)` directly (when no container interaction):**

```php
$reconciler = Mockery::mock(BillingReconciler::class);
$reconciler->shouldReceive('reconcile')->once();
```

**3. Fakes (`Mail::fake()`, `Queue::fake()`, etc.) — see below.**

Always close Mockery in `tearDown` (Laravel's `TestCase` does this automatically — don't override `tearDown` without calling `parent::tearDown()`).

## Built-In Fakes

Laravel ships fakes for every I/O-side facade. Always prefer fakes over mocking the facade manually:

```php
public function test_invoice_paid_dispatches_notification(): void
{
    Notification::fake();
    Mail::fake();
    Queue::fake();
    Event::fake([InvoicePaid::class]);
    Bus::fake();
    Storage::fake('s3');

    // ... exercise code ...

    Notification::assertSentTo($user, InvoicePaidNotification::class);
    Mail::assertQueued(InvoiceReceipt::class, fn ($mail) => $mail->hasTo($user->email));
    Queue::assertPushed(SendReminder::class);
    Event::assertDispatched(InvoicePaid::class);
    Bus::assertDispatched(ProcessRefund::class);
    Storage::disk('s3')->assertExists("invoices/{$invoice->id}.pdf");
}
```

`Event::fake([SpecificEvent::class])` (with an array) only swallows the listed events — observers and other listeners still fire. Crucial when testing model lifecycle hooks.

## HTTP Client Faking

For services that call external APIs via Laravel's HTTP client:

```php
Http::fake([
    'api.stripe.com/*' => Http::response(['id' => 'ch_123'], 201),
    'api.example.com/users/*' => Http::sequence()
        ->push(['id' => 1], 200)
        ->push(['id' => 2], 200)
        ->pushStatus(500),
]);

$service->charge();

Http::assertSent(fn ($request) =>
    $request->url() === 'https://api.stripe.com/charges' && $request['amount'] === 1000
);
```

Never let real HTTP traffic leave the test process — `Http::fake()` (without arguments) intercepts all outbound requests.

## Parallel Testing

```bash
php artisan test --parallel
php artisan test --parallel --processes=4
```

`--parallel` runs feature tests in worker processes, each with its own SQLite database (`testing-1.sqlite`, `testing-2.sqlite`, etc.). Caveats:

- The `RefreshDatabase` trait works out of the box with parallel — Laravel handles per-worker DB setup
- Tests that touch shared resources (a single Redis instance, a single S3 bucket) must namespace their writes by worker token: `parallel_token_value()`
- File-based caches must be configured per-worker — `cache.stores.file.path` should include `parallel_token_value()`

## Pest Interop

If the project uses Pest (`pestphp/pest`), the Laravel testing helpers (`actingAs`, `getJson`, fakes, factories) work identically — Pest is a syntactic layer over PHPUnit:

```php
use App\Models\User;
use function Pest\Laravel\actingAs;
use function Pest\Laravel\postJson;

it('creates a post when authenticated', function () {
    $user = User::factory()->create();

    actingAs($user)
        ->postJson('/api/posts', ['title' => 'Hi', 'body' => 'There'])
        ->assertCreated();
});
```

The conventions in this file apply equally to PHPUnit class style and Pest function style.

## What to Test at Each Layer

| Layer | Test type | Notes |
|---|---|---|
| Controller / Route | Feature | `actingAs` + `postJson` + `assertJsonStructure` + `assertDatabaseHas` |
| FormRequest rules | Feature (preferred) | Test the controller endpoint with invalid input; assert `assertJsonValidationErrors` |
| FormRequest authorize() | Feature | Acting as authorized vs unauthorized user; assert 403 vs 200 |
| Service / Action | Unit | No app boot; mock collaborators via Mockery |
| Eloquent model | Feature (uses DB) | Factories + `RefreshDatabase`; test scopes, accessors, casts |
| Policy | Feature | `Gate::forUser($user)->allows('update', $post)` |
| Job | Feature | `Bus::fake()` + `Bus::assertDispatched`; or run synchronously and assert outcome |
| Mail / Notification | Feature | `Mail::fake()` / `Notification::fake()` + assertSent assertions |
| Console command | Feature | `$this->artisan('app:cmd')->expectsOutput(...)->assertExitCode(0)` |
| Event listener | Feature | `Event::fake([SpecificEvent::class])` + assert that the listener side effect occurred |

## Common Pitfalls

- **Mixing `RefreshDatabase` + `DatabaseTransactions`** — they conflict; pick one per test class
- **Forgetting `Mail::fake()` in tests that send mail** — real emails ship from the test runner; SES bills you
- **`Event::fake()` without arguments** swallows ALL events including model observers — pass `[SpecificEvent::class]` if you still want observer side effects
- **Time-dependent assertions** without `Carbon::setTestNow(...)` — flake on slow CI
- **Asserting on `$response->json()` without `assertJson(...)`** — drops the helpful diff output on failure

## Dos

- Use `RefreshDatabase` with SQLite in-memory by default; switch to `DatabaseTransactions` for speed once the schema is stable
- Use factories with `state()` / `for()` / `has()` — never `Model::create([...])` in tests
- Use `actingAs($user)` (or `Sanctum::actingAs(...)` for scoped tokens) instead of authenticating via the login endpoint in every test
- Use `Mail::fake()` / `Queue::fake()` / `Bus::fake()` / `Notification::fake()` / `Event::fake([...])` / `Http::fake([...])` for every external-effect test
- Pin time with `Carbon::setTestNow(now()->addDay())` for time-dependent tests
- Run `php artisan test --parallel --processes=4` in CI for >100 feature tests

## Don'ts

- Don't mix `RefreshDatabase` and `DatabaseTransactions` traits in the same test class — they conflict
- Don't assert on raw `$response->getContent()` JSON strings — use `assertJsonStructure` / `assertJsonPath` for diff-friendly output
- Don't rely on auto-discovery for events / observers in tests without verifying the registration via `Event::hasListeners(...)` — they sometimes fail silently
- Don't seed databases via `\Artisan::call('db:seed')` in `setUp` — adds 100s of ms per test; use targeted factories instead
- Don't leave `dd()` / `dump()` in committed tests — block via lint rule

For generic PHPUnit conventions (data providers, mocks, attributes, configuration) see `modules/testing/phpunit.md`.
