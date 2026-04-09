# Cross-Repo Contract-First Protocol

When a feature spans multiple repositories (e.g., backend + frontend), establish API contracts BEFORE implementation to prevent integration failures.

## Protocol

### 1. Contract Identification (PLAN stage)

The planner identifies shared contracts affected by the requirement:
- OpenAPI specs (`*.yaml`, `*.json` in api/ or openapi/ directories)
- Protocol Buffers (`*.proto`)
- GraphQL schemas (`*.graphql`, `*.gql`)
- Shared TypeScript types (in shared/ or types/ directories)
- Database migration schemas affecting cross-service queries

### 2. Contract Agreement (within VALIDATING state)

After the validator returns GO but before transitioning to IMPLEMENTING:

a. **Generate contract stub** from the plan (schema changes only, no implementation logic)
b. **Validate stub** against both producer and consumer expectations:
   - Producer: can the planned implementation satisfy this contract?
   - Consumer: does this contract provide what the consumer needs?
c. **Commit contract stub** to both repo branches (via cross-repo coordinator)
d. **Only after agreement**: proceed to IMPLEMENT on both sides

This is implemented as a sub-step within the VALIDATING state, not a new top-level state. It runs after `verdict_GO` and before the transition to IMPLEMENTING. No new transition table rows are needed — the orchestrator handles it as conditional logic within the VALIDATING → IMPLEMENTING transition, similar to how contract validation (fg-250) already works.

If contract agreement fails, it routes back to PLANNING (increment `validation_retries`).

### 3. Contract Checkpoint (VERIFY stage)

At VERIFY, both sides validate their implementation matches the agreed contract stub:
- Producer: API responses match the contract schema
- Consumer: API requests match the contract schema
- Mismatches are reported as CRITICAL findings

### 4. Integration Verification (pre-SHIP gate)

Before creating PRs for cross-repo features:
1. Check if both repos have `commands.integration_test` configured
2. If yes: run integration tests that exercise the contract boundary
3. If tests fail: report findings, block PR creation for both repos
4. If no integration tests configured: skip with advisory warning

## Bi-directional Dependencies

When both sides need each other's output (e.g., FE needs BE contract, BE needs FE data model):
1. Both sides implement to the contract stub (not to each other's actual code)
2. Contract stub serves as the stable interface
3. Integration verification happens at SHIP, not during IMPLEMENT

This prevents circular dependency deadlocks. The contract stub is the source of truth during implementation.

## Configuration

In `forge.local.md`:
```yaml
cross_repo:
  contract_first: true      # Enable contract-first protocol (default: true when related_projects configured)
  integration_test: true     # Run integration tests at SHIP (default: false)
  timeout_minutes: 30        # Cross-repo operation timeout
```
