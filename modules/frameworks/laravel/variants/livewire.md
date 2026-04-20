# Laravel + Livewire Variant

> Livewire 3.x + Laravel 11. Extends `modules/frameworks/laravel/conventions.md`.
> Use this variant for server-rendered, dynamic UIs without leaving PHP — great for admin dashboards,
> internal tools, and forms with cross-field validation. Choose Inertia (`variants/inertia.md`) when
> the team wants a full SPA in Vue/React.

## Component Anatomy

```php
namespace App\Livewire\Posts;

use App\Models\Post;
use Livewire\Attributes\Computed;
use Livewire\Attributes\Validate;
use Livewire\Component;
use Livewire\WithPagination;

class PostList extends Component
{
    use WithPagination;

    #[Validate('string|max:120')]
    public string $search = '';

    public string $sort = 'latest';

    public function mount(string $initialSort = 'latest'): void
    {
        $this->sort = $initialSort;
    }

    public function updatedSearch(): void
    {
        $this->resetPage();           // pagination resets when filters change
    }

    #[Computed]
    public function posts()
    {
        return Post::query()
            ->where('title', 'like', "%{$this->search}%")
            ->when($this->sort === 'latest', fn ($q) => $q->latest())
            ->paginate(20);
    }

    public function delete(Post $post): void
    {
        $this->authorize('delete', $post);
        $post->delete();
        $this->dispatch('post-deleted');
    }

    public function render()
    {
        return view('livewire.posts.post-list');
    }
}
```

```blade
{{-- resources/views/livewire/posts/post-list.blade.php --}}
<div>
    <input type="text" wire:model.live.debounce.300ms="search" placeholder="Search posts" />

    @foreach ($this->posts as $post)
        <article wire:key="post-{{ $post->id }}">
            <h2>{{ $post->title }}</h2>
            <button wire:click="delete({{ $post->id }})" wire:confirm="Delete this post?">
                Delete
            </button>
        </article>
    @endforeach

    {{ $this->posts->links() }}
</div>
```

## Lifecycle Hooks

| Hook | When | Use |
|---|---|---|
| `mount(...)` | First render only | Read route parameters, set initial state |
| `hydrate()` / `hydrateProperty()` | Every subsequent request before action | Re-resolve non-serializable state (rare) |
| `updating($key, $value)` / `updated($key, $value)` | Before/after a property changes | Validation triggers, side effects |
| `updatingFoo($value)` / `updatedFoo($value)` | Per-property variant | Reset pagination when a filter changes |
| `dehydrate()` | Before sending HTML to browser | Cleanup, snapshot trimming |
| `render()` | Every render | Build the view (no side effects) |

`mount` runs only once. State accumulates across requests via the snapshot — keep it minimal.

## `wire:model.live` vs `wire:model.lazy` vs `wire:model.blur`

| Modifier | When the server is contacted | Use case |
|---|---|---|
| `wire:model` (default) | Only on action / submit | Most form fields |
| `wire:model.live` | Every keystroke | Search-as-you-type, live validation |
| `wire:model.lazy` (legacy 2.x naming) | On `change` event | Single-value selects, blur-to-validate |
| `wire:model.live.debounce.500ms` | Debounced live | Search inputs (essential — without debounce you DDoS yourself) |
| `wire:model.blur` | When the field loses focus | Login email, post-validation friendlier than .live |

**Always debounce `.live` on text inputs** — every keystroke is a server round-trip otherwise. 300-500ms is a sane default.

## Computed Properties

`#[Computed]` properties memoize within a single request. Call as `$this->posts` (not `$this->posts()`):

```php
#[Computed]
public function posts()
{
    return Post::with('author')->paginate();
}
```

Use `#[Computed(persist: true, seconds: 60)]` for per-component cross-request caching (Livewire 3.1+).

## Full-Page Components

Register a Livewire component as a route directly:

```php
// routes/web.php
use App\Livewire\Posts\PostList;

Route::get('/posts', PostList::class)->name('posts.index');
```

The component's view is wrapped in `resources/views/components/layouts/app.blade.php` by default. Override with the `#[Layout('layouts.dashboard')]` attribute on the component class.

## Nested Components and `wire:key`

```blade
@foreach ($posts as $post)
    <livewire:posts.row :post="$post" :key="'row-' . $post->id" />
@endforeach
```

