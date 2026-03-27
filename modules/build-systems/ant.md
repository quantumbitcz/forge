# Ant

## Overview

Apache Ant (Another Neat Tool) is an imperative, XML-based build system for JVM projects that predates Maven and Gradle. It was the first widely adopted Java build tool, replacing platform-specific Makefiles with a portable, XML-driven task execution engine. Ant makes no assumptions about project structure — there are no conventions, no standard directory layouts, and no lifecycle phases. Every build step is explicitly defined as a task in `build.xml`, giving complete control at the cost of significant boilerplate and per-project inconsistency.

Ant is a legacy tool. No greenfield project should use Ant. Its inclusion in this module exists for one purpose: to provide migration guidance for the millions of existing Ant-based projects that need to move to Gradle or Maven. Ant's lack of built-in dependency management (addressed partially by Ivy), absence of incremental compilation, no parallel execution support, and imperative XML programming model make it fundamentally unsuitable for modern development workflows. Every aspect of build engineering that Gradle and Maven automate — dependency resolution, transitive dependency management, convention-based configuration, build caching, parallel execution — must be manually implemented in Ant.

Use Ant only when maintaining an existing Ant-based project that cannot be migrated immediately. Common scenarios include: legacy enterprise applications with deeply customized build processes that would take significant effort to replicate in Gradle/Maven, projects with regulatory constraints on build tool changes, and build pipelines that execute Ant as a subroutine for specific tasks (e.g., legacy code generation scripts). In all these cases, the long-term goal should be migration to Gradle or Maven.

Do not use Ant for new projects of any kind. Do not add new Ant tasks to existing projects when the equivalent can be achieved with a Gradle task or Maven plugin. Every new Ant task increases the migration cost and deepens the legacy investment.

Key limitations compared to Gradle/Maven: (1) No built-in dependency management — Ant does not resolve, download, or manage library dependencies. Apache Ivy adds this capability, but it is a separate tool with its own configuration. (2) No convention over configuration — every project must define its own directory structure, compilation sequence, test execution, and packaging in build.xml. (3) No incremental builds — Ant re-executes tasks based on basic file timestamp checking, not content hashing or input/output tracking. (4) No build cache — task outputs are never cached across builds. (5) No parallel execution — tasks execute sequentially within a target, and targets execute in dependency order with no parallelism. (6) No plugin ecosystem — reusable build logic is shared via custom task JARs or macrodefs, not a package registry.

## Architecture Patterns

### Build.xml Structure

Ant's `build.xml` defines a project with properties, targets (analogous to tasks), and tasks (the actual work units). Targets have dependencies — `compile` depends on `init`, `test` depends on `compile`, etc. — forming a DAG that Ant executes in topological order. Unlike Maven's fixed lifecycle or Gradle's lazy task graph, Ant's target graph is entirely developer-defined.

