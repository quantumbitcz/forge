# SwiftUI + swiftlint

> Extends `modules/code-quality/swiftlint.md` with SwiftUI-specific integration.
> Generic swiftlint conventions (installation, rule categories, CI integration) are NOT repeated here.

## Integration Setup

Add SwiftLint as an SPM build tool plugin in `Package.swift` (preferred over Xcode build phase for SwiftUI packages):

```swift
// Package.swift
.target(
    name: "MyApp",
    plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLint")]
)
```

Configure `.swiftlint.yml` at the project root with SwiftUI-aware exclusions:

```yaml
# .swiftlint.yml
opt_in_rules:
  - force_unwrapping
  - missing_docs
  - strict_fileprivate
  - empty_xctest_method
  - closure_spacing

disabled_rules:
  - trailing_closure   # SwiftUI DSL relies heavily on trailing closures

included:
  - Sources

excluded:
  - .build
  - DerivedData
  - Sources/Generated

function_body_length:
  warning: 50
  error: 100    # SwiftUI body vars can be long; enforce via custom rule below

type_body_length:
  warning: 300
  error: 500

custom_rules:
  view_body_complexity:
    name: "View Body Complexity"
    regex: '(var body: some View \{[\s\S]{3000,}?\})'
    message: "View body exceeds recommended complexity. Extract subviews."
    severity: warning
```

## Framework-Specific Patterns

### View Body Complexity

SwiftUI `body` computed properties can grow large without triggering standard `function_body_length` rules (which count lines, not visual nesting depth). Use the `function_body_length` rule with a lower threshold for view files:

```yaml
# .swiftlint.yml — stricter limits for view files
custom_rules:
  view_body_length:
    name: "View Body Length"
    regex: 'var body: some View \{'
    message: "View body: extract subviews when body exceeds 50 lines."
    severity: warning
```

Keep `body` under 50 lines by extracting subviews:

```swift
// Bad — view body too long
var body: some View {
    VStack {
        // 80 lines of inline UI
    }
}

// Good — extracted subviews
var body: some View {
    VStack {
        HeaderView(title: title)
        ContentSection(items: items)
        FooterView(onAction: handleAction)
    }
}
```

### @ViewBuilder Functions

`@ViewBuilder` functions are exempt from normal function naming rules but must still comply with `function_body_length`. Name them as noun phrases describing the content returned:

```swift
// swiftlint:disable:next function_body_length — complex view composition
@ViewBuilder
private func contentSection() -> some View {
    // ...
}
```

### Property Wrapper Naming

SwiftUI's property wrappers (`@State`, `@Binding`, `@Environment`, `@StateObject`, `@ObservedObject`, `@EnvironmentObject`) must follow naming conventions:

- `@State` and `@StateObject` properties: private, camelCase, no `is` prefix for non-boolean state
- `@Binding` properties: camelCase, matches the parent's `@State` name
- `@Environment` properties: descriptive name matching the `EnvironmentKey`

```swift
// Bad — violates naming convention (revive/identifier_name)
@State private var isShowingModal: Bool = false  // Bool: "is" prefix OK
@State private var UserName: String = ""          // uppercase — flagged

// Good
@State private var isModalPresented = false
@State private var userName = ""
@ObservedObject var viewModel: UserViewModel     // public — no private required
```

### Closure Spacing in View Modifiers

SwiftUI DSL uses trailing closures extensively. Enable `closure_spacing` to enforce consistent spacing:

```swift
// Bad — inconsistent spacing
.onTapGesture{handleTap()}

// Good — closure_spacing enforces this
.onTapGesture { handleTap() }
```

Disable `trailing_closure` lint — SwiftUI's entire syntax is built around trailing closures and the rule generates constant false positives.

## Additional Dos

- Disable `trailing_closure` rule — SwiftUI's DSL is built on trailing closures; flagging them as non-idiomatic contradicts SwiftUI convention.
- Use `strict_fileprivate` opt-in — SwiftUI subviews defined in the same file should use `private` rather than `fileprivate`.
- Enforce `function_body_length` at warning threshold 50 for view files — complex views should extract subviews, not grow body vars indefinitely.

## Additional Don'ts

- Don't disable `force_unwrapping` globally for SwiftUI projects — force unwraps in view models and data-binding code cause crashes on nil state.
- Don't suppress `missing_docs` for public view types in framework/library targets — SwiftUI views used across modules need doc comments for Xcode Quick Help.
- Don't use `// swiftlint:disable:next` inside SwiftUI `body` properties to suppress complexity lints — extract a subview instead.
