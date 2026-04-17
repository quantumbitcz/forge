---
name: forge-security-audit
description: "[read-only] Run module-appropriate security scanners and aggregate vulnerability results. Use when preparing for a release, after dependency updates, when reviewing third-party package security, or when onboarding to a new codebase to assess its security posture."
allowed-tools: ['Read', 'Bash', 'Glob', 'Grep']
disable-model-invocation: false
---

# /forge-security-audit -- Security Audit

Run security vulnerability scanners appropriate for the current module.

## Flags

- **--help**: print usage and exit 0
- **--json**: structured JSON output

## Exit codes

See `shared/skill-contract.md` for the standard exit-code table.

## Prerequisites

Before any action, verify:

1. **Git repository:** Run `git rev-parse --show-toplevel 2>/dev/null`. If fails: report "Not a git repository. Navigate to a project directory." and STOP.
2. **Forge initialized:** Check `.claude/forge.local.md` exists. If not: try to detect the module from project files (package.json, build.gradle.kts, Cargo.toml, go.mod, etc.). If detection also fails: report "Could not detect project type. Run `/forge-init` to configure, or specify the framework manually." and STOP.
3. **Scanner available:** Verify at least one appropriate scanner is installed for the detected framework (see scanner table below). If none: report which scanner to install and how.

## Instructions

1. Read `.claude/forge.local.md` for the `components` section (language, framework)
   - If the file does not exist: try to detect the module from project files (package.json, build.gradle.kts, Cargo.toml, go.mod, etc.)

2. Run the appropriate scanner based on module:

   | Framework | Scanner Command | Fallback |
   |-----------|----------------|----------|
   | react, nextjs, sveltekit, express, angular, nestjs, vue, svelte | `npm audit --json` or `pnpm audit --json` or `bun audit` | `npx auditjs` |
   | spring (kotlin or java) | `./gradlew dependencyCheckAnalyze` | Manual check of build.gradle.kts |
   | fastapi, django | `pip-audit` or `safety check` | `pip list --outdated` |
   | axum | `cargo audit` | `cargo deny check` |
   | go-stdlib, gin | `govulncheck ./...` | `go list -m -json all` |
   | swiftui, vapor | Manual review of Package.resolved | -- |
   | jetpack-compose, kotlin-multiplatform, scala (sbt) | `./gradlew dependencyCheckAnalyze` or `sbt dependencyCheck` | Manual check of build file |
   | aspnet | `dotnet list package --vulnerable` | Manual check of .csproj |
   | embedded | `cppcheck --enable=all src/` | -- |
   | k8s | `trivy config .` or `kubeaudit all` | `helm lint charts/` |
   | ruby | `bundler-audit check` or `bundle audit` | `gem list --outdated` |
   | php | `composer audit` or `local-php-security-checker` | `composer outdated` |
   | elixir | `mix deps.audit` or `mix sobelow` | `mix hex.audit` |

3. Aggregate results:
   ```
   ## Security Audit Results

   - Critical: {count}
   - High: {count}
   - Medium: {count}
   - Low: {count}

   ### Top Issues
   1. {package} {version} -- {vulnerability} -- {fix: upgrade to {version}}
   ...
   ```

## Error Handling

| Condition | Action |
|-----------|--------|
| Prerequisites fail | Report specific error message and STOP |
| Scanner not installed | Report "Scanner {name} not found. Install with: {command}" and suggest alternatives from the fallback column |
| Scanner command fails | Report the error output. If it is a configuration issue, suggest how to configure the scanner |
| No vulnerabilities found | Report "No known vulnerabilities detected" -- this is a positive result |
| Multiple frameworks detected | Run scanners for all detected frameworks and aggregate results |
| forge.local.md missing | Fall back to auto-detection from project files |
| State corruption | This skill does not depend on state.json -- it runs independently |

## Important

- Do NOT fix vulnerabilities -- only report them
- If scanner is not installed, report: "Scanner {name} not found. Install with: {command}"
- If no vulnerabilities found, report: "No known vulnerabilities detected"

## See Also

- `/forge-review` -- Review code for quality and security findings using forge review agents
- `/forge-codebase-health` -- Full codebase scan against convention rules including security patterns
- `/forge-deep-health` -- Iteratively fix all codebase issues including security findings
- `/forge-verify` -- Quick build + lint + test check (does not include security scanning)
