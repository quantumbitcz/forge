# pmd

## Overview

Multi-language static analyzer for Java (and limited Kotlin/JavaScript) that detects code smells, anti-patterns, dead code, and design violations via configurable rule sets. PMD operates on AST (not bytecode), so it runs without compilation. Use PMD alongside Checkstyle (style) and SpotBugs (bug patterns) — they have minimal rule overlap and catch different issue classes. PMD is strongest on unused code detection, design violations, and Java-specific anti-patterns.

## Architecture Patterns

### Installation & Setup

**Gradle (built-in `pmd` plugin — no extra plugin ID needed):**

```kotlin
// build.gradle.kts
plugins {
    pmd
}

pmd {
    toolVersion = "7.8.0"
    isConsoleOutput = true
    isIgnoreFailures = false
    ruleSetFiles = files("$rootDir/config/pmd/ruleset.xml")
    ruleSets = emptyList()  // clear defaults — use ruleSetFiles only
}

tasks.withType<Pmd> {
    reports {
        html.required.set(true)
        xml.required.set(true)
    }
}
```

**Maven (`maven-pmd-plugin`):**

```xml
<!-- pom.xml -->
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-pmd-plugin</artifactId>
    <version>3.25.0</version>
    <configuration>
        <rulesets>
            <ruleset>/config/pmd/ruleset.xml</ruleset>
        </rulesets>
        <failOnViolation>true</failOnViolation>
        <printFailingErrors>true</printFailingErrors>
        <linkXRef>false</linkXRef>
    </configuration>
    <executions>
        <execution>
            <goals><goal>check</goal></goals>
        </execution>
    </executions>
</plugin>
```

**PMD CLI (for non-JVM build systems):**
```bash
pmd check -d src/main/java -R config/pmd/ruleset.xml -f text --no-progress
```

### Rule Categories

PMD organizes rules into categories. Mapping to pipeline severity:

| Category | What It Checks | Pipeline Severity |
|---|---|---|
| `bestpractices` | AbstractClassWithoutAbstractMethod, DefaultLabelNotLastInSwitch, LooseCoupling, UnusedImports | WARNING |
| `codestyle` | ConfusingTernary, FieldDeclarationsShouldBeAtStart, LocalVariableCouldBeFinal, UnnecessaryReturn | INFO |
| `design` | AvoidDeeplyNestedIfStmts, CouplingBetweenObjects, DataClass, ExcessiveClassLength, GodClass | WARNING |
| `errorprone` | AssignmentInOperand, BrokenNullCheck, CloneMethodMustImplementCloneable, EmptyCatchBlock, NullAssignment | CRITICAL |
| `multithreading` | AvoidSynchronizedAtMethodLevel, AvoidThreadGroup, DontCallThreadRun, DoubleCheckedLocking | CRITICAL |
| `performance` | AddEmptyString, AvoidInstantiatingObjectsJustToGetClass, InefficientEmptyStringCheck, UseStringBufferForStringAppends | WARNING |
| `security` | HardCodedCryptoKey, InsecureCryptoIv, AvoidFileStream | CRITICAL |

### Configuration Patterns

Minimal production ruleset at `config/pmd/ruleset.xml`:

```xml
<?xml version="1.0"?>
<ruleset name="Custom PMD Rules"
         xmlns="http://pmd.sourceforge.net/ruleset/2.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://pmd.sourceforge.net/ruleset/2.0.0 https://pmd.github.io/ruleset_2_0_0.xsd">

    <description>Project PMD ruleset</description>

    <!-- Exclude generated sources and build output -->
    <exclude-pattern>.*/generated/.*</exclude-pattern>
    <exclude-pattern>.*/build/.*</exclude-pattern>

    <!-- Best Practices -->
    <rule ref="category/java/bestpractices.xml">
        <exclude name="GuardLogStatement"/>     <!-- too noisy with SLF4J -->
        <exclude name="JUnitTestContainsTooManyAsserts"/>
    </rule>

    <!-- Code Style (informational only) -->
    <rule ref="category/java/codestyle.xml">
        <exclude name="AtLeastOneConstructor"/>
        <exclude name="CallSuperInConstructor"/>
        <exclude name="CommentDefaultAccessModifier"/>
        <exclude name="DefaultPackage"/>
        <exclude name="LongVariable"/>
        <exclude name="OnlyOneReturn"/>
        <exclude name="ShortClassName"/>
        <exclude name="ShortVariable"/>
    </rule>

    <!-- Design -->
    <rule ref="category/java/design.xml">
        <exclude name="LawOfDemeter"/>          <!-- too many false positives with builders -->
        <exclude name="LoosePackageCoupling"/>
    </rule>
    <rule ref="category/java/design.xml/ExcessiveClassLength">
        <properties>
            <property name="minimum" value="500"/>
        </properties>
    </rule>
    <rule ref="category/java/design.xml/CyclomaticComplexity">
        <properties>
            <property name="methodReportLevel" value="15"/>
        </properties>
    </rule>

    <!-- Error Prone — high value, keep all -->
    <rule ref="category/java/errorprone.xml">
        <exclude name="BeanMembersShouldSerialize"/>
        <exclude name="DataflowAnomalyAnalysis"/>    <!-- high false positive rate -->
    </rule>

    <!-- Multithreading — all critical -->
    <rule ref="category/java/multithreading.xml"/>

    <!-- Performance -->
    <rule ref="category/java/performance.xml"/>

    <!-- Security -->
    <rule ref="category/java/security.xml"/>

</ruleset>
```

