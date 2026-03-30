# stryker

## Overview

Stryker Mutator is the mutation testing framework for JavaScript, TypeScript, and C#. It injects faults into source code (not bytecode) and verifies that your test suite kills the resulting mutants. JS/TS projects use `@stryker-mutator/core` with framework-specific runners (Jest, Vitest, Jasmine); C# projects use `dotnet-stryker` as a .NET global tool. Stryker generates HTML and JSON reports; the dashboard reporter pushes results to the Stryker Dashboard for trend tracking across branches. A mutation score below 60 indicates tests that assert on the wrong things or have missing negative-path coverage.

## Architecture Patterns

### Installation & Setup

**JavaScript / TypeScript:**
```bash
npm install --save-dev @stryker-mutator/core @stryker-mutator/jest-runner
# or for Vitest projects:
npm install --save-dev @stryker-mutator/core @stryker-mutator/vitest-runner
```

```javascript
// stryker.conf.js
/** @type {import('@stryker-mutator/api/core').PartialStrykerOptions} */
module.exports = {
  packageManager: 'npm',
  reporters: ['html', 'clear-text', 'progress', 'dashboard'],
  testRunner: 'jest',             // or 'vitest'
  coverageAnalysis: 'perTest',    // skip running against tests that don't cover the mutant
  mutate: [
    'src/**/*.ts',
    '!src/**/*.spec.ts',
    '!src/**/*.test.ts',
    '!src/**/*.d.ts',
    '!src/**/generated/**',
    '!src/**/__mocks__/**'
  ],
  mutator: {
    excludedMutations: ['StringLiteral'] // noisy in i18n-heavy code
  },
  thresholds: {
    high: 80,
    low: 60,
    break: 50        // exit non-zero (fail CI) below 50
  },
  timeoutMS: 10000,
  timeoutFactor: 2.5,
  concurrency: 4,    // parallel test runner processes
  dashboard: {
    project: 'github.com/your-org/your-repo',
    version: process.env.GITHUB_REF_NAME || 'main',
    baseUrl: 'https://dashboard.stryker-mutator.io',
    reportType: 'full'
  },
  disableTypeChecks: true,   // faster — type errors won't surface mutations anyway
  incremental: true,         // cache results; re-test only changed files
  incrementalFile: '.stryker-tmp/incremental.json'
};
```

**TypeScript variant (tsconfig-aware):**
```javascript
// stryker.conf.js addition for TypeScript
module.exports = {
  // ...base config
  testRunner: 'jest',
  jest: {
    projectType: 'custom',
    configFile: 'jest.config.ts',
    enableFindRelatedTests: true  // map mutant → only covering tests
  }
};
```

**C# (.NET):**
```bash
# Install as global tool
dotnet tool install --global dotnet-stryker

# or as local tool (recommended for team projects)
dotnet new tool-manifest   # creates .config/dotnet-tools.json if not present
dotnet tool install dotnet-stryker
```

```json
// stryker-config.json (place alongside .csproj)
{
  "stryker-config": {
    "project": "MyApp.csproj",
    "test-projects": ["../MyApp.Tests/MyApp.Tests.csproj"],
    "target-framework": "net8.0",
    "mutation-level": "Standard",
    "mutate": ["src/**/*.cs", "!src/**/Migrations/**", "!src/**/*.g.cs"],
    "reporters": ["html", "json", "dashboard"],
    "threshold-high": 80,
    "threshold-low": 60,
    "threshold-break": 50,
    "concurrency": 4,
    "since": {
      "enabled": true,
      "target": "main"          // incremental: only mutate files changed vs main
    },
    "dashboard": {
      "project": "github.com/your-org/your-repo",
      "version": "main"
    }
  }
}
```

### Rule Categories

| Mutator | JS/TS Name | What it changes |
|---|---|---|
| Arithmetic | `ArithmeticOperator` | `+` → `-`, `*` → `/`, `%` → `*` |
| Boolean | `BooleanLiteral` | `true` → `false`, `!x` → `x` |
| Conditional | `ConditionalExpression` | `a ? b : c` → `b` or `c` always |
| Equality | `EqualityOperator` | `===` → `!==`, `>` → `>=` |
| Logical | `LogicalOperator` | `&&` → `\|\|`, `\|\|` → `&&` |
| String | `StringLiteral` | `"foo"` → `""` |
| Block statement | `BlockStatement` | Removes entire function body |
| Update | `UpdateOperator` | `++i` → `--i` |
| Optional chaining | `OptionalChaining` | `a?.b` → `a.b` (removes guard) |

### Configuration Patterns

