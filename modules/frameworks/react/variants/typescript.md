# React + TypeScript Variant

> TypeScript-specific patterns for React projects. Extends `modules/languages/typescript.md` and `modules/frameworks/react/conventions.md`.

## Component Typing

- Prefer plain function components over `React.FC` -- it adds implicit `children` typing
- Type props inline or with a named interface (prefer interface for exported components)
- Use `React.ReactNode` for children prop type, `React.ReactElement` when narrower type needed

```tsx
interface UserCardProps {
  user: User;
  onSelect: (id: string) => void;
  className?: string;
}

function UserCard({ user, onSelect, className }: UserCardProps) {
  return <div className={className}>...</div>;
}
```

## Hook Typing

- Type custom hook return values explicitly when not obvious from inference
- Use tuple return `[value, setValue]` for hooks mimicking `useState` pattern
- Generic hooks: `function useFetch<T>(url: string): { data: T | null; ... }`

## Event Handlers

- Use `React.ChangeEvent<HTMLInputElement>` for input handlers
- Use `React.FormEvent<HTMLFormElement>` for form submit
- Use `React.MouseEvent<HTMLButtonElement>` for click handlers
- Prefer named handler functions over inline arrows for complex logic

## Ref Typing

- `useRef<HTMLDivElement>(null)` -- always specify element type
- `useRef<number | null>(null)` for mutable refs not attached to DOM

## Context Typing

- Type context value with interface, provide default or use `null` + non-null assertion hook
- Create a typed `useMyContext()` hook that throws if used outside provider

## Discriminated Unions for State

```tsx
type AsyncState<T> =
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'success'; data: T }
  | { status: 'error'; error: Error };
```

## Strict Mode

- `strict: true` in tsconfig -- no exceptions
- No `any` type -- use `unknown` and narrow with type guards
- No `as` type assertions unless narrowing from `unknown`
- TSDoc on all exported functions, types, components (what + why, not how)

## Generic Components

Use generic components for lists, tables, selects -- constrain with `extends`:

```typescript
interface ListProps<T extends { id: string }> {
  items: T[];
  renderItem: (item: T) => React.ReactNode;
  keyExtractor?: (item: T) => string;
}

function List<T extends { id: string }>({ items, renderItem, keyExtractor }: ListProps<T>) {
  return <ul>{items.map(item => <li key={keyExtractor?.(item) ?? item.id}>{renderItem(item)}</li>)}</ul>;
}
```

## Dos

- Use strict TypeScript config (`strict: true`, `noUncheckedIndexedAccess: true`)
- Define API response types matching backend contracts
- Use Zod or similar for runtime validation at API boundaries
- Type CSS custom properties with `CSSProperties` extension
- Export component props for documentation and testing

## Don'ts

- Don't use `@ts-ignore` -- fix the type or use `@ts-expect-error` with explanation
- Don't use non-null assertion (`!`) except in `createContext` pattern
- Don't type state as `Object` or `{}` -- use specific interfaces
- Don't spread props without `Omit` to prevent DOM leakage
