# F25: Consumer-Driven Contract Testing (Pact Integration)

## Status
DRAFT — 2026-04-13 (Forward-Looking)

## Problem Statement

Forge's `fg-250-contract-validator` detects breaking changes in shared API contracts (OpenAPI, Protobuf, GraphQL) by diffing the current spec against its git baseline and checking consumer usage via grep. This is producer-side, schema-level validation. It catches "did the producer change the API in a breaking way?" but does not answer "does the producer actually satisfy what consumers expect?"

Consumer-driven contract testing inverts this: consumers define what they need from a producer, and the producer verifies it satisfies all consumer expectations. This is the Pact model (adopted across the industry for microservice architectures) and fills several gaps:

1. **Consumer expectations are implicit:** The current contract validator greps consumer code for usage of specific endpoints/fields. This is heuristic — it catches direct references but misses consumers that access fields via dynamic paths, computed property names, or generated clients. Pact contracts are explicit declarations of exactly what the consumer needs.
2. **No pre-merge verification:** Teams cannot answer "can I deploy this producer change without breaking consumers?" before merging. The current validator compares against the baseline branch, not against published consumer pacts.
3. **No cross-service orchestration:** In a microservice architecture, deploying a producer that breaks consumer contracts should be blocked before it reaches production. Forge has no integration with a Pact broker or similar contract registry.
4. **Missing contract types:** `fg-250-contract-validator` implements only the `openapi` strategy. Protobuf, GraphQL, and TypeScript types are listed as "Future" in the agent's extension points (section 7). Pact is protocol-agnostic — it tests interactions, not schemas.
5. **No can-i-deploy gate:** Before shipping, teams need to verify that all consumers of the producer's API have passing pact verifications for the version being deployed. This is the "can-i-deploy" check. Forge's shipping gate (`fg-590-pre-ship-verifier`) has no awareness of this.

## Proposed Solution

Add a `modules/api-protocols/pact/` module with conventions for Pact-based consumer-driven contract testing. Enhance `fg-250-contract-validator` with a `pact` analysis strategy that runs Pact provider verification, checks the Pact broker for pending/failed verifications, and blocks shipping when can-i-deploy fails. Add alternative modules for Specmatic and Spring Cloud Contract. Integrate with the shipping gate via evidence requirements.

## Detailed Design

### Architecture

```
Consumer Repo (frontend)                    Producer Repo (backend)
+---------------------------+              +---------------------------+
| Consumer tests generate   |              | fg-250-contract-validator |
| pact files                |              | (enhanced with pact       |
|                           |              |  strategy)                |
| → .forge/pacts/*.json     |              +---------------------------+
|   (or published to broker)|                     |           |
+---------------------------+              +------+           +-------+
              |                            |                          |
              v                            v                          v
       Pact Broker                  Provider verification     Can-I-Deploy
       (optional)                   (run consumer pacts       (check broker
                                    against provider)          for readiness)
              |                            |                          |
              +-------- Results -----------+                          |
                                                                      v
                                                              fg-590-pre-ship-verifier
                                                              (blocks SHIP if fails)
```

**Components:**

1. **Pact module** (`modules/api-protocols/pact/conventions.md`) — conventions for Pact broker patterns, consumer test structure, provider verification setup, versioning, and tagging.

2. **Enhanced contract validator** (`agents/fg-250-contract-validator.md`) — new `pact` analysis strategy alongside existing `openapi`. Runs Pact provider verification, checks broker state, and produces `CONTRACT-PACT-*` findings.

3. **Pact broker integration** (`modules/api-protocols/pact/broker-integration.md`) — conventions for broker setup, webhook configuration, and API usage patterns. Supports both self-hosted Pact broker and PactFlow (SaaS).

4. **Specmatic module** (`modules/api-protocols/specmatic/conventions.md`) — alternative contract testing framework using OpenAPI specs as executable contracts.

5. **Spring Cloud Contract module** (`modules/api-protocols/spring-cloud-contract/conventions.md`) — alternative for Spring-based microservices using Groovy/YAML contract DSL.

### Schema / Data Model

#### New Finding Categories

