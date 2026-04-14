# Eval: Documentation contradicts implementation

## Language: typescript

## Context
JSDoc says function throws on invalid input, but implementation returns null instead.

## Code Under Review

```typescript
// file: src/services/parser.ts
/**
 * Parses a date string in ISO 8601 format.
 * @param input - ISO 8601 date string
 * @returns Parsed Date object
 * @throws {Error} If the input is not a valid ISO 8601 date string
 */
export function parseDate(input: string): Date | null {
  const parsed = new Date(input);
  if (isNaN(parsed.getTime())) {
    return null;
  }
  return parsed;
}
```

## Expected Behavior
Reviewer should flag that JSDoc says "@throws Error" but implementation returns null instead of throwing.
