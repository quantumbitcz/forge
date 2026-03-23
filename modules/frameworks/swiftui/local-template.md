---
project_type: mobile
components:
  language: swift
  framework: swiftui
  variant: swift
  testing: xctest

explore_agents:
  primary: "feature-dev:code-explorer"
  secondary: "Explore"

commands:
  build: "xcodebuild -scheme MyApp -destination 'platform=iOS Simulator,name=iPhone 16' build"
  build_alt: "swift build"
  lint: "swiftlint lint"
  test: "xcodebuild test -scheme MyApp -destination 'platform=iOS Simulator,name=iPhone 16'"
  test_single: "xcodebuild test -scheme MyApp -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing"
  format: "swiftlint lint --autocorrect"
  build_timeout: 120
  test_timeout: 300
  lint_timeout: 60

scaffolder:
  enabled: true
  patterns:
    view: "Sources/Features/{Feature}/Views/{Feature}View.swift"
    viewmodel: "Sources/Features/{Feature}/ViewModels/{Feature}ViewModel.swift"
    model: "Sources/Models/{Entity}.swift"
    service: "Sources/Services/{Domain}Service.swift"
    test: "Tests/{Subject}Tests.swift"

quality_gate:
  max_review_cycles: 2
  batch_1:
    - agent: architecture-reviewer
      focus: "MVVM adherence, layer boundaries, dependency direction"
    - agent: security-reviewer
      focus: "Keychain usage, App Transport Security, certificate pinning"
    - agent: "Code Reviewer"
      source: builtin
      focus: "general correctness, MVVM adherence, view complexity"
  batch_2:
    - agent: "pr-review-toolkit:code-reviewer"
      source: plugin
      focus: "CLAUDE.md adherence"
  inline_checks: []

test_gate:
  command: "xcodebuild test -scheme MyApp -destination 'platform=iOS Simulator,name=iPhone 16'"
  max_test_cycles: 2
  analysis_agents:
    - agent: "pr-review-toolkit:pr-test-analyzer"
      source: plugin

validation:
  perspectives: [architecture, usability, performance, test_strategy, conventions]
  max_validation_retries: 2

implementation:
  parallel_threshold: 3
  max_fix_loops: 3
  tdd: true
  scaffolder_before_impl: true

risk:
  auto_proceed: MEDIUM

linear:
  enabled: false
  team: ""
  project: ""
  labels: ["pipeline-managed"]

conventions_file: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/swiftui/conventions.md"
preempt_file: ".claude/pipeline-log.md"
config_file: ".claude/pipeline-config.md"

context7_libraries:
  - "swift"
  - "swiftui"
  - "combine"
  - "swiftdata"
---

## Swift/iOS Context

SwiftUI with MVVM pattern. Views are small and composable, ViewModels use @Observable macro
(Swift 5.9+), async/await for concurrency, SwiftData or Core Data for persistence.
Xcode project organized by feature.

Customize the scheme name and commands above to match your Xcode project.
