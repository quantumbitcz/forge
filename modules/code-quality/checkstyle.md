---
name: checkstyle
categories: [linter, formatter]
languages: [java]
exclusive_group: java-formatter
recommendation_score: 70
detection_files: [checkstyle.xml, .checkstyle, google_checks.xml, sun_checks.xml]
---

# checkstyle

## Overview

Configurable Java style checker that enforces coding standards at the source level: naming conventions, import ordering, whitespace, Javadoc completeness, and line length. Checkstyle catches style issues a compiler ignores but code reviewers flag. Use it for Java projects as a formatting/convention gate; pair with PMD for semantic code quality and SpotBugs for bug pattern detection. Does not require compilation — runs on raw `.java` source files.

## Architecture Patterns

### Installation & Setup

**Gradle (built-in `checkstyle` plugin — no extra plugin ID needed):**

```kotlin
// build.gradle.kts
plugins {
    checkstyle
}

checkstyle {
    toolVersion = "10.20.1"
    configFile = file("$rootDir/config/checkstyle/checkstyle.xml")
    configDirectory.set(file("$rootDir/config/checkstyle"))
    isIgnoreFailures = false
    maxWarnings = 0
    maxErrors = 0
}

tasks.withType<Checkstyle> {
    reports {
        html.required.set(true)
        xml.required.set(true)
        sarif.required.set(false)   // available from checkstyle 10.14+
    }
}
```

**Maven (`maven-checkstyle-plugin`):**

```xml
<!-- pom.xml -->
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-checkstyle-plugin</artifactId>
    <version>3.6.0</version>
    <configuration>
        <configLocation>config/checkstyle/checkstyle.xml</configLocation>
        <suppressionsLocation>config/checkstyle/suppressions.xml</suppressionsLocation>
        <failsOnError>true</failsOnError>
        <consoleOutput>true</consoleOutput>
    </configuration>
    <executions>
        <execution>
            <id>validate</id>
            <phase>validate</phase>
            <goals><goal>check</goal></goals>
        </execution>
    </executions>
</plugin>
```

### Rule Categories

Checkstyle groups rules into modules. Key modules and their pipeline severity:

| Module | What It Checks | Pipeline Severity |
|---|---|---|
| `TreeWalker > Naming` | ClassNameCheck, MethodNameCheck, ConstantNameCheck, LocalVariableNameCheck | WARNING |
| `TreeWalker > Imports` | AvoidStarImport, UnusedImports, ImportOrder | WARNING |
| `TreeWalker > Whitespace` | WhitespaceAround, NoWhitespaceBefore, OperatorWrap | INFO |
| `TreeWalker > Blocks` | NeedBraces, LeftCurly, RightCurly | WARNING |
| `TreeWalker > Coding` | EqualsHashCode, EmptyCatchBlock, HiddenField, IllegalCatch | CRITICAL |
| `TreeWalker > Javadoc` | JavadocMethod, JavadocVariable, MissingJavadocMethod | INFO |
| `TreeWalker > Metrics` | CyclomaticComplexity, ClassFanOutComplexity, MethodLength | WARNING |
| `FileTabCharacter` | Tabs vs spaces | INFO |
| `LineLength` | Max line length | WARNING |

### Configuration Patterns

Start from Google's style guide — most teams extend it. Config at `config/checkstyle/checkstyle.xml`:

```xml
<?xml version="1.0"?>
<!DOCTYPE module PUBLIC
    "-//Checkstyle//DTD Checkstyle Configuration 1.3//EN"
    "https://checkstyle.org/dtds/configuration_1_3.dtd">

<module name="Checker">
    <property name="charset" value="UTF-8"/>
    <property name="severity" value="error"/>
    <property name="fileExtensions" value="java"/>

    <!-- Suppress from file -->
    <module name="SuppressionFilter">
        <property name="file" value="${config_loc}/suppressions.xml"/>
        <property name="optional" value="true"/>
    </module>

    <module name="FileTabCharacter">
        <property name="eachLine" value="true"/>
    </module>

    <module name="LineLength">
        <property name="max" value="140"/>
        <property name="ignorePattern" value="^package.*|^import.*|a href|href|http://|https://|ftp://"/>
    </module>

    <module name="TreeWalker">
        <!-- Naming -->
        <module name="ClassTypeParameterName">
            <property name="format" value="^[A-Z][0-9]?$"/>
        </module>
        <module name="ConstantName"/>
        <module name="LocalVariableName"/>
        <module name="MemberName"/>
        <module name="MethodName"/>
        <module name="PackageName">
            <property name="format" value="^[a-z]+(\.[a-z][a-z0-9]*)*$"/>
        </module>
        <module name="TypeName"/>

        <!-- Imports -->
        <module name="AvoidStarImport"/>
        <module name="UnusedImports"/>
        <module name="ImportOrder">
            <property name="groups" value="java,javax,org,com"/>
            <property name="option" value="top"/>
            <property name="sortStaticImportsAlphabetically" value="true"/>
        </module>

        <!-- Blocks -->
        <module name="NeedBraces"/>
        <module name="LeftCurly"/>
        <module name="RightCurly"/>
        <module name="EmptyBlock">
            <property name="option" value="TEXT"/>
            <property name="tokens" value="LITERAL_TRY, LITERAL_FINALLY, LITERAL_IF, LITERAL_ELSE, LITERAL_SWITCH"/>
        </module>

        <!-- Coding -->
        <module name="EqualsHashCode"/>
        <module name="EmptyCatchBlock">
            <property name="exceptionVariableName" value="expected|ignore"/>
        </module>
        <module name="HiddenField">
            <property name="ignoreSetter" value="true"/>
            <property name="ignoreConstructorParameter" value="true"/>
        </module>
        <module name="IllegalCatch"/>
        <module name="OneStatementPerLine"/>
        <module name="StringLiteralEquality"/>

        <!-- Metrics -->
        <module name="CyclomaticComplexity">
            <property name="max" value="15"/>
        </module>
        <module name="MethodLength">
            <property name="max" value="80"/>
        </module>

        <!-- Whitespace -->
        <module name="WhitespaceAround"/>
        <module name="NoWhitespaceBefore"/>

        <!-- Suppress via annotation -->
        <module name="SuppressWarningsHolder"/>
    </module>

    <module name="SuppressWarningsFilter"/>
</module>
```

