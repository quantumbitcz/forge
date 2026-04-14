# Eval: Public function without JSDoc documentation

## Language: typescript

## Context
Exported functions lack JSDoc comments describing parameters, return values, and behavior.

## Code Under Review

```typescript
// file: src/lib/calculator.ts
export function compound(principal: number, rate: number, periods: number): number {
  return principal * Math.pow(1 + rate, periods);
}

export function amortize(principal: number, rate: number, periods: number): number[] {
  const payment = principal * (rate * Math.pow(1 + rate, periods)) /
    (Math.pow(1 + rate, periods) - 1);
  const schedule: number[] = [];
  let balance = principal;
  for (let i = 0; i < periods; i++) {
    balance = balance * (1 + rate) - payment;
    schedule.push(Math.round(balance * 100) / 100);
  }
  return schedule;
}
```

## Expected Behavior
Reviewer should flag missing documentation on exported public functions.
