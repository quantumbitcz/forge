---
name: forge-migration
description: "[writes] Plan and execute a library or framework migration using the migration planner agent (fg-160). Use when upgrading major framework versions (e.g., Spring Boot 2→3, Angular 16→17), migrating between libraries (e.g., Enzyme→Testing Library), or checking for breaking changes before upgrading."
allowed-tools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'Agent']
disable-model-invocation: false
---

# /forge-migration -- Migration Assistant

Plan and execute a library or framework migration.

Dispatches `fg-160-migration-planner` to handle the migration in phases.

## Flags

- **--help**: print usage and exit 0
- **--dry-run**: preview actions without writing

## Exit codes

See `shared/skill-contract.md` for the standard exit-code table.

## Instructions

Provide a description of what to migrate:

```
/migration Upgrade Spring Boot from 3.2 to 3.4
/migration Migrate from Moment.js to date-fns
/migration Update React from 18 to 19
```

### Usage Patterns

| Command | Behavior |
|---------|----------|
| `/forge-migration upgrade Spring Boot` | Auto-detect current version, propose latest stable target, show analysis |
| `/forge-migration upgrade Spring Boot to 3.4` | Auto-detect current, use specified target |
| `/forge-migration upgrade Spring Boot from 3.2 to 3.4` | Use both specified versions |
| `/forge-migration upgrade all` | Detect ALL outdated dependencies, propose upgrades, prioritize by risk |
| `/forge-migration check` | Dry-run: detect all outdated deps, show what WOULD be upgraded, no changes |

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

## Prerequisites

Before dispatching the migration planner, verify:

1. **Git repository:** Run `git rev-parse --is-inside-work-tree`. If not: "Not a git repository."
2. **Clean working tree recommended:** Run `git status --porcelain`. If dirty, warn: "You have uncommitted changes. Migrations create commits per batch — consider committing or stashing first."

## What to Expect

After dispatch, fg-160-migration-planner will:
1. Detect current version from project manifests
2. Query Context7 for breaking changes between versions
3. Create a phased migration plan with per-batch commits
4. Execute batches with rollback points between each
5. Verify each batch passes tests before proceeding

Total time: 10-45 minutes depending on version gap. High-risk upgrades will ask for confirmation.

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

1. **Parse input**: The user's argument (everything after `/forge-migration`) is the migration description — a free-text string like "Upgrade Spring Boot from 3.2 to 3.4" or "Migrate from Moment.js to date-fns". It may also be a keyword command like `check` or `upgrade all`.

2. **Detect available MCPs**: Detect available MCPs per `shared/mcp-detection.md` detection table. For each MCP, check if its probe tool is available. Mark unavailable MCPs as degraded and apply the documented degradation behavior. Include Context7 availability in the dispatch prompt so the planner knows whether to use it for migration guide lookups.

3. **Dispatch the migration planner**: Use the Agent tool to invoke `fg-160-migration-planner` with the following prompt:

   > Plan and execute migration: `{user_input}`
   >
   > Context7 available: `{yes|no}`

   Where `{user_input}` is the raw text the user provided.

4. **Do nothing else**: Do not analyze dependencies, modify files, or make migration decisions. The migration planner handles detection, auditing, migration, cleanup, and verification autonomously.

5. **Relay the result**: When the migration planner completes, relay its final output (migration summary, rollback instructions, or escalation) back to the user unchanged.

## Error Handling

| Condition | Action |
|-----------|--------|
| Prerequisites fail | Report specific error message and STOP |
| Empty input (no migration description) | Ask user what to migrate: "What would you like to migrate? e.g., 'Upgrade Spring Boot from 3.2 to 3.4'" |
| Migration planner dispatch fails | Report "Migration planner failed to start. Check plugin installation." and STOP |
| Migration planner returns error | Relay the error unchanged. Each batch has its own commit for independent rollback |
| Context7 unavailable | Migration planner falls back to CHANGELOG analysis and conservative migration. Log INFO |
| Version detection fails | Migration planner will ask user for current and target versions interactively |
| Build/test fails after batch | Migration planner handles rollback of the failed batch. Suggest reviewing rollback instructions |
| State corruption | Suggest `/forge-repair-state` to fix state, then retry |

## See Also

- `/forge-run` -- Full pipeline entry point (use `migrate:` prefix for migration routing)
- `/forge-rollback` -- Rollback migration changes if something goes wrong
- `/forge-diagnose` -- Diagnose pipeline health if the migration stalls
- `/forge-config-validate` -- Validate configuration before starting a migration