Suppressions file at `config/checkstyle/suppressions.xml`:
```xml
<?xml version="1.0"?>
<!DOCTYPE suppressions PUBLIC
    "-//Checkstyle//DTD SuppressionFilter Configuration 1.2//EN"
    "https://checkstyle.org/dtds/suppressions_1_2.dtd">

<suppressions>
    <!-- Suppress in generated sources -->
    <suppress files="[\\/]generated[\\/]" checks=".*"/>
    <!-- Suppress Javadoc in test files -->
    <suppress files=".*Test\.java" checks="Javadoc.*"/>
</suppressions>
```

Suppress inline in Java source:
```java
@SuppressWarnings("checkstyle:MagicNumber")
private static final int RETRY_LIMIT = 3;
```

### CI Integration

```yaml
# .github/workflows/quality.yml
- name: Run Checkstyle
  run: ./gradlew checkstyleMain checkstyleTest --continue

- name: Upload Checkstyle report
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: checkstyle-report
    path: build/reports/checkstyle/
```

For GitHub PR annotations, use the `checkstyle-github-actions-reporter` or pipe XML through `reviewdog`:
```yaml
- uses: reviewdog/action-checkstyle@v1
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
    reporter: github-pr-review
    checkstyle_flags: -c config/checkstyle/checkstyle.xml src/main/java/**/*.java
```

## Performance

- Checkstyle analyzes source text without compilation — typically 2-5x faster than PMD or SpotBugs.
- A 500-class project runs in under 10 seconds with Gradle's incremental task support.
- Gradle caches results: unchanged `.java` files are skipped on subsequent runs.
- Separate `checkstyleMain` and `checkstyleTest` tasks let you skip test checking in fast feedback loops.

## Security

Checkstyle has no dedicated security module, but these rules catch security-adjacent issues:
- `IllegalCatch` — prevents `catch (Exception e)` that can silently swallow security exceptions
- `StringLiteralEquality` — catches `==` on String which fails for user input comparison
- `EmptyCatchBlock` — flags silently swallowed exceptions including `SecurityException`

For security-focused Java static analysis, use SpotBugs with FindSecBugs plugin.

## Testing

```bash
# Gradle: verify config is valid and no violations
./gradlew checkstyleMain

# Maven: run only checkstyle phase
mvn checkstyle:check

# CLI (standalone):
java -jar checkstyle-10.20.1-all.jar -c config/checkstyle/checkstyle.xml src/main/java/
```

Gradual adoption via `maxErrors`/`maxWarnings`:
```kotlin
// Start permissive, ratchet down over time
checkstyle {
    maxErrors = 0      // zero tolerance for errors
    maxWarnings = 50   // allow existing warnings, reduce sprint by sprint
}
```

## Dos

- Base your `checkstyle.xml` on Google's style (`google_checks.xml` ships with checkstyle) or Sun's style (`sun_checks.xml`) rather than writing from scratch.
- Use `suppressions.xml` with file patterns to exclude generated code — inline suppressions in generated files are unreliable.
- Separate `checkstyleMain` and `checkstyleTest` in Gradle and apply relaxed rules to test sources (e.g., skip Javadoc checks).
- Pin `toolVersion` explicitly — checkstyle adds rules and changes defaults between releases.
- Use `${config_loc}` variable in config to reference sibling files (like `suppressions.xml`) portably across developer machines and CI.
- Enable `isIgnoreFailures = false` in CI environments and set `maxWarnings = 0` once the baseline is clean.

## Don'ts

- Don't enforce Javadoc on test classes (`.*Test.java`) — test method names should be self-documenting, not Javadoc'd.
- Don't use Checkstyle for semantic checks (null checks, exception handling logic) — PMD and SpotBugs handle those better.
- Don't set `maxErrors` to a large number hoping to fix violations "later" — they compound and teams learn to ignore CI warnings.
- Don't mix tabs and spaces in your `checkstyle.xml` itself — Checkstyle can fail to parse its own config.
- Don't skip the `EqualsHashCode` rule — inconsistent `equals`/`hashCode` is a correctness bug disguised as a style issue.
- Don't apply the same strict Javadoc rules to internal utility classes — reserve strict documentation requirements for public API surfaces.
