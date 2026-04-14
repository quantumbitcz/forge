# Eval: Magic numbers without named constants

## Language: typescript

## Context
Code uses unexplained numeric literals instead of named constants.

## Code Under Review

```typescript
// file: src/pricing.ts
function calculateDiscount(amount: number, tier: string): number {
  if (tier === 'gold') {
    return amount * 0.15;
  }
  if (tier === 'silver') {
    return amount * 0.10;
  }
  if (amount > 500) {
    return amount * 0.05;
  }
  return 0;
}

function isEligible(score: number): boolean {
  return score >= 75 && score <= 100;
}
```

## Expected Behavior
Reviewer should flag magic numbers (0.15, 0.10, 0.05, 500, 75, 100) that should be named constants.