Added to `shared/checks/category-registry.json`:

```json
{
  "CONTRACT-PACT-FAIL": {
    "description": "Pact provider verification failed — consumer expectation not met",
    "agents": ["fg-250-contract-validator"],
    "wildcard": false,
    "priority": 1,
    "affinity": ["fg-250-contract-validator"]
  },
  "CONTRACT-PACT-PENDING": {
    "description": "Pending pact verification — consumer has published new expectations not yet verified",
    "agents": ["fg-250-contract-validator"],
    "wildcard": false,
    "priority": 3,
    "affinity": ["fg-250-contract-validator"]
  },
  "CONTRACT-PACT-MISSING": {
    "description": "Expected pact file or broker entry not found for a configured consumer",
    "agents": ["fg-250-contract-validator"],
    "wildcard": false,
    "priority": 3,
    "affinity": ["fg-250-contract-validator"]
  },
  "CONTRACT-PACT-STALE": {
    "description": "Pact verification is stale — last verified more than stale_threshold_days ago",
    "agents": ["fg-250-contract-validator"],
    "wildcard": false,
    "priority": 5,
    "affinity": ["fg-250-contract-validator"]
  }
}
```

#### Severity Mapping

| Finding | Severity | Rationale |
|---|---|---|
| `CONTRACT-PACT-FAIL` | CRITICAL | Provider does not satisfy consumer expectations. Deploying would break the consumer. |
| `CONTRACT-PACT-PENDING` | WARNING | New consumer expectations exist but have not been verified. Risk of unknown incompatibility. |
| `CONTRACT-PACT-MISSING` | WARNING | Expected pact not found. Consumer may not be generating pacts, or broker URL is misconfigured. |
| `CONTRACT-PACT-STALE` | INFO | Verification exists but is old. Re-verification recommended. |

#### Contracts Configuration Extension

The existing `contracts:` configuration in `forge.local.md` is extended with pact-specific entries:

```yaml
contracts:
  # Existing OpenAPI contract
  - name: "api-contract"
    type: openapi
    source: api/openapi.yml
    consumer: ../frontend/src/api/
    baseline_branch: master
    breaking_change_severity: CRITICAL

  # New: Pact consumer contract
  - name: "frontend-pact"
    type: pact
    consumer_name: "frontend-app"
    provider_name: "backend-api"
    pact_source: broker              # broker | local | a2a
    broker_url: "https://pact-broker.internal"
    broker_token_env: "PACT_BROKER_TOKEN"
    local_pact_dir: "../frontend/.forge/pacts/"   # Used when pact_source: local
    provider_verification_command: "./gradlew pactVerify"
    can_i_deploy: true
    stale_threshold_days: 7

  # New: Specmatic contract
  - name: "api-specmatic"
    type: specmatic
    source: api/openapi.yml
    test_command: "npx specmatic test --host localhost --port 8080"
```

#### Pact Source Resolution

Three modes for locating consumer pacts:

