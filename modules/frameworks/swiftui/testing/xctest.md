# SwiftUI + XCTest Testing Conventions

## Test Structure

- Tests in `Tests/` target matching main target name
- Name files: `<Feature>Tests.swift`
- Use `XCTestCase` subclasses
- `@MainActor` for UI-related tests

## View Testing with ViewInspector

- Add `ViewInspector` via SPM for view inspection
- Access view hierarchy: `try view.inspect().find(text: "Hello")`
- Test view modifiers: `try view.inspect().find(ViewType.Button.self)`
- Test navigation: inspect `NavigationLink` destinations

## ViewModel Testing

- Test `@Published` properties via `XCTestExpectation`:
  ```swift
  let expectation = expectation(description: "value changed")
  viewModel.$value.dropFirst().sink { _ in expectation.fulfill() }.store(in: &cancellables)
  viewModel.loadData()
  await fulfillment(of: [expectation], timeout: 1.0)
  ```
- Test `@Observable` (iOS 17+): observe property changes directly

## Async Testing

- Use `async` test methods: `func testFetch() async throws`
- Use `XCTestExpectation` for Combine publishers
- Test `Task` cancellation explicitly

## Core Data Testing

- Use in-memory persistent store: `NSPersistentStoreDescription().url = URL(fileURLWithPath: "/dev/null")`
- Create test context per test case
- Reset context in `tearDown`

## Mocking

- Protocol-based mocking: define protocols for services, create mock implementations
- Use `@Dependency` from swift-dependencies for DI in TCA
- Mock `URLSession` with `URLProtocol` subclass

## Dos

- Test ViewModels independently from Views
- Test Combine pipelines with `expectation` pattern
- Test error states and loading states
- Use `@MainActor` for tests touching UI state
- Test accessibility labels exist

## Don'ts

- Don't test SwiftUI layout rendering (positions, frames)
- Don't test system views (NavigationView internals)
- Don't use `sleep` in async tests (use expectations)
- Don't test previews at runtime
- Don't mock SwiftUI environment values in unit tests
