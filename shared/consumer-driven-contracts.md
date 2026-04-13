# Consumer-Driven Contract Testing

Integration of consumer-driven contract testing into the forge pipeline. Supports Pact (primary), Specmatic, and Spring Cloud Contract as alternative frameworks.

## Contract Testing Lifecycle

```
1. PREFLIGHT: Auto-detect contract testing framework from dependencies
2. VALIDATING: Run provider verification against consumer pacts
3. SHIPPING: Run can-i-deploy check to verify deployment safety
4. IMPLEMENTING: Follow pact conventions when modifying API endpoints (consumer side)
5. VERIFYING: Run pact consumer tests to generate/update pact files
```

## Framework Detection (PREFLIGHT)

Auto-detection signals:

| Signal | Framework | Confidence |
|--------|-----------|-----------|
| `pact` in package.json / requirements.txt / build.gradle | Pact | HIGH |
| `@pactflow` in package.json / build.gradle | PactFlow (SaaS broker) | HIGH |
| `specmatic` in package.json / build.gradle | Specmatic | HIGH |
| `spring-cloud-contract` in build.gradle / pom.xml | Spring Cloud Contract | HIGH |
| `*.pact.json` files in project | Pact (local mode) | MEDIUM |

When `contract_testing.provider: auto`, the detected framework is used. When explicitly set, detection is skipped.

## Pact Integration

### Pact Source Resolution

Three modes for locating consumer pacts:

| Mode | Description | Fallback |
|------|-------------|----------|
| `broker` | Fetch from Pact broker (self-hosted or PactFlow) | Falls back to `local` if broker unreachable |
| `local` | Read from local directory (`local_pact_dir`) | No fallback — emit `CONTRACT-PACT-MISSING` if empty |
| `a2a` | Fetch from consumer via A2A protocol | Falls back to `broker`, then `local` |

### Provider Verification (VALIDATING)

For each contract entry with `type: pact`:

1. **Resolve pacts** from configured source (broker, local, or A2A)
2. **Execute provider verification** via configured command (e.g., `./gradlew pactVerify`)
3. **Check for pending pacts** (new consumer expectations not yet verified)
4. **Check staleness** (verification older than `stale_threshold_days`)
5. **Publish results** to broker if `publish_results: true`

Finding production:

| Condition | Finding | Severity |
|-----------|---------|----------|
| Provider verification fails | `CONTRACT-PACT-FAIL` | CRITICAL |
| Pending pacts exist | `CONTRACT-PACT-PENDING` | WARNING |
| Expected pact not found | `CONTRACT-PACT-MISSING` | WARNING |

### Can-I-Deploy Gate (SHIPPING)

Integrated into `fg-590-pre-ship-verifier`:

```bash
pact-broker can-i-deploy \
  --pacticipant {provider_name} \
  --version {git_sha} \
  --to-environment production
```

- Exit 0: allow shipping
- Exit 1: emit `CONTRACT-PACT-FAIL | CRITICAL`, block SHIP

Result written to `.forge/evidence.json`:

```json
{
  "contract_verification": {
    "can_i_deploy": true,
    "provider": "backend-api",
    "version": "abc1234",
    "consumers_verified": 3,
    "consumers_pending": 0,
    "checked_at": "2026-04-13T14:00:00Z"
  }
}
```

When the broker is unavailable, fall back to local verification results from the VALIDATE stage.

### Consumer-Side Generation

When the project is a pact consumer (pact dependency + consumer test files):

1. **IMPLEMENTING:** Implementer follows pact conventions when adding/changing API calls
2. **VERIFYING:** Test gate runs pact consumer tests, generates pact files to `.forge/pacts/`
3. **SHIPPING:** If broker configured, publish consumer pacts with git SHA and branch tag

## Alternative Frameworks

### Specmatic

OpenAPI specs as executable contracts. No broker needed — the OpenAPI spec is the contract.

Module: `modules/api-protocols/specmatic/conventions.md` (when created)

```bash
# Run Specmatic contract tests
npx specmatic test --host localhost --port 8080 --contract api/openapi.yml
```

### Spring Cloud Contract

Groovy/YAML contract DSL for Spring-based microservices. Contracts live in the producer repo and generate consumer stubs.

Module: `modules/api-protocols/spring-cloud-contract/conventions.md` (when created)

```groovy
// contract DSL
Contract.make {
    request {
        method GET()
        url '/api/users/42'
    }
    response {
        status OK()
        body([id: 42, name: 'Jane Doe'])
    }
}
```

## Interaction with Existing Contract Validator

The `pact` strategy coexists with the existing `openapi` strategy in `fg-250-contract-validator`:

| Aspect | OpenAPI (existing) | Pact (new) |
|--------|-------------------|------------|
| Direction | Producer-side (diff against baseline) | Consumer-driven (verify against expectations) |
| What it checks | Schema-level breaking changes | Interaction-level contract compliance |
| Data source | Git baseline vs current file | Pact broker / local pact files |
| Finding categories | `CONTRACT-BREAK`, `CONTRACT-CHANGE`, `CONTRACT-ADD` | `CONTRACT-PACT-FAIL`, `CONTRACT-PACT-PENDING`, `CONTRACT-PACT-MISSING` |

Both strategies can run on the same API when configured as separate contract entries.

## Finding Categories

| Category | Severity | Description |
|----------|----------|-------------|
| `CONTRACT-PACT-FAIL` | CRITICAL | Pact provider verification failed (consumer expectation not met) |
| `CONTRACT-PACT-PENDING` | WARNING | Pending pact verification (new consumer expectations not yet verified) |
| `CONTRACT-PACT-MISSING` | WARNING | Expected pact file or broker entry not found for a configured consumer |

## Configuration Reference

### forge-config.md (plugin-wide defaults)

```yaml
contract_testing:
  provider: auto
  can_i_deploy: true
```

### forge.local.md (per-project)

```yaml
contracts:
  - name: "frontend-pact"
    type: pact
    consumer_name: "frontend-app"
    provider_name: "backend-api"
    pact_source: broker
    broker_url: "https://pact-broker.internal"
    broker_token_env: "PACT_BROKER_TOKEN"
    provider_verification_command: "./gradlew pactVerify"
    can_i_deploy: true
    stale_threshold_days: 7
```

## Error Handling

| Failure Mode | Behavior |
|-------------|----------|
| Broker unreachable | WARNING, fall back to local pact files |
| Broker token invalid | WARNING, skip broker operations |
| Verification command fails (non-pact) | CRITICAL, treat as verification failure |
| Verification command not found | WARNING, skip pact verification |
| Pact file malformed | WARNING, skip that pact, continue with others |
| Consumer pact directory empty | `CONTRACT-PACT-MISSING | WARNING` |
| can-i-deploy CLI not found | INFO, use local verification results |
| A2A transport unavailable | Fall back to broker, then local |

## Agent Interaction

| Agent | Role |
|-------|------|
| `fg-250-contract-validator` | Runs pact provider verification alongside existing openapi strategy |
| `fg-590-pre-ship-verifier` | Runs can-i-deploy check, blocks SHIP on failure |
| `fg-300-implementer` | Follows pact conventions when modifying API endpoints |
| `fg-500-test-gate` | Runs pact consumer tests, verifies pact file generation |
| `fg-103-cross-repo-coordinator` | Coordinates pact verification across producer and consumer repos |
