# SwiftUI + xcov

> Extends `modules/code-quality/xcov.md` with SwiftUI-specific integration.
> Generic xcov conventions (installation, xcresult bundles, CI integration) are NOT repeated here.

## Integration Setup

Run coverage using Xcode's test scheme with `-enableCodeCoverage YES`. For SwiftUI apps, target the main app scheme and exclude system-generated files:

```yaml
# .github/workflows/ios-test.yml
- name: Run SwiftUI tests with coverage
  run: |
    xcodebuild test \
      -workspace MyApp.xcworkspace \
      -scheme MyApp \
      -destination "platform=iOS Simulator,name=iPhone 16,OS=18.0" \
      -enableCodeCoverage YES \
      -resultBundlePath TestResults.xcresult \
      CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
      | xcpretty

- name: Generate coverage report
  run: xcrun xccov view --report --json TestResults.xcresult > coverage.json
```

Configure `.xcovignore` to exclude SwiftUI infrastructure from coverage calculations:

```
# .xcovignore
.*AppDelegate.*
.*SceneDelegate.*
.*Preview.*          # Xcode Preview providers
.*\.generated\.swift
.*CoreDataModel.*
.*Assets.*
```

## Framework-Specific Patterns

### Coverage for ViewModels and Business Logic

SwiftUI views are difficult to unit test directly — focus coverage on ViewModels, services, and domain logic. Apply thresholds only to non-view packages:

```ruby
# Fastfile
xcov(
  workspace: "MyApp.xcworkspace",
  scheme: "MyApp",
  output_directory: "coverage/",
  minimum_coverage_percentage: 75.0,
  include_targets: [
    "MyAppCore.framework",    # domain logic
    "MyAppViewModel.framework" # ViewModels
  ],
  exclude_targets: [
    "MyApp.app",              # SwiftUI views — low testability
    "Pods",
  ]
)
```

### Testing @Observable ViewModels

Use `@MainActor` ViewModel testing with `@Observable` (iOS 17+) or `ObservableObject` to drive view behavior in unit tests:

```swift
@MainActor
final class HomeViewModelTests: XCTestCase {
    func test_loadUsers_populatesItems() async {
        let mockRepo = MockUserRepository()
        mockRepo.stubbedUsers = [.fixture()]
        let viewModel = HomeViewModel(repository: mockRepo)

        await viewModel.loadUsers()

        XCTAssertEqual(viewModel.users.count, 1)
        XCTAssertFalse(viewModel.isLoading)
    }

    func test_loadUsers_setsError_onFailure() async {
        let mockRepo = MockUserRepository()
        mockRepo.shouldFail = true
        let viewModel = HomeViewModel(repository: mockRepo)

        await viewModel.loadUsers()

        XCTAssertNotNil(viewModel.error)
        XCTAssertTrue(viewModel.users.isEmpty)
    }
}
```

### Preview Provider Coverage

`#Preview` blocks and legacy `PreviewProvider` conformances are compiler-generated and cannot be meaningfully tested. Always add them to `.xcovignore`:

```
# .xcovignore
.*PreviewProvider.*
.*_Previews.*
```

### Coverage for SwiftUI Navigation and Sheets

Navigation coordinator patterns (NavigationStack path binding, sheet presentation) are testable via ViewModel state:

```swift
func test_presentDetailSheet_onItemTap() {
    let viewModel = ListViewModel()
    viewModel.selectItem(.fixture(id: "123"))
    XCTAssertEqual(viewModel.selectedItem?.id, "123")
    XCTAssertTrue(viewModel.isDetailPresented)
}
```

Test the state transitions, not the SwiftUI rendering — the framework handles rendering from state.

## Additional Dos

- Set coverage thresholds on ViewModel and domain logic targets only — SwiftUI view code has low unit test ROI; coverage should be measured where business decisions live.
- Add `.*Preview.*` and `.*_Previews.*` to `.xcovignore` — Preview providers inflate the denominator without providing testable coverage.
- Use `@MainActor` in ViewModel tests with `async`/`await` — SwiftUI ViewModels with `@Observable` or `@Published` require main actor isolation.

## Additional Don'ts

- Don't apply coverage thresholds to the main `.app` target — SwiftUI rendering and lifecycle code is not unit-testable and will always show low coverage.
- Don't skip testing ViewModels because the views look correct — visual correctness does not guarantee state transition correctness under edge cases.
- Don't include third-party SPM packages in coverage targets — they inflate both the denominator and the analysis time.
