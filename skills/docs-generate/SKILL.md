---
name: docs-generate
description: Generate or update project documentation on demand. Bootstraps full documentation suites for undocumented codebases or updates specific doc types. Supports README, architecture, ADRs, API docs, onboarding, runbooks, changelogs, diagrams, domain docs, user guides, migration guides.
---

# /docs-generate — On-Demand Documentation Generation

Generates project documentation independently of the pipeline. Run this skill at any time to bootstrap a full documentation suite for an undocumented codebase, update specific document types, or audit coverage gaps — without triggering a pipeline run or touching `.pipeline/` state.

## Arguments

Parse `$ARGUMENTS` for the following flags:

| Flag | Behavior |
|------|----------|
| (none) | Interactive mode — present coverage report, ask what to generate |
| `--all` | Generate full documentation suite (all supported types) |
| `--type <type>` | Generate specific type(s): `readme`, `architecture`, `adr`, `api-spec`, `onboarding`, `runbook`, `changelog`, `domain-model`, `user-guide`, `migration-guide`, `diagrams` |
| `--export` | After generation, push to configured external systems (Confluence, Notion, etc.) |
| `--coverage` | Report coverage only — no generation |
| `--from-code <path>` | Limit scope to a specific code path |
| `--confirm-decisions` | Interactive review of MEDIUM-confidence decisions before generation |

Multiple `--type` flags may be combined. `--from-code` applies as a scope filter to any generation step.

## What to do

### Step 1: Detect Framework

1. If `.claude/dev-pipeline.local.md` exists → read `components.framework` from it.
2. If absent → run stack marker detection (same heuristics as `/pipeline-init`):
   - `build.gradle.kts` + `.kt` files → `spring`
   - `package.json` + `vite.config.*` + React imports → `react`
   - `package.json` + `next.config.*` → `nextjs`
   - `package.json` + `svelte.config.*` + `@sveltejs/kit` → `sveltekit`
   - `package.json` + `svelte.config.*` (no kit) → `svelte`
   - `package.json` + `angular.json` → `angular`
   - `package.json` + `nest-cli.json` → `nestjs`
   - `package.json` + `nuxt.config.*` → `vue`
   - `Cargo.toml` + `axum` dependency → `axum`
   - `go.mod` present → `go-stdlib`
   - `requirements.txt` or `pyproject.toml` + FastAPI import → `fastapi`
   - `requirements.txt` or `pyproject.toml` + Django import → `django`
   - `Package.swift` + iOS/macOS targets → `swiftui`
   - `Package.swift` + Vapor dependency → `vapor`
   - `build.gradle.kts` + Android imports → `jetpack-compose`
   - `*.csproj` present → `aspnet`
   - `CMakeLists.txt` or `.c`/`.cpp` files only → `embedded`
   - Kubernetes manifests (`*.yaml` with `kind: Deployment`) → `k8s`
3. If detection fails → log INFO "Framework not detected; using generic conventions only."
4. Load conventions: generic documentation conventions + framework-specific binding if detected.

### Step 2: Run Discovery

- If `.pipeline/docs-index.json` exists and was last modified less than 1 hour ago → use it directly (skip re-discovery).
- Otherwise → dispatch `pl-130-docs-discoverer` to scan the codebase and produce a fresh `docs-index.json`.

### Step 3: Handle Arguments

#### `--coverage` (report only, no generation)

Present the coverage report and exit without generating anything:

```
## Documentation Coverage Report

Documented:       <list of existing docs with type labels>
Missing:          <list of doc types with no corresponding file>
Stale:            <docs whose source code has changed since last generation>
External Refs:    <references to external docs (Confluence, Notion, etc.)>

Coverage: {X}/{total} doc types present
```

#### `--confirm-decisions` (interactive review before generation)

List all MEDIUM-confidence decisions identified during discovery (e.g., inferred audience, assumed scope, guessed module boundaries). For each:
- Show the decision and its basis
- Prompt the user to upgrade to HIGH confidence (accept) or dismiss (skip that section)

Continue to the generation step once the user has reviewed all MEDIUM items.

#### `--all` or `--type <type>`

Dispatch `pl-350-docs-generator` in standalone mode with:
- `mode: standalone` (no pipeline state, no worktree)
- `types`: the requested type(s), or all types if `--all`
- `framework`: detected framework (or `null` if unknown)
- `scope`: path from `--from-code` if provided, otherwise full project root
- `confirm_decisions`: `true` if `--confirm-decisions` was also passed

#### Interactive (no args)

1. Present the coverage report (same as `--coverage`).
2. Ask: "Which documentation would you like to generate?" with a numbered list of missing/stale types.
3. Accept user selection (single type, multiple types, or "all").
4. Dispatch `pl-350-docs-generator` in standalone mode with the selected types.

#### `--from-code <path>`

Pass the provided path as the `scope` filter when dispatching `pl-350-docs-generator`. All other argument handling applies normally.

### Step 4: Report Results

After generation completes, show a summary:

```
## Documentation Generation Complete

Created:
  - {file path} ({doc type})
  ...

Updated:
  - {file path} ({doc type})
  ...

Coverage delta: {before}% → {after}%
```

If `--export` was passed and external systems are configured, report export status per system. If export is not configured, log INFO "No external export targets configured; skipping --export."

## Important

- Do NOT create `.pipeline/` or `state.json` — this skill operates entirely outside pipeline state.
- Do NOT create a worktree — all writes go directly to the project working tree.
- If generation produces no useful content for a doc type (e.g., no API endpoints found for `api-spec`), skip that type and log INFO "Skipped {type}: no source content found."
- This skill may be run at any time, including mid-pipeline — it does not interact with pipeline state.
