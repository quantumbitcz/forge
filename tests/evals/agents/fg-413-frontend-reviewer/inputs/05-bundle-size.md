# Eval: Heavy library import for trivial operation

## Language: typescript

## Context
Component imports entire lodash library for a single utility function available natively.

## Code Under Review

```typescript
// file: src/utils/format.ts
import _ from 'lodash';

export function capitalize(str: string): string {
  return _.capitalize(str);
}

export function unique(arr: string[]): string[] {
  return _.uniq(arr);
}

export function isEmpty(obj: Record<string, unknown>): boolean {
  return _.isEmpty(obj);
}
```

## Expected Behavior
Reviewer should flag full lodash import when specific subpath imports or native alternatives exist.
