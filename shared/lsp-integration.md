# LSP Integration

Defines how forge agents use the LSP tool (Language Server Protocol) available in Claude Code. LSP provides precise structural code intelligence — references, definitions, type hierarchies — that complements text-based search. Detected at runtime; never required.

## When to Use LSP

| Operation | Without LSP | With LSP |
|-----------|-------------|----------|
| Find references | `Grep` for symbol name — noisy, misses dynamic references | `find-references` — precise, scope-aware, includes transitive callers |
| Go to definition | `Grep` for `class Foo` / `fun bar` — fragile across modules | `go-to-definition` — resolves through interfaces, generics, re-exports |
| Unused code detection | Manual inspection or linter-specific rules | `find-references` returns 0 results — definitive proof of dead code |
| Import boundary analysis | `Grep` for `import` patterns — misses re-exports and barrel files | `find-references` traces actual usage across module boundaries |
| Type checking | Infer from context or rely on build output | `diagnostics` — real-time type errors without a full build cycle |

**Rule:** Prefer LSP when the question is "who uses X?" or "where is X defined?" — these are structural queries that text search answers unreliably.

## Agents That Benefit

| Agent | Use Case |
|-------|----------|
| `fg-412-architecture-reviewer` | Detect layering violations, circular dependencies, unused public APIs |
| `fg-416-backend-performance-reviewer` | Find hot paths via callers-of-callers, identify N+1 query origins |
| `fg-300-implementer` | Navigate to interfaces before implementing, verify no existing implementation |
| `fg-410-code-reviewer` | Confirm dead code, trace impact of changed signatures, validate encapsulation |
| EXPLORE stage | Build accurate dependency maps, discover entry points, map module boundaries |

Agents not listed here may still use LSP opportunistically. The above are the primary beneficiaries where LSP meaningfully improves output quality.

## Graceful Degradation

LSP is **always optional**. Every agent must function correctly without it.

1. **Silent fallback.** If LSP is unavailable, fall back to `Grep`/`Glob` without user-visible warnings. Do not emit INFO findings about LSP unavailability.
2. **No quality penalty.** Scores, thresholds, and pass criteria are identical whether LSP is available or not. LSP improves precision, not pass/fail outcomes.
3. **Stage notes only.** Record LSP availability in `stage_notes` for telemetry:

        ## LSP
        - Available: true
        - Languages: typescript, kotlin
        - Queries: 14 (12 succeeded, 2 timed out)

4. **Per-query resilience.** If a single LSP call fails or times out, continue with text-based fallback for that query. Do not disable LSP for the remainder of the stage.

## Supported Languages

| Language | Language Server | Detection |
|----------|----------------|-----------|
| TypeScript | tsserver | `tsconfig.json` or `package.json` with typescript dependency |
| Kotlin | kotlin-language-server | `build.gradle.kts` or `build.gradle` with kotlin plugin |
| Python | pyright | `pyproject.toml`, `setup.py`, or `requirements.txt` |
| Rust | rust-analyzer | `Cargo.toml` |
| Go | gopls | `go.mod` |
| Java | Eclipse JDT | `pom.xml` or `build.gradle` with java plugin |
| C# | OmniSharp | `*.csproj` or `*.sln` |
| Swift | sourcekit-lsp | `Package.swift` or `*.xcodeproj` |

Language server availability depends on the user's Claude Code environment. The plugin does not install or manage language servers.

## Configuration

In `forge-config.md`:

    lsp:
      enabled: true
      languages: []

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `lsp.enabled` | `bool` | `true` | Master switch. When `false`, agents skip all LSP calls. |
| `lsp.languages` | `string[]` | `[]` (auto-detect) | Restrict LSP to listed languages. Empty = auto-detect from project manifests. |

When `lsp.enabled` is `true` and `lsp.languages` is empty, PREFLIGHT populates `state.json.lsp.detected_languages` by scanning project manifests against the Supported Languages table.

### PREFLIGHT Validation

| Parameter | Valid Values | Default |
|-----------|-------------|---------|
| `lsp.enabled` | `true`, `false` | `true` |
| `lsp.languages` | array of language names from Supported Languages table | `[]` |

Unknown language names in `lsp.languages` produce WARNING (typo protection) but do not fail PREFLIGHT.

## Agent Integration Pattern

Every LSP interaction follows a four-step sequence:

1. **Check availability.** Before the first LSP call in a stage, test whether the LSP tool is accessible:

        # Attempt a lightweight LSP probe
        LSP(action: "diagnostics", file: "src/main.ts")

   If this returns an error indicating LSP is unavailable, set `lsp_available = false` for the stage and skip all subsequent LSP calls.

2. **Attempt LSP.** Use the appropriate LSP action for the structural query:

        LSP(action: "find-references", file: "src/service.ts", symbol: "UserRepository")
        LSP(action: "go-to-definition", file: "src/handler.ts", symbol: "processOrder")

3. **Fall back if failed.** If the LSP call returns an error or times out (10-second ceiling per call), silently fall back:

        # LSP failed or timed out — use text search
        Grep(pattern: "UserRepository", type: "ts")

4. **Record telemetry.** At stage end, record aggregate LSP usage in stage notes. Include: total queries, successes, failures, timeouts. No per-query logging.

### Timeout

- **Per-call timeout:** 10 seconds. Enforced by the agent, not the LSP tool itself.
- **Timeout handling:** Treat as a transient failure — fall back to text search for that query. Do not retry the same LSP call.
- **Repeated timeouts:** If 3+ LSP calls time out within the same stage, disable LSP for the remainder of that stage (circuit breaker). Record in stage notes.
