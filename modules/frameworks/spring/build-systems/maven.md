# Maven with Spring

> Extends `modules/build-systems/maven.md` with Spring Boot Maven plugin patterns.
> Generic Maven conventions (lifecycle phases, dependency scoping, profiles) are NOT repeated here.

## Integration Setup

### Parent POM (recommended)

```xml
<parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.4.3</version>
    <relativePath/>
</parent>
```

Inheriting `spring-boot-starter-parent` provides managed dependency versions, sensible plugin defaults, and resource filtering for `application.yml`.

### BOM Import (when parent POM is unavailable)

```xml
<dependencyManagement>
    <dependencies>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-dependencies</artifactId>
            <version>3.4.3</version>
            <type>pom</type>
            <scope>import</scope>
        </dependency>
    </dependencies>
</dependencyManagement>
```

Use BOM import when your project already has a corporate parent POM.

## Framework-Specific Patterns

### Spring Boot Maven Plugin

```xml
<build>
    <plugins>
        <plugin>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-maven-plugin</artifactId>
            <configuration>
                <layers>
                    <enabled>true</enabled>
                </layers>
                <image>
                    <name>${project.artifactId}:${project.version}</name>
                </image>
            </configuration>
        </plugin>
    </plugins>
</build>
```

Key goals:
- `spring-boot:run` -- starts the application with DevTools support
- `spring-boot:repackage` -- creates the executable fat JAR (runs automatically in `package` phase)
- `spring-boot:build-image` -- builds OCI image using Cloud Native Buildpacks

### Profile-Based Configuration

```xml
<profiles>
    <profile>
        <id>local</id>
        <activation>
            <activeByDefault>true</activeByDefault>
        </activation>
        <properties>
            <spring.profiles.active>local</spring.profiles.active>
        </properties>
    </profile>
    <profile>
        <id>prod</id>
        <properties>
            <spring.profiles.active>prod</spring.profiles.active>
        </properties>
    </profile>
</profiles>
```

With `spring-boot-starter-parent`, `application.yml` supports `@spring.profiles.active@` resource filtering.

### Integration Test Separation

```xml
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-failsafe-plugin</artifactId>
    <configuration>
        <includes>
            <include>**/*IT.java</include>
        </includes>
        <systemPropertyVariables>
            <spring.profiles.active>test</spring.profiles.active>
        </systemPropertyVariables>
    </configuration>
</plugin>
```

Failsafe runs `*IT.java` files during the `verify` phase -- keeps integration tests separate from unit tests in `mvn test`.

### Multi-Module Spring Boot Project

```xml
<!-- root pom.xml -->
<modules>
    <module>app</module>
    <module>core</module>
    <module>infra</module>
</modules>

<!-- app/pom.xml (the bootable module) -->
<plugin>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-maven-plugin</artifactId>
</plugin>

<!-- core/pom.xml (library module) -->
<!-- No spring-boot-maven-plugin — produces plain JAR -->
```

Only the runnable application module should include the Spring Boot Maven plugin.

## Scaffolder Patterns

```yaml
patterns:
  build_file: "pom.xml"
  parent_pom: "pom.xml"
  module_pom: "{module}/pom.xml"
```

## Additional Dos

- DO use `spring-boot-starter-parent` as parent POM when possible -- simplifies version management
- DO enable layered JAR in the Maven plugin for Docker image optimization
- DO use Maven Failsafe plugin for `*IT.java` integration tests
- DO configure resource filtering for `@spring.profiles.active@` in `application.yml`
- DO use `mvn spring-boot:build-image` for Buildpacks-based container images

## Additional Don'ts

- DON'T include `spring-boot-maven-plugin` in library submodules -- only the application module
- DON'T override managed dependency versions without a documented reason
- DON'T skip the `verify` phase in CI -- Failsafe integration tests only run there
- DON'T use `mvn package -DskipTests` in production builds -- use profiles to control test scope
