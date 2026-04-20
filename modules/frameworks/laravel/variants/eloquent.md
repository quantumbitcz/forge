# Laravel + Eloquent Variant

> ORM-centric Laravel projects. Extends `modules/frameworks/laravel/conventions.md`.
> This is the **default** variant for new Laravel projects in this plugin — the eloquent stack
> (models + relationships + scopes + observers + factories + resources) is the canonical Laravel
> persistence layer.

## Model Layout

```
app/Models/
  Concerns/                # Reusable traits — HasUuid, Sluggable, Auditable
  Casts/                   # Custom Casts (encrypted JSON, enum sets)
  Scopes/                  # Global scopes (TenantScope, ActiveScope)
  User.php
  Post.php
  Comment.php
```

```php
namespace App\Models;

use App\Enums\PostStatus;
use Illuminate\Database\Eloquent\Casts\Attribute;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\SoftDeletes;

class Post extends Model
{
    use HasFactory, SoftDeletes;

    protected $fillable = ['title', 'slug', 'body', 'status', 'published_at'];

    protected $casts = [
        'status'       => PostStatus::class,
        'published_at' => 'datetime',
        'meta'         => 'array',
    ];

    protected $with = ['author:id,name'];   // implicit eager load — use sparingly

    public function author(): BelongsTo
    {
        return $this->belongsTo(User::class, 'author_id');
    }

    public function tags(): BelongsToMany
    {
        return $this->belongsToMany(Tag::class)->withTimestamps();
    }

    /** Local scope: Post::published()->latest()->paginate() */
    public function scopePublished($query)
    {
        return $query->where('status', PostStatus::Published)
                     ->whereNotNull('published_at');
    }

    /** Accessor (Laravel 9+ Attribute API) */
    protected function excerpt(): Attribute
    {
        return Attribute::make(
            get: fn () => str(strip_tags($this->body))->limit(160)->toString(),
        );
    }
}
```

## Local vs Global Scopes

**Local scopes** (`scopeXxx`) are opt-in per query — preferred for query reuse:

```php
Post::published()->forAuthor($userId)->latest()->paginate();
```

**Global scopes** apply to every query against the model. Use sparingly — they cause invisible filtering that surprises maintainers.

```php
class TenantScope implements Scope
{
    public function apply(Builder $builder, Model $model): void
    {
        if ($tenantId = app(TenantContext::class)->id()) {
            $builder->where('tenant_id', $tenantId);
        }
    }
}

class Post extends Model
{
    protected static function booted(): void
    {
        static::addGlobalScope(new TenantScope());
    }
}
```

Always document global scopes in the model docblock — and provide an explicit `withoutGlobalScope(...)` escape hatch for system-level queries (admin reports, data export).

## Accessors and Mutators (Attribute API)

Use `Attribute::make(get: ..., set: ...)` (Laravel 9+) — the legacy `getXxxAttribute` / `setXxxAttribute` methods are deprecated:

```php
protected function fullName(): Attribute
{
    return Attribute::make(
        get: fn ($value, array $attributes) => trim($attributes['first_name'] . ' ' . $attributes['last_name']),
    )->shouldCache();              // memoize per request
}

protected function email(): Attribute
{
    return Attribute::make(
        get: fn ($value) => $value,
        set: fn ($value) => strtolower(trim($value)),
    );
}
```

`shouldCache()` memoizes computed accessors per model instance — invaluable for expensive derivations.

## Casts

Casts are the only place to declare typed attributes. Common cases:

```php
protected $casts = [
    'is_active'    => 'boolean',
    'settings'     => 'array',
    'metadata'     => AsCollection::class,         // Collection wrapper
    'role'         => RoleEnum::class,             // Enum cast (Laravel 9+)
    'published_at' => 'datetime',
    'price_cents'  => 'integer',
    'address'      => AsArrayObject::class,        // mutable nested data
    'token'        => 'encrypted',                 // app key encryption
    'profile'      => AsEncryptedArrayObject::class,
];
```

Custom casts implement `CastsAttributes`:

```php
class Money implements CastsAttributes
{
    public function get($model, string $key, $value, array $attributes): MoneyValueObject
    {
        return new MoneyValueObject(cents: (int) $value, currency: $attributes['currency']);
    }
    public function set($model, string $key, $value, array $attributes): array
    {
        return ['price_cents' => $value->cents, 'currency' => $value->currency];
    }
}
```

## Relationships

| Relationship | Direction | Example |
|---|---|---|
| `hasOne` | one-to-one (parent) | `User::profile()` |
| `belongsTo` | inverse (child) | `Post::author()` |
| `hasMany` | one-to-many (parent) | `User::posts()` |
| `belongsToMany` | many-to-many (pivot) | `Post::tags()` with `withPivot([...])` |
| `hasManyThrough` | one-to-many through intermediate | `Country::posts()` (User between) |
| `morphTo` / `morphMany` | polymorphic | `Comment::commentable()` |
| `morphToMany` / `morphedByMany` | polymorphic many-to-many | `Tag::posts()`, `Tag::videos()` |

