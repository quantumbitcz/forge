# Eval: Hardcoded API key and database password

## Language: typescript

## Context
Source code contains hardcoded credentials instead of environment variables.

## Code Under Review

```typescript
// file: src/config.ts
export const config = {
  apiKey: 'HARDCODED-API-KEY-EXAMPLE-abc123def456',
  dbPassword: 'SuperSecret123!',
  jwtSecret: 'my-jwt-secret-key-do-not-share',
  stripeKey: 'HARDCODED-STRIPE-KEY-EXAMPLE-xyz789',
};
```

## Expected Behavior
Reviewer should flag all hardcoded secrets (API keys, passwords, JWT secrets).
