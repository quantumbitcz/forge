# Bun with Angular

> Extends `modules/build-systems/bun.md` with Angular CLI build patterns.
> Generic Bun conventions (workspaces, lockfile, script runner) are NOT repeated here.

## Integration Setup

```json
// package.json
{
  "scripts": {
    "start": "ng serve",
    "build": "ng build --configuration production",
    "test": "ng test --no-watch --browsers=ChromeHeadless",
    "lint": "ng lint",
    "format": "bunx prettier --write ."
  }
}
```

Angular CLI (`ng`) runs on Node.js internally, so `bun run` delegates to Node for Angular commands. Bun's value here is faster dependency installation and script launching, not replacing the Angular compiler.

## Framework-Specific Patterns

### Dependency Installation

```bash
bun install                        # install all deps (uses bun.lockb)
bun add @angular/core @angular/common  # add Angular packages
bun add -d @angular/cli            # add CLI as dev dep
```

Commit `bun.lockb` for reproducible builds. Run `bun install --frozen-lockfile` in CI.

### Angular Build Configuration

```json
// angular.json (build section)
{
  "architect": {
    "build": {
      "builder": "@angular-devkit/build-angular:application",
      "options": {
        "outputPath": "dist/app",
        "index": "src/index.html",
        "browser": "src/main.ts",
        "tsConfig": "tsconfig.app.json"
      },
      "configurations": {
        "production": {
          "budgets": [
            { "type": "initial", "maximumWarning": "500kB", "maximumError": "1MB" }
          ],
          "outputHashing": "all"
        }
      }
    }
  }
}
```

### Bundle Budgets

Angular's built-in bundle budget enforcement in `angular.json` catches size regressions at build time. Set `maximumWarning` to flag gradual growth and `maximumError` to fail the build on critical bloat.

### esbuild (Angular 17+)

Angular 17+ uses the `application` builder backed by esbuild and Vite. It is significantly faster than the legacy webpack-based `browser` builder. Ensure `angular.json` uses `@angular-devkit/build-angular:application` (not `:browser`).

## Scaffolder Patterns

```yaml
patterns:
  package_json: "package.json"
  angular_json: "angular.json"
  tsconfig: "tsconfig.json"
```

## Additional Dos

- DO use Bun for dependency installation speed while keeping Angular CLI for builds
- DO commit `bun.lockb` and use `--frozen-lockfile` in CI
- DO configure bundle budgets in `angular.json` to catch size regressions early
- DO use the `application` builder (Angular 17+) for esbuild-powered faster builds

## Additional Don'ts

- DON'T replace `ng build` with a custom Vite/esbuild setup -- Angular CLI handles AOT, i18n, and budgets
- DON'T mix `bun.lockb` with `package-lock.json` -- choose one package manager
- DON'T skip `--configuration production` in CI builds -- it enables AOT, tree-shaking, and budgets