**Standard `build.xml` structure:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<project name="my-project" default="build" basedir=".">

    <!-- Properties — equivalent to constants -->
    <property name="src.dir" value="src/main/java"/>
    <property name="test.dir" value="src/test/java"/>
    <property name="build.dir" value="build"/>
    <property name="classes.dir" value="${build.dir}/classes"/>
    <property name="test.classes.dir" value="${build.dir}/test-classes"/>
    <property name="lib.dir" value="lib"/>
    <property name="dist.dir" value="${build.dir}/dist"/>
    <property name="reports.dir" value="${build.dir}/reports"/>
    <property name="java.version" value="21"/>

    <!-- Classpaths — must be declared explicitly -->
    <path id="compile.classpath">
        <fileset dir="${lib.dir}" includes="*.jar" excludes="*-test.jar"/>
    </path>

    <path id="test.classpath">
        <path refid="compile.classpath"/>
        <fileset dir="${lib.dir}" includes="*-test.jar"/>
        <pathelement location="${classes.dir}"/>
        <pathelement location="${test.classes.dir}"/>
    </path>

    <!-- Targets -->
    <target name="init" description="Create output directories">
        <mkdir dir="${classes.dir}"/>
        <mkdir dir="${test.classes.dir}"/>
        <mkdir dir="${dist.dir}"/>
        <mkdir dir="${reports.dir}"/>
    </target>

    <target name="compile" depends="init" description="Compile source">
        <javac srcdir="${src.dir}"
               destdir="${classes.dir}"
               classpathref="compile.classpath"
               source="${java.version}"
               target="${java.version}"
               includeantruntime="false"
               debug="true"
               encoding="UTF-8">
            <compilerarg value="-Xlint:all"/>
        </javac>
    </target>

    <target name="compile-tests" depends="compile" description="Compile tests">
        <javac srcdir="${test.dir}"
               destdir="${test.classes.dir}"
               classpathref="test.classpath"
               source="${java.version}"
               target="${java.version}"
               includeantruntime="false"
               debug="true"
               encoding="UTF-8"/>
    </target>

    <target name="test" depends="compile-tests" description="Run tests">
        <junit printsummary="on" haltonfailure="yes" fork="yes" forkmode="once">
            <classpath refid="test.classpath"/>
            <formatter type="xml"/>
            <batchtest todir="${reports.dir}">
                <fileset dir="${test.dir}" includes="**/*Test.java"/>
            </batchtest>
        </junit>
    </target>

    <target name="jar" depends="compile" description="Create JAR">
        <jar destfile="${dist.dir}/${ant.project.name}.jar" basedir="${classes.dir}">
            <manifest>
                <attribute name="Main-Class" value="com.example.Main"/>
                <attribute name="Built-By" value="${user.name}"/>
                <attribute name="Build-Date" value="${TODAY}"/>
            </manifest>
        </jar>
    </target>

    <target name="build" depends="test,jar" description="Full build"/>

    <target name="clean" description="Delete build artifacts">
        <delete dir="${build.dir}"/>
    </target>
</project>
```

This build.xml contains roughly 70 lines of XML to achieve what Gradle does in 5 lines with a convention plugin, or what Maven does with zero configuration (convention over configuration). Every directory, classpath, compiler flag, and execution step is manually declared. This verbosity is Ant's fundamental problem at scale — a 20-module project requires thousands of lines of build XML that must be maintained in sync.

Note `includeantruntime="false"` on `<javac>` — without this, Ant adds its own JAR to the compilation classpath, which pollutes the build with Ant-specific classes and produces builds that are not reproducible outside Ant. Always set this to `false`.

### Ivy Dependency Management

Apache Ivy adds dependency resolution to Ant, filling Ant's most critical gap. Ivy resolves dependencies from Maven repositories (including Maven Central), manages transitive dependencies, and creates classpaths from resolved artifacts. However, Ivy is a separate project with its own XML configuration, and its integration with Ant is manual — there is no seamless experience like Maven's or Gradle's.

**`ivy.xml` — dependency descriptor:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<ivy-module version="2.0">
    <info organisation="com.example" module="my-project" revision="1.0.0"/>

    <configurations>
        <conf name="compile" description="Compile dependencies"/>
        <conf name="test" extends="compile" description="Test dependencies"/>
        <conf name="runtime" extends="compile" description="Runtime dependencies"/>
    </configurations>

    <dependencies>
        <dependency org="org.springframework.boot" name="spring-boot-starter-web"
                    rev="3.4.1" conf="compile->default"/>
        <dependency org="com.fasterxml.jackson.core" name="jackson-databind"
                    rev="2.18.2" conf="compile->default"/>
        <dependency org="org.slf4j" name="slf4j-api"
                    rev="2.0.16" conf="compile->default"/>

        <!-- Test dependencies -->
        <dependency org="junit" name="junit"
                    rev="4.13.2" conf="test->default"/>
        <dependency org="org.mockito" name="mockito-core"
                    rev="5.14.2" conf="test->default"/>
    </dependencies>
</ivy-module>
```

**`ivysettings.xml` — repository configuration:**
```xml
<ivysettings>
    <settings defaultResolver="chain"/>
    <resolvers>
        <chain name="chain">
            <ibiblio name="maven-central" m2compatible="true"
                     root="https://repo.maven.apache.org/maven2/"/>
            <ibiblio name="internal" m2compatible="true"
                     root="https://nexus.internal.example.com/repository/releases/"/>
        </chain>
    </resolvers>
</ivysettings>
```

