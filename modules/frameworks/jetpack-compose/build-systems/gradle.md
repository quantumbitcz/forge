# Gradle with Jetpack Compose

> Extends `modules/build-systems/gradle.md` with Android Gradle Plugin (AGP) + Compose patterns.
> Generic Gradle conventions (task lifecycle, dependency configurations, build cache) are NOT repeated here.

## Integration Setup

```kotlin
// build.gradle.kts (app module)
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("com.google.dagger.hilt.android")
    id("com.google.devtools.ksp")
}

android {
    namespace = "com.example.app"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.example.app"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    buildFeatures {
        compose = true
    }
}
```

The Compose compiler plugin (`org.jetbrains.kotlin.plugin.compose`) was decoupled from the Compose library in Kotlin 2.0. It automatically matches the Kotlin version.

## Framework-Specific Patterns

### Build Variants

```kotlin
android {
    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            isDebuggable = true
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    flavorDimensions += "environment"
    productFlavors {
        create("dev") {
            dimension = "environment"
            applicationIdSuffix = ".dev"
            buildConfigField("String", "API_URL", "\"https://api-dev.example.com\"")
        }
        create("prod") {
            dimension = "environment"
            buildConfigField("String", "API_URL", "\"https://api.example.com\"")
        }
    }
}
```

### Compose Compiler Reports

```kotlin
// build.gradle.kts
composeCompiler {
    reportsDestination = layout.buildDirectory.dir("compose_compiler")
    stabilityConfigurationFile = rootProject.layout.projectDirectory.file("stability_config.conf")
}
```

```bash
./gradlew assembleRelease  # generates compose_compiler/app_release-composables.txt
```

Compose compiler reports reveal which composables skip recomposition and which are restartable. Use these to identify performance issues.

### Version Catalog

```toml
# gradle/libs.versions.toml
[versions]
agp = "8.7.3"
kotlin = "2.1.10"
compose-bom = "2024.12.01"
hilt = "2.53.1"
room = "2.7.0-alpha12"

[plugins]
android-application = { id = "com.android.application", version.ref = "agp" }
kotlin-android = { id = "org.jetbrains.kotlin.android", version.ref = "kotlin" }
kotlin-compose = { id = "org.jetbrains.kotlin.plugin.compose", version.ref = "kotlin" }
hilt = { id = "com.google.dagger.hilt.android", version.ref = "hilt" }

[libraries]
compose-bom = { module = "androidx.compose:compose-bom", version.ref = "compose-bom" }
compose-ui = { module = "androidx.compose.ui:ui" }
compose-material3 = { module = "androidx.compose.material3:material3" }
```

Use the Compose BOM to align all Compose library versions. Individual library versions are omitted when using the BOM.

### Test Suites

```kotlin
android {
    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

dependencies {
    testImplementation(libs.junit.jupiter)
    testImplementation(libs.compose.ui.test.junit4)
    androidTestImplementation(libs.compose.ui.test.manifest)
    androidTestImplementation(libs.espresso.core)
}
```

## Scaffolder Patterns

```yaml
patterns:
  build_file: "app/build.gradle.kts"
  settings_file: "settings.gradle.kts"
  version_catalog: "gradle/libs.versions.toml"
  proguard: "app/proguard-rules.pro"
```

## Additional Dos

- DO use the Compose BOM for consistent library version alignment
- DO use `kotlin.plugin.compose` (Kotlin 2.0+) instead of the legacy `compose-compiler` artifact
- DO enable Compose compiler reports to monitor recomposition performance
- DO use product flavors for environment-specific configuration (API URLs, feature flags)
- DO enable `isShrinkResources` alongside `isMinifyEnabled` in release builds

## Additional Don'ts

- DON'T specify individual Compose library versions when using the BOM
- DON'T use the legacy `composeOptions.kotlinCompilerExtensionVersion` with Kotlin 2.0+
- DON'T skip ProGuard/R8 in release builds -- it significantly reduces APK size
- DON'T use `buildConfig` for secrets -- they're embedded in the APK and easily extracted