| Source Mode | Description | Prerequisites |
|---|---|---|
| `broker` | Fetch pacts from a Pact broker (self-hosted or PactFlow) | `broker_url` configured, `broker_token_env` set |
| `local` | Read pact JSON files from a local directory (typically the consumer's `.forge/pacts/`) | `local_pact_dir` configured, directory accessible (filesystem or A2A HTTP transport) |
| `a2a` | Fetch pacts from the consumer's forge instance via A2A protocol | Consumer repo configured in `related_projects`, A2A transport available |

### Configuration

In `forge-config.md` (plugin-wide defaults):

```yaml
contract_testing:
  enabled: true                       # Master toggle for contract testing
  provider: auto                      # auto | pact | specmatic | spring-cloud-contract
  auto_detect: true                   # Detect from dependencies
  broker_url: ""                      # Pact broker URL (empty = no broker)
  broker_token_env: "PACT_BROKER_TOKEN"  # Environment variable for broker auth
  can_i_deploy: true                  # Run can-i-deploy check before shipping
  stale_threshold_days: 7             # Days before pact verification is considered stale
  provider_verification_timeout_s: 300  # Timeout for provider verification command
  publish_results: true               # Publish verification results back to broker
  tag_with_branch: true               # Tag pact versions with git branch name
```

| Parameter | Type | Default | Range | Description |
|---|---|---|---|---|
| `contract_testing.enabled` | boolean | `true` | -- | Master toggle |
| `contract_testing.provider` | string | `auto` | `auto`, `pact`, `specmatic`, `spring-cloud-contract` | Contract testing framework |
| `contract_testing.auto_detect` | boolean | `true` | -- | Detect from project dependencies |
| `contract_testing.broker_url` | string | `""` | Valid URL or empty | Pact broker URL |
| `contract_testing.broker_token_env` | string | `"PACT_BROKER_TOKEN"` | Valid env var name | Environment variable for broker auth token |
| `contract_testing.can_i_deploy` | boolean | `true` | -- | Run can-i-deploy check at SHIPPING |
| `contract_testing.stale_threshold_days` | integer | `7` | 1-90 | Staleness threshold for pact verifications |
| `contract_testing.provider_verification_timeout_s` | integer | `300` | 30-600 | Timeout for provider verification |
| `contract_testing.publish_results` | boolean | `true` | -- | Publish verification results to broker |
| `contract_testing.tag_with_branch` | boolean | `true` | -- | Tag pact versions with branch name |

### Data Flow

#### Auto-Detection (PREFLIGHT)

| Signal File / Pattern | Framework Detected | Confidence |
|---|---|---|
| `pact` in package.json / `pact` in requirements.txt / `pact-jvm` in build.gradle | Pact | HIGH |
| `@pactflow` in package.json / `pactflow` in build.gradle | PactFlow (SaaS broker) | HIGH |
| `specmatic` in package.json / `specmatic` in build.gradle | Specmatic | HIGH |
| `spring-cloud-contract` in build.gradle / pom.xml | Spring Cloud Contract | HIGH |
| `*.pact.json` files in project | Pact (local mode) | MEDIUM |

#### Contract Validation Flow (VALIDATING stage)

For each contract entry with `type: pact`:

```
1. RESOLVE PACT SOURCE
   |
   +-- broker: GET {broker_url}/pacts/provider/{provider_name}/latest
   +-- local: Read {local_pact_dir}/*.pact.json
   +-- a2a: GET {consumer_a2a_url}/files/.forge/pacts/{consumer_name}-{provider_name}.json
   |
   If no pacts found: emit CONTRACT-PACT-MISSING | WARNING
   |
2. RUN PROVIDER VERIFICATION
   |
   Execute provider_verification_command
   (e.g., ./gradlew pactVerify, npx pact-verifier)
   |
   Parse output for pass/fail per interaction
   |
   +-- All interactions pass: emit CONTRACT-PACT-PASS (not scored, logged only)
   +-- Any interaction fails: emit CONTRACT-PACT-FAIL | CRITICAL per failed interaction
   |
3. CHECK FOR PENDING PACTS
   |
   If broker: GET {broker_url}/pacts/provider/{provider_name}/for-verification
   Check for "pending" pacts (new consumer expectations)
   |
   +-- Pending pacts exist: emit CONTRACT-PACT-PENDING | WARNING per pending pact
   +-- No pending pacts: no finding
   |
4. CHECK STALENESS
   |
   If broker: check last verification date
   |
   +-- Last verified > stale_threshold_days ago: emit CONTRACT-PACT-STALE | INFO
   |
5. PUBLISH RESULTS
   |
   If publish_results: true and broker available:
   POST verification results to broker with git SHA and branch tag
```

#### Can-I-Deploy Gate (SHIPPING stage)

Integrated into `fg-590-pre-ship-verifier`:

```
1. If can_i_deploy: true and broker_url is configured:
   |
   Execute: pact-broker can-i-deploy \
     --pacticipant {provider_name} \
     --version {git_sha} \
     --to-environment production
   |
   +-- Success (exit 0): log "Can-I-Deploy: PASS for {provider_name}@{git_sha}"
   +-- Failure (exit 1): emit CONTRACT-PACT-FAIL | CRITICAL "Can-I-Deploy failed.
       One or more consumers have failing or missing pact verifications."
   |
2. If can_i_deploy: true and broker not configured:
   |
   Check local pact verification results from VALIDATE stage
   |
   +-- All passed: allow shipping
   +-- Any failed: block shipping with CRITICAL finding

3. Write result to .forge/evidence.json under "contract_verification":
   {
     "contract_verification": {
       "can_i_deploy": true/false,
       "provider": "{provider_name}",
       "version": "{git_sha}",
       "consumers_verified": 3,
       "consumers_pending": 0,
       "checked_at": "2026-04-13T14:00:00Z"
     }
   }
```

#### Consumer-Side Pact Generation

When forge detects the project is a pact consumer (pact dependency + consumer test files):

1. At IMPLEMENTING: implementer follows pact conventions when adding/changing API calls
   - Generate or update pact files from consumer tests
   - Pact files written to `.forge/pacts/` (or configured output directory)
2. At VERIFYING: test gate (fg-500) runs pact consumer tests
   - Ensures pact files are generated and valid
   - Generated pact files committed to `.forge/pacts/`
3. At SHIPPING: if broker configured, publish consumer pacts to broker
   - Tag with git branch and SHA
   - Webhook on broker notifies provider repos

### Integration Points

| Agent / System | Integration | Change Required |
|---|---|---|
| `fg-250-contract-validator` | Add `pact` analysis strategy to section 7 (Extension Points). Implement pact source resolution, provider verification, pending pact check, and staleness check. | Major enhancement — new strategy implementation alongside existing `openapi`. |
| `fg-590-pre-ship-verifier` | Add can-i-deploy check to shipping evidence requirements. Block SHIP if can-i-deploy fails. | Add contract verification section to evidence collection. |
| `fg-300-implementer` | Follow pact conventions when modifying API endpoints. Generate consumer pact files when project is a consumer. | No agent change — conventions loaded via standard composition. |
| `fg-500-test-gate` | Run pact consumer tests as part of test verification. Verify pact file generation. | Add pact test detection to test discovery. |
| `fg-103-cross-repo-coordinator` | Coordinate pact verification across producer and consumer repos. When consumer publishes new pact, notify producer. | Add pact publication event to cross-repo communication. |
| `/deploy` skill | Check can-i-deploy status before deploying producer. | Add pre-deploy contract check (similar to F23's flag check). |
| `modules/api-protocols/` | Add `pact/`, `specmatic/`, and `spring-cloud-contract/` directories. | New module files. |
| `shared/checks/category-registry.json` | Add `CONTRACT-PACT-FAIL`, `CONTRACT-PACT-PENDING`, `CONTRACT-PACT-MISSING`, `CONTRACT-PACT-STALE` categories. | Registry update. |
| `state-schema.md` | Add `contract_verification` section to evidence schema. | Schema extension. |
| F21 (A2A Network Protocol) | Use HTTP transport for fetching pacts from remote consumer repos (`pact_source: a2a`). | Depends on F21 for cross-machine pact exchange. |

#### Interaction with Existing Contract Validator

The `pact` strategy coexists with the existing `openapi` strategy:

| Aspect | OpenAPI Strategy (existing) | Pact Strategy (new) |
|---|---|---|
| Direction | Producer-side (diff against baseline) | Consumer-driven (verify against expectations) |
| What it checks | Schema-level breaking changes | Interaction-level contract compliance |
| Data source | git baseline vs current file | Pact broker / local pact files |
| Consumer analysis | Grep-based heuristic | Explicit consumer expectations |
| Finding categories | `CONTRACT-BREAK`, `CONTRACT-CHANGE`, `CONTRACT-ADD` | `CONTRACT-PACT-FAIL`, `CONTRACT-PACT-PENDING`, `CONTRACT-PACT-MISSING` |

Both strategies can run on the same contract entry if configured:
```yaml
contracts:
  - name: "api-contract"
    type: openapi
    source: api/openapi.yml
    # ... openapi config
  - name: "api-pact"
    type: pact
    provider_name: "backend-api"
    # ... pact config
```

### Error Handling

| Failure Mode | Behavior | Degradation |
|---|---|---|
| Pact broker unreachable | Log WARNING. If `pact_source: broker`, fall back to local pact files if `local_pact_dir` is configured. If neither available, skip pact verification with INFO. | Schema-level validation (openapi strategy) still runs. |
| Broker token invalid or expired | Log WARNING. Skip broker operations. Emit `CONTRACT-PACT-MISSING | WARNING`. | Same as broker unreachable. |
| Provider verification command fails (non-pact error) | Log CRITICAL: "Provider verification command failed: {error}". Emit `CONTRACT-PACT-FAIL | CRITICAL`. | Treat as verification failure — safe default. |
| Provider verification command not found | Log WARNING: "Provider verification command not found: {command}". Skip pact verification. | No pact verification for this run. |
| Pact file malformed (invalid JSON) | Log WARNING. Skip that specific pact. Continue with others. | Partial verification. |
| Consumer pact directory empty | Emit `CONTRACT-PACT-MISSING | WARNING`. | No pacts to verify. |
| can-i-deploy command not installed | Log INFO: "pact-broker CLI not found. Skipping can-i-deploy." Use local verification results instead. | Local verification as fallback. |
| A2A transport unavailable for pact_source: a2a | Fall back to broker, then local. Log INFO with fallback path. | Three-tier fallback. |
| Multiple consumers with conflicting pacts | Run all consumer pacts independently. Report failures per consumer. | All consumers verified, conflicts surfaced as separate findings. |

## Performance Characteristics

### Verification Timing

| Operation | Expected Duration | Variables |
|---|---|---|
| Fetch pacts from broker | 500ms-2s | Network latency, number of consumers |
| Fetch pacts locally | <100ms | File I/O |
| Fetch pacts via A2A HTTP | 1-5s | Network latency, file size |
| Provider verification | 10s-5min | Number of interactions, provider startup time, test complexity |
| Can-i-deploy check | 500ms-2s | Broker API latency |
| Publish results | 500ms-2s | Broker API latency |

### Token Impact

Pact verification is command-based (executed via Bash), not LLM-based. Token impact is limited to:
- Contract validator agent context: +200-400 tokens for pact strategy logic
- Findings output: 50-200 tokens per finding
- Evidence section: ~100 tokens
- Total: 500-1,000 additional tokens per run with pact contracts configured

### Scaling

| Consumers | Pact Interactions | Estimated Verification Time |
|---|---|---|
| 1-3 | 10-50 | 10-30s |
| 5-10 | 50-200 | 30s-2min |
| 10-20 | 200-500 | 2-5min |

Provider verification time scales linearly with interaction count. The `provider_verification_timeout_s` config (default 300s) provides a ceiling.

## Testing Approach

### Structural Tests

1. **Module structure:** `modules/api-protocols/pact/` contains `conventions.md`
2. **Module structure:** `modules/api-protocols/specmatic/` contains `conventions.md`
3. **Module structure:** `modules/api-protocols/spring-cloud-contract/` contains `conventions.md`
4. **Category codes:** `CONTRACT-PACT-*` codes in `category-registry.json`
5. **Agent extension:** `fg-250-contract-validator.md` lists `pact` in section 7 extension table

### Unit Tests (`tests/unit/pact-contracts.bats`)

1. **Pact source resolution (local):** Place `.pact.json` files in a temp directory, configure `local_pact_dir`, verify files are discovered
2. **Pact source resolution (broker):** Mock broker HTTP response, verify pacts are fetched and parsed
3. **Provider verification pass:** Mock verification command returning exit 0, verify no CRITICAL findings
4. **Provider verification fail:** Mock verification command returning exit 1 with failure details, verify `CONTRACT-PACT-FAIL | CRITICAL` finding
5. **Pending pact detection:** Mock broker response with pending pacts, verify `CONTRACT-PACT-PENDING | WARNING` finding
6. **Missing pact:** Configure consumer with no pact files, verify `CONTRACT-PACT-MISSING | WARNING` finding
7. **Can-i-deploy pass:** Mock `pact-broker can-i-deploy` returning exit 0, verify evidence records success
8. **Can-i-deploy fail:** Mock returning exit 1, verify CRITICAL finding and shipping blocked
9. **Staleness:** Mock broker response with verification date 14 days ago (threshold 7), verify `CONTRACT-PACT-STALE | INFO`
10. **Scoring integration:** Verify `CONTRACT-PACT-FAIL` deducts 20 points (CRITICAL weight)

### Integration Tests

1. **Full validation pipeline:** Configure a pact contract entry, run `/forge-run --dry-run`. Verify contract validator includes pact strategy execution.
2. **Coexistence:** Configure both openapi and pact entries for the same API. Verify both strategies run and produce independent findings.
3. **Cross-repo pact exchange:** Configure `pact_source: local` pointing to a sibling repo's `.forge/pacts/`. Verify pact files are read.

### Scenario Tests

1. **Producer breaks consumer:** Modify a provider endpoint to remove a field. Run pact verification. Verify CRITICAL finding with clear message about which consumer interaction fails.
2. **New consumer expectation:** Add a new pact interaction for a field the provider does not serve. Verify CRITICAL finding.
3. **Successful deployment gate:** All pacts pass, can-i-deploy succeeds, shipping evidence includes contract verification. Verify SHIP verdict is not blocked by contracts.

## Acceptance Criteria

1. `fg-250-contract-validator` implements a `pact` analysis strategy that runs Pact provider verification
2. Pact source resolution supports three modes: broker, local, and A2A
3. Failed provider verification produces `CONTRACT-PACT-FAIL | CRITICAL` with specific interaction details
4. Pending pacts produce `CONTRACT-PACT-PENDING | WARNING`
5. Can-i-deploy check runs at SHIPPING stage and blocks SHIP on failure
6. Verification results are published to the Pact broker when `publish_results: true`
7. `modules/api-protocols/pact/conventions.md` provides Dos/Don'ts for Pact usage
8. `modules/api-protocols/specmatic/conventions.md` provides alternative contract testing conventions
9. `modules/api-protocols/spring-cloud-contract/conventions.md` provides Spring-specific conventions
10. All `CONTRACT-PACT-*` categories are registered in `category-registry.json` and integrate with scoring
11. `./tests/validate-plugin.sh` passes with new modules and category codes
12. Graceful degradation: when broker is unreachable, fall back to local pacts; when no pacts exist, emit WARNING and continue

## Migration Path

1. **v2.0.0:** Ship `pact`, `specmatic`, and `spring-cloud-contract` modules as convention files.
2. **v2.0.0:** Enhance `fg-250-contract-validator` with `pact` strategy. Mark `protobuf`, `graphql`, `typescript-types` strategies as still "Future" in section 7.
3. **v2.0.0:** Add `contract_testing:` section to `forge-config-template.md` for Spring, NestJS, FastAPI, and Express frameworks.
4. **v2.0.0:** Add can-i-deploy check to `fg-590-pre-ship-verifier` evidence requirements.
5. **v2.0.0:** Add `CONTRACT-PACT-*` categories to `category-registry.json`.
6. **v2.1.0 (future):** Add `protobuf` strategy to contract validator using Buf breaking change detection.
7. **v2.1.0 (future):** Add `graphql` strategy using GraphQL Inspector.
8. **v2.2.0 (future):** Auto-generate consumer pact stubs from OpenAPI specs during IMPLEMENT.
9. **No breaking changes:** Existing `openapi` strategy contracts are unchanged. Pact is a new `type` option.

## Dependencies

**Depends on:**
- `fg-250-contract-validator` — existing contract validation agent (extended with new strategy)
- `fg-590-pre-ship-verifier` — shipping evidence gate (extended with can-i-deploy check)
- Pact CLI / provider verification tool (detected at PREFLIGHT, graceful degradation)
- Optional: Pact broker (self-hosted or PactFlow SaaS) for broker mode

**Depended on by:**
- No other F-series features directly depend on this. However, F21 (A2A Network Protocol) enables cross-machine pact exchange when `pact_source: a2a` is configured.
