# Laravel + API-Only Variant

> Stateless / Sanctum-first JSON API. Extends `modules/frameworks/laravel/conventions.md`.
> Use this variant when the app's surface is exclusively `/api/*` endpoints — mobile backends,
> microservices, third-party integrations. The `web` middleware group, sessions, and CSRF
> protection are typically disabled or absent.

## Auth Modes

| Mode | Use case | Endpoint |
|---|---|---|
| Sanctum personal access token | First-party mobile apps, internal tools | `POST /sanctum/token` (custom) |
| Sanctum SPA token | Same-domain SPA on the same Laravel host | Cookie-based, EnsureFrontendRequestsAreStateful |
| Passport (OAuth2) | Third-party OAuth2 clients, public APIs | `POST /oauth/token` (Passport routes) |
| API key | Server-to-server with low-trust scope | Custom middleware reading `X-API-Key` |

This variant assumes **Sanctum personal access token** as the default. Switch to Passport when OAuth2 grant types (authorization code, client credentials) are required.

### Sanctum Token Flow

```php
// Issuing a token
public function login(LoginRequest $request): JsonResponse
{
    $user = User::where('email', $request->email)->firstOrFail();

    if (! Hash::check($request->password, $user->password)) {
        throw ValidationException::withMessages(['email' => 'Invalid credentials']);
    }

    $token = $user->createToken($request->device_name, ['*'], expiresAt: now()->addDays(30));

    return response()->json([
        'token'      => $token->plainTextToken,
        'expires_at' => $token->accessToken->expires_at,
    ]);
}

// Revoking
public function logout(Request $request): JsonResponse
{
    $request->user()->currentAccessToken()->delete();
    return response()->json(['ok' => true]);
}
```

Configure token expiration in `config/sanctum.php` (`expiration` key) and prune expired tokens via `Schedule::command('sanctum:prune-expired --hours=24')->daily()`.

## Route Layout

```php
// routes/api.php
Route::middleware(['throttle:api'])->group(function (): void {
    Route::post('login',  [AuthController::class, 'login'])->middleware('throttle:auth');
    Route::post('logout', [AuthController::class, 'logout'])->middleware('auth:sanctum');

    Route::middleware('auth:sanctum')->group(function (): void {
        Route::apiResource('posts', PostController::class)->scoped(['post' => 'slug']);
        Route::apiResource('posts.comments', CommentController::class)->shallow();
    });
});
```

`apiResource` (vs `resource`) skips the `create` and `edit` form routes — there's no HTML form in an API-only app.

## Versioning

Two viable strategies:

**URL prefix (recommended for first version bump):**

```php
Route::prefix('v1')->group(base_path('routes/api/v1.php'));
Route::prefix('v2')->group(base_path('routes/api/v2.php'));
```

Each version owns its controllers (`App\Http\Controllers\Api\V1\PostController`, `App\Http\Controllers\Api\V2\PostController`) — never share controllers across versions, breaking changes will leak.

**Header-based (`Accept: application/vnd.app.v2+json`):**

Implemented via custom middleware that swaps the route group based on the header. More flexible, harder to debug, and confuses tooling (Postman, browser cache). Use only when URL versioning is genuinely impractical.

## API Resources (`JsonResource`)

Always serialize through `JsonResource` — never return `Model::all()` or raw arrays:

```php
class PostResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id'           => $this->id,
            'slug'         => $this->slug,
            'title'        => $this->title,
            'excerpt'      => $this->excerpt,
            'published_at' => $this->published_at?->toIso8601String(),
            'author'       => UserResource::make($this->whenLoaded('author')),
            'tags'         => TagResource::collection($this->whenLoaded('tags')),
            'links'        => [
                'self' => route('posts.show', $this->resource),
            ],
        ];
    }
}
```

`whenLoaded(...)` keeps the resource graceful when the relationship isn't eager-loaded — prevents accidental N+1 from serializers.

`ResourceCollection` for paginated lists wraps `data`, `links`, `meta` automatically:

```php
public function index(): ResourceCollection
{
    return PostResource::collection(
        Post::query()->with('author:id,name')->latest()->cursorPaginate(20)
    );
}
```

## Pagination Metadata

Three Laravel paginators:

