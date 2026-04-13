# Unleash — Toggle Types & Strategies

## Overview

Unleash is an open-source feature flag management system. It supports multiple toggle types (release, experiment, operational, kill-switch, permission), activation strategies (gradual rollout, user IDs, IPs, custom), and variants for A/B testing. Unleash can be self-hosted or used as Unleash Cloud. The client SDK evaluates flags locally using a cached configuration fetched from the Unleash server.

## Architecture Patterns

### Toggle Types

```
Release   — Short-lived, gates new features during development
Experiment — Medium-lived, A/B testing with metrics tracking
Operational — Long-lived, circuit breakers and kill switches
Kill-switch — Emergency toggle, disables features instantly
Permission — Per-user or per-group feature access
```

Select the appropriate toggle type when creating a flag. This metadata drives lifecycle management — release toggles trigger stale-flag alerts; operational toggles do not.

### Client Initialization

```typescript
import { initialize } from "unleash-client";

const unleash = initialize({
    url: "https://unleash.example.com/api/",
    appName: "my-service",
    instanceId: "instance-1",
    customHeaders: { Authorization: "API-TOKEN" },
    refreshInterval: 15000,
});

unleash.on("ready", () => console.log("Unleash client ready"));
```

Initialize the client at application startup. The SDK fetches the full toggle configuration and evaluates locally — no network call per `isEnabled()` check.

### Flag Evaluation

```typescript
const isEnabled = unleash.isEnabled("new.checkout.flow", {
    userId: user.id,
    properties: { plan: user.plan, region: user.region },
});

if (isEnabled) {
    return renderNewCheckout();
} else {
    return renderLegacyCheckout();
}
```

Use `isEnabled()` with an Unleash context for targeting. The context supports `userId`, `sessionId`, `remoteAddress`, `environment`, and custom `properties`.

### Variants

```typescript
const variant = unleash.getVariant("checkout.cta.experiment", {
    userId: user.id,
});

switch (variant.name) {
    case "green-button": return renderGreenCta();
    case "blue-button": return renderBlueCta();
    default: return renderDefaultCta();
}
```

Use variants for multivariate experiments. Each variant has a name, weight, and optional payload. Always handle the default case for users not included in the experiment.

### Strategies

```
Standard      — Simple on/off
GradualRollout — Percentage-based with stickiness (userId, sessionId, random)
UserIds       — Whitelist specific user IDs
IPs           — Whitelist IP ranges
Custom        — Application-defined strategy logic
```

Use `GradualRollout` for incremental releases. Stickiness ensures the same user consistently sees the same flag state.

## Configuration

- Set `refreshInterval` based on use case: 15s for release toggles, 5s for ops toggles.
- Use `environment` in the Unleash context to separate dev/staging/production configurations.
- Configure `disableMetrics: true` in local development to reduce noise.
- Use `fallbackFunction` for custom fallback logic when Unleash is unreachable.
- Name toggles with dot-separated convention: `feature.checkout.new-flow`.

## Performance

- The SDK evaluates flags locally from an in-memory cache — evaluation is sub-millisecond.
- Reduce `refreshInterval` for real-time toggles (ops/kill-switch), increase for stable release toggles.
- Use `isEnabled()` result caching within a request scope for hot paths with multiple evaluations.
- Avoid creating thousands of toggles — the full configuration is fetched on each refresh.

## Security

- Use API tokens with appropriate scope (client or admin) — never use admin tokens in application code.
- Restrict toggle creation and modification via Unleash RBAC.
- Use environment-scoped tokens: production tokens should not have access to development toggles.
- Audit toggle changes via Unleash's event log.

## Testing

- Use `FakeUnleash` from the SDK's test utilities for unit tests.
- Override toggles in tests: `fakeUnleash.enable("toggle.name")` or `fakeUnleash.disable("toggle.name")`.
- Test both enabled and disabled states for every toggle.
- Test variant distribution: verify that each variant is reachable.
- Test fallback behavior: verify that `fallbackFunction` returns the expected value when Unleash is unavailable.

## Dos
- Use dot-separated naming for toggle keys: `feature.checkout.new-flow`.
- Select the correct toggle type (release, experiment, operational, kill-switch, permission) when creating.
- Implement both enabled and disabled code paths with full functionality.
- Use `GradualRollout` with `userId` stickiness for consistent user experience during rollout.
- Handle the default variant case in all `getVariant()` switches.
- Clean up release toggles after full rollout.

## Don'ts
- Don't use admin API tokens in application code — use client tokens with read-only scope.
- Don't create toggles without selecting the appropriate type — lifecycle management depends on it.
- Don't hardcode toggle names as string literals scattered through the codebase — centralize them.
- Don't skip the disabled code path — disabling a toggle must safely restore previous behavior.
- Don't use `isEnabled()` without an Unleash context when targeting rules depend on user properties.
- Don't create toggles without documenting the cleanup plan and expected lifetime.