Suppress a specific violation inline:
```java
@SuppressWarnings("PMD.AvoidDeeplyNestedIfStmts")
public void processData(Data data) { ... }

// Or suppress multiple:
@SuppressWarnings({"PMD.CyclomaticComplexity", "PMD.NPathComplexity"})
public void complexRouter(Request req) { ... }
```

Suppress via `pmd-exclude.properties` for entire files:
```
# config/pmd/pmd-exclude.properties
com.example.generated.SomeGenerated=AvoidDeeplyNestedIfStmts
```

### CI Integration

```yaml
# .github/workflows/quality.yml
- name: Run PMD
  run: ./gradlew pmdMain pmdTest --continue

- name: Upload PMD report
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: pmd-report
    path: build/reports/pmd/

- name: PMD annotations via reviewdog
  uses: reviewdog/action-suggester@v1
  if: github.event_name == 'pull_request'
  with:
    tool_name: pmd
```

PMD 7.x supports SARIF output for GitHub Security tab integration:
```bash
pmd check -d src/main/java -R config/pmd/ruleset.xml -f sarif -r build/reports/pmd/pmd.sarif
```

## Performance

- PMD 7.x uses incremental analysis: `--cache build/.pmd/cache` avoids re-analyzing unchanged files. Enable in Gradle:
```kotlin
pmd {
    incrementalAnalysis.set(true)   // Gradle PMD plugin 7.x
}
```
- Without incremental analysis, PMD analyzes ~50k lines/second — a 200k-line project takes ~4 seconds.
- Limit categories to only those you enforce to avoid running all 7 categories on every build.
- Run `pmdMain` and `pmdTest` as separate tasks to parallelize with `--parallel` in Gradle.

## Security

PMD 7.x includes a dedicated `security` category for Java:
- `HardCodedCryptoKey` — CRITICAL: detects string literals used directly as encryption keys
- `InsecureCryptoIv` — CRITICAL: detects hardcoded initialization vectors
- `AvoidFileStream` — WARNING: `FileInputStream`/`FileOutputStream` don't respect stream close on GC (use `Files.newInputStream()`)

These rules map to pipeline CRITICAL severity. Always include `category/java/security.xml` in your ruleset.

## Testing

```bash
# Gradle: run PMD on main sources
./gradlew pmdMain

# Maven: run PMD check
mvn pmd:check

# CLI: quick check with verbose output
pmd check -d src/main/java -R config/pmd/ruleset.xml -f text -v

# List all available rules in a category
pmd rules -category security
```

Validate your ruleset XML before CI:
```bash
pmd check -d src/main/java -R config/pmd/ruleset.xml --dry-run
```

For gradual adoption, start with only `errorprone` and `multithreading` categories (highest signal), then add others incrementally:
```kotlin
pmd {
    isIgnoreFailures = true    // warn-only mode to establish baseline
}
```

## Dos

- Always set `ruleSets = emptyList()` in Gradle and use `ruleSetFiles` — the default rulesets change between PMD versions and will surprise you after upgrades.
- Include `category/java/security.xml` — PMD's security rules catch hardcoded crypto keys that no other tool in the JVM stack reliably finds.
- Enable incremental analysis for local development speed — `pmd { incrementalAnalysis.set(true) }`.
- Exclude generated sources via `<exclude-pattern>` in the ruleset XML rather than in Gradle config — portable across Maven, Gradle, and CLI.
- Use `@SuppressWarnings("PMD.RuleName")` with a comment explaining why — reviewers need context.
- Pin `toolVersion` — PMD 7.x broke compatibility with 6.x rulesets (rule names changed, categories restructured).

## Don'ts

- Don't include `category/java/codestyle.xml` fully without heavy exclusions — it has 40+ rules, many of which are purely aesthetic and cause developer friction.
- Don't use PMD's `LawOfDemeter` rule on projects using builders or fluent APIs — it generates false positives for every chained call.
- Don't rely on PMD for formatting or import checks — Checkstyle handles those with better accuracy.
- Don't suppress `multithreading` category rules without thorough review — thread safety violations are correctness bugs.
- Don't run PMD without `isIgnoreFailures = false` in CI — warn-only mode silently lets new violations accumulate.
- Don't use `DataflowAnomalyAnalysis` rule in production rulesets — it has a high false positive rate and causes developer distrust of the tool.
