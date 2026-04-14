# GitHub Actions with SwiftUI

> Extends `modules/ci-cd/github-actions.md` with iOS/SwiftUI CI patterns.
> Generic GitHub Actions conventions (workflow triggers, caching strategies, matrix builds) are NOT repeated here.

## Integration Setup

```yaml
# .github/workflows/ci.yml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.2.app

      - name: Build
        run: |
          xcodebuild build \
            -scheme MyApp \
            -destination 'platform=iOS Simulator,name=iPhone 16' \
            -skipPackagePluginValidation \
            CODE_SIGNING_ALLOWED=NO

      - name: Test
        run: |
          xcodebuild test \
            -scheme MyApp \
            -destination 'platform=iOS Simulator,name=iPhone 16' \
            -resultBundlePath TestResults.xcresult \
            CODE_SIGNING_ALLOWED=NO

      - uses: actions/upload-artifact@v4
        if: failure()
        with:
          name: test-results
          path: TestResults.xcresult
```

## Framework-Specific Patterns

### MacOS Runner Selection

GitHub Actions provides MacOS runners with Xcode pre-installed. Use `macos-15` for the latest Xcode versions. Pin the Xcode version with `xcode-select` for reproducibility.

```yaml
runs-on: macos-15
steps:
  - run: sudo xcode-select -s /Applications/Xcode_16.2.app
  - run: xcodebuild -version
```

### SPM Dependency Caching

```yaml
- uses: actions/cache@v4
  with:
    path: |
      ~/Library/Developer/Xcode/DerivedData
      .build/
    key: spm-${{ runner.os }}-${{ hashFiles('**/Package.resolved') }}
    restore-keys: |
      spm-${{ runner.os }}-
```

Cache `DerivedData` and `.build/` keyed by `Package.resolved` to speed up SPM resolution.

### SwiftLint

```yaml
- name: Lint
  run: |
    brew install swiftlint
    swiftlint lint --reporter github-actions-logging
```

The `github-actions-logging` reporter annotates PRs with inline warnings and errors.

### Code Signing and TestFlight Distribution

```yaml
distribute:
  needs: build
  if: github.ref == 'refs/heads/main'
  runs-on: macos-15
  steps:
    - uses: actions/checkout@v4

    - name: Import certificates
      uses: apple-actions/import-codesign-certs@v3
      with:
        p12-file-base64: ${{ secrets.CERTIFICATES_P12 }}
        p12-password: ${{ secrets.CERTIFICATES_PASSWORD }}

    - name: Import provisioning profile
      uses: apple-actions/download-provisioning-profiles@v3
      with:
        bundle-id: com.example.myapp
        issuer-id: ${{ secrets.APPSTORE_ISSUER_ID }}
        api-key-id: ${{ secrets.APPSTORE_KEY_ID }}
        api-private-key: ${{ secrets.APPSTORE_PRIVATE_KEY }}

    - name: Archive
      run: |
        xcodebuild archive \
          -scheme MyApp \
          -archivePath build/MyApp.xcarchive \
          -destination 'generic/platform=iOS'

    - name: Export IPA
      run: |
        xcodebuild -exportArchive \
          -archivePath build/MyApp.xcarchive \
          -exportPath build/ \
          -exportOptionsPlist ExportOptions.plist

    - name: Upload to TestFlight
      uses: apple-actions/upload-testflight-build@v3
      with:
        app-path: build/MyApp.ipa
        issuer-id: ${{ secrets.APPSTORE_ISSUER_ID }}
        api-key-id: ${{ secrets.APPSTORE_KEY_ID }}
        api-private-key: ${{ secrets.APPSTORE_PRIVATE_KEY }}
```

### Simulator Testing Matrix

```yaml
test:
  strategy:
    matrix:
      destination:
        - "platform=iOS Simulator,name=iPhone 16"
        - "platform=iOS Simulator,name=iPad Pro 13-inch (M4)"
  runs-on: macos-15
  steps:
    - uses: actions/checkout@v4
    - run: |
        xcodebuild test \
          -scheme MyApp \
          -destination '${{ matrix.destination }}' \
          CODE_SIGNING_ALLOWED=NO
```

## Scaffolder Patterns

```yaml
patterns:
  workflow: ".github/workflows/ci.yml"
  distribute_workflow: ".github/workflows/distribute.yml"
  export_options: "ExportOptions.plist"
```

## Additional Dos

- DO use `macos-15` runners and pin the Xcode version with `xcode-select`
- DO set `CODE_SIGNING_ALLOWED=NO` for CI builds -- signing is only needed for distribution
- DO cache SPM dependencies keyed by `Package.resolved`
- DO use `apple-actions/*` for certificate management and TestFlight uploads
- DO upload `.xcresult` bundles on test failure for debugging

## Additional Don'ts

- DON'T use `macos-latest` without pinning Xcode -- it may change between runs
- DON'T embed signing certificates in the repository -- use GitHub Secrets
- DON'T skip `skipPackagePluginValidation` when using SPM plugins in CI
- DON'T run TestFlight uploads on every PR -- limit to `main` branch
