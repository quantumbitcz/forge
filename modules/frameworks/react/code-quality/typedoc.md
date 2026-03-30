# React + typedoc

> Extends `modules/code-quality/typedoc.md` with React-specific integration.
> Generic typedoc conventions (installation, `typedoc.json`, entryPoints) are NOT repeated here.

## Integration Setup

```bash
npm install --save-dev typedoc typedoc-plugin-markdown
```

**`typedoc.json` for a React component library:**
```json
{
  "$schema": "https://typedoc.org/schema.json",
  "entryPoints": ["src/components/index.ts", "src/hooks/index.ts"],
  "entryPointStrategy": "expand",
  "out": "docs/api",
  "tsconfig": "./tsconfig.json",
  "excludePrivate": true,
  "excludeInternal": true,
  "categorizeByGroup": true,
  "categoryOrder": ["Components", "Hooks", "Types", "*"]
}
```

## Framework-Specific Patterns

### Component prop documentation

Document props via the exported interface, not the component function signature — TypeDoc renders interface members as a table:

```tsx
/** Props for the primary action button. */
export interface ButtonProps {
  /** Button label text — must be non-empty. */
  label: string;
  /** Visual variant. Defaults to `"primary"`. */
  variant?: "primary" | "secondary" | "danger";
  /** Called when the button is clicked. */
  onClick?: (event: React.MouseEvent<HTMLButtonElement>) => void;
}

export function Button({ label, variant = "primary", onClick }: ButtonProps) { ... }
```

### Custom hooks documentation

Document the return type explicitly — TypeDoc infers complex return objects poorly without explicit types:

```tsx
/**
 * Manages paginated data fetching with cursor-based navigation.
 * @param endpoint - API endpoint path
 * @returns Pagination state and navigation controls
 */
export function usePagination(endpoint: string): PaginationResult { ... }
```

### Entry point strategy for apps vs. libraries

- **Libraries:** Use `"entryPointStrategy": "expand"` with `src/index.ts` re-exporting the public surface.
- **Apps:** Skip TypeDoc — use Storybook for component documentation instead.

## Additional Dos

- Export prop interfaces alongside components — unlocks TypeDoc's interface member table rendering.
- Use `@example` JSDoc tags on complex hooks — TypeDoc renders these as copyable code blocks.

## Additional Don'ts

- Don't generate TypeDoc for internal components (prefixed `_` or in `src/internal/`) — expose only the public API.
- Don't replace Storybook with TypeDoc for visual component documentation — they serve different purposes.
