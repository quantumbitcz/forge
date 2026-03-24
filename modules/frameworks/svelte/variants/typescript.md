# Svelte 5 + TypeScript Variant

> TypeScript-specific patterns for standalone Svelte 5 projects. Extends `modules/languages/typescript.md` and `modules/frameworks/svelte/conventions.md`.

## Component Props Typing

Always use `lang="ts"` in script blocks. Type props inline in the `$props()` destructuring or extract to a named interface.

```svelte
<script lang="ts">
  interface ButtonProps {
    label: string;
    variant?: 'primary' | 'secondary' | 'ghost';
    disabled?: boolean;
    onclick?: () => void;
    class?: string;
  }

  let {
    label,
    variant = 'primary',
    disabled = false,
    onclick,
    class: className = '',
  }: ButtonProps = $props();
</script>

<button
  class="{variant} {className}"
  {disabled}
  {onclick}
>
  {label}
</button>
```

## Snippet Props Typing

Use the `Snippet` type from `svelte` for typed snippet (formerly slot) props:

```svelte
<script lang="ts">
  import type { Snippet } from 'svelte';

  interface CardProps {
    title: string;
    children: Snippet;
    footer?: Snippet<[{ close: () => void }]>;
  }

  let { title, children, footer }: CardProps = $props();
</script>
```

## Bindable Props Typing

```svelte
<script lang="ts">
  let { value = $bindable('') }: { value?: string } = $props();
</script>
```

## Store Typing (`.svelte.ts`)

Export store objects with explicit return types:

```typescript
// src/stores/counter.svelte.ts
interface CounterStore {
  readonly count: number;
  increment(): void;
  decrement(): void;
  reset(): void;
}

let _count = $state(0);

export const counterStore: CounterStore = {
  get count() { return _count; },
  increment() { _count++; },
  decrement() { _count--; },
  reset() { _count = 0; },
};
```

## Typed $state with Explicit Generics

Use explicit generic when TypeScript inference is insufficient:

```typescript
// Explicit generic when initial value is null/undefined
let user = $state<User | null>(null);
let items = $state<Item[]>([]);
```

## Discriminated Unions for Async State

```typescript
type AsyncState<T> =
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'success'; data: T }
  | { status: 'error'; error: Error };

let userState = $state<AsyncState<User>>({ status: 'idle' });
```

## Event Handler Typing

Callback props typed as function signatures in `$props()`:

```svelte
<script lang="ts">
  let {
    onSelect,
    onChange,
    onSubmit,
  }: {
    onSelect: (item: Item) => void;
    onChange: (value: string) => void;
    onSubmit: (event: SubmitEvent) => Promise<void>;
  } = $props();
</script>
```

## Svelte HTML Element Typing

```svelte
<script lang="ts">
  let inputEl = $state<HTMLInputElement | null>(null);

  $effect(() => {
    if (inputEl) {
      inputEl.focus();
      return () => { /* cleanup */ };
    }
  });
</script>

<input bind:this={inputEl} />
```

## Service Typing

```typescript
// src/services/user.service.ts
import type { User } from '../types/user.ts';
import { apiFetch } from '../api/client.ts';

export async function fetchUser(id: string): Promise<User> {
  return apiFetch<User>(`/users/${id}`);
}

export async function updateUser(id: string, patch: Partial<Omit<User, 'id'>>): Promise<User> {
  return apiFetch<User>(`/users/${id}`, {
    method: 'PATCH',
    body: JSON.stringify(patch),
  });
}
```

## Strict Mode

- `strict: true` in `tsconfig.json` — no exceptions
- No `any` types — use `unknown` and narrow with type guards
- No `as` assertions except narrowing from `unknown`
- TSDoc on all exported functions, types, components (what + why, not how)
- `svelte-check` must pass cleanly as part of the lint step

## tsconfig.json Baseline

```json
{
  "extends": "@tsconfig/svelte/tsconfig.json",
  "compilerOptions": {
    "strict": true,
    "moduleResolution": "bundler",
    "target": "ESNext",
    "module": "ESNext",
    "verbatimModuleSyntax": true
  }
}
```