**Integrating Ivy with Ant's build.xml:**
```xml
<!-- Load Ivy task definitions -->
<taskdef resource="org/apache/ivy/ant/antlib.xml"
         uri="antlib:org.apache.ivy.ant"
         classpath="lib/ivy-2.5.2.jar"/>

<!-- Resolve dependencies -->
<target name="resolve" description="Resolve Ivy dependencies">
    <ivy:retrieve pattern="${lib.dir}/[conf]/[artifact]-[revision].[ext]"
                  sync="true"/>
</target>

<!-- Create classpaths from resolved dependencies -->
<target name="init-classpath" depends="resolve">
    <ivy:cachepath pathid="compile.classpath" conf="compile"/>
    <ivy:cachepath pathid="test.classpath" conf="test"/>
</target>
```

Ivy's `<retrieve>` task downloads dependencies into the `lib/` directory with a configurable naming pattern. The `sync="true"` attribute removes artifacts that are no longer declared, preventing stale JARs. The `<cachepath>` task creates Ant path references directly from Ivy's cache, avoiding the need to copy JARs into the project.

### Macrodef Patterns

Macrodefs are Ant's mechanism for reusable build logic — they define parameterized task sequences that can be called like built-in tasks. They are the closest Ant equivalent to Gradle's convention plugins or Maven's plugin MOJOs.

**Reusable compilation macrodef:**
```xml
<macrodef name="compile-module">
    <attribute name="src"/>
    <attribute name="dest"/>
    <attribute name="classpathref"/>
    <sequential>
        <mkdir dir="@{dest}"/>
        <javac srcdir="@{src}"
               destdir="@{dest}"
               classpathref="@{classpathref}"
               source="${java.version}"
               target="${java.version}"
               includeantruntime="false"
               debug="true"
               encoding="UTF-8">
            <compilerarg value="-Xlint:all"/>
        </javac>
    </sequential>
</macrodef>

<!-- Usage -->
<target name="compile-core" depends="init">
    <compile-module src="modules/core/src" dest="${build.dir}/core"
                    classpathref="compile.classpath"/>
</target>

<target name="compile-api" depends="compile-core">
    <compile-module src="modules/api/src" dest="${build.dir}/api"
                    classpathref="api.classpath"/>
</target>
```

Macrodefs reduce duplication but do not solve Ant's fundamental problems: they cannot manage dependencies, they do not support incremental compilation, and they execute imperatively (no task avoidance, no caching). They are a band-aid on a structural issue.

**Import pattern for shared build logic:**
```xml
<!-- common-build.xml — shared across projects -->
<project name="common">
    <macrodef name="compile-module">
        <!-- ... as above ... -->
    </macrodef>

    <macrodef name="run-tests">
        <!-- ... test execution template ... -->
    </macrodef>
</project>

<!-- Project-specific build.xml -->
<project name="my-project" default="build">
    <import file="common-build.xml"/>
    <!-- Use macrodefs from common-build.xml -->
</project>
```

The import pattern is Ant's version of build logic inheritance. Unlike Maven's parent POM (which publishes to a repository), Ant imports are file-based — the shared build file must be accessible via the filesystem, typically through a checked-out shared repository or a submodule.

### Migration to Gradle/Maven

Migration from Ant is the most important architectural decision for any Ant-based project. The approach depends on the project's complexity and the team's familiarity with the target build tool.

**Migration strategy 1: Gradle wrapping Ant (incremental migration)**

Gradle can execute Ant targets directly, enabling incremental migration where Ant targets are replaced one at a time with Gradle tasks:

```kotlin
// build.gradle.kts — wraps existing build.xml
ant.importBuild("build.xml")

// Override the Ant 'compile' target with a Gradle task
tasks.register<JavaCompile>("compile") {
    source = fileTree("src/main/java")
    classpath = files("lib/")
    destinationDirectory.set(layout.buildDirectory.dir("classes"))
    sourceCompatibility = "21"
    targetCompatibility = "21"
}
```

This approach lets the team migrate one target at a time while maintaining a working build at every step. The Ant targets and Gradle tasks coexist — Gradle delegates to Ant for unmigrated targets and uses native Gradle tasks for migrated ones.

**Migration strategy 2: Maven pom.xml generation (full migration)**

For projects with standard layouts, generate a `pom.xml` from the Ant build structure:

