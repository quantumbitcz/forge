# Ant with Spring (Legacy)

> Legacy binding for projects still using Apache Ant with Spring.
> Primary guidance: migrate to Gradle or Maven with Spring Boot.

## Context

Apache Ant predates Spring Boot's opinionated build tooling. Spring Boot does not provide an Ant plugin. Projects using Ant with Spring are typically legacy applications on Spring Framework (non-Boot) or early Spring Boot versions with custom build scripts.

## Legacy Integration Pattern

### Ivy-Based Spring Dependency Resolution

```xml
<!-- ivy.xml -->
<ivy-module version="2.0">
    <dependencies>
        <dependency org="org.springframework" name="spring-context" rev="6.2.3"/>
        <dependency org="org.springframework" name="spring-web" rev="6.2.3"/>
        <dependency org="org.springframework" name="spring-webmvc" rev="6.2.3"/>
        <dependency org="org.springframework.boot" name="spring-boot" rev="3.4.3"/>
    </dependencies>
</ivy-module>
```

```xml
<!-- build.xml -->
<project name="spring-app" default="build">
    <target name="resolve">
        <ivy:retrieve pattern="lib/[artifact]-[revision].[ext]"/>
    </target>
    <target name="compile" depends="resolve">
        <javac srcdir="src/main/java" destdir="build/classes">
            <classpath>
                <fileset dir="lib" includes="*.jar"/>
            </classpath>
        </javac>
    </target>
</project>
```

## Migration Guidance

### Recommended Migration Path

1. **Ant + Ivy to Maven**: Lower friction -- Maven's convention-over-configuration aligns with most Ant project layouts
2. **Ant + Ivy to Gradle**: Better for projects needing custom task logic that Ant provided
3. **Target**: Spring Boot with `spring-boot-starter-parent` (Maven) or `org.springframework.boot` plugin (Gradle)

### Step-by-Step Migration

1. **Inventory dependencies** -- extract all JARs from `lib/` or Ivy config into a dependency list
2. **Map to Spring Boot starters** -- replace individual Spring JARs with corresponding `spring-boot-starter-*`
3. **Convert build targets to lifecycle phases** (Maven) or tasks (Gradle)
4. **Replace XML-based Spring config** (`applicationContext.xml`) with `@Configuration` classes
5. **Add `@SpringBootApplication`** entry point
6. **Migrate properties** from custom locations to `application.yml`

### Dependency Mapping

| Ant/Ivy Dependency | Spring Boot Starter |
|---|---|
| `spring-webmvc` + `spring-web` + `servlet-api` | `spring-boot-starter-web` |
| `spring-orm` + `hibernate-core` + `spring-tx` | `spring-boot-starter-data-jpa` |
| `spring-security-*` | `spring-boot-starter-security` |
| `spring-test` + `junit` | `spring-boot-starter-test` |

## Scaffolder Patterns

```yaml
patterns:
  build_file: "build.xml"
  ivy_file: "ivy.xml"
  ivy_settings: "ivysettings.xml"
```

## Additional Dos

- DO prioritize migration to Gradle or Maven -- Ant receives no Spring Boot tooling support
- DO inventory all transitive dependencies before migration -- Ivy resolution may pull unexpected JARs
- DO migrate incrementally: build system first, then Spring Boot auto-configuration

## Additional Don'ts

- DON'T start new Spring projects with Ant -- use Gradle (preferred) or Maven
- DON'T attempt to replicate Spring Boot's layered JAR or auto-configuration in Ant
- DON'T maintain parallel Ant and Gradle/Maven builds long-term -- commit to one and remove the other
