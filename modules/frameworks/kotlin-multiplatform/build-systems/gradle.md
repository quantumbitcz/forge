# Gradle with Kotlin Multiplatform

> Extends `modules/build-systems/gradle.md` with KMP plugin and multi-target build patterns.
> Generic Gradle conventions (task lifecycle, dependency configurations, build cache) are NOT repeated here.

## Integration Setup

```kotlin
// shared/build.gradle.kts
plugins {
    kotlin("multiplatform")
    kotlin("plugin.serialization")
    id("com.squareup.sqldelight")
}

kotlin {
    androidTarget()
    iosX64()
    iosArm64()
    iosSimulatorArm64()
    jvm()

    sourceSets {
        commonMain.dependencies {
            implementation(libs.kotlinx.coroutines.core)
            implementation(libs.kotlinx.serialization.json)
            implementation(libs.ktor.client.core)
            implementation(libs.koin.core)
        }
        commonTest.dependencies {
            implementation(kotlin("test"))
            implementation(libs.kotlinx.coroutines.test)
        }
        androidMain.dependencies {
            implementation(libs.ktor.client.okhttp)
        }
        iosMain.dependencies {
            implementation(libs.ktor.client.darwin)
        }
    }
}
```

## Framework-Specific Patterns

### Source Set Hierarchy

```kotlin
kotlin {
    applyDefaultHierarchyTemplate()

    // Custom intermediate source sets
    sourceSets {
        val mobileMain by creating {
            dependsOn(commonMain.get())
        }
        androidMain.get().dependsOn(mobileMain)
        iosMain.get().dependsOn(mobileMain)
    }
}
```

The default hierarchy template (`applyDefaultHierarchyTemplate()`) creates `iosMain`, `nativeMain`, etc. Use custom intermediate source sets for platform groups that share code (e.g., `mobileMain` for Android + iOS).

### expect/actual Declarations

```kotlin
// commonMain
expect class PlatformLogger() {
    fun log(tag: String, message: String)
}

// androidMain
actual class PlatformLogger {
    actual fun log(tag: String, message: String) = Log.d(tag, message)
}

// iosMain
actual class PlatformLogger {
    actual fun log(tag: String, message: String) = NSLog("[$tag] $message")
}
```

### iOS Framework Publishing

```kotlin
kotlin {
    listOf(iosX64(), iosArm64(), iosSimulatorArm64()).forEach {
        it.binaries.framework {
            baseName = "shared"
            isStatic = true
        }
    }
}
```

```bash
./gradlew :shared:linkReleaseFrameworkIosArm64  # single architecture
./gradlew :shared:assembleXCFramework           # universal framework
```

### Version Catalog

```toml
# gradle/libs.versions.toml
[versions]
kotlin = "2.1.10"
kotlinx-coroutines = "1.9.0"
kotlinx-serialization = "1.7.3"
ktor = "3.0.3"
koin = "4.0.2"
sqldelight = "2.0.2"

[plugins]
kotlin-multiplatform = { id = "org.jetbrains.kotlin.multiplatform", version.ref = "kotlin" }
kotlin-serialization = { id = "org.jetbrains.kotlin.plugin.serialization", version.ref = "kotlin" }
sqldelight = { id = "app.cash.sqldelight", version.ref = "sqldelight" }
```

### Multi-Module Project

```kotlin
// settings.gradle.kts
include(":shared")
include(":androidApp")
```

```kotlin
// androidApp/build.gradle.kts
dependencies {
    implementation(project(":shared"))
}
```

## Scaffolder Patterns

```yaml
patterns:
  build_file: "shared/build.gradle.kts"
  settings_file: "settings.gradle.kts"
  version_catalog: "gradle/libs.versions.toml"
```

## Additional Dos

- DO use `applyDefaultHierarchyTemplate()` for standard source set hierarchy
- DO use version catalog for all dependency versions across modules
- DO use `XCFramework` for iOS distribution (universal framework)
- DO keep platform-specific code in `*Main` source sets via `expect`/`actual`
- DO use `isStatic = true` for iOS frameworks to avoid dynamic linking issues

## Additional Don'ts

- DON'T put JVM-only or iOS-only imports in `commonMain` -- use the correct source set
- DON'T use `kapt` in KMP modules -- use `ksp` which supports multiplatform
- DON'T specify Ktor engine in `commonMain` -- engine selection belongs in platform source sets
- DON'T use `actual typealias` as a shortcut -- it couples common code to platform types
