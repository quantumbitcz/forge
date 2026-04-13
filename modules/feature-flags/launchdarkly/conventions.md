# LaunchDarkly — SDK Patterns & Flag Evaluation

## Overview

LaunchDarkly is a feature flag management platform with server-side and client-side SDKs. The server-side SDK streams flag configuration and evaluates locally (no network round-trip per evaluation). The client-side SDK evaluates against a user context. LaunchDarkly supports targeting rules, percentage rollouts, multivariate flags, and experimentation. Use the SDK's typed variation methods for type-safe flag evaluation.

## Architecture Patterns

### SDK Initialization

```typescript
import * as LaunchDarkly from "@launchdarkly/node-server-sdk";

const client = LaunchDarkly.init("sdk-key-server-side");
await client.waitForInitialization();
```

Initialize the client once at application startup. The server-side SDK maintains a streaming connection for real-time flag updates. Never create multiple client instances — reuse the singleton.

### Flag Evaluation

```typescript
const context = {
    kind: "user",
    key: user.id,
    email: user.email,
    custom: { plan: user.plan, region: user.region },
};

const showNewCheckout = await client.boolVariation("new-checkout-flow", context, false);
const checkoutVariant = await client.stringVariation("checkout-variant", context, "control");
const maxRetries = await client.numberVariation("max-api-retries", context, 3);
```

Use typed variation methods (`boolVariation`, `stringVariation`, `numberVariation`, `jsonVariation`). Always provide a default value — it is returned when the flag is not found or the SDK is not initialized.

### Context Kinds

```typescript
const multiContext = {
    kind: "multi",
    user: { key: user.id, email: user.email },
    organization: { key: org.id, name: org.name },
    device: { key: deviceId, os: "ios" },
};
```

Use multi-contexts for targeting rules that span user, organization, and device dimensions. LaunchDarkly's targeting rules can evaluate against any context kind.

### React SDK

```tsx
import { useFlags, useLDClient } from "launchdarkly-react-client-sdk";

function CheckoutPage() {
    const { newCheckoutFlow } = useFlags();
    return newCheckoutFlow ? <NewCheckout /> : <LegacyCheckout />;
}
```

Use the React SDK's hooks for client-side evaluation. Flag values update in real-time via streaming. Wrap the application with `LDProvider` at the root.

## Configuration

- Use server-side SDK keys for backend services and client-side SDK keys for frontend apps — never expose server-side keys to the client.
- Configure `flushInterval` for analytics event batching (default 5s is fine for most use cases).
- Use `offline: true` for local development without a LaunchDarkly connection.
- Set `baseUri` and `streamUri` for self-hosted LaunchDarkly Relay Proxy deployments.
- Use flag prerequisites in the dashboard to create dependency chains between flags.

## Performance

- Server-side SDKs evaluate flags locally using a cached configuration — no network call per evaluation.
- Client-side SDKs stream updates — flag changes propagate within seconds without polling.
- Use `allFlagsState()` for server-side rendering to pass all flag values to the client in a single request.
- Avoid calling `variation()` in tight loops — evaluate once and store the result for the request scope.

## Security

- Never expose server-side SDK keys in client-side code or public repositories.
- Use targeting rules and segments to control access — do not implement authorization logic in flag evaluation code.
- Audit flag changes via LaunchDarkly's audit log and integrations (Slack, Datadog).
- Use `secureModeHash` for client-side evaluation to prevent users from spoofing their context.

## Testing

- Use `TestData` source for unit tests: `td = LaunchDarkly.integrations.TestData(); td.flag("flag-key").booleanFlag().variationForAll(true)`.
- Test both flag states for every flagged code path.
- Use LaunchDarkly's API to programmatically set flag states in integration test environments.
- Verify default values are returned when the SDK is not initialized (graceful degradation).

## Dos
- Use typed variation methods (`boolVariation`, `stringVariation`) — never use untyped `variation()`.
- Provide meaningful default values for all flag evaluations.
- Use multi-contexts for complex targeting across user, organization, and device.
- Initialize the SDK client once and reuse it — never create per-request instances.
- Use kebab-case for flag keys: `new-checkout-flow`, not `newCheckoutFlow` or `NEW_CHECKOUT_FLOW`.
- Clean up flags after full rollout — use LaunchDarkly's stale flag detection dashboard.

## Don'ts
- Don't expose server-side SDK keys in client-side code.
- Don't evaluate flags at module/class initialization — wait until the SDK is ready.
- Don't create multiple SDK client instances — use a singleton per application.
- Don't use `variation()` without a default value — it throws if the flag is missing.
- Don't hardcode flag keys as string literals scattered across the codebase — centralize them in a constants file.
- Don't use flag evaluation for authorization decisions — flags are for feature rollout, not access control.
