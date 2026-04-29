# Version Resolution — Cross-Cutting Constraint

## Rule

Agents **MUST NEVER** use dependency versions from training data or agent memory. Every version number written to a manifest, config, or generated file must be resolved at runtime.

Resolution order:
1. **Search the internet** for the latest stable release of the package
2. **Verify compatibility** with detected project versions in `state.json.detected_versions`
3. **Use the latest compatible version**

## Rationale

Training data versions are stale by definition. Using them leads to:
- Known security vulnerabilities (CVEs patched in newer releases)
- Version conflicts with already-resolved project dependencies
- Deprecated or removed APIs that cause build failures
- Missed bug fixes and performance improvements

## Applies To

| Context | Agent / Entry Point |
|---|---|
| New project recommendations | `/forge` |
| Implementation dependencies | `/forge run` → `fg-300-implementer` |
| Bugfix dependencies | `/forge fix` → `fg-300-implementer` |
| Project scaffold | `fg-050-project-bootstrapper` |
| Dependency declarations | `fg-310-scaffolder` |
| Deprecation checks | `fg-140-deprecation-refresh` |
| Plugin-local MCP package generation | project-local plugin generation |

## Implementation Requirements

Agents that write version numbers must have `WebSearch` in their `tools` list, or must explicitly delegate version resolution to the orchestrator before writing.

### When internet is available

1. Use `WebSearch` to find the latest stable release (e.g., search `{package} latest stable release`)
2. Cross-check against `state.json.detected_versions` for the project's ecosystem constraints
3. Write the resolved version

### When internet is unavailable

1. Emit a user-visible warning: `WARNING: Could not resolve latest version for {package} — internet unavailable`
2. Fall back to versions already present in the project's manifest files (e.g., `package.json`, `build.gradle.kts`, `go.mod`, `Cargo.toml`, `pom.xml`, `pyproject.toml`)
3. **Never fall back to training data versions**
4. If no manifest version exists and internet is unavailable, omit the version and ask the user to supply it

## Anti-Patterns

- `implementation("org.springframework.boot:spring-boot-starter:3.2.0")` — hardcoded training-data version
- `"react": "^18.2.0"` — version from memory without runtime verification
- Assuming `latest` tag is acceptable — always resolve to an explicit pinned version

## Examples

**Wrong:**
```kotlin
implementation("io.ktor:ktor-server-core:2.3.7")
```

**Correct:**
Search internet → find Ktor latest stable → verify against `state.json.detected_versions.kotlin` → write resolved version.
