# Feature Flag Management

Shared contract for feature flag lifecycle management across the forge pipeline. Loaded by the orchestrator when `feature_flags.enabled: true` or when a feature flag provider is auto-detected at PREFLIGHT.

## Stale Flag Detection

A feature flag is considered **stale** when it meets all of these criteria:

1. The flag is referenced in production code (not just tests).
2. The flag configuration shows 100% rollout (all users receive the flag-on value).
3. The flag has been at 100% rollout for longer than `feature_flags.stale_threshold_days` (default: 30 days).

### Detection Mechanisms

**Code-level detection** (L1 pattern engine):
- Scan source files for flag SDK evaluation calls (`variation()`, `isEnabled()`, `useFlags()`, etc.).
- Extract flag key names from string literals in evaluation calls.
- Cross-reference extracted flag keys against the flag configuration file (if `flag_config_path` is configured).

**Configuration-level detection** (reviewer analysis):
- If a flag key is referenced in code but absent from the flag configuration, it may have been removed from the flag service without code cleanup -> `FLAG-STALE`.
- If a flag key is in the configuration at 100% rollout for > `stale_threshold_days` -> `FLAG-STALE`.

### Severity Escalation

- Single stale flag: `WARNING` (-5 points).
- 3+ stale flags in the same project: each additional flag escalates to `WARNING` with an `APPROACH-FLAG-DEBT` accumulation note.
- Stale flag in security-sensitive code path (auth, payment): `CRITICAL` (-20 points).

## Dual-Path Testing

Feature-flagged code must have tests covering both the flag-on and flag-off paths.

### Detection

For each flag evaluation call found in production code:
1. Search test files for the same flag key string.
2. Verify that tests exist which set the flag to both `true` and `false`.
3. If only one path is tested -> `FLAG-UNTESTED` (WARNING).
4. If no tests reference the flag key -> `FLAG-UNTESTED` (WARNING).

### Test Patterns by Provider

**LaunchDarkly:**
```typescript
// TestData source
const td = LaunchDarkly.integrations.TestData();
td.flag("new-checkout").booleanFlag().variationForAll(true);
// ... test flag-on behavior
td.flag("new-checkout").booleanFlag().variationForAll(false);
// ... test flag-off behavior
```

**Unleash:**
```typescript
const fakeUnleash = new FakeUnleash();
fakeUnleash.enable("feature.checkout.new");
// ... test enabled behavior
fakeUnleash.disable("feature.checkout.new");
// ... test disabled behavior
```

**Generic (custom):**
```typescript
jest.spyOn(featureFlags, "isEnabled").mockReturnValue(true);
// ... test flag-on behavior
jest.spyOn(featureFlags, "isEnabled").mockReturnValue(false);
// ... test flag-off behavior
```

## Deploy-Time Verification

When `feature_flags.deploy_flag_check: true` and the `/forge deploy` skill is invoked:

### Pre-Deploy Check

1. Enumerate all flag keys referenced in the code being deployed.
2. Query the flag service for each flag's current state in the target environment.
3. For each flag that is `OFF` in the target environment:
   - If the deployed code introduces NEW references to this flag -> `WARNING`: "Flag `{key}` is OFF in `{environment}`. Deployed code will not execute the flagged path until enabled."
   - If the deployed code only modifies EXISTING references -> `INFO`: "Flag `{key}` is OFF in `{environment}`. Existing behavior will continue."
4. For flags that are `ON` in the target environment with a scheduled kill-date that has passed -> `FLAG-CLEANUP` (INFO).

### Post-Deploy Verification

After deployment completes:
1. Verify flag state has not changed during the deployment (prevents mid-deploy flag toggles).
2. If flag state changed during deploy -> `WARNING`: "Flag `{key}` state changed during deployment. Verify intended behavior."

## Flag Lifecycle

```
CREATED -> DEVELOPMENT -> TESTING -> STAGED_ROLLOUT -> FULL_ROLLOUT -> CLEANUP_DUE -> CLEANED_UP
```

| Stage | Duration | Action |
|-------|----------|--------|
| CREATED | 0 days | Flag created in service and code |
| DEVELOPMENT | 1-14 days | Feature developed behind flag |
| TESTING | 1-7 days | Both paths tested in CI |
| STAGED_ROLLOUT | 1-30 days | Progressive rollout (1% -> 10% -> 50% -> 100%) |
| FULL_ROLLOUT | 0-30 days | Flag at 100%, monitoring for rollback need |
| CLEANUP_DUE | After stale_threshold_days | Remove flag conditional and dead code |
| CLEANED_UP | - | Flag removed from code and service |

## Finding Categories

| Category | Severity | Trigger |
|----------|----------|---------|
| `FLAG-STALE` | WARNING | Flag at 100% rollout beyond stale threshold |
| `FLAG-UNTESTED` | WARNING | Flagged code without tests for both paths |
| `FLAG-HARDCODED` | INFO | Boolean literal used as ad-hoc toggle |
| `FLAG-CLEANUP` | INFO | Flag eligible for removal |

All findings use standard scoring weights: CRITICAL=-20, WARNING=-5, INFO=-2.