**Scope to business logic, exclude infrastructure:**
```javascript
mutate: [
  'src/domain/**/*.ts',
  'src/application/**/*.ts',
  'src/utils/**/*.ts',
  '!src/**/*.spec.ts',
  '!src/**/*.test.ts',
  '!src/infrastructure/**',   // DB adapters, HTTP clients
  '!src/config/**',
  '!src/generated/**',
  '!src/migrations/**'
]
```

**Per-file mutation override (disable noisy mutators in specific files):**
```javascript
// stryker.conf.js
mutator: {
  plugins: [],
  excludedMutations: [],
  // Disable StringLiteral globally — noisy in validation error message files
},
// Or use inline comments in source:
// Stryker disable StringLiteral: noisy in error message catalog
```

### CI Integration

```yaml
# .github/workflows/mutation.yml
- name: Restore Stryker incremental cache
  uses: actions/cache@v4
  with:
    path: .stryker-tmp/
    key: stryker-${{ github.ref }}-${{ github.sha }}
    restore-keys: |
      stryker-${{ github.ref }}-
      stryker-

- name: Run mutation tests
  run: npx stryker run
  env:
    STRYKER_DASHBOARD_API_KEY: ${{ secrets.STRYKER_DASHBOARD_API_KEY }}

- name: Upload Stryker HTML report
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: stryker-report
    path: reports/mutation/

# C# variant:
- name: Run dotnet-stryker
  run: dotnet stryker --config-file stryker-config.json
  working-directory: src/MyApp
```

## Performance

- Use `coverageAnalysis: 'perTest'` (JS/TS) — Stryker maps each mutant to only the tests that cover it, skipping the full suite for uncovered lines. This is the single biggest speedup (3-10×).
- Enable `incremental: true` and cache `.stryker-tmp/incremental.json` in CI — unchanged files are skipped on re-runs.
- Use `concurrency: N` matching available CPU cores — each worker runs an isolated test process.
- `disableTypeChecks: true` in JS/TS removes TypeScript compilation overhead per mutant — type errors don't change mutation behavior.
- For C#, `--since main` mode runs only on files changed relative to a base branch — ideal for PR checks.
- Split `mutate` globs to exclude slow integration tests; reserve mutation testing for unit-tested domain code.

## Security

- Stryker runs mutated source in isolated child processes — mutants cannot escape the sandbox or modify files on disk.
- Stryker Dashboard API key (`STRYKER_DASHBOARD_API_KEY`) is the only secret required — store in CI secrets, never in `stryker.conf.js`.
- HTML reports contain source code snippets with surviving mutants highlighted — treat as internal artifacts; do not publish to public URLs.
- `dotnet-stryker` executes `dotnet test` in temp directories — no production assemblies are modified.

## Testing

```bash
# JS/TS: run full mutation suite
npx stryker run

# JS/TS: run only for changed files (requires incremental config)
npx stryker run --incremental

# C#: run mutation tests
dotnet stryker

# C#: incremental since main branch
dotnet stryker --since main

# View HTML report locally (JS/TS)
open reports/mutation/index.html

# View HTML report locally (C#)
open StrykerOutput/*/reports/mutation-report.html

# Print surviving mutants summary
npx stryker run 2>&1 | grep -E 'Survived|Timeout|Score'
```

## Dos

- Set `thresholds.break` in JS/TS (or `threshold-break` in C#) to fail CI when mutation score drops below an absolute floor — without it, regressions go undetected.
- Use `coverageAnalysis: 'perTest'` for all JS/TS projects with Jest or Vitest — it is always faster and never reduces accuracy.
- Enable incremental mode and cache the state file in CI — the first run is slow; subsequent incremental runs are fast.
- Scope `mutate` to domain/application code only — infrastructure adapters (HTTP clients, database repositories) generate noisy, low-value mutants.
- Review surviving `BlockStatement` mutants — they indicate entire functions that are never verified to have a return value effect, which is a high-risk gap.
- For C# projects, pin `dotnet-stryker` as a local tool in `.config/dotnet-tools.json` — ensures all team members and CI use the same version.

## Don'ts

- Don't run Stryker on every commit without incremental mode on large codebases — a full run on 10k+ lines can take 30+ minutes.
- Don't set `break` threshold to 80+ on a project first adopting mutation testing — start at 50, measure surviving mutants, raise the bar iteratively.
- Don't add `StringLiteral` to the mutator set for i18n-heavy code — translation key mutations are unkillable without testing every locale string.
- Don't ignore surviving `LogicalOperator` mutants (`&&` → `||`) — they indicate missing boundary tests for compound conditions, which are common sources of production bugs.
- Don't commit `stryker-config.json` with a hardcoded `dashboard.version` — use an environment variable so PR builds report against the correct branch.
- Don't use `--open-report` flag in CI — it blocks the process waiting for a browser.
