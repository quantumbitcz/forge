# Laravel + Inertia.js Variant

> Inertia 1.x + Laravel 11 with Vue 3 or React 18 frontend. Extends
> `modules/frameworks/laravel/conventions.md`. Use this variant for SPA-like apps that keep
> Laravel's routing and controllers as the source of truth — Inertia replaces Blade with
> client-side rendering, but server actions remain conventional Laravel.

## Architecture

```
app/
  Http/Controllers/PostController.php       # returns Inertia::render(...)
  Http/Middleware/HandleInertiaRequests.php # shares persistent props
resources/
  js/
    Pages/Posts/Index.vue                   # one component per route
    Pages/Posts/Show.vue
    Layouts/AppLayout.vue
    app.js                                  # createInertiaApp()
routes/web.php                              # standard Laravel routes
```

Inertia's contract: every controller returns an `Inertia::render('Page/Name', $props)` instead of a view. The first request renders the full HTML; subsequent navigations swap the page component via XHR with `X-Inertia: true` headers.

## Controller Pattern

```php
namespace App\Http\Controllers;

use App\Http\Resources\PostResource;
use App\Models\Post;
use Inertia\Inertia;
use Inertia\Response;

class PostController extends Controller
{
    public function index(): Response
    {
        return Inertia::render('Posts/Index', [
            'posts'   => PostResource::collection(
                Post::query()->with('author:id,name')->latest()->paginate(20)
            ),
            'filters' => request()->only(['search', 'sort']),
        ]);
    }

    public function show(Post $post): Response
    {
        return Inertia::render('Posts/Show', [
            'post' => new PostResource($post->load('author', 'tags')),
        ]);
    }
}
```

The Vue/React component receives `posts` and `filters` as props.

## Shared Data via Middleware

Persistent props (auth user, flash messages, CSRF token) live in `HandleInertiaRequests::share()`:

```php
public function share(Request $request): array
{
    return array_merge(parent::share($request), [
        'auth' => [
            'user' => fn () => $request->user()
                ? UserResource::make($request->user()->only('id', 'name', 'email'))
                : null,
        ],
        'flash' => [
            'success' => fn () => $request->session()->get('success'),
            'error'   => fn () => $request->session()->get('error'),
        ],
        'ziggy' => fn () => array_merge((new Ziggy)->toArray(), [
            'location' => $request->url(),
        ]),
    ]);
}
```

Wrap shared props in closures (`fn () => ...`) so they're evaluated lazily — only computed when the page actually accesses them.

Register the middleware in Laravel 11 inside `bootstrap/app.php`:

```php
->withMiddleware(function (Middleware $middleware): void {
    $middleware->web(append: [HandleInertiaRequests::class]);
})
```

## Partial Reloads (`only` / `except`)

Server-side: declare top-level props normally. Client-side: request a partial reload to fetch only changed props:

```js
// Vue example
import { router } from '@inertiajs/vue3'

router.reload({ only: ['posts'] })           // re-fetch posts prop only
router.reload({ except: ['ziggy', 'auth'] }) // skip persistent props
```

Server controller is unchanged — Inertia tracks the `X-Inertia-Partial-Data` header and skips evaluating closures for omitted props.

## Lazy Props

Heavy props (counts, aggregates) can defer until requested:

```php
return Inertia::render('Dashboard', [
    'stats' => Inertia::lazy(fn () => app(StatsService::class)->compute()),
]);
```

The `stats` prop is null on first render; client requests it via partial reload when needed:

```js
router.reload({ only: ['stats'] })
```

## Form Helper

Inertia's form helper handles validation errors, CSRF, and pending state:

```vue
<script setup>
import { useForm } from '@inertiajs/vue3'

const form = useForm({
    title: '',
    body:  '',
})

function submit() {
    form.post(route('posts.store'), {
        preserveScroll: true,
        onSuccess: () => form.reset(),
    })
}
</script>

<template>
    <form @submit.prevent="submit">
        <input v-model="form.title" />
        <span v-if="form.errors.title">{{ form.errors.title }}</span>

        <textarea v-model="form.body"></textarea>
        <span v-if="form.errors.body">{{ form.errors.body }}</span>

        <button :disabled="form.processing">Save</button>
    </form>
</template>
```

Server-side returns standard Laravel validation errors via `FormRequest`. Inertia automatically deserializes `422` responses into `form.errors`.

## SSR Considerations

Inertia supports SSR via a Node sidecar (`@inertiajs/vue3` / `@inertiajs/react`):

```bash
php artisan inertia:start-ssr
```

SSR caveats:

- Window/document references inside `setup()` / `useEffect` break SSR — guard with `import.meta.env.SSR`
- Flash session data via `share()` is unavailable during SSR boot — design components to render gracefully without flash
- Build the SSR bundle in CI: `vite build --ssr` produces `bootstrap/ssr/ssr.js`
- Run SSR in production via `node bootstrap/ssr/ssr.js` behind a process supervisor (Supervisor / systemd / PM2)

For most apps SSR is optional — Inertia's first-request HTML is already server-rendered Blade. SSR is needed only when the first paint must be fully styled / SEO-critical content must appear without JS.

## Validation Error Propagation

`FormRequest` validation throws `ValidationException` → Inertia translates `422` → Vue/React component receives `form.errors`:

```php
class StorePostRequest extends FormRequest
{
    public function rules(): array
    {
        return ['title' => 'required|max:120'];
    }
}
```

The Inertia frontend never needs to know HTTP status codes — `form.errors.title` is populated automatically when the request fails.

## CSRF with Axios

Inertia uses Axios under the hood. Axios reads the `XSRF-TOKEN` cookie that Laravel sets and submits it as `X-XSRF-TOKEN`. **Do not exempt Inertia routes from CSRF** — they're session-cookie-authenticated and need the token.

If you build a custom Axios call outside of Inertia (e.g. for autocomplete), make sure to use the same Axios instance so it inherits the CSRF setup:

```js
import axios from 'axios'
window.axios = axios
window.axios.defaults.headers.common['X-Requested-With'] = 'XMLHttpRequest'
```

## Ziggy and `route()` Helper

`Ziggy` exports Laravel's named routes to JavaScript. Install via `composer require tightenco/ziggy`.

```js
import { route } from 'ziggy-js'
import { Ziggy } from './ziggy.js'

route('posts.show', { post: 42 })       // → '/posts/42'
```

Share Ziggy in `HandleInertiaRequests::share()` (see "Shared Data via Middleware" above) so `route(...)` is identical on the server (`route()` PHP helper) and the client.

## Dos

- Use `Inertia::render('Page/Name', $props)` — every controller returns a Page, never a Blade view (except the root SPA layout)
- Wrap shared props in closures (`fn () => ...`) so unused props don't run their resolvers
- Use the `useForm` helper for forms — it handles CSRF, validation errors, and pending state
- Use `Inertia::lazy(fn () => ...)` for expensive props that aren't always needed; client requests them with `router.reload({ only: [...] })`
- Use Ziggy + `route('name', ...)` on the client — never hardcode URL strings
- Keep validation in `FormRequest` classes; Inertia automatically deserializes 422 responses into `form.errors`

## Don'ts

- Don't `csrf` exempt Inertia routes — they use session cookies, CSRF protection is required
- Don't return raw `view(...)` from Inertia-served controllers — Inertia expects `Inertia::render(...)` or it falls back to a full page reload
- Don't put expensive computations directly in shared props — wrap in closures so unused pages don't pay the cost
- Don't reference `window` / `document` inside SSR-rendered code without guarding with `import.meta.env.SSR`
- Don't forget to run `php artisan inertia:start-ssr` in production if SSR is enabled — without it, the SSR endpoint returns 503 and Inertia falls back to client-side rendering with a noticeable hydration flash
