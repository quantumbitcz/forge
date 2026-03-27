# Maven

## Overview

Maven is a declarative build automation and project management tool for JVM projects (Java, Kotlin, Scala, Groovy) that enforces convention over configuration through a fixed lifecycle model, standard directory layout, and POM (Project Object Model) XML descriptors. It remains the most widely deployed build system in the Java ecosystem — the majority of enterprise Java projects, open-source libraries published to Maven Central, and Spring Boot quickstarts use Maven. Its strength is predictability: every Maven project follows the same conventions, making onboarding trivial and CI pipelines interchangeable.

Use Maven when the project is an enterprise Java application that values ecosystem compatibility and team familiarity over build customization, when publishing libraries to Maven Central (which was designed around Maven's coordinate system), or when organizational policy mandates XML-based declarative builds with minimal procedural escape hatches. Maven's BOM (Bill of Materials) pattern and dependency management system are the de facto standard for version alignment across the Java ecosystem — even Gradle projects often consume Maven BOMs. For large multi-module projects (20+ modules), Maven's fixed lifecycle becomes a constraint rather than a feature — consider Gradle's task DAG model for finer-grained execution control.

Do not use Maven for non-JVM projects (use the language-native tool), for builds requiring complex conditional logic or dynamic task graphs (Maven's lifecycle is rigid by design), or for projects where build performance is critical and the build graph exceeds 15 modules (Maven's lack of configuration caching, limited parallel execution, and inability to skip unchanged modules without external tooling like `mvnd` put it at a significant disadvantage versus Gradle). For Android projects, Maven is not viable — Gradle is the only supported build system.

Key differentiators from Gradle: (1) Maven uses a fixed lifecycle (validate → compile → test → package → verify → install → deploy) rather than a task DAG — every build follows the same phase sequence, which is simple but inflexible. (2) POM files are pure XML with no procedural logic — this prevents the "build script as code" complexity that Gradle projects sometimes accumulate, but also prevents simple conditional logic without profiles. (3) Maven's dependency mediation uses "nearest wins" for version conflicts (the version declared closest to the root wins), while Gradle uses "highest version wins" by default — Maven's behavior is more surprising and requires explicit `<dependencyManagement>` to control. (4) Maven Wrapper (`mvnw`) mirrors Gradle Wrapper's purpose: pinning the exact Maven version per project. (5) Maven has no equivalent to Gradle's configuration cache, build cache, or task avoidance — every `mvn compile` re-evaluates the full project model and re-executes every phase up to `compile`.

## Architecture Patterns

### Parent POM Pattern

The parent POM is Maven's mechanism for sharing build configuration across modules. A parent POM defines plugin versions, plugin configurations, compiler settings, and common properties that child modules inherit. Unlike Gradle's convention plugins (which are composable and independently testable), Maven parent POMs form a single inheritance chain — a module can have only one parent. This is both a strength (simple mental model) and a limitation (no composition without profiles or mixins).

**Directory structure:**
```
project-root/
  pom.xml                    (parent POM, packaging = pom)
  core/
    pom.xml                  (child, inherits parent)
  adapter/
    api/
      pom.xml
    persistence/
      pom.xml
  app/
    pom.xml
  .mvn/
    wrapper/
      maven-wrapper.properties
    maven.config             (default CLI args)
    jvm.config               (JVM args for Maven)
```

**Root `pom.xml` — the parent POM:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
         https://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.example</groupId>
    <artifactId>my-project</artifactId>
    <version>1.0.0-SNAPSHOT</version>
    <packaging>pom</packaging>

    <modules>
        <module>core</module>
        <module>adapter/api</module>
        <module>adapter/persistence</module>
        <module>app</module>
    </modules>

    <properties>
        <java.version>21</java.version>
        <maven.compiler.source>${java.version}</maven.compiler.source>
        <maven.compiler.target>${java.version}</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
        <kotlin.version>2.1.0</kotlin.version>
        <spring-boot.version>3.4.1</spring-boot.version>
        <kotest.version>5.9.1</kotest.version>
        <mockk.version>1.13.13</mockk.version>
        <testcontainers.version>1.20.4</testcontainers.version>
    </properties>

    <dependencyManagement>
        <dependencies>
            <!-- Spring Boot BOM — manages all Spring dependency versions -->
            <dependency>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-dependencies</artifactId>
                <version>${spring-boot.version}</version>
                <type>pom</type>
                <scope>import</scope>
            </dependency>

            <!-- Kotlin BOM -->
            <dependency>
                <groupId>org.jetbrains.kotlin</groupId>
                <artifactId>kotlin-bom</artifactId>
                <version>${kotlin.version}</version>
                <type>pom</type>
                <scope>import</scope>
            </dependency>

            <!-- Project modules — allows children to declare without version -->
            <dependency>
                <groupId>com.example</groupId>
                <artifactId>core</artifactId>
                <version>${project.version}</version>
            </dependency>
        </dependencies>
    </dependencyManagement>

    <build>
        <pluginManagement>
            <plugins>
                <plugin>
                    <groupId>org.apache.maven.plugins</groupId>
                    <artifactId>maven-compiler-plugin</artifactId>
                    <version>3.13.0</version>
                    <configuration>
                        <release>${java.version}</release>
                        <parameters>true</parameters>
                    </configuration>
                </plugin>
                <plugin>
                    <groupId>org.apache.maven.plugins</groupId>
                    <artifactId>maven-surefire-plugin</artifactId>
                    <version>3.5.2</version>
                </plugin>
                <plugin>
                    <groupId>org.apache.maven.plugins</groupId>
                    <artifactId>maven-failsafe-plugin</artifactId>
                    <version>3.5.2</version>
                </plugin>
                <plugin>
                    <groupId>org.springframework.boot</groupId>
                    <artifactId>spring-boot-maven-plugin</artifactId>
                    <version>${spring-boot.version}</version>
                </plugin>
            </plugins>
        </pluginManagement>
    </build>
</project>
```

The critical distinction between `<dependencyManagement>` and `<dependencies>` is often misunderstood: `<dependencyManagement>` declares version constraints that child modules can opt into by declaring the dependency without a version. It does not add the dependency to any module's classpath. `<dependencies>` in the parent POM actually adds dependencies to every child module — use this only for truly universal dependencies (e.g., logging facades, annotation libraries). Misusing parent `<dependencies>` inflates every module's classpath with libraries it does not need.

### BOM Import Pattern

BOMs (Bills of Materials) are specialized POMs with `<packaging>pom</packaging>` that contain only `<dependencyManagement>`. They align versions across a family of libraries without imposing a parent POM relationship. Import multiple BOMs into a single project using `<scope>import</scope>` — this is Maven's closest equivalent to Gradle's platform dependencies.

```xml
<dependencyManagement>
    <dependencies>
        <!-- Spring Boot BOM -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-dependencies</artifactId>
            <version>${spring-boot.version}</version>
            <type>pom</type>
            <scope>import</scope>
        </dependency>

        <!-- Spring Cloud BOM -->
        <dependency>
            <groupId>org.springframework.cloud</groupId>
            <artifactId>spring-cloud-dependencies</artifactId>
            <version>2024.0.0</version>
            <type>pom</type>
            <scope>import</scope>
        </dependency>

        <!-- Jackson BOM -->
        <dependency>
            <groupId>com.fasterxml.jackson</groupId>
            <artifactId>jackson-bom</artifactId>
            <version>2.18.2</version>
            <type>pom</type>
            <scope>import</scope>
        </dependency>
    </dependencies>
</dependencyManagement>
```

BOM import order matters: when two BOMs manage the same dependency, the first BOM listed wins. Place the most important BOM first (typically Spring Boot, which manages hundreds of transitive versions). Override a BOM-managed version by declaring it explicitly in `<dependencyManagement>` before the BOM import — explicit declarations always take precedence over imported BOMs.

**Publishing a BOM for shared version alignment across repositories:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<project>
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.example</groupId>
    <artifactId>company-bom</artifactId>
    <version>1.0.0</version>
    <packaging>pom</packaging>

    <dependencyManagement>
        <dependencies>
            <dependency>
                <groupId>com.example</groupId>
                <artifactId>shared-model</artifactId>
                <version>2.3.0</version>
            </dependency>
            <dependency>
                <groupId>com.example</groupId>
                <artifactId>shared-security</artifactId>
                <version>1.5.0</version>
            </dependency>
        </dependencies>
    </dependencyManagement>
</project>
```

Consuming projects import this BOM and declare dependencies without versions. When the BOM publishes a new version, consumers update a single version string to align all shared library versions.

### Multi-Module Structure

Multi-module Maven projects use the reactor to build modules in dependency order. The reactor analyzes inter-module dependencies and computes a topological build order. Unlike Gradle, which can build independent modules in parallel by default, Maven's reactor processes modules sequentially unless explicitly configured with `-T`.

**Child module `core/pom.xml` — pure domain, no framework dependencies:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<project>
    <modelVersion>4.0.0</modelVersion>
    <parent>
        <groupId>com.example</groupId>
        <artifactId>my-project</artifactId>
        <version>1.0.0-SNAPSHOT</version>
    </parent>

    <artifactId>core</artifactId>

    <dependencies>
        <dependency>
            <groupId>org.jetbrains.kotlin</groupId>
            <artifactId>kotlin-stdlib</artifactId>
        </dependency>

        <dependency>
            <groupId>io.kotest</groupId>
            <artifactId>kotest-runner-junit5-jvm</artifactId>
            <version>${kotest.version}</version>
            <scope>test</scope>
        </dependency>
    </dependencies>
</project>
```

Child modules inherit `groupId`, `version`, plugin configurations, and property definitions from the parent. They must declare `<parent>` with the correct `relativePath` (defaults to `../pom.xml`). The `<artifactId>` is the only required unique identifier per child.

**Application module `app/pom.xml` — Spring Boot packaged:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<project>
    <modelVersion>4.0.0</modelVersion>
    <parent>
        <groupId>com.example</groupId>
        <artifactId>my-project</artifactId>
        <version>1.0.0-SNAPSHOT</version>
        <relativePath>../pom.xml</relativePath>
    </parent>

    <artifactId>app</artifactId>

    <dependencies>
        <dependency>
            <groupId>com.example</groupId>
            <artifactId>core</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-actuator</artifactId>
        </dependency>

        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-test</artifactId>
            <scope>test</scope>
        </dependency>
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
                <configuration>
                    <layers>
                        <enabled>true</enabled>
                    </layers>
                </configuration>
            </plugin>
        </plugins>
    </build>
</project>
```

Spring Boot starters do not declare a version because the Spring Boot BOM imported in the parent's `<dependencyManagement>` provides it. The `spring-boot-maven-plugin` is declared in `<plugins>` (not `<pluginManagement>`) because only the `app` module produces a bootable JAR — other modules are plain JARs.

### Maven Wrapper

Maven Wrapper (`mvnw`) pins the exact Maven version per project, eliminating "works on my Maven" issues. Every project should use it — never rely on a globally installed `mvn`.

**Setup:**
```bash
# Generate wrapper files (run once, commit the results)
mvn wrapper:wrapper -Dmaven=3.9.9

# Resulting files (all committed to version control)
.mvn/wrapper/maven-wrapper.properties
.mvn/wrapper/maven-wrapper.jar
mvnw
mvnw.cmd
```

**`.mvn/wrapper/maven-wrapper.properties`:**
```properties
distributionUrl=https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.9/apache-maven-3.9.9-bin.zip
wrapperUrl=https://repo.maven.apache.org/maven2/org/apache/maven/wrapper/maven-wrapper/3.3.2/maven-wrapper-3.3.2.jar
distributionSha256Sum=7a5c4a2b1b89756c10b5e84f59f97577faa5b87155a0708c890894b59fc9aa55
wrapperSha256Sum=e63a53cfb9c4d291ebe3c2564c3f29e6fc1b8302e7b09c25b5f51a1b66febb97
```

Always include `distributionSha256Sum` for integrity verification. Commit `maven-wrapper.jar` to version control — it bootstraps the download of the pinned Maven version. Use `./mvnw` instead of `mvn` in all CI scripts and developer documentation.

**`.mvn/maven.config`** — default CLI arguments applied to every invocation:
```
--batch-mode
--strict-checksums
--fail-at-end
--show-version
```

**`.mvn/jvm.config`** — JVM arguments for Maven itself:
```
-Xmx2g
-XX:+UseG1GC
```

These files are committed and shared by the team. They eliminate the need for every developer to remember the correct CLI flags and JVM settings.

## Configuration

### Development

Maven's configuration is layered: project `pom.xml` (committed), user `~/.m2/settings.xml` (not committed), and environment variables or system properties (`-D`). The `settings.xml` contains repository credentials, mirror configurations, and active profile selections that vary per developer.

**`~/.m2/settings.xml`** — developer-local settings:
```xml
<settings>
    <servers>
        <server>
            <id>nexus-releases</id>
            <username>${env.MAVEN_USERNAME}</username>
            <password>${env.MAVEN_PASSWORD}</password>
        </server>
        <server>
            <id>nexus-snapshots</id>
            <username>${env.MAVEN_USERNAME}</username>
            <password>${env.MAVEN_PASSWORD}</password>
        </server>
    </servers>

    <mirrors>
        <mirror>
            <id>nexus</id>
            <mirrorOf>central</mirrorOf>
            <url>https://nexus.internal.example.com/repository/maven-central/</url>
        </mirror>
    </mirrors>
</settings>
```

Credentials reference environment variables (`${env.MAVEN_USERNAME}`) rather than hardcoded values. The `<mirrors>` section routes all Maven Central traffic through an internal proxy (Nexus, Artifactory) for caching, auditing, and network isolation.

**Maven profiles for environment-specific configuration:**
```xml
<profiles>
    <profile>
        <id>dev</id>
        <activation>
            <activeByDefault>true</activeByDefault>
        </activation>
        <properties>
            <spring.profiles.active>dev</spring.profiles.active>
        </properties>
    </profile>

    <profile>
        <id>ci</id>
        <activation>
            <property>
                <name>env.CI</name>
            </property>
        </activation>
        <properties>
            <spring.profiles.active>ci</spring.profiles.active>
            <maven.test.failure.ignore>false</maven.test.failure.ignore>
        </properties>
        <build>
            <plugins>
                <plugin>
                    <groupId>org.jacoco</groupId>
                    <artifactId>jacoco-maven-plugin</artifactId>
                    <version>0.8.12</version>
                    <executions>
                        <execution>
                            <goals><goal>prepare-agent</goal></goals>
                        </execution>
                        <execution>
                            <id>report</id>
                            <phase>verify</phase>
                            <goals><goal>report</goal></goals>
                        </execution>
                    </executions>
                </plugin>
            </plugins>
        </build>
    </profile>
</profiles>
```

The `ci` profile activates automatically when the `CI` environment variable is set (standard in GitHub Actions, GitLab CI, Jenkins). It enables JaCoCo coverage reporting and strict test failure handling. Profiles replace conditional logic that Gradle handles with `if/else` in Kotlin scripts — they are Maven's mechanism for build variants.

### Production

**CI pipeline invocation — optimized for reproducible, auditable builds:**
```bash
./mvnw clean verify \
  --batch-mode \
  --strict-checksums \
  --fail-at-end \
  --show-version \
  -T 1C \
  -Pci
```

- `--batch-mode` — disables interactive input, produces clean log output for CI.
- `--strict-checksums` — fails if downloaded artifact checksums do not match. This is Maven's defense against tampered dependencies.
- `--fail-at-end` — reports all module failures instead of stopping at the first one. Essential for multi-module projects where unrelated modules may fail independently.
- `-T 1C` — parallel build using 1 thread per CPU core.
- `-Pci` — activates the CI profile.

**Maven Enforcer Plugin — prevents common build hygiene issues:**
```xml
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-enforcer-plugin</artifactId>
    <version>3.5.0</version>
    <executions>
        <execution>
            <id>enforce</id>
            <goals><goal>enforce</goal></goals>
            <configuration>
                <rules>
                    <requireMavenVersion>
                        <version>[3.9.0,)</version>
                    </requireMavenVersion>
                    <requireJavaVersion>
                        <version>[21,)</version>
                    </requireJavaVersion>
                    <banDuplicatePomDependencyVersions/>
                    <dependencyConvergence/>
                    <reactorModuleConvergence/>
                    <requireUpperBoundDeps/>
                    <banDistributionManagement/>
                </rules>
            </configuration>
        </execution>
    </executions>
</plugin>
```

- `dependencyConvergence` — fails if the same dependency is resolved at different versions across the reactor. This catches version conflicts that Maven's "nearest wins" mediation silently resolves.
- `requireUpperBoundDeps` — fails if a transitive dependency is resolved at a lower version than a direct dependency requires. This catches cases where "nearest wins" selects an older version.
- `banDuplicatePomDependencyVersions` — fails if the same dependency is declared twice with different versions in the same POM.
- `reactorModuleConvergence` — fails if reactor modules have inconsistent parent versions.

The enforcer plugin is the single most important plugin for multi-module Maven project health. Enable it from day one.

**GitHub Actions example:**
```yaml
- name: Set up JDK 21
  uses: actions/setup-java@v4
  with:
    java-version: '21'
    distribution: 'temurin'
    cache: 'maven'

- name: Build and verify
  run: |
    ./mvnw clean verify \
      --batch-mode \
      --strict-checksums \
      -T 1C \
      -Pci

- name: Publish test results
  uses: mikepenz/action-junit-report@v4
  if: always()
  with:
    report_paths: '**/target/surefire-reports/TEST-*.xml'
```

The `actions/setup-java` action with `cache: 'maven'` caches `~/.m2/repository` across CI runs, reducing dependency download time from minutes to seconds.

**`mvnd` (Maven Daemon) for faster local builds:**

`mvnd` is a daemon-based Maven distribution that keeps the JVM resident between builds, similar to Gradle's daemon. It provides 2-5x faster builds on multi-module projects by avoiding JVM cold starts and leveraging JIT compilation across invocations.

```bash
# Install mvnd (macOS)
brew install mvndaemon/mvnd/mvnd

# Use as drop-in replacement for mvn/mvnw
mvnd clean verify -T 1C

# Configure daemon JVM args
# ~/.mvnd/mvnd.properties
mvnd.jvmArgs=-Xmx4g -XX:+UseG1GC
```

`mvnd` is a development-time optimization only. CI pipelines should use `./mvnw` for reproducibility — the daemon's persistent JVM state can mask initialization bugs and environment issues.

## Performance

**Parallel builds** (`-T`) are Maven's primary performance lever. The reactor builds modules concurrently when their dependency graph allows it. Use `-T 1C` (one thread per CPU core) as the default and adjust based on available memory:

```bash
# 1 thread per core (recommended default)
./mvnw clean verify -T 1C

# Fixed thread count (for memory-constrained CI runners)
./mvnw clean verify -T 4

# Skip tests for fast feedback (development only, never CI)
./mvnw clean package -DskipTests
```

**Incremental builds** are Maven's weakness compared to Gradle. Maven does not cache task outputs, does not track file-level dependencies for incremental compilation (the compiler plugin does, but Maven itself does not), and re-evaluates the entire project model on every invocation. The workarounds are:

1. **`mvnd`** — the Maven Daemon keeps the JVM warm and caches classloader trees, providing 2-5x speedup for local builds.
2. **Module-targeted builds** — build only the module you are working on and its dependents:
   ```bash
   # Build only the core module
   ./mvnw -pl core clean verify

   # Build core and all modules that depend on it
   ./mvnw -pl core -amd clean verify

   # Build core and all modules it depends on
   ./mvnw -pl app -am clean verify
   ```
3. **Skip unchanged modules** — Maven 4.x introduces `--resume-from` and experimental incremental module detection. For Maven 3.x, use `-pl` targeting.

**Dependency resolution performance:**
- Configure a repository mirror (Nexus/Artifactory) to avoid direct Maven Central lookups.
- Use `--offline` or `-o` for fully cached local builds when no dependency changes are expected.
- Avoid SNAPSHOT dependencies in multi-module builds when possible — Maven checks for updated SNAPSHOTs on every build, adding network latency. Configure `<updatePolicy>interval:60</updatePolicy>` to limit checks.

**Build profiling:**
```bash
# Verbose timing output
./mvnw clean verify -X 2>&1 | grep -E "\[INFO\] -------|Total time"

# Maven build time extension
./mvnw clean verify -Dorg.slf4j.simpleLogger.dateTimeFormat=HH:mm:ss,SSS

# Third-party profiler
./mvnw clean verify -Dmaven.ext.class.path=path/to/maven-profiler.jar
```

**Plugin execution optimization:**
- Pin all plugin versions explicitly in `<pluginManagement>` — Maven resolves the latest version at build time if not pinned, adding network lookups and non-reproducibility.
- Use `<skip>` properties to disable plugins per module when they are not needed:
  ```xml
  <properties>
      <jacoco.skip>true</jacoco.skip>  <!-- Skip coverage for utility modules -->
  </properties>
  ```

## Security

**Checksum verification** is Maven's primary defense against tampered dependencies. Use `--strict-checksums` to fail the build if any downloaded artifact's checksum does not match the repository-provided checksum. Without this flag, Maven logs a warning and continues — which means a supply chain attack produces a warning in build logs that nobody reads.

**Repository security — prevent dependency confusion attacks:**
```xml
<!-- settings.xml or pom.xml -->
<repositories>
    <repository>
        <id>internal</id>
        <url>https://nexus.internal.example.com/repository/internal/</url>
        <releases><enabled>true</enabled></releases>
        <snapshots><enabled>false</enabled></snapshots>
    </repository>
    <repository>
        <id>central</id>
        <url>https://repo.maven.apache.org/maven2</url>
        <releases><enabled>true</enabled></releases>
        <snapshots><enabled>false</enabled></snapshots>
    </repository>
</repositories>
```

Maven resolves dependencies by checking repositories in declaration order. If an attacker publishes a same-named artifact to Maven Central with a higher version than your internal artifact, Maven may resolve the malicious version. Mitigate by:
1. Using a repository manager (Nexus/Artifactory) as a mirror for all external repositories.
2. Configuring repository routing rules in the repository manager so internal group IDs can only resolve from internal repositories.
3. Never using `<snapshots><enabled>true</enabled></snapshots>` for external repositories in production builds.

**Maven Enforcer for security constraints:**
```xml
<rules>
    <bannedDependencies>
        <excludes>
            <exclude>commons-logging:commons-logging</exclude>
            <exclude>log4j:log4j</exclude>
            <exclude>org.apache.logging.log4j:log4j-core:(,2.17.1)</exclude>
        </excludes>
        <message>Banned dependencies detected — use SLF4J with Logback</message>
    </bannedDependencies>
</rules>
```

Ban known-vulnerable libraries from the dependency tree. The enforcer plugin fails the build if any transitive path pulls in a banned artifact, which is more reliable than relying on developers to notice CVE reports.

**No secrets in `pom.xml`** — the POM is committed to version control. All credentials belong in `~/.m2/settings.xml` (developer machines) or CI secret stores (environment variables). Reference them in the POM via property interpolation:

```xml
<distributionManagement>
    <repository>
        <id>nexus-releases</id>
        <url>https://nexus.internal.example.com/repository/releases/</url>
    </repository>
</distributionManagement>
```

The `<id>nexus-releases</id>` matches the `<server><id>` in `settings.xml` where credentials are stored. The POM contains only the URL; the credentials travel through a separate, uncommitted channel.

**GPG signing for artifact publishing:**
```bash
# Sign artifacts during deploy
./mvnw deploy -Dgpg.keyname=YOUR_KEY_ID -Dgpg.passphrase="${GPG_PASSPHRASE}"
```

Configure the `maven-gpg-plugin` in `<pluginManagement>` and activate it via a `release` profile to avoid signing during local development.

**Supply chain hardening checklist:**
- Enable `--strict-checksums` in `.mvn/maven.config`.
- Use Maven Enforcer with `dependencyConvergence`, `requireUpperBoundDeps`, and `bannedDependencies`.
- Route all repository traffic through an internal mirror (Nexus/Artifactory).
- Pin all plugin versions — never rely on Maven's default plugin versions.
- Use Maven Wrapper and commit the wrapper JAR.
- Enable GPG signing for all published artifacts.
- Run `./mvnw dependency:tree` in CI and diff against the previous run to detect unexpected transitive changes.
- Audit new dependencies with `./mvnw dependency:analyze` to find unused declared and used undeclared dependencies.

## Testing

**Surefire plugin** runs unit tests during the `test` phase. **Failsafe plugin** runs integration tests during the `integration-test` and `verify` phases. The naming convention matters: Surefire picks up `*Test.java`, `Test*.java`, `*Tests.java`, `*TestCase.java`. Failsafe picks up `*IT.java`, `IT*.java`, `*ITCase.java`. Mixing these naming conventions is the most common cause of "my tests don't run" issues.

**Surefire configuration with JUnit 5:**
```xml
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-surefire-plugin</artifactId>
    <configuration>
        <includes>
            <include>**/*Test.java</include>
            <include>**/*Tests.java</include>
            <include>**/*Spec.java</include>
        </includes>
        <argLine>
            -XX:+EnableDynamicAgentLoading
            --add-opens java.base/java.lang=ALL-UNNAMED
        </argLine>
        <forkCount>1C</forkCount>
        <reuseForks>true</reuseForks>
    </configuration>
</plugin>
```

- `forkCount=1C` — one fork per CPU core for parallel test execution.
- `reuseForks=true` — reuse JVM forks across test classes (faster) rather than spawning a new JVM per class.

**Failsafe configuration for integration tests:**
```xml
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-failsafe-plugin</artifactId>
    <executions>
        <execution>
            <goals>
                <goal>integration-test</goal>
                <goal>verify</goal>
            </goals>
        </execution>
    </executions>
    <configuration>
        <includes>
            <include>**/*IT.java</include>
            <include>**/*IntegrationTest.java</include>
        </includes>
        <systemPropertyVariables>
            <spring.profiles.active>integration</spring.profiles.active>
        </systemPropertyVariables>
    </configuration>
</plugin>
```

The two-phase execution (integration-test + verify) is critical: `integration-test` runs the tests, and `verify` checks the results. If you only bind to `integration-test`, the build succeeds even when integration tests fail — the results are not checked until `verify`.

**Test filtering for fast feedback:**
```bash
# Run a single test class
./mvnw -pl core test -Dtest=UserServiceTest

# Run a single test method
./mvnw -pl core test -Dtest="UserServiceTest#should create user with valid email"

# Run tests matching a pattern
./mvnw -pl core test -Dtest="*UserService*"

# Skip all tests
./mvnw clean package -DskipTests

# Skip test compilation AND execution
./mvnw clean package -Dmaven.test.skip=true
```

The difference between `-DskipTests` and `-Dmaven.test.skip=true` is subtle but important: `-DskipTests` compiles test classes but does not run them (catches compilation errors), while `-Dmaven.test.skip=true` skips both compilation and execution (faster but misses compile errors in test code).

**Test reporting in CI:**
```bash
# Surefire reports (unit tests)
target/surefire-reports/TEST-*.xml

# Failsafe reports (integration tests)
target/failsafe-reports/TEST-*.xml
```

Configure your CI platform to collect both report directories. The `maven-surefire-report-plugin` generates HTML reports, but for CI, the XML format consumed by test result aggregators (GitHub Actions, Jenkins) is more useful.

## Dos

- Use Maven Wrapper (`mvnw`) for every project and commit the wrapper files. Never rely on a globally installed `mvn`. The wrapper guarantees every developer and CI runner uses the exact same Maven version.
- Use `<dependencyManagement>` in the parent POM for all shared dependency versions. Child modules declare dependencies without versions — the parent provides them. This creates a single source of truth for version alignment across the entire multi-module project.
- Import BOMs (`<scope>import</scope>`) for library families (Spring Boot, Jackson, Kotlin). BOMs align transitive dependency versions and prevent version conflicts that Maven's "nearest wins" mediation would otherwise resolve silently and incorrectly.
- Enable the Maven Enforcer Plugin with `dependencyConvergence`, `requireUpperBoundDeps`, and minimum version rules from day one. The enforcer catches dependency conflicts, version downgrades, and build hygiene issues that would otherwise surface as mysterious runtime `ClassNotFoundException` or `NoSuchMethodError`.
- Use `--strict-checksums` in `.mvn/maven.config` to fail on tampered dependencies. This is Maven's defense against supply chain attacks — without it, checksum failures produce warnings that nobody reads.
- Pin all plugin versions in `<pluginManagement>`. Maven's default plugin versions (the "super POM") change between Maven releases, producing non-reproducible builds. Pinning eliminates this variable.
- Separate unit tests (Surefire, `*Test.java`) from integration tests (Failsafe, `*IT.java`). This allows running fast unit tests independently (`mvn test`) while still running the full suite in CI (`mvn verify`).
- Use `--batch-mode` and `--fail-at-end` in CI. Batch mode produces clean logs without interactive prompts. Fail-at-end reports all module failures instead of stopping at the first one.
- Use profiles for environment-specific configuration. Activate CI profiles via environment properties rather than manual `-P` flags to avoid human error.
- Use `./mvnw dependency:analyze` regularly to detect unused declared dependencies and used-but-undeclared dependencies. Both are dependency hygiene issues that accumulate into classpath bloat and mysterious failures.

## Don'ts

- Don't use `<dependencies>` in the parent POM for anything except truly universal dependencies. Every dependency in the parent's `<dependencies>` section is inherited by every child module, inflating classpaths with irrelevant libraries. Use `<dependencyManagement>` to define versions, and let child modules explicitly declare what they need.
- Don't rely on Maven's "nearest wins" dependency mediation without the enforcer plugin. When two transitive paths resolve the same dependency at different versions, Maven picks the version closest to the root of the dependency tree — which may be the older, incompatible version. `dependencyConvergence` and `requireUpperBoundDeps` catch these conflicts before runtime.
- Don't hardcode credentials in `pom.xml` or committed `settings.xml`. The POM is committed to version control. Credentials belong in `~/.m2/settings.xml` (developer machines) or CI secret stores. Reference repository IDs that match `<server>` entries in `settings.xml`.
- Don't use Maven 2.x lifecycle plugins or legacy plugin versions without checking compatibility. Plugins like `maven-compiler-plugin` version 2.x, `maven-deploy-plugin` version 2.x, and the original `maven-site-plugin` have been superseded by 3.x versions with different behaviors, better performance, and security fixes.
- Don't use `<snapshots><enabled>true</enabled></snapshots>` for external repositories in production builds. SNAPSHOT dependencies are mutable — the same coordinate can resolve to different bytecode on different builds. Disable snapshot resolution for all external repositories and use release versions only.
- Don't skip the `verify` phase when using Failsafe. Running only `mvn integration-test` executes integration tests but does not check their results — the build succeeds even if tests fail. Always run `mvn verify` to ensure Failsafe reports failures correctly.
- Don't use `<repositories>` in child POMs. Repository declarations should be centralized in the parent POM or `settings.xml`. Scattered repository declarations across modules create inconsistent dependency resolution and make security auditing impossible.
- Don't ignore `dependency:analyze` warnings. "Unused declared dependencies" bloat the classpath and slow compilation. "Used undeclared dependencies" work by accident (resolved transitively) and break when the transitive path changes. Fix both categories proactively.
- Don't use property-based version management (`${some.version}`) without documenting the properties in the parent POM. Unlike Gradle's version catalogs (which generate type-safe accessors), Maven properties are stringly-typed and produce unhelpful errors when misspelled. Keep all version properties in the parent POM's `<properties>` section as the single source of truth.
- Don't use the `maven-release-plugin` without understanding its two-phase workflow (prepare + perform). The `release:prepare` goal modifies the POM, commits, and tags — if it fails halfway through, the repository is left in an inconsistent state. Consider simpler alternatives like `jgitver-maven-plugin` or CI-driven versioning with `${revision}` placeholders for projects that do not need Maven Central publication.
