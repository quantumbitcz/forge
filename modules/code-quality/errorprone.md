# errorprone

## Overview

Google's compile-time bug checker for Java that hooks into the Java compiler (`javac`) as an annotation processor. Error Prone catches common Java bugs — misuse of `@Nullable`, incorrect `equals()` usage, mismatched format strings, `Collection.toArray()` mistakes — at compile time with zero extra build steps. Because it runs during `javac`, it has access to the full type system and produces zero-overhead at runtime. Use it as a baseline for any Java project; it's the most developer-friendly tool in the JVM static analysis stack because violations appear inline in the IDE.

## Architecture Patterns

### Installation & Setup

**Gradle (`net.ltgt.errorprone` plugin, current: 4.x):**

```kotlin
// build.gradle.kts
plugins {
    id("net.ltgt.errorprone") version "4.1.0"
}

dependencies {
    errorprone("com.google.errorprone:error_prone_core:2.35.1")
    // Optional: NullAway for null safety enforcement
    errorprone("com.uber.nullaway:nullaway:0.12.2")
}

tasks.withType<JavaCompile>().configureEach {
    options.errorprone {
        disableWarningsInGeneratedCode.set(true)
        // Treat all enabled checks as errors:
        allErrorsAsWarnings.set(false)
        // Enable specific checks as errors:
        error("NullAway")
        error("MissingOverride")
        error("EqualsGetClass")
        // Downgrade to warnings:
        warn("UnnecessaryParentheses")
        // Disable checks:
        disable("AndroidJdkLibsChecker")
    }
}
```

**NullAway integration** (recommended for null safety in Java):

```kotlin
tasks.withType<JavaCompile>().configureEach {
    options.errorprone {
        option("NullAway:AnnotatedPackages", "com.example")
        option("NullAway:TreatGeneratedAsUnannotated", "true")
        option("NullAway:CheckOptionalEmptiness", "true")
    }
}
```

**Maven (`maven-compiler-plugin` with `annotationProcessorPaths`):**

```xml
<!-- pom.xml -->
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-compiler-plugin</artifactId>
    <version>3.13.0</version>
    <configuration>
        <compilerArgs>
            <arg>-XDcompilePolicy=simple</arg>
            <arg>-Xplugin:ErrorProne -Xep:NullAway:ERROR -XepOpt:NullAway:AnnotatedPackages=com.example</arg>
        </compilerArgs>
        <annotationProcessorPaths>
            <path>
                <groupId>com.google.errorprone</groupId>
                <artifactId>error_prone_core</artifactId>
                <version>2.35.1</version>
            </path>
            <path>
                <groupId>com.uber.nullaway</groupId>
                <artifactId>nullaway</artifactId>
                <version>0.12.2</version>
            </path>
        </annotationProcessorPaths>
    </configuration>
</plugin>
```

**Java 17+ module system** — Error Prone requires JVM flags when the build runs on JDK 17+:
```kotlin
// In gradle.properties or as a Gradle JVM arg:
// org.gradle.jvmargs=-J--add-exports=jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED \
//     -J--add-exports=jdk.compiler/com.sun.tools.javac.file=ALL-UNNAMED \
//     -J--add-exports=jdk.compiler/com.sun.tools.javac.main=ALL-UNNAMED \
//     -J--add-exports=jdk.compiler/com.sun.tools.javac.model=ALL-UNNAMED \
//     -J--add-exports=jdk.compiler/com.sun.tools.javac.parser=ALL-UNNAMED \
//     -J--add-exports=jdk.compiler/com.sun.tools.javac.processing=ALL-UNNAMED \
//     -J--add-exports=jdk.compiler/com.sun.tools.javac.tree=ALL-UNNAMED \
//     -J--add-exports=jdk.compiler/com.sun.tools.javac.util=ALL-UNNAMED \
//     -J--add-opens=jdk.compiler/com.sun.tools.javac.code=ALL-UNNAMED \
//     -J--add-opens=jdk.compiler/com.sun.tools.javac.comp=ALL-UNNAMED
```

### Rule Categories

Error Prone has ~300 checks organized by severity:

| Severity | Category | Examples | Pipeline Severity |
|---|---|---|---|
| `ERROR` | BugPattern | `BadInstanceof`, `CollectionIncompatibleType`, `EqualsIncompatibleType`, `MissingOverride`, `NullAway` | CRITICAL |
| `WARNING` | BugPattern | `CanIgnoreReturnValueSuggester`, `UnnecessaryParentheses`, `UnusedVariable` | WARNING |
| `SUGGESTION` | BugPattern | `ReturnsNullCollection`, `FieldCanBeFinal` | INFO |

Key checks by category:

**Correctness (ERROR-level):**
- `CollectionIncompatibleType` — `Set<String>.contains(Integer)` always returns false
- `EqualsIncompatibleType` — `equals()` between incompatible types is always false
- `BadInstanceof` — `instanceof` that is always true or always false
- `MissingCasesInEnumSwitch` — switch on enum missing cases
- `FormatStringAnnotation` — wrong number of format args

**Null Safety (via NullAway, ERROR-level):**
- `NullAway` — passing `@Nullable` to `@NonNull` parameter, dereferencing `@Nullable` without null check

**Concurrency (WARNING-level):**
- `GuardedBy` — accessing `@GuardedBy` field without holding the lock
- `SynchronizeOnNonFinalField` — synchronizing on a non-final field can deadlock

### Configuration Patterns

