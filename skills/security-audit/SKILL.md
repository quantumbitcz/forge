---
name: security-audit
description: Run module-appropriate security scanners and aggregate vulnerability results
disable-model-invocation: false
---

# Security Audit

Run security vulnerability scanners appropriate for the current module.

## What to do

1. Read `.claude/dev-pipeline.local.md` for the `module` field
   - If missing: try to detect from project files

2. Run the appropriate scanner based on module:

   | Framework | Scanner Command | Fallback |
   |-----------|----------------|----------|
   | react, nextjs, sveltekit, express | `npm audit --json` or `bun audit` | `npx auditjs` |
   | spring (kotlin or java) | `./gradlew dependencyCheckAnalyze` | Manual check of build.gradle.kts |
   | fastapi, django | `pip-audit` or `safety check` | `pip list --outdated` |
   | axum | `cargo audit` | `cargo deny check` |
   | go-stdlib, gin | `govulncheck ./...` | `go list -m -json all` |
   | swiftui, vapor | Manual review of Package.resolved | — |
   | jetpack-compose, kotlin-multiplatform | `./gradlew dependencyCheckAnalyze` | Manual check of build.gradle.kts |
   | aspnet | `dotnet list package --vulnerable` | Manual check of .csproj |
   | embedded | `cppcheck --enable=all src/` | — |
   | k8s | `trivy config .` or `kubeaudit all` | `helm lint charts/` |

3. Aggregate results:
   ```
   ## Security Audit Results

   - Critical: {count}
   - High: {count}
   - Medium: {count}
   - Low: {count}

   ### Top Issues
   1. {package} {version} — {vulnerability} — {fix: upgrade to {version}}
   ...
   ```

## Important
- Do NOT fix vulnerabilities — only report them
- If scanner is not installed, report: "Scanner {name} not found. Install with: {command}"
- If no vulnerabilities found, report: "No known vulnerabilities detected"
