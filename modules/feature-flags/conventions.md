# Feature Flags — General Best Practices

## Overview

Feature flags (feature toggles) decouple deployment from release. They enable trunk-based development, canary releases, A/B testing, and progressive rollouts. A feature flag wraps new behavior in a conditional check — when the flag is on, the new code path executes; when off, the existing behavior continues. Flags have a lifecycle: created -> active -> fully rolled out -> cleaned up. Stale flags (permanently enabled with dead code branches) are a major source of technical debt.

## Architecture Patterns

### Flag Evaluation

```typescript
// Good: centralized flag evaluation via SDK
if (featureFlags.isEnabled("new-checkout-flow", { userId: user.id })) {
    return renderNewCheckout();
} else {
    return renderLegacyCheckout();
}
```

Always evaluate flags through the SDK — never cache flag values in local variables across request boundaries. Flag values can change between evaluations for different users or contexts.

### Flag Types

| Type | Purpose | Lifetime | Example |
|------|---------|----------|---------|
| Release toggle | Gate incomplete features | Short (days-weeks) | `new-checkout-flow` |
| Experiment toggle | A/B testing | Medium (weeks-months) | `checkout-cta-variant` |
| Ops toggle | Circuit breaker, kill switch | Long (persistent) | `enable-external-payment-api` |
| Permission toggle | User-specific features | Long (persistent) | `beta-features` |

Each flag type has different lifecycle expectations. Release toggles must be cleaned up after full rollout. Ops toggles may persist indefinitely but should be documented.

### Dual-Path Implementation

```typescript
// Always implement BOTH paths
function getRecommendations(userId: string): Recommendation[] {
    if (featureFlags.isEnabled("ml-recommendations", { userId })) {
        return mlRecommendationService.getForUser(userId);  // New path
    }
    return legacyRecommendationService.getForUser(userId);  // Fallback path
}
```

Both flag-on and flag-off paths must be fully functional. The off path is the safety net — if the new feature causes issues, disabling the flag must restore previous behavior completely.

### Naming Conventions

Use a consistent naming pattern across the codebase:

| Pattern | Example | Notes |
|---------|---------|-------|
| kebab-case | `new-checkout-flow` | Preferred — matches URL slugs and most flag SDKs |
| dot-separated | `checkout.new.flow` | Used by Unleash — implies hierarchy |

Choose one pattern for the project and enforce it. Include the feature area as a prefix for discoverability: `checkout-new-flow`, `search-fuzzy-matching`, `billing-annual-plans`.

## Configuration

- Configure a single flag evaluation entry point (SDK client) shared across the application.
- Use typed flag accessors: `getBoolFlag("name")`, `getStringFlag("name", "default")` — avoid untyped `getFlag()`.
- Set meaningful defaults: if the flag service is unreachable, the default value should be the safe (existing) behavior.
- Configure flag refresh intervals based on use case: real-time for ops toggles, polling for release toggles.
- Document all flags in a central registry (flag service dashboard, `flags.json`, or code comments).

## Performance

- Cache flag evaluation results per request (not across requests) to avoid redundant SDK calls within a single user session.
- Use streaming/SSE connections to the flag service for real-time updates instead of frequent polling.
- Minimize the number of flag evaluations in hot paths — evaluate once and pass the result down.
- Use local evaluation SDKs (LaunchDarkly, Unleash) that cache the full flag configuration locally — no network round-trip per evaluation.

## Security

- Never expose flag internals (configuration rules, percentage rollout values) to client-side code beyond the boolean evaluation result.
- Use server-side evaluation for security-sensitive flags (payment, auth, admin features).
- Audit flag changes: log who changed a flag, when, and the before/after state.
- Restrict flag creation and modification permissions to appropriate team roles.

## Testing

- Test both flag-on and flag-off paths in every test suite.
- Use the flag SDK's test mode to control flag values in tests without network calls.
- Write cleanup tests: verify that removing a flag and its conditionals does not break the application.
- Test default values: simulate flag service unavailability and verify fallback behavior.

## Dos
- Implement both flag-on and flag-off code paths with full functionality.
- Clean up fully-rolled-out flags within 30 days — remove the conditional and dead code branch.
- Use a consistent naming convention for all flags across the project.
- Set safe defaults for all flags — flag service unavailability should not break the application.
- Document each flag with its type, owner, expected lifetime, and cleanup date.
- Test both flag states in every test suite that covers flagged code.
- Use server-side evaluation for security-sensitive flags.

## Don'ts
- Don't leave fully-rolled-out flags in the codebase — stale flags accumulate technical debt.
- Don't nest feature flags — `if (flagA && flagB)` creates a combinatorial explosion of test paths.
- Don't use boolean literals or environment variables as ad-hoc feature flags — use a proper flag service.
- Don't cache flag values across request boundaries — flags can change between evaluations.
- Don't expose flag configuration (rules, percentages) to the client — only expose the evaluation result.
- Don't create flags without documenting the cleanup plan and expected lifetime.
- Don't test only the flag-on path — the flag-off path is the safety net for production incidents.