Compiler flag syntax to configure individual checks:
```
-Xep:CheckName:OFF       # disable completely
-Xep:CheckName:WARN      # downgrade to warning
-Xep:CheckName:ERROR     # upgrade to error
-XepOpt:CheckName:Key=Value   # pass option to a check
```

In Gradle `options.errorprone` DSL (equivalent to above flags):
```kotlin
tasks.withType<JavaCompile>().configureEach {
    options.errorprone {
        // Enable all checks as warnings, then selectively escalate
        allSuggestionsAsWarnings.set(true)
        error(
            "NullAway",
            "MissingOverride",
            "CollectionIncompatibleType",
            "EqualsIncompatibleType"
        )
        warn(
            "UnusedVariable",
            "FieldCanBeFinal"
        )
        disable(
            "AndroidJdkLibsChecker",
            "Java7ApiChecker",
            "Java8ApiChecker"   // if targeting Java 11+
        )
        // Generated code
        disableWarningsInGeneratedCode.set(true)
        // Exclude specific paths from NullAway
        option("NullAway:ExcludedFieldAnnotations", "lombok.Builder.Default")
    }
}
```

Suppress inline in source:
```java
@SuppressWarnings("MissingOverride")
public String toString() { return "..."; }

// Multiple:
@SuppressWarnings({"MissingOverride", "EqualsGetClass"})
```

### CI Integration

Error Prone runs as part of normal compilation — no extra CI step needed:

```yaml
# .github/workflows/quality.yml
- name: Compile with Error Prone
  run: ./gradlew compileJava compileTestJava

# Error Prone failures appear as compiler errors in the build log.
# No separate report upload needed — violations are in the build output.
```

For structured output in CI:
```yaml
- name: Compile with Error Prone (JSON output)
  run: ./gradlew compileJava 2>&1 | tee build/errorprone-output.txt
```

## Performance

- Error Prone adds ~5-15% overhead to `javac` compilation time — negligible for projects where compilation is not the bottleneck.
- It runs within the compiler process with full type information — no separate analysis phase, no extra subprocess.
- NullAway adds ~3% additional overhead on top of base Error Prone.
- Incremental compilation respects Error Prone — only recompiled classes are analyzed.
- On JDK 17+, the required `--add-exports` flags are set once in `gradle.properties` (not per-module) — no per-compilation overhead.

## Security

Error Prone has limited security-specific checks, but these are valuable:
- `InsecureCryptoUsage` (via NullAway/extended checks) — detects known-insecure cipher modes
- `MissingBraces` — can prevent accidental Apple `goto fail`-style bugs
- NullAway's `@NonNull`/`@Nullable` enforcement prevents null pointer bugs that become security vulnerabilities in input parsing paths

For comprehensive security analysis, pair with SpotBugs + FindSecBugs.

## Testing

Error Prone provides a testing framework for custom checks:

```kotlin
dependencies {
    testImplementation("com.google.errorprone:error_prone_test_helpers:2.35.1")
}
```

```java
@RunWith(JUnit4.class)
public class MyCustomCheckTest {
    @Test
    public void flagsViolation() {
        CompilationTestHelper.newInstance(MyCustomCheck.class, getClass())
            .addSourceLines("Test.java",
                "class Test {",
                "  // BUG: Diagnostic contains: Use factory method",
                "  Object x = new MyObject();",
                "}")
            .doTest();
    }

    @Test
    public void suggestsFixCorrectly() {
        BugCheckerRefactoringTestHelper.newInstance(MyCustomCheck.class, getClass())
            .addInputLines("Before.java", "class Before { Object x = new MyObject(); }")
            .addOutputLines("After.java", "class After { Object x = MyObject.create(); }")
            .doTest();
    }
}
```

Verify Error Prone is active on your project:
```bash
# Introduce a deliberate MissingOverride violation and confirm build fails:
./gradlew compileJava
# Should fail with: [MissingOverride] toString() overrides method in Object...
```

## Dos

- Enable Error Prone in all Java submodules via a convention plugin — it's zero-overhead once configured.
- Add NullAway and set your root package in `NullAway:AnnotatedPackages` — it enforces null safety without requiring full Kotlin migration.
- Escalate `MissingOverride`, `CollectionIncompatibleType`, and `EqualsIncompatibleType` to ERROR — these are always real bugs.
- Use `disableWarningsInGeneratedCode.set(true)` — generated sources (JAXB, protobuf, Lombok) will otherwise flood your build log.
- Set the required `--add-exports` JVM args in `gradle.properties` once at the project root — don't repeat per-module.
- Pin `error_prone_core` version explicitly and coordinate it with the `net.ltgt.errorprone` plugin version — they have independent release cycles.

## Don'ts

- Don't use `allDisabledChecksAsWarnings.set(true)` on existing codebases — it enables 200+ disabled checks and breaks the build before you can review the output.
- Don't suppress Error Prone warnings globally with `-XepAllErrorsAsWarnings` just to unblock a build — fix the underlying issue.
- Don't run Error Prone without specifying target Java version — `Java8ApiChecker` will fire on `java.util.List.of()` if you haven't disabled Java 8 API checks.
- Don't mix Error Prone with other annotation processors that modify the AST (e.g., some Lombok modes) — they can conflict and produce confusing errors.
- Don't skip the JVM `--add-exports` flags on JDK 17+ — Error Prone will silently degrade and stop reporting findings without them.
- Don't treat ERROR-level findings as optional — they represent bugs that will manifest at runtime.