```bash
# Analyze the Ant build to understand the dependency and target structure
ant -projecthelp -verbose

# Map Ant targets to Maven lifecycle phases:
# init        → (automatic in Maven)
# compile     → compile phase
# test        → test phase
# jar/war     → package phase
# deploy      → deploy phase

# Move source files to Maven standard layout:
# src/main/java/ (from wherever Ant configured them)
# src/test/java/
# src/main/resources/
```

**Migration strategy 3: Gradle with Ant compatibility (hybrid)**

```kotlin
// settings.gradle.kts
rootProject.name = "migrated-project"

// build.gradle.kts
plugins {
    java
}

java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(21))
    }
}

repositories {
    mavenCentral()
}

// Migrate Ivy dependencies to Gradle
dependencies {
    implementation("org.springframework.boot:spring-boot-starter-web:3.4.1")
    implementation("com.fasterxml.jackson.core:jackson-databind:2.18.2")
    testImplementation("org.junit.jupiter:junit-jupiter:5.11.4")
}

// If custom Ant tasks still needed temporarily
tasks.register("legacyCodeGen") {
    doLast {
        ant.withGroovyBuilder {
            "taskdef"(
                "name" to "custom-codegen",
                "classname" to "com.example.CodeGenTask",
                "classpath" to configurations.getByName("runtimeClasspath").asPath
            )
            "custom-codegen"("src" to "schema/", "dest" to "build/generated/")
        }
    }
}
```

**Migration checklist:**
1. Inventory all Ant targets and their dependencies — draw the target DAG.
2. Identify custom Ant tasks (Java classes extending `org.apache.tools.ant.Task`) — these need Gradle/Maven equivalents or wrappers.
3. Map Ivy dependencies to Maven coordinates — most will be 1:1.
4. Migrate the directory layout to the standard convention (`src/main/java`, `src/test/java`).
5. Replace Ant property files with the target tool's configuration (Gradle `gradle.properties`, Maven `pom.xml` properties).
6. Replace macrodefs with convention plugins (Gradle) or plugin configurations (Maven).
7. Verify the migrated build produces identical artifacts — compare JAR contents, classpath, and test results.
8. Remove `build.xml`, `ivy.xml`, `ivysettings.xml`, and the `lib/` directory of checked-in JARs.

## Configuration

### Development

Ant's configuration is purely file-based: `build.xml` (the build descriptor), optional `build.properties` (externalized property values), and `ivy.xml` / `ivysettings.xml` (if using Ivy for dependencies).

**`build.properties` — externalized configuration:**
```properties
# Source directories
src.dir=src/main/java
test.dir=src/test/java
resources.dir=src/main/resources

# Build output
build.dir=build
dist.dir=build/dist

# Compiler settings
java.version=21
debug=true
encoding=UTF-8

# Ivy settings
ivy.cache.dir=${user.home}/.ivy2/cache
```

**Environment-specific overrides:**
```bash
# Override properties via command line
ant build -Djava.version=17 -Ddebug=false

# Use an alternate properties file
ant build -propertyfile ci-build.properties
```

Ant properties are immutable once set — the first definition wins. Command-line `-D` overrides take precedence over `build.properties`, which takes precedence over properties defined in `build.xml`. This immutability is both a safety feature (prevents accidental overrides) and a limitation (no conditional logic without property-based `<if>`/`<unless>` attributes on targets).

### Production

**CI invocation:**
```bash
ant clean build \
  -propertyfile ci-build.properties \
  -Denv=ci \
  -logfile build.log \
  -Dbuild.number=${CI_BUILD_NUMBER}
```

- `-logfile` — redirects output to a file for CI artifact collection.
- `-Dbuild.number` — injects the CI build number into the build for artifact versioning.

**CI-specific build properties (`ci-build.properties`):**
```properties
debug=false
optimize=true
test.haltonfailure=true
javadoc.skip=false
```

**Ant does not have a CI ecosystem** — there are no Ant-specific GitHub Actions, no Ant-compatible build scan services, and no Ant CI integrations. CI pipelines must invoke `ant` directly and parse the output. This is another reason to migrate: Gradle and Maven have rich CI integrations (caching, test result publishing, dependency scanning) that Ant cannot leverage.

## Performance

