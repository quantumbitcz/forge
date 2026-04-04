---
name: istanbul
categories: [coverage]
languages: [javascript, typescript]
exclusive_group: js-coverage
recommendation_score: 90
detection_files: [.nycrc, .nycrc.json, .c8rc, nyc.config.js, package.json]
---

# istanbul

## Overview

Istanbul is the JavaScript/TypeScript coverage instrumentation library. The modern CLI is `c8` (uses V8's built-in coverage — no instrumentation overhead) or `nyc` (Istanbul's legacy CLI, transforms source). Vitest and Jest expose Istanbul-compatible coverage through `--coverage` flags. `c8` is preferred for Node.js 18+ because it reads V8's native coverage data and handles ESM without transpilation. `.nycrc` / `.c8rc` configures thresholds, reporters, and include/exclude patterns.

## Architecture Patterns

### Installation & Setup

**c8 (V8 coverage — preferred for Node.js ESM/CJS):**
```bash
npm install --save-dev c8
```
```json
// package.json
{
  "scripts": {
    "test": "node --test",
    "coverage": "c8 --check-coverage --lines 80 --branches 70 --functions 85 --statements 80 node --test"
  }
}
```

**nyc (Istanbul CLI — for CommonJS or legacy setups):**
```bash
npm install --save-dev nyc
```
```json
// package.json
{
  "scripts": {
    "coverage": "nyc --check-coverage --lines 80 mocha"
  }
}
```

**Vitest (built-in Istanbul or V8 provider):**
```bash
npm install --save-dev @vitest/coverage-v8
# or Istanbul instrumentation:
npm install --save-dev @vitest/coverage-istanbul
```
```ts
// vitest.config.ts
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    coverage: {
      provider: "v8",           // or "istanbul"
      reporter: ["text", "html", "lcov"],
      reportsDirectory: "coverage",
      thresholds: {
        lines: 80,
        branches: 70,
        functions: 85,
        statements: 80,
        perFile: false,         // set true to enforce per-file minimums
      },
      include: ["src/**/*.{ts,tsx}"],
      exclude: [
        "src/**/*.d.ts",
        "src/**/*.test.ts",
        "src/**/*.spec.ts",
        "src/**/index.ts",      // barrel files — no logic
        "src/generated/**",
      ],
    },
  },
});
```

**Jest:**
```js
// jest.config.js
module.exports = {
  collectCoverageFrom: ["src/**/*.{js,ts}", "!src/**/*.d.ts", "!src/generated/**"],
  coverageReporters: ["text", "html", "lcov"],
  coverageDirectory: "coverage",
  coverageThreshold: {
    global: {
      lines: 80,
      branches: 70,
      functions: 85,
      statements: 80,
    },
  },
};
```

### Rule Categories

| Metric | Description | Recommended |
|---|---|---|
| `statements` | Executable statements run | 80% |
| `branches` | True/false branches taken | 70% |
| `functions` | Functions called at least once | 85% |
| `lines` | Source lines touched | 80% |

### Configuration Patterns

**`.nycrc` (nyc config file):**
```json
{
  "extends": "@istanbuljs/nyc-config-typescript",
  "include": ["src/**/*.ts"],
  "exclude": ["src/**/*.spec.ts", "src/generated/**"],
  "reporter": ["text", "html", "lcov"],
  "branches": 70,
  "lines": 80,
  "functions": 85,
  "statements": 80,
  "check-coverage": true,
  "all": true,
  "source-map": true,
  "instrument": true
}
```

**Per-file threshold enforcement (Vitest):**
```ts
coverage: {
  thresholds: {
    perFile: true,
    lines: 70,      // lower per-file minimum is realistic
    branches: 60,
  },
}
```

**Inline coverage ignore comments:**
```ts
/* istanbul ignore next */
function unreachableErrorBranch() { throw new Error("impossible"); }

/* c8 ignore next 3 */
if (process.env.NODE_ENV === "development") {
  setupDevTools();
}
```

### CI Integration

```yaml
# .github/workflows/test.yml
- name: Run tests with coverage
  run: npx vitest run --coverage

- name: Upload coverage to Codecov
  uses: codecov/codecov-action@v4
  with:
    files: coverage/lcov.info
    fail_ci_if_error: true

- name: Upload HTML coverage report
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: coverage-report
    path: coverage/
```

**PR coverage comment (Vitest):**
```yaml
- name: Coverage comment
  uses: davelosert/vitest-coverage-report-action@v2
  with:
    json-summary-path: coverage/coverage-summary.json
    json-final-path: coverage/coverage-final.json
```

## Performance

- `c8` with V8 coverage adds negligible overhead vs `nyc` which instruments source before execution (adds 5-20% run time for large TS projects).
- Use `--reporter=text` only in CI; `html` generation is slow — generate it only on failure or in a separate `coverage:report` script.
- `all: true` in nyc config instruments all files (including untested ones) — accurate but slower. Omit for large repos where cold starts matter.
- Run coverage only in CI or pre-merge, not on every local test run — `npm test` without coverage keeps the local feedback loop fast.

## Security

- Coverage reports do not expose secret values — they reflect which lines executed, not variable values.
- `lcov.info` and coverage JSON are safe to upload to external services (Codecov, Coveralls) — they contain file paths and counts only.
- Do not expose HTML coverage reports publicly if source code is proprietary — HTML embeds actual source lines.

## Testing

```bash
# c8: run tests and check coverage thresholds
npx c8 --check-coverage --lines 80 --branches 70 --functions 85 node --test

# Vitest: run with V8 coverage
npx vitest run --coverage

# Jest: run with coverage
npx jest --coverage

# nyc: run mocha with istanbul
npx nyc --check-coverage mocha

# View HTML report
open coverage/index.html

# Print lcov summary
npx c8 report --reporter=text-summary
```

## Dos

- Use `c8` (V8) for Node.js 18+ ESM projects — avoids transpilation, handles `import.meta`, and is faster than Istanbul instrumentation.
- Enable `lcov` reporter in CI — it is the standard format consumed by GitHub Actions, Codecov, and Sonar.
- Set `all: true` (nyc) or `include` patterns to instrument files that have no tests — zero-coverage files are hidden otherwise.
- Use `perFile: true` thresholds to catch low-coverage new files rather than relying on the global average masking them.
- Exclude generated files, barrel `index.ts` re-exports, type-only files, and test files themselves from coverage targets.
- Pin the coverage provider version — `@vitest/coverage-v8` minor releases occasionally change branch counting behavior.

## Don'ts

- Don't set `branches` threshold equal to `lines` — branch coverage is harder to achieve; 70% branches with 80% lines is a realistic pair.
- Don't use `/* istanbul ignore */` to suppress coverage gaps in business logic — use it only for platform-specific guards or truly unreachable defensive code.
- Don't run `--coverage` on every `npm test` invocation locally — the overhead slows the feedback loop and discourages running tests frequently.
- Don't rely on statement coverage alone — 100% statement coverage is achievable without ever exercising the false branch of a conditional.
- Don't mix `nyc` and `c8` in the same project — they produce different `.json` formats and can double-count or conflict in monorepos.