**`wire:key` (or `:key=` on `<livewire:...>`) is mandatory inside loops.** Without it, Livewire's morph algorithm misidentifies child components when the list reorders, leading to wrong-state bugs that look like data corruption.

## Alpine.js Interop

Livewire bundles Alpine. Use Alpine for purely client-side interactions (dropdowns, modals open/close, focus trap):

```blade
<div x-data="{ open: false }">
    <button @click="open = ! open">Toggle</button>
    <div x-show="open">...</div>
</div>
```

Bridge to Livewire via `$wire`:

```blade
<button @click="$wire.delete({{ $post->id }})">Delete</button>
```

`$wire.delete(...)` triggers the Livewire action without a full re-render; ideal for fire-and-forget actions tied to client state.

## Validation In-Component

Two patterns:

**Real-time via `#[Validate]` attribute:**

```php
#[Validate('required|email|unique:users,email')]
public string $email = '';

public function save(): void
{
    $this->validate();           // throws ValidationException → renders error bag
    User::create(['email' => $this->email]);
}
```

**Form objects** (Livewire 3.x — extracts validation + state from the component):

```php
namespace App\Livewire\Forms;

use Livewire\Attributes\Validate;
use Livewire\Form;

class CreateUserForm extends Form
{
    #[Validate('required|string|max:120')]
    public string $name = '';

    #[Validate('required|email')]
    public string $email = '';

    public function store(): void
    {
        $this->validate();
        \App\Models\User::create($this->all());
    }
}
```

```php
class CreateUser extends Component
{
    public CreateUserForm $form;

    public function save(): void
    {
        $this->form->store();
        $this->reset('form');
    }
}
```

Form objects keep the component class small and make the form portable across components.

## Lazy Loading

```blade
<livewire:dashboard.stats lazy />
```

The component renders a placeholder on first paint, then loads its real content via a follow-up request. Use for heavy components on otherwise fast pages.

```php
class Stats extends Component
{
    public function placeholder(): string
    {
        return <<<'HTML'
            <div class="animate-pulse">Loading dashboard…</div>
        HTML;
    }
}
```

## File Uploads

```php
use Livewire\WithFileUploads;
use Illuminate\Http\UploadedFile;

class AvatarUpload extends Component
{
    use WithFileUploads;

    #[Validate('image|max:1024')]   // 1 MB
    public ?UploadedFile $avatar = null;

    public function save(): void
    {
        $this->validate();
        $path = $this->avatar->store('avatars', 'public');
        auth()->user()->update(['avatar_path' => $path]);
    }
}
```

The temporary upload lives in `livewire-tmp/`. Configure cleanup retention in `config/livewire.php` (`temporary_file_upload.max_lifetime`).

## Testing Components

```php
use Livewire\Livewire;

it('filters posts by search term', function () {
    Post::factory()->create(['title' => 'Hello world']);
    Post::factory()->create(['title' => 'Other']);

    Livewire::test(PostList::class)
        ->set('search', 'Hello')
        ->assertSee('Hello world')
        ->assertDontSee('Other');
});

it('requires authorization to delete', function () {
    $post = Post::factory()->create();

    Livewire::actingAs(User::factory()->create())
        ->test(PostList::class)
        ->call('delete', $post)
        ->assertForbidden();
});
```

Always test through `Livewire::test(...)` — never invoke component methods directly.

## Dos

- Always declare `wire:key` on every direct child inside a loop — without it, morph errors look like data bugs
- Debounce `wire:model.live` on text inputs (`.live.debounce.300ms` minimum)
- Use `#[Computed]` properties for derived data instead of recomputing inside `render()`
- Authorize state-changing actions inside the action method via `$this->authorize(...)` — never trust `wire:click` to be safe
- Test components through `Livewire::test(...)`, including authorization assertions (`assertForbidden`)

## Don'ts

- Don't store large objects (collections of >100 rows, file blobs) on public component properties — they snapshot on every request
- Don't make HTTP requests inside `render()` — it runs every roundtrip; cache via `#[Computed]` or move to `mount()`
- Don't put `wire:click` on a destructive action without `wire:confirm="..."` — Livewire ships a built-in confirmation prompt
- Don't bypass Livewire actions by mutating state from Alpine (`$wire.foo = bar` and then calling `$wire.save()`) without re-validating server-side
- Don't forget `wire:loading` indicators on long actions — users assume the click "didn't work" without visible feedback
