# Svelte Documentation Conventions

> Support tier: community

> Extends `modules/documentation/conventions.md` with Svelte 5-specific patterns.
> Note: Svelte (standalone SPAs) is distinct from SvelteKit (SSR/routing layer).

## Code Documentation

- Use TSDoc (`/** */`) for all exported utility functions, stores, and module-level APIs.
- Components: document non-obvious `$props()` rune usage with inline TSDoc comments. The prop type interface IS the component's API documentation.
- `$state` and `$derived` runes: document complex derivations — `$derived` expressions that are not immediately readable.
- Event handlers passed as props: document the event payload type in the prop interface.
- Shared stores (`svelte/store`): document the store type, initial value, and update semantics.

```typescript
// In the component's <script lang="ts">:

interface Props {
  /** ID of the session to display. Must be a valid UUID. */
  sessionId: string;
  /** Called when the user marks the session complete. */
  onComplete?: (id: string) => void;
}

let { sessionId, onComplete }: Props = $props();
```

## Architecture Documentation

- Svelte 5 SPAs: document the routing strategy (client-side router used, e.g., `svelte-routing`, `@melt-ui/svelte`).
- Document the shared store architecture: which stores exist, what state they hold, and the component tree that reads/writes them.
- Document the build configuration: Vite config, environment variables, and output targets.
- Document the design token / theming approach: CSS custom properties, Tailwind config, or component-level styles.

## Diagram Guidance

- **Component tree:** Mermaid class diagram for complex feature areas with 5+ components.
- **Store data flow:** Sequence diagram for stores with complex reactive update chains.

## Dos

- Document the `$props()` interface for all reusable components — it is the public API
- Document `$effect` side effects that have non-obvious cleanup requirements
- Keep store documentation updated as `$state` reactive roots change shape

## Don'ts

- Don't document Svelte 4 reactive statement patterns (`$:`) — project uses Svelte 5 runes
- Don't skip prop interface documentation for components exported from a shared component library
