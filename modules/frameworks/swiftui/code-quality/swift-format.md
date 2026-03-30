# SwiftUI + swift-format

> Extends `modules/code-quality/swift-format.md` with SwiftUI-specific integration.
> Generic swift-format conventions (installation, configuration, CI integration) are NOT repeated here.

## Integration Setup

Use the SPM plugin for SwiftUI projects to ensure formatting runs consistently in Xcode and CI:

```bash
# Install via Homebrew for local dev
brew install swift-format

# Or via Mint for version locking
mint install apple/swift-format@600.0.0
```

```yaml
# .github/workflows/quality.yml
- name: swift-format lint
  run: swift-format lint --recursive --strict Sources/ Tests/
```

## Framework-Specific Patterns

### SwiftUI DSL Formatting

SwiftUI view modifiers chain vertically. swift-format respects existing line breaks (`respectsExistingLineBreaks: true`) for modifier chains — use intentional line breaks to control formatting:

```swift
// SwiftUI modifier chains: break after each modifier
Text(title)
    .font(.headline)
    .foregroundColor(.primary)
    .padding(.horizontal, 16)
    .accessibilityLabel(title)
```

Configure `.swift-format` to avoid aggressive reformatting of intentional SwiftUI chains:

```json
{
  "version": 1,
  "lineLength": 100,
  "indentation": { "spaces": 4 },
  "respectsExistingLineBreaks": true,
  "lineBreakBeforeEachArgument": false,
  "rules": {
    "OrderedImports": true,
    "UseTripleSlashForDocumentationComments": true,
    "FileScopedDeclarationPrivacy": true,
    "NeverForceUnwrap": true,
    "NeverUseForceTry": true,
    "AlwaysUseLowerCamelCase": true
  }
}
```

### Formatting @ViewBuilder and View Extensions

`@ViewBuilder` functions and `View` extension methods are critical to SwiftUI code organization. swift-format leaves their internal content alone if you use `respectsExistingLineBreaks: true`:

```swift
extension View {
    /// Applies the standard card styling.
    func cardStyle() -> some View {
        self
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
    }
}
```

### Property Wrapper Alignment

swift-format does not align property wrappers vertically — it normalizes spacing. Rely on the formatter rather than manual alignment:

```swift
// Let swift-format normalize spacing (do not manually align)
@State private var isPresented = false
@State private var selectedItem: Item?
@ObservedObject var viewModel: HomeViewModel
@Environment(\.colorScheme) var colorScheme
```

### Import Ordering in SwiftUI Files

Enable `OrderedImports: true` — SwiftUI files typically import `SwiftUI`, `Combine`, and custom modules. Alphabetical ordering prevents merge conflicts:

```swift
// Correct import order (enforced by OrderedImports)
import Combine
import Foundation
import SwiftUI
import MyAppCore    // local modules after stdlib
```

## Additional Dos

- Set `NeverForceUnwrap: true` and `NeverUseForceTry: true` in `.swift-format` for SwiftUI projects — force unwraps in view models crash the entire UI, not just a request.
- Use `lineLength: 100` — SwiftUI modifier chains are verbose; 80 columns forces awkward breaks in common patterns like `.padding(.horizontal, 16)`.
- Scope swift-format to `Sources/` and `Tests/` — avoid running it on `DerivedData`, `.build`, or generated Core Data Swift files.

## Additional Don'ts

- Don't set `respectsExistingLineBreaks: false` for SwiftUI projects — it will collapse intentional vertical modifier chains into horizontal expressions that are harder to read.
- Don't run swift-format on Preview code in `#Preview` macros — generated preview scaffolding may have intentional formatting that the tool rewrites.
- Don't use swift-format as a replacement for SwiftLint — swift-format handles style/whitespace only; SwiftLint covers idiomatic Swift patterns unique to SwiftUI.
