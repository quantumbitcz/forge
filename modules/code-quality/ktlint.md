---
name: ktlint
categories: [linter, formatter]
languages: [kotlin]
exclusive_group: kotlin-formatter
recommendation_score: 90
detection_files: [.editorconfig, .ktlint, .ktlint-baseline.xml]
---

# ktlint

## Overview

Kotlin linter and auto-formatter enforcing the official Kotlin coding conventions and Android Kotlin style guide. ktlint has zero configuration by design — if you need to adjust a rule, you do so via `.editorconfig`, not a custom ruleset. Use ktlint for formatting consistency (spacing, imports, indentation); pair with detekt for semantic code quality checks. Faster than detekt for formatting-only pipelines since it requires no type resolution.

## Architecture Patterns

### Installation & Setup

Two integration paths: Gradle plugin (recommended for JVM projects) or Pinterest CLI (recommended for polyglot monorepos).

**Gradle — `org.jlleitschuh.gradle.ktlint` plugin (current: 12.x):**

```kotlin
// build.gradle.kts
plugins {
    id("org.jlleitschuh.gradle.ktlint") version "12.1.1"
}

ktlint {
    version.set("1.4.1")         // pin the ktlint engine version
    android.set(false)           // set true for Android projects
    outputToConsole.set(true)
    ignoreFailures.set(false)    // fail build on violations
    enableExperimentalRules.set(false)
    filter {
        exclude("**/generated/**")
        exclude("**/build/**")
        include("**/kotlin/**")
    }
}
```

For multi-module projects, apply in `build-logic/src/main/kotlin/kotlin-conventions.gradle.kts` so all modules share the same ktlint version and config.

**Pinterest CLI (alternative, no Gradle required):**
```bash
# Install via Homebrew
brew install ktlint

# Or download directly
curl -sSLO https://github.com/pinterest/ktlint/releases/download/1.4.1/ktlint
chmod +x ktlint && mv ktlint /usr/local/bin/

ktlint --version   # verify
```

### Rule Categories

ktlint ships two built-in rule sets:

| Rule Set | What It Checks | Pipeline Severity |
|---|---|---|
| `standard` | Import ordering, spacing, indentation, trailing commas, wrapping | WARNING |
| `experimental` | Function expression body, unnecessary parentheses | INFO |

Key standard rules:
- `import-ordering` — enforces ascii-sort + no wildcard imports
- `indent` — 4-space indentation (configurable in `.editorconfig`)
- `trailing-comma-on-call-site` / `trailing-comma-on-declaration-site` — enforces trailing commas in multiline
- `no-wildcard-imports` — bans `import foo.*`
- `final-newline` — requires newline at end of file
- `max-line-length` — respects `max_line_length` from `.editorconfig`

### Configuration Patterns

ktlint reads `.editorconfig` — place at project root:

```ini
# .editorconfig
root = true

[*.{kt,kts}]
charset = utf-8
end_of_line = lf
indent_size = 4
indent_style = space
insert_final_newline = true
max_line_length = 140
trim_trailing_whitespace = true

# ktlint-specific overrides
ktlint_standard_import-ordering = enabled
ktlint_standard_no-wildcard-imports = enabled
ktlint_standard_trailing-comma-on-call-site = enabled
ktlint_standard_trailing-comma-on-declaration-site = enabled

# Disable specific rules
ktlint_standard_filename = disabled   # if filename != class name is intentional

# Experimental rules opt-in
ktlint_experimental_function-expression-body = enabled
```

To disable a rule for a specific file or block:
```kotlin
// Per-line suppression (ktlint 1.x):
val x = someValue // ktlint-disable max-line-length

// Block suppression:
/* ktlint-disable no-wildcard-imports */
import com.example.*
/* ktlint-enable no-wildcard-imports */
```

### CI Integration

