# Eval: Well-documented code with accurate docs

## Language: typescript

## Context
Code with accurate JSDoc that matches the implementation.

## Code Under Review

```typescript
// file: src/utils/string-utils.ts
/**
 * Truncates a string to the specified maximum length.
 * Appends an ellipsis if the string was truncated.
 * @param input - The string to truncate
 * @param maxLength - Maximum allowed length (must be >= 3)
 * @returns The truncated string, or the original if shorter than maxLength
 */
export function truncate(input: string, maxLength: number): string {
  if (maxLength < 3) {
    throw new RangeError('maxLength must be >= 3');
  }
  if (input.length <= maxLength) {
    return input;
  }
  return input.slice(0, maxLength - 3) + '...';
}
```

## Expected Behavior
No findings expected. Documentation accurately describes the implementation.