Ant's performance model is simple and limited: tasks execute sequentially within targets, targets execute in dependency order, and there is no caching, no incremental compilation tracking (beyond javac's basic timestamp checking), and no parallel execution.

**What you can do:**
- Use `fork="yes"` with `forkmode="once"` on `<junit>` to run all tests in a single forked JVM rather than forking per test class.
- Use `<javac>` with `debug="false"` and `optimize="true"` for release builds (marginal improvement).
- Use Ivy's local cache to avoid re-downloading dependencies on every build.
- Use `<uptodate>` tasks to skip targets when output files are newer than input files:
  ```xml
  <target name="compile" depends="init" unless="compile.uptodate">
      <uptodate property="compile.uptodate" targetfile="${classes.dir}/.compiled">
          <srcfiles dir="${src.dir}" includes="**/*.java"/>
      </uptodate>
      <javac srcdir="${src.dir}" destdir="${classes.dir}" .../>
      <touch file="${classes.dir}/.compiled"/>
  </target>
  ```
  This is a manual, fragile approximation of what Gradle does automatically with input/output tracking.

**What you cannot do:**
- Parallel target execution — Ant is single-threaded. The `<parallel>` task exists but is for executing tasks concurrently within a single target, not for building independent modules in parallel.
- Build caching — there is no mechanism to cache task outputs by input hash.
- Configuration caching — the entire `build.xml` is re-parsed on every invocation.
- Cross-machine cache sharing — not possible.

The only effective performance strategy for Ant is migration to a modern build tool. A 20-module Ant build that takes 10 minutes will typically take 2-3 minutes with Gradle (parallel execution + incremental compilation + build cache) and 4-5 minutes with Maven (parallel reactor + dependency caching).

## Security

**Checked-in JARs** are Ant's most serious security problem. Because Ant has no built-in dependency management, many Ant projects check JAR files directly into version control (`lib/*.jar`). These JARs are binary blobs with no version metadata, no integrity verification, and no CVE tracking. They accumulate over years — old, vulnerable versions of libraries persist indefinitely because nobody knows which JARs are still needed.

**Mitigation — use Ivy for dependency management:**
- Replace checked-in JARs with Ivy declarations.
- Configure Ivy to resolve from Maven Central and internal repositories.
- Use `<ivy:report>` to generate dependency reports for security auditing.
- Gitignore the `lib/` directory and let Ivy populate it during the build.

**Ant build script injection** — because Ant build files support property interpolation and `<exec>` tasks, a malicious property value can inject commands:
```xml
<!-- Dangerous if ${user.input} contains shell metacharacters -->
<exec executable="sh">
    <arg value="-c"/>
    <arg value="echo ${user.input}"/>
</exec>
```

Avoid `<exec>` with interpolated properties. If external commands are necessary, validate inputs and use argument lists rather than shell interpolation.

**No Wrapper** — Ant has no equivalent to Maven Wrapper or Gradle Wrapper. The Ant version used to build the project depends on what is installed on each machine. This means:
- Different developers may use different Ant versions with different behaviors.
- CI runners must have the exact Ant version installed.
- There is no integrity verification of the Ant installation.

Mitigate by documenting the required Ant version, checking `ant -version` in the build script, and using containerized CI builds with a fixed Ant version. Better yet, migrate to a tool with a wrapper.

## Testing

**JUnit integration** — Ant's `<junit>` and `<junitreport>` tasks run JUnit tests and generate reports:

```xml
<target name="test" depends="compile-tests">
    <junit printsummary="on"
           haltonfailure="${test.haltonfailure}"
           fork="yes"
           forkmode="once"
           dir="${basedir}">
        <classpath refid="test.classpath"/>
        <formatter type="xml"/>
        <formatter type="plain" usefile="false"/>
        <batchtest todir="${reports.dir}">
            <fileset dir="${test.classes.dir}" includes="**/*Test.class"/>
        </batchtest>
        <jvmarg value="-XX:+EnableDynamicAgentLoading"/>
    </junit>

    <junitreport todir="${reports.dir}">
        <fileset dir="${reports.dir}" includes="TEST-*.xml"/>
        <report format="frames" todir="${reports.dir}/html"/>
    </junitreport>
</target>
```

