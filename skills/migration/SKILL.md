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

## What happens

The migration planner will:
1. **Audit** — find all usages of the old library/version
2. **Prepare** — create adapter/shim if needed for gradual migration
3. **Migrate** — batch-by-batch file migration with rollback on failure
4. **Cleanup** — remove old dependencies and adapters
5. **Verify** — run full build + test suite

Each batch gets its own commit for independent rollback.

$ARGUMENTS
