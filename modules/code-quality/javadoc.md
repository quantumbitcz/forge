# javadoc

## Overview

Javadoc is the built-in Java documentation tool that generates HTML API docs from `/** */` comment blocks. Invocable via the `javadoc` CLI, Gradle `javadoc` task, or Maven `javadoc:javadoc`. Enable `-Xdoclint:all` to enforce strict comment validation (missing tags, broken HTML, bad references). Use `package-info.java` to document packages. The Doclet API allows custom output formats — the standard HTML doclet is the default; tools like Asciidoclet or the Javadoc JSON doclet extend it.

## Architecture Patterns

### Installation & Setup

Javadoc ships with the JDK — no extra dependency required.

**Gradle configuration:**
```kotlin
// build.gradle.kts
tasks.javadoc {
    options {
        (this as StandardJavadocDocletOptions).apply {
            addStringOption("Xdoclint:all", "-quiet")
            addStringOption("encoding", "UTF-8")
            addStringOption("docencoding", "UTF-8")
            addBooleanOption("html5", true)
            links("https://docs.oracle.com/en/java/javase/21/docs/api/")
            windowTitle = "My Library API"
            header = "<b>My Library</b>"
        }
    }
    source = sourceSets["main"].allJava
    classpath = configurations["compileClasspath"]
}
```

**Maven configuration:**
```xml
<!-- pom.xml -->
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-javadoc-plugin</artifactId>
    <version>3.6.3</version>
    <configuration>
        <doclint>all</doclint>
        <show>protected</show>
        <encoding>UTF-8</encoding>
        <links>
            <link>https://docs.oracle.com/en/java/javase/21/docs/api/</link>
        </links>
        <additionalOptions>-html5</additionalOptions>
    </configuration>
</plugin>
```

### Rule Categories

| Category | Pattern | Pipeline Severity |
|---|---|---|
| Missing summary sentence | Public member without opening description | WARNING |
| Missing `@param` | Public method param undocumented | WARNING |
| Missing `@return` | Non-void public method without `@return` | WARNING |
| Missing `@throws` | Declared checked exception without `@throws` | WARNING |
| Broken `{@link}` reference | Link to non-existent class/method | CRITICAL |
| Malformed HTML in comment | Unclosed tags or invalid HTML | WARNING |

### Configuration Patterns

**Standard Javadoc comment structure:**
```java
/**
 * Returns the user associated with the given identifier.
 *
 * <p>Looks up the user in the repository. Returns {@code Optional.empty()} if
 * no user exists with the specified {@code id}.
 *
 * @param id the unique user identifier; must not be {@code null}
 * @return an {@link Optional} containing the user, or empty if not found
 * @throws IllegalArgumentException if {@code id} is negative
 * @since 2.1
 * @see UserRepository#findAll()
 */
Optional<User> findById(long id);
```

**Package documentation via `package-info.java`:**
```java
/**
 * Public API for the authentication subsystem.
 *
 * <p>Entry point: {@link com.example.auth.AuthService}.
 *
 * @since 1.0
 */
package com.example.auth;
```

**Custom doclet (Gradle):**
```kotlin
tasks.javadoc {
    options.docletpath = configurations["jsonDoclet"].files.toList()
    options.doclet = "com.example.JsonDoclet"
}
```

**Aggregate Javadoc for multi-module Maven projects:**
```xml
<!-- In parent pom.xml -->
<plugin>
    <artifactId>maven-javadoc-plugin</artifactId>
    <executions>
        <execution>
            <id>aggregate</id>
            <goals><goal>aggregate</goal></goals>
            <phase>site</phase>
        </execution>
    </executions>
</plugin>
```

### CI Integration

```yaml
# .github/workflows/docs.yml
- name: Generate Javadoc
  run: ./gradlew javadoc

- name: Fail on doclint errors
  run: ./gradlew javadoc --warning-mode all

- name: Upload Javadoc artifact
  uses: actions/upload-artifact@v4
  with:
    name: javadoc
    path: build/docs/javadoc/
```

```yaml
# Maven
- name: Generate Javadoc
  run: mvn javadoc:javadoc -Ddoclint=all
```

## Performance

- Javadoc runs annotation processing and resolves the full classpath — it is slow (10-60s) on large modules. Run it only on publish branches or as a nightly job.
- Enable incremental builds in Gradle: Javadoc tasks are `@CacheableTask` since Gradle 7 — enable the build cache with `org.gradle.caching=true`.
- Use `excludePackageNames` / `-subpackages` flags to exclude generated or internal code from the analysis scope.
- In Maven, skip during fast local builds: `mvn install -Dmaven.javadoc.skip=true`.

## Security

- Javadoc generates static HTML — no runtime security concerns once deployed.
- `-Xdoclint:html` catches injected `<script>` tags in comment blocks that could affect doc consumers if hosted internally without sanitization.
- Avoid documenting internal credentials, URLs, or environment-specific details in `@see` or `@link` tags — they appear in the generated HTML.
- Generated docs from third-party sources can contain malicious HTML in descriptions if you aggregate external Javadocs. Vet linked packages.

## Testing

```bash
# Generate docs with strict doclint
./gradlew javadoc

# Maven
mvn javadoc:javadoc

# Test that Javadoc compiles without errors (fail on warnings)
./gradlew javadoc --warning-mode all 2>&1 | grep -E "^[0-9]+ (warning|error)"

# Check specific doclint category
javadoc -Xdoclint:reference src/**/*.java

# Generate aggregate docs in Maven multi-module
mvn javadoc:aggregate
```

## Dos

- Enable `-Xdoclint:all` in CI — it catches broken `{@link}` references, missing tags, and invalid HTML before they reach published docs.
- Write `package-info.java` for every non-trivial package — it provides the first impression for consumers browsing the API.
- Use `{@code}` for inline code snippets and `{@link}` for cross-references — they survive refactoring renames better than plain text.
- Add `@since` tags on newly introduced public API — consumers need to know the minimum version that includes each symbol.
- Link to the JDK Javadoc via the `links` option so standard type cross-references resolve correctly.
- Document `@throws` for every checked exception declared in the method signature.

## Don'ts

- Don't skip `-Xdoclint:all` — undiscovered broken links and missing tags cause confusion for library consumers.
- Don't write Javadoc only on classes and skip methods — method-level docs are what IDE tooltip popups show.
- Don't use raw HTML blocks for code examples — use `{@code}` or the `<pre>{@code ...}</pre>` pattern instead.
- Don't publish internal packages (`*.internal`, `*.impl`) in the public Javadoc — use `-exclude` or access modifiers to hide them.
- Don't duplicate the method signature in the Javadoc summary sentence — describe behavior and contracts, not what the code already states.
- Don't omit `@return` on non-void methods — it is the most commonly referenced tag when evaluating whether to call a function.