**Via Gradle plugin:**
```yaml
# .github/workflows/quality.yml
- name: ktlint check
  run: ./gradlew ktlintCheck

- name: ktlint format (auto-fix on PR)
  if: github.event_name == 'pull_request'
  run: |
    ./gradlew ktlintFormat
    git diff --exit-code || (git add -A && git commit -m "style: ktlint auto-format" && git push)
```

**Via Pinterest CLI:**
```yaml
- name: ktlint check
  run: ktlint --reporter=checkstyle,output=build/reports/ktlint.xml "src/**/*.kt"

- name: Upload ktlint results
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: ktlint-report
    path: build/reports/ktlint.xml
```

For GitHub PR annotations, use the `--reporter=github-actions` flag (ktlint 1.x+):
```bash
ktlint --reporter=github-actions "src/**/*.kt"
```

## Performance

- ktlint is fast: processes ~10k lines/second on a modern laptop. A 100k-line project runs in under 15 seconds.
- No type resolution overhead — purely AST-based, making it 3-5x faster than detekt for the same source set.
- Gradle up-to-date checks skip unchanged files. Incremental runs on changed files only take milliseconds.
- The Gradle plugin runs `ktlintCheck` before `check` by default — opt out with `tasks.named("check") { dependsOn.remove("ktlintCheck") }` if you want manual control.

## Security

ktlint has no security-specific rules — it's a formatting tool. For security analysis on Kotlin code, use detekt (potential-bugs rule set) or SpotBugs with FindSecBugs on the compiled bytecode.

## Testing

Verify your `.editorconfig` rules take effect:
```bash
# Format all files in place:
./gradlew ktlintFormat    # Gradle
ktlint --format "src/**/*.kt"  # CLI

# Check only (non-destructive):
./gradlew ktlintCheck
ktlint "src/**/*.kt"

# Check a single file:
ktlint src/main/kotlin/com/example/MyClass.kt
```

Writing custom rules (ktlint 1.x Rule API):
```kotlin
class NoDebugLogRule : Rule(
    ruleId = RuleId("custom:no-debug-log"),
    about = About(maintainer = "Team")
) {
    override fun beforeVisitChildNodes(
        node: ASTNode, autoCorrect: Boolean, emit: (offset: Int, errorMessage: String, canBeAutoCorrected: Boolean) -> Unit
    ) {
        if (node.elementType == KtNodeTypes.DOT_QUALIFIED_EXPRESSION && node.text.startsWith("Log.d(")) {
            emit(node.startOffset, "Avoid Log.d in production code", false)
        }
    }
}
```

Register via `RuleSetProviderV3` and add as `ktlintRuleset` dependency.

## Dos

- Pin the ktlint engine version in `ktlint { version.set("...") }` — the Gradle plugin and engine versions are independent and can diverge.
- Use `ktlintFormat` as a pre-commit hook or in IDE on-save to eliminate formatting-only CI failures.
- Configure `.editorconfig` at the repository root so all editors (IntelliJ, VS Code, vim) apply the same rules without IDE-specific config.
- Enable `trailing-comma-on-call-site` and `trailing-comma-on-declaration-site` — trailing commas in Kotlin reduce diff noise in multiline expressions.
- Use `android.set(true)` for Android modules — it applies Google's Android Kotlin style guide variant.
- Apply ktlint in convention plugins for consistency across all submodules rather than copy-pasting config.

## Don'ts

- Don't edit rules via Gradle `disabledRules` property — it's deprecated in ktlint 1.x. Use `.editorconfig` with `ktlint_standard_<rule> = disabled`.
- Don't run `ktlintFormat` in CI without committing the result back or failing the build — silent format-and-ignore defeats the purpose.
- Don't mix ktlint and IntelliJ auto-formatting without aligning `.editorconfig` — divergent settings cause developers to bounce files between tools.
- Don't suppress rules globally to pass CI — each suppression should have a comment explaining why.
- Don't use ktlint alone as a substitute for detekt — ktlint catches formatting only; detekt catches logic smells, complexity, and coroutine misuse.
- Don't skip ktlint for `*.kts` build files — they support the same rules and drift in formatting creates confusion.
