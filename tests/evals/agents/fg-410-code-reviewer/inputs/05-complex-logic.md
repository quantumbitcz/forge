# Eval: Deeply nested complex logic

## Language: typescript

## Context
Function with excessive nesting and cyclomatic complexity.

## Code Under Review

```typescript
// file: src/validator.ts
function validateOrder(order: any, config: any): string[] {
  const errors: string[] = [];
  if (order) {
    if (order.items) {
      for (const item of order.items) {
        if (item.quantity) {
          if (item.quantity > 0) {
            if (config.maxQuantity) {
              if (item.quantity > config.maxQuantity) {
                errors.push(`Item ${item.id} exceeds max`);
              }
            }
          } else {
            errors.push(`Item ${item.id} invalid qty`);
          }
        }
      }
    }
  }
  return errors;
}
```

## Expected Behavior
Reviewer should flag deeply nested logic and high cyclomatic complexity.