| Paginator | Returns | Use case |
|---|---|---|
| `paginate()` | `data` + `links.next/prev` + `meta.total/last_page` | Stable lists, page navigation |
| `simplePaginate()` | `data` + `links.next/prev` (no count) | Faster — no `COUNT(*)` query |
| `cursorPaginate()` | `data` + `next_cursor` / `prev_cursor` | Unbounded feeds, write-heavy lists |

`cursorPaginate` is the right default for activity feeds and unbounded lists — no expensive count, stable across writes.

## Rate Limiting

Define named limiters in `AppServiceProvider::boot()`:

```php
RateLimiter::for('api', function (Request $request) {
    return $request->user()
        ? Limit::perMinute(120)->by($request->user()->id)
        : Limit::perMinute(60)->by($request->ip());
});

RateLimiter::for('auth', fn (Request $request) =>
    Limit::perMinute(5)->by($request->ip())
);
```

Apply via `->middleware('throttle:api')`. Laravel surfaces `X-RateLimit-Limit`, `X-RateLimit-Remaining`, and `Retry-After` headers automatically.

## Error Response Shape

Two contracts to choose from — pick one and document it:

**Laravel default:**

```json
{
    "message": "The given data was invalid.",
    "errors": {
        "email": ["The email field is required."]
    }
}
```

**RFC 7807 problem+json:**

```json
{
    "type":   "https://errors.example.com/validation",
    "title":  "Validation failed",
    "status": 422,
    "detail": "The given data was invalid.",
    "errors": {
        "email": ["The email field is required."]
    }
}
```

If you choose problem+json, register a global exception renderer in `bootstrap/app.php`:

```php
->withExceptions(function (Exceptions $exceptions): void {
    $exceptions->render(function (ValidationException $e, Request $request) {
        return response()->json([
            'type'   => url('/errors/validation'),
            'title'  => 'Validation failed',
            'status' => 422,
            'detail' => $e->getMessage(),
            'errors' => $e->errors(),
        ], 422, ['Content-Type' => 'application/problem+json']);
    });
});
```

Mixing the two formats across endpoints causes painful client-side parsing — pick one at design time.

## Conditional Resources

Use `when()`, `whenLoaded()`, `mergeWhen()` to omit fields based on context:

```php
return [
    'id'        => $this->id,
    'email'     => $this->when($request->user()?->is($this->resource), $this->email),
    'is_admin'  => $this->mergeWhen($request->user()?->isAdmin(), [
        'last_login_at' => $this->last_login_at?->toIso8601String(),
        'failed_logins' => $this->failed_logins,
    ]),
];
```

Never expose admin-only fields unconditionally — token leakage of one user's response should not leak others' admin metadata.

## API Documentation (Scribe)

Scribe generates OpenAPI 3 + a styled HTML doc site from controller annotations + FormRequest rules:

```bash
composer require --dev knuckleswtf/scribe
php artisan scribe:generate
```

```php
class PostController extends Controller
{
    /**
     * List published posts.
     *
     * @group Posts
     * @authenticated
     * @queryParam search string Filter by title substring. Example: laravel
     * @queryParam sort string Sort order: latest|oldest. Example: latest
     * @responseFile responses/posts.index.200.json
     */
    public function index(): ResourceCollection
    {
        // ...
    }
}
```

Scribe runs in CI to detect drift; commit the generated docs to a `docs/api/` directory and reference them from the README.

## Dos

- Always serialize via `JsonResource` / `ResourceCollection` — never `Model::all()->toJson()`
- Use `cursorPaginate()` for unbounded feeds, `paginate()` for stable lists with known size, `simplePaginate()` to skip the count query
- Apply named rate limiters per route group; surface `X-RateLimit-*` headers
- Pick one error response shape (Laravel default or problem+json) and document it in the API spec
- Use `whenLoaded(...)` in resources to gracefully omit unloaded relationships (prevents serializer N+1)

## Don'ts

- Don't return paginated collections with `paginate()` on unbounded sets — the count query becomes the bottleneck; switch to `cursorPaginate()`
- Don't share controllers between API versions — breaking changes silently leak from v1 to v2
- Don't expose conditional fields unconditionally (`$this->email` for non-owner) — gate via `when(...)` based on the authenticated user
- Don't generate Sanctum tokens with `*` ability scope when your API surface has scoped permissions — pass an explicit ability list to `createToken($name, [$abilities])` and check via `tokenCan('post:write')`
- Don't bypass FormRequest validation in API controllers because the input is JSON — `$request->validate(...)` works but loses the reusable rules + `authorize()` integration
