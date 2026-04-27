# Pact Consumer-Driven Contract Testing Conventions

> Support tier: community

## Overview

Pact is a consumer-driven contract testing framework that verifies service integrations by having consumers define their expectations as contracts (pacts) and providers verify they satisfy those expectations. This inverts traditional API testing: instead of producers testing their own schemas, consumers declare exactly what they need.

- **Use for:** microservice architectures where API compatibility between services is critical, pre-merge verification of producer changes against consumer expectations, deployment gates (can-i-deploy)
- **Avoid for:** monolithic applications without service boundaries, internal-only APIs with a single consumer that is always deployed together, performance/load testing (Pact tests interaction contracts, not throughput)
- **Key differentiators:** consumer-driven (consumers define contracts), interaction-level (tests request/response pairs, not schemas), broker-based coordination (centralized contract registry), language-agnostic (Pact FFI supports 10+ languages)

## Architecture Patterns

### Consumer-Side Testing

Consumers write tests that define their expected interactions with a provider. Pact captures these interactions as JSON contract files.

```javascript
// JavaScript (Pact JS)
const { PactV3 } = require('@pact-foundation/pact');

const provider = new PactV3({
  consumer: 'frontend-app',
  provider: 'backend-api',
});

describe('User API', () => {
  it('fetches user by ID', async () => {
    provider
      .given('user 42 exists')
      .uponReceiving('a request for user 42')
      .withRequest({
        method: 'GET',
        path: '/api/users/42',
        headers: { Accept: 'application/json' },
      })
      .willRespondWith({
        status: 200,
        headers: { 'Content-Type': 'application/json' },
        body: {
          id: 42,
          name: like('Jane Doe'),
          email: like('jane@example.com'),
        },
      });

    await provider.executeTest(async (mockServer) => {
      const response = await fetchUser(mockServer.url, 42);
      expect(response.id).toBe(42);
    });
  });
});
```

```kotlin
// Kotlin (Pact JVM)
@ExtendWith(PactConsumerTestExt::class)
@PactTestFor(providerName = "backend-api")
class UserApiPactTest {

    @Pact(consumer = "frontend-app")
    fun userPact(builder: PactDslWithProvider): V4Pact =
        builder
            .given("user 42 exists")
            .uponReceiving("a request for user 42")
            .method("GET")
            .path("/api/users/42")
            .willRespondWith()
            .status(200)
            .headers(mapOf("Content-Type" to "application/json"))
            .body(
                PactDslJsonBody()
                    .integerType("id", 42)
                    .stringType("name", "Jane Doe")
                    .stringType("email", "jane@example.com")
            )
            .toPact(V4Pact::class.java)

    @Test
    @PactTestFor(pactMethod = "userPact")
    fun `fetches user by ID`(mockServer: MockServer) {
        val response = userClient.getUser(mockServer.getUrl(), 42)
        assertThat(response.id).isEqualTo(42)
    }
}
```

```python
# Python (Pact Python)
import atexit
from pact import Consumer, Provider

pact = Consumer('frontend-app').has_pact_with(
    Provider('backend-api'),
    pact_dir='./pacts'
)
pact.start_service()
atexit.register(pact.stop_service)

def test_get_user():
    (pact
     .given('user 42 exists')
     .upon_receiving('a request for user 42')
     .with_request('GET', '/api/users/42')
     .will_respond_with(200, body={
         'id': Like(42),
         'name': Like('Jane Doe'),
         'email': Like('jane@example.com'),
     }))

    with pact:
        result = get_user(pact.uri, 42)
        assert result['id'] == 42
```

### Provider-Side Verification

Providers run consumer pacts against their actual implementation to verify compatibility:

```bash
# Gradle (Pact JVM)
./gradlew pactVerify

# npm (Pact JS)
npx pact-provider-verifier --provider-base-url=http://localhost:8080 --pact-broker-base-url=https://broker.internal

# Python
pact-verifier --provider-base-url=http://localhost:8080 --pact-url=./pacts/frontend-backend.json
```

### Provider States

Provider states set up test data before verification. Each `given()` clause maps to a state handler:

