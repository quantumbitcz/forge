---
name: migration
description: Plan and execute a library or framework migration using the migration planner agent
disable-model-invocation: false
---

# Migration Assistant

Plan and execute a library or framework migration.

Dispatches `pl-160-migration-planner` to handle the migration in phases.

## Usage

Provide a description of what to migrate:

```
/migration Upgrade Spring Boot from 3.2 to 3.4
/migration Migrate from Moment.js to date-fns
/migration Update React from 18 to 19
```

### Usage Patterns

| Command | Behavior |
|---------|----------|
| `/migration upgrade Spring Boot` | Auto-detect current version, propose latest stable target, show analysis |
| `/migration upgrade Spring Boot to 3.4` | Auto-detect current, use specified target |
| `/migration upgrade Spring Boot from 3.2 to 3.4` | Use both specified versions |
| `/migration upgrade all` | Detect ALL outdated dependencies, propose upgrades, prioritize by risk |
| `/migration check` | Dry-run: detect all outdated deps, show what WOULD be upgraded, no changes |

### Version Auto-Detection

When versions are not explicitly specified:
- Read `state.json.detected_versions` if available (from a previous pipeline run)
- Otherwise detect from project manifest files
- For `upgrade all`: scan all dependencies, compare with registry latest, filter by: security patches first, then minor upgrades, then major upgrades
- Present a prioritized table before proceeding:

    ## Upgrade Candidates

    | Package | Current | Latest | Change | Risk | Action |
    |---------|---------|--------|--------|------|--------|
    | spring-boot | 3.2.4 | 3.4.1 | minor | LOW | Auto |
    | spring-security | 6.1.0 | 6.3.2 | minor | LOW | Auto |
    | kotlin | 1.9.22 | 2.0.10 | major | HIGH | Confirm |

    Proceed with LOW-risk upgrades? (HIGH-risk requires explicit confirmation)

## What happens

The migration planner will:
1. **Detect** — auto-detect current and target versions, analyze breaking changes (skipped if versions are explicit)
2. **Audit** — find all usages of the old library/version
3. **Prepare** — create adapter/shim if needed for gradual migration
4. **Migrate** — batch-by-batch file migration with rollback on failure
5. **Cleanup** — remove old dependencies and adapters
6. **Verify** — run full build + test suite

Each batch gets its own commit for independent rollback.

### Context7 Integration for Migration

When Context7 MCP is available, the migration planner uses it for:
1. **Migration guide lookup:** Query for official upgrade guides between versions
2. **Breaking change analysis:** Extract API changes, removals, renames from changelogs
3. **Replacement mapping:** Build old-API → new-API mapping from documentation
4. **Configuration changes:** Detect renamed/removed config properties

When Context7 is unavailable, fallback to:
1. CHANGELOG.md / CHANGES.md in the dependency's repository
2. Package registry metadata (npm, Maven Central, PyPI, crates.io)
3. Known-deprecations.json entries matching the version range
4. Conservative migration (compile, test, fix iteratively)

## Dispatch Instructions

You are a thin launcher. Your ONLY job is to dispatch the migration planner agent.

1. **Parse input**: The user's argument (everything after `/migration`) is the migration description — a free-text string like "Upgrade Spring Boot from 3.2 to 3.4" or "Migrate from Moment.js to date-fns". It may also be a keyword command like `check` or `upgrade all`.

2. **Detect available MCPs**: Before dispatching, check whether Context7 is available by looking for `mcp__plugin_context7_context7__*` tool patterns. Include this in the dispatch prompt so the planner knows whether to use Context7 for migration guide lookups.

3. **Dispatch the migration planner**: Use the Agent tool to invoke `pl-160-migration-planner` with the following prompt:

   > Plan and execute migration: `{user_input}`
   >
   > Context7 available: `{yes|no}`

   Where `{user_input}` is the raw text the user provided.

4. **Do nothing else**: Do not analyze dependencies, modify files, or make migration decisions. The migration planner handles detection, auditing, migration, cleanup, and verification autonomously.

5. **Relay the result**: When the migration planner completes, relay its final output (migration summary, rollback instructions, or escalation) back to the user unchanged.