Always type-hint the return: `public function tags(): BelongsToMany`. The IDE and PHPStan need it.

For polymorphic types, register a morph map in `AppServiceProvider::boot()` so the database stores stable aliases instead of fully-qualified class names:

```php
Relation::enforceMorphMap([
    'post'  => Post::class,
    'video' => Video::class,
]);
```

Without the morph map, refactoring namespaces breaks every existing polymorphic row.

## Eager Loading and N+1

```php
// BAD — N+1
foreach (Post::all() as $post) {
    echo $post->author->name;
}

// GOOD
$posts = Post::with('author')->get();

// BETTER — limit columns
$posts = Post::with('author:id,name')->get();

// BEST for production — assert no lazy loads
Model::preventLazyLoading(! app()->isProduction());
```

`Model::preventLazyLoading(true)` throws `LazyLoadingViolationException` whenever a relationship is accessed without being eager-loaded. Enable in `AppServiceProvider::boot()` for non-prod environments to catch N+1 in development and CI.

For relationships used in 100% of cases, declare on the model:

```php
protected $with = ['author:id,name'];
```

Use this *sparingly* — it loads the relation on every read, including writes-then-read flows where it's not needed.

## `withCount` and `loadCount`

Aggregate without loading the relation rows:

```php
$users = User::withCount('posts')->get();
foreach ($users as $user) {
    echo "{$user->name} has {$user->posts_count} posts";   // single query
}
```

`loadCount` runs after the parent is loaded:

```php
$user = User::find(1);
$user->loadCount(['posts', 'comments']);
```

## Chunking vs Cursor

For large reads, never `->all()` / `->get()` directly:

```php
// chunk() — paginates internally, fetches N rows per round trip
Post::where('status', 'pending')->chunk(1000, function ($posts) {
    foreach ($posts as $post) { ... }
});

// chunkById() — uses id > last_id; safer when concurrent writes are happening
Post::where('status', 'pending')->chunkById(1000, function ($posts) { ... });

// lazy() — yields one row at a time via a cursor (memory-tight)
foreach (Post::where('status', 'pending')->lazy(1000) as $post) {
    // ...
}
```

`chunk()` and `chunkById()` differ on offset behavior — prefer `chunkById()` when the source set may be modified concurrently (otherwise `chunk()` skips rows when earlier pages have been deleted).

## Model Events and Observers

Prefer **observers** over inline `static::created(fn ($model) => ...)` closures inside the model. Observers are testable and discoverable:

```bash
php artisan make:observer UserObserver --model=User
```

```php
class UserObserver
{
    public function creating(User $user): void
    {
        $user->slug ??= str($user->name)->slug()->toString();
    }

    public function created(User $user): void
    {
        Mail::to($user)->queue(new WelcomeMail($user));
    }
}
```

Register in `AppServiceProvider::boot()`:

```php
public function boot(): void
{
    User::observe(UserObserver::class);
}
```

**Discipline:** Observers fire for `Model::create`, `Model::update`, etc. They DO NOT fire for `DB::table('users')->insert(...)`, `Model::query()->update(...)`, or bulk inserts. Document this constraint and use the model API consistently for any operation that needs the lifecycle hooks.

## Dos

- Declare `$fillable` on every model — never `$guarded = []` in this variant
- Type-hint every relationship return: `BelongsTo`, `HasMany`, `MorphTo`, etc.
- Use `Attribute::make(get: ..., set: ...)` for accessors/mutators — not the legacy `getXxxAttribute`
- Cast typed columns explicitly (`enum`, `array`, `datetime`, `boolean`, `encrypted`)
- Use observers for lifecycle hooks; register in `AppServiceProvider::boot()` — not closures inside the model
- Eager-load at the query site (`->with([...])`) and enable `Model::preventLazyLoading()` in non-prod
- Use `withCount()` / `loadCount()` for relationship counts — never `$model->posts->count()` in a loop

## Don'ts

- Don't access relationships inside Blade / Resource loops without eager loading — N+1 silently in production
- Don't put global scopes on user-facing models without documenting them in the model docblock — invisible filtering surprises maintainers
- Don't use `Model::query()->update(...)` / `DB::table(...)::insert(...)` when you need observers to fire — they bypass the model lifecycle
- Don't rely on `$with` for eager loading — declare per-query with `->with([...])` so writes don't pay the read cost
- Don't store fully qualified class names in polymorphic `*_type` columns without `Relation::enforceMorphMap([...])` — refactoring namespaces will break every row
- Don't override `getKeyName()` / `getRouteKeyName()` ad-hoc per route — declare it once on the model so route model binding stays consistent
- Don't use `Model::all()` / `->get()` on unbounded sets — chunk via `->chunkById(1000, ...)` or `->lazy(1000)`