```kotlin
// Provider state setup (Pact JVM)
@State("user 42 exists")
fun setupUser42() {
    userRepository.save(User(id = 42, name = "Jane Doe", email = "jane@example.com"))
}
```

### Pact Broker

The Pact broker is a central registry for contracts and verification results:

```
Consumer publishes pact  -->  Pact Broker  <--  Provider verifies pact
                                  |
                           can-i-deploy check
                                  |
                            Deploy or Block
```

**Self-hosted:** `pact-broker` Docker image or Helm chart.
**SaaS:** PactFlow (pactflow.io) — adds features like bi-directional contracts and webhook management.

### Versioning and Tagging

```bash
# Publish consumer pact with version and branch tag
pact-broker publish ./pacts \
  --consumer-app-version=$(git rev-parse --short HEAD) \
  --branch=$(git branch --show-current) \
  --broker-base-url=https://broker.internal \
  --broker-token=$PACT_BROKER_TOKEN

# Tag provider version after verification
pact-broker create-version-tag \
  --pacticipant=backend-api \
  --version=$(git rev-parse --short HEAD) \
  --tag=$(git branch --show-current)
```

### Can-I-Deploy

Pre-deployment compatibility check:

```bash
# Check if provider version is safe to deploy
pact-broker can-i-deploy \
  --pacticipant=backend-api \
  --version=$(git rev-parse --short HEAD) \
  --to-environment=production
```

Exit code 0 = safe to deploy. Exit code 1 = one or more consumer contracts are failing or unverified.

## Configuration

### forge.local.md

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

### Pact Source Modes

| Mode | Description | Prerequisites |
|------|-------------|---------------|
| `broker` | Fetch pacts from Pact broker | `broker_url` configured, `broker_token_env` set |
| `local` | Read pact JSON from local directory | `local_pact_dir` configured |
| `a2a` | Fetch from consumer via A2A protocol | Consumer in `related_projects`, A2A available |

## Performance

| Operation | Duration | Notes |
|-----------|----------|-------|
| Fetch pacts (broker) | 500ms-2s | Network latency |
| Fetch pacts (local) | <100ms | File I/O |
| Provider verification | 10s-5min | Depends on interaction count |
| Can-i-deploy check | 500ms-2s | Broker API |

Provider verification scales linearly with interaction count. The `provider_verification_timeout_s` config (default 300s) provides a ceiling.

## Security

- Broker tokens stored in environment variables (`broker_token_env`), never in config files
- Pact files may contain example data — ensure provider states use synthetic test data, not production copies
- Broker access should be scoped per team (PactFlow supports team-level permissions)
- Webhook secrets for broker notifications should be rotated regularly

## Testing

```
# Consumer-side
- Consumer tests generate pact JSON files
- Pact files are valid JSON matching Pact specification v4
- All interactions have unique descriptions
- Provider states are descriptive and testable

# Provider-side
- Provider verification passes for all consumer interactions
- Provider state handlers exist for every given() clause
- Verification results published to broker

# Deployment gate
- can-i-deploy returns exit 0 before deploying provider
- SHIPPING stage blocks on can-i-deploy failure
```

## Dos

- Use Pact Specification v4 for new contracts (supports synchronous HTTP, async messages, and plugins)
- Name consumers and providers consistently across all services (e.g., `{team}-{service}`)
- Keep pact interactions minimal — test the contract shape, not business logic
- Use matchers (`like()`, `eachLike()`, `regex()`) instead of exact values for flexible contracts
- Publish pacts with git SHA and branch tag for traceability
- Run can-i-deploy in CI before every deployment
- Set up broker webhooks to trigger provider verification when consumers publish new pacts
- Write provider state handlers that create isolated test data (no shared mutable state)

## Don'ts

- Do not use Pact as a functional test framework — it tests contracts, not business rules
- Do not include exact timestamps, UUIDs, or auto-generated values without matchers
- Do not publish pacts from local development machines — only from CI
- Do not skip can-i-deploy checks — they are the deployment safety gate
- Do not share provider state data between tests — each test should set up its own state
- Do not test every API endpoint in pacts — focus on the interactions the consumer actually uses
- Do not hardcode broker URLs or tokens in code — use environment variables
- Do not use Pact for testing third-party APIs you do not control — Pact requires both sides to participate
