# React Documentation Conventions

> Support tier: community

> Extends `modules/documentation/conventions.md` with React-specific patterns.

## Code Documentation

- Use TSDoc for all exported components, hooks, and utility functions.
- Every exported component must have a TSDoc block with: summary line, `@param props` describing the props interface, and `@example` showing minimal usage.
- Props interfaces: document non-obvious props with inline JSDoc. Required vs optional is inferred from TypeScript — don't restate it.
- Custom hooks: document the return value shape and any side effects (network calls, subscriptions).

```tsx
/**
 * Displays a user profile card with avatar and contact info.
 *
 * @param props - See {@link UserCardProps}
 * @example
 * <UserCard userId="abc123" onEdit={() => navigate('/profile')} />
 */
export function UserCard({ userId, onEdit }: UserCardProps) { ... }

interface UserCardProps {
  userId: string;
  /** Called when the user clicks the edit button. */
  onEdit?: () => void;
}
```

## Architecture Documentation

- Document the component tree structure for complex feature areas — use a Mermaid class or component diagram.
- State management: document which slices/stores exist, what data they hold, and which components subscribe.
- Server data: document TanStack Query / SWR query keys and their invalidation relationships.
- Error Boundary placement: document which routes have Error Boundaries and what fallback UI they render.
- Theme and design tokens: reference the token system in the architecture doc. Do not document individual token values — link to the design system.

## Diagram Guidance

- **Component tree:** Mermaid class diagram showing parent-child relationships for feature areas with 5+ components.
- **Data flow:** Sequence diagram for complex async flows (optimistic updates, multi-step forms).
- **Route map:** Mermaid flowchart for apps with 10+ routes.

## Dos

- TSDoc `@example` for every exported component
- Document hook return shapes — they are the public API
- Link to Storybook stories from component TSDoc when stories exist

## Don'ts

- Don't document internal implementation components (prefixed `_` or not exported)
- Don't duplicate prop descriptions between the interface and the component JSDoc — pick one location
- Don't document CSS class names — document behavior and visual intent instead
