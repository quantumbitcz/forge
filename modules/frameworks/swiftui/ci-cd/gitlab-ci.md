# GitLab CI with SwiftUI

> Extends `modules/ci-cd/gitlab-ci.md` with iOS/SwiftUI CI patterns.
> Generic GitLab CI conventions (stages, artifacts, includes) are NOT repeated here.

## Integration Setup

```yaml
# .gitlab-ci.yml
stages:
  - build
  - test
  - distribute

variables:
  XCODE_VERSION: "16.2"

build:
  stage: build
  tags:
    - macos
    - xcode
  before_script:
    - sudo xcode-select -s /Applications/Xcode_${XCODE_VERSION}.app
  script:
    - xcodebuild build
        -scheme MyApp
        -destination 'platform=iOS Simulator,name=iPhone 16'
        -skipPackagePluginValidation
        CODE_SIGNING_ALLOWED=NO

test:
  stage: test
  tags:
    - macos
    - xcode
  before_script:
    - sudo xcode-select -s /Applications/Xcode_${XCODE_VERSION}.app
  script:
    - xcodebuild test
        -scheme MyApp
        -destination 'platform=iOS Simulator,name=iPhone 16'
        -resultBundlePath TestResults.xcresult
        CODE_SIGNING_ALLOWED=NO
  artifacts:
    when: on_failure
    paths:
      - TestResults.xcresult
    expire_in: 7 days
```

## Framework-Specific Patterns

### macOS Runner Requirement

GitLab CI requires self-hosted macOS runners for iOS builds. Tag runners with `macos` and `xcode` to route jobs correctly.

```yaml
tags:
  - macos
  - xcode
```

Install GitLab Runner on a macOS host with Xcode, then register with these tags.

### SwiftLint

```yaml
lint:
  stage: build
  tags:
    - macos
  script:
    - brew install swiftlint
    - swiftlint lint --reporter json > swiftlint-report.json
  artifacts:
    reports:
      codequality: swiftlint-report.json
```

### SPM Dependency Caching

```yaml
cache:
  key: spm-${CI_COMMIT_REF_SLUG}
  paths:
    - ~/Library/Developer/Xcode/DerivedData
    - .build/
```

### TestFlight Distribution

```yaml
distribute:
  stage: distribute
  tags:
    - macos
    - xcode
  before_script:
    - sudo xcode-select -s /Applications/Xcode_${XCODE_VERSION}.app
  script:
    - security import $CERTIFICATES_P12 -P $CERTIFICATES_PASSWORD -A
    - xcodebuild archive
        -scheme MyApp
        -archivePath build/MyApp.xcarchive
        -destination 'generic/platform=iOS'
    - xcodebuild -exportArchive
        -archivePath build/MyApp.xcarchive
        -exportPath build/
        -exportOptionsPlist ExportOptions.plist
    - xcrun altool --upload-app
        -f build/MyApp.ipa
        -u $APPSTORE_USER
        -p $APPSTORE_PASSWORD
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
```

## Scaffolder Patterns

```yaml
patterns:
  pipeline: ".gitlab-ci.yml"
  export_options: "ExportOptions.plist"
```

## Additional Dos

- DO use self-hosted macOS runners tagged with `macos` and `xcode`
- DO pin the Xcode version via `XCODE_VERSION` variable and `xcode-select`
- DO set `CODE_SIGNING_ALLOWED=NO` for build and test stages
- DO upload `.xcresult` bundles on test failure
- DO cache SPM-derived data keyed by branch

## Additional Don'ts

- DON'T use Linux runners for iOS builds -- Xcode requires macOS
- DON'T embed signing credentials in the pipeline file -- use CI/CD variables
- DON'T run TestFlight distribution on every commit -- limit to `main` branch
- DON'T skip `skipPackagePluginValidation` when using SPM plugins