**Limitations:**
- JUnit 5 (Jupiter) is not natively supported by Ant's `<junit>` task. Use the `junitlauncher` task (Ant 1.10.6+) or the JUnit Platform Console Launcher.
- No test filtering by pattern (Ant runs all tests matching the fileset).
- No parallel test execution within the `<junit>` task.
- No test caching or rerun-only-failed functionality.

**JUnit 5 with Ant:**
```xml
<target name="test" depends="compile-tests">
    <junitlauncher haltonfailure="true" printsummary="true">
        <classpath refid="test.classpath"/>
        <testclasses outputdir="${reports.dir}">
            <fileset dir="${test.classes.dir}" includes="**/*Test.class"/>
            <listener type="legacy-xml" sendSysOut="true" sendSysErr="true"/>
        </testclasses>
    </junitlauncher>
</target>
```

**Test reporting for CI:**
Ant generates JUnit XML reports in the same format as Maven and Gradle. Point CI test result parsers to `${reports.dir}/TEST-*.xml`.

## Dos

- Migrate to Gradle or Maven. This is the single most impactful improvement for any Ant-based project. Every hour spent maintaining Ant build scripts is an hour that could be spent on product development with a modern build tool.
- Use Ivy for dependency management if migration is not yet possible. Replace checked-in JARs with declared dependencies, enabling CVE tracking, version auditing, and transitive dependency resolution.
- Use macrodefs to reduce duplication in build.xml. While they do not solve Ant's fundamental limitations, they make the build script more maintainable and easier to migrate by clarifying the build's structure.
- Set `includeantruntime="false"` on every `<javac>` task. Without this, Ant adds its own JAR to the compilation classpath, creating non-reproducible builds.
- Use `fork="yes"` and `forkmode="once"` on `<junit>` tasks to run tests in a separate JVM with consistent settings. Without forking, tests run in Ant's own JVM with Ant's classpath, which can mask ClassNotFoundException issues that appear in production.
- Document the target dependency graph. Ant's build.xml can become an opaque web of targets — draw the DAG and keep it updated. This documentation is essential for migration planning.
- Use property files (`build.properties`) to externalize environment-specific values. Never hardcode paths, versions, or credentials in build.xml.
- Pin the Ant version in CI and document it for developers. Without a wrapper mechanism, version drift causes subtle build differences.

## Don'ts

- Don't start new projects with Ant. There is no use case where Ant is the best choice for a new project. Gradle provides superior performance, dependency management, and IDE support. Maven provides superior convention-over-configuration and ecosystem compatibility. Both have active communities and modern CI integrations that Ant lacks.
- Don't check JAR files into version control. Checked-in JARs are unversioned, unauditable binary blobs that accumulate security vulnerabilities over time. Use Ivy for dependency management or migrate to a tool with built-in dependency resolution.
- Don't write complex logic in build.xml. Ant's XML scripting language (conditionals via `<if>`/`<unless>`, loops via `<for>`, string manipulation via `<propertyregex>`) is barely readable and impossible to test. If the build requires complex logic, it is a strong signal to migrate to Gradle where build logic is real Kotlin/Groovy code with IDE support.
- Don't use `<exec>` with interpolated properties for security-sensitive operations. Property values can contain shell metacharacters that lead to command injection. Use Ant's built-in tasks or validate all inputs.
- Don't mix Ant and Maven/Gradle in the same project without a clear migration plan. Dual build systems create confusion about which one is authoritative, double the maintenance burden, and inevitably drift out of sync. Choose a target and migrate incrementally.
- Don't use the `<parallel>` task for build parallelism. It is designed for concurrent I/O operations (e.g., parallel file copies), not for building independent modules. Ant has no module-level parallelism — if you need parallel builds, migrate to Gradle.
- Don't maintain Ant build scripts that exceed 500 lines. At that point, the maintenance cost exceeds the migration cost. Large build.xml files are the strongest argument for migration — they represent build complexity that Gradle/Maven handles automatically through conventions.
- Don't rely on Ant's `<uptodate>` task as a substitute for incremental builds. It checks file timestamps, not content hashes, and requires manual setup for every target. It misses transitive dependency changes, configuration changes, and resource file modifications. It is a fragile approximation of what modern build tools do automatically.
