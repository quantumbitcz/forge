# SwiftUI + DocC

> Extends `modules/code-quality/docc.md` with SwiftUI-specific integration.
> Generic DocC conventions (installation, symbol docs, CI integration) are NOT repeated here.

## Integration Setup

Use the DocC SPM plugin for SwiftUI framework targets. Add it to the framework package, not the app target:

```swift
// Package.swift (framework package)
dependencies: [
    .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.3.0"),
],
targets: [
    .target(
        name: "MyUIKit",
        path: "Sources/MyUIKit"
    )
]
```

```yaml
# .github/workflows/docs.yml
- name: Generate DocC
  run: |
    swift package \
      --allow-writing-to-directory ./docs \
      generate-documentation \
      --target MyUIKit \
      --output-path ./docs \
      --transform-for-static-hosting \
      --hosting-base-path MyUIKit

- name: Deploy to GitHub Pages
  uses: peaceiris/actions-gh-pages@v4
  if: github.ref == 'refs/heads/main'
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
    publish_dir: ./docs
```

## Framework-Specific Patterns

### Tutorial Catalogs for Component Libraries

SwiftUI component libraries benefit enormously from DocC `@Tutorial` directives — interactive step-by-step tutorials teach developers how to compose custom views:

```
# Sources/MyUIKit/MyUIKit.docc/Tutorials/table-of-contents.tutorial
@Tutorials(name: "MyUIKit") {
    @Intro(title: "Building with MyUIKit") {
        Learn to compose MyUIKit views in 15 minutes.

        @Image(source: "hero-image.png", alt: "MyUIKit component showcase")
    }

    @Chapter(name: "Core Components") {
        @TutorialReference(tutorial: "doc:BuildingACard")
        @TutorialReference(tutorial: "doc:CustomButtons")
    }

    @Chapter(name: "Data Display") {
        @TutorialReference(tutorial: "doc:ListViews")
    }
}
```

### @Tutorial Directives for SwiftUI Steps

Use `@Step` with `@Code` and `@Image` to show view code evolving:

```
@Tutorial(time: 10) {
    @Intro(title: "Building a Card Component") {
        This tutorial walks through creating a reusable card view.
    }

    @Section(title: "Create the Card View") {
        @ContentAndMedia {
            Start with a plain VStack and add styling progressively.
        }

        @Steps {
            @Step {
                Create a new SwiftUI view file `CardView.swift`.
                @Code(name: "CardView.swift", file: "card-step-1.swift")
            }
            @Step {
                Add corner radius and shadow modifiers.
                @Code(name: "CardView.swift", file: "card-step-2.swift")
            }
        }
    }
}
```

### Interactive Previews in DocC Articles

Reference `#Preview` code in DocC articles using `@Links` to point readers to preview-enabled pages:

```markdown
# CardView

CardView renders content in a rounded card with configurable padding and shadow.

## Overview

Use `CardView` to group related content visually:

```swift
CardView {
    Text("Hello, world!")
}
```

@Links(visualStyle: detailedGrid) {
    - <doc:CardViewStyling>
    - <doc:CardViewAccessibility>
}
```

### Documenting SwiftUI Views

Document public `View` types with usage examples, parameter descriptions, and accessibility notes:

```swift
/// A card-shaped container that groups related content.
///
/// Use `CardView` to visually group related UI elements with a rounded
/// corner background and subtle shadow:
///
/// ```swift
/// CardView {
///     VStack(alignment: .leading) {
///         Text("Title").font(.headline)
///         Text("Description").foregroundColor(.secondary)
///     }
/// }
/// ```
///
/// - Parameter content: The content to display inside the card.
///
/// ## Topics
///
/// ### Styling
/// - ``padding(_:)``
/// - ``cardStyle(_:)``
///
/// ## Accessibility
///
/// CardView does not add accessibility traits. Apply traits to the content
/// views or use `.accessibilityElement(children: .combine)` on CardView.
public struct CardView<Content: View>: View {
```

### Documenting Property Wrappers and Environment Values

Custom `EnvironmentKey` and `EnvironmentValues` extensions should be documented — they are invisible API surface:

```swift
/// The current design token color scheme provided via the environment.
///
/// Access the theme in any SwiftUI view:
///
/// ```swift
/// @Environment(\.appTheme) var theme
/// ```
///
/// Inject a custom theme in tests or previews:
///
/// ```swift
/// SomeView()
///     .environment(\.appTheme, .dark)
/// ```
public struct AppThemeKey: EnvironmentKey { ... }
```

## Additional Dos

- Create tutorial catalogs for reusable SwiftUI component libraries — step-by-step tutorials dramatically reduce onboarding for design system consumers.
- Document all `EnvironmentKey` types and custom property wrappers — they are invisible without documentation since the compiler provides no type-level guidance.
- Use `@Links(visualStyle: detailedGrid)` in article pages to cross-link related component documentation — SwiftUI developers navigate by visual component name.

## Additional Don'ts

- Don't generate DocC for app targets — DocC is most valuable for reusable framework/library targets; app-level code is not consumed by other developers.
- Don't leave `@ViewBuilder` closure parameters undocumented — callers need to know what constraints the closure content must satisfy.
- Don't use DocC as the sole source of component previews — `#Preview` macros in the source remain the primary interactive development tool; DocC articles complement them.
