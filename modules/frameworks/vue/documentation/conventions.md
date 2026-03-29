# Vue Documentation Conventions

> Extends `modules/documentation/conventions.md` with Vue 3-specific patterns.

## Code Documentation

- Use TSDoc (`/** */`) for all composables, utility functions, and Pinia store definitions.
- Components (`<script setup>`): document non-obvious `defineProps` entries with TSDoc inline comments. Use `defineEmits` with typed signatures — the type IS the documentation.
- Composables: document the return shape, side effects, and any required setup/teardown (lifecycle hooks, watchers).
- Pinia stores: document the state shape, each action's mutation contract, and any getters with non-obvious derivation logic.
- Nuxt composables (`useFetch`, `useAsyncData`): document the key, what data is fetched, and the refresh strategy.

```typescript
// composables/useAthleteSession.ts

/**
 * Manages the currently active coaching session for an athlete.
 *
 * Fetches session data on mount and sets up a polling interval for live updates.
 * Call `stopPolling()` in onUnmounted if the component does not handle it automatically.
 *
 * @param athleteId - The athlete whose session to track.
 * @returns `{ session, isLoading, error, stopPolling }`
 */
export function useAthleteSession(athleteId: Ref<string>) { ... }
```

## Architecture Documentation

- Document the Pinia store layout: which stores exist, what domain state they own, and which pages/components use them.
- Document the `useFetch`/`useAsyncData` key taxonomy — keys are cache identifiers and must be documented for correct invalidation.
- Nuxt: document the auto-import conventions — what is auto-imported from `composables/`, `utils/`, and `components/`.
- Document the plugin registration in `plugins/` and what each plugin provides to the app instance.
- Document Vue Router route guards: which routes have guards, what they check, and redirect targets.

## Diagram Guidance

- **Store dependency graph:** Mermaid class diagram showing Pinia stores and the pages/components that consume them.
- **Nuxt route tree:** Mermaid flowchart for file-based routing structure with 10+ routes.

## Dos

- TSDoc return shapes on all composables — they are the primary reusable API
- Document `useFetch` key naming conventions — consistent keys prevent cache collisions
- Keep Pinia store action docs updated when mutation logic changes

## Don'ts

- Don't document Vue 2 Options API patterns — project uses Composition API + `<script setup>`
- Don't skip `defineEmits` type signatures — untyped emits are undocumented API surface
