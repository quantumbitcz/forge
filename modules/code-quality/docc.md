---
name: docc
categories: [doc-generator]
languages: [swift]
exclusive_group: swift-doc-generator
recommendation_score: 90
detection_files: [*.docc, Package.swift]
---

# docc

## Overview

DocC (Documentation Compiler) is Apple's documentation tool for Swift and Objective-C frameworks and apps. It is integrated directly into Xcode and Swift Package Manager. DocC compiles source comments, Markdown articles, and tutorial catalogs into a `.doccarchive` bundle. The archive can be hosted on GitHub Pages using the `swift-docc-plugin` or on any static host. DocC renders modern interactive HTML documentation matching the developer.apple.com style.

## Architecture Patterns

### Installation & Setup

DocC ships with Xcode 13+. For SPM projects without Xcode:
```bash
# Add to Package.swift
.package(url: "https://github.com/apple/swift-docc-plugin", from: "1.3.0")

# Generate docs
swift package generate-documentation

# Generate and preview locally
swift package --disable-sandbox preview-documentation --target MyLibrary
```

**Xcode build:**
```
Product → Build Documentation (⌃⇧⌘D)
```

**`Package.swift` with DocC plugin:**
```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MyLibrary",
    products: [
        .library(name: "MyLibrary", targets: ["MyLibrary"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.3.0"),
    ],
    targets: [
        .target(name: "MyLibrary", path: "Sources/MyLibrary"),
    ]
)
```

### Rule Categories

| Category | Pattern | Pipeline Severity |
|---|---|---|
| Missing symbol documentation | Public struct/class/func without `///` comment | WARNING |
| Missing `Parameters` section | Public function with params but no doc parameter list | INFO |
| Broken symbol link | `<doc:SymbolName>` or ` ``SymbolName`` ` pointing to undefined | WARNING |
| Missing article | Framework with no top-level getting-started article | INFO |
| Uncategorized symbols | Public symbols not organized via extension files | INFO |

### Configuration Patterns

**Symbol documentation (Swift):**
```swift
/// A type that represents a network request.
///
/// Use `NetworkRequest` to configure and execute HTTP requests. Call
/// ``execute(with:)`` to perform the request and decode the response.
///
/// ```swift
/// let request = NetworkRequest(url: URL(string: "https://api.example.com/users")!)
/// let users: [User] = try await request.execute(with: session)
/// ```
///
/// - Important: Always call ``cancel()`` when the owning view disappears.
///
/// ## Topics
///
/// ### Creating a Request
/// - ``init(url:method:headers:)``
///
/// ### Executing
/// - ``execute(with:)``
/// - ``cancel()``
public struct NetworkRequest {
    /// Creates a new network request targeting the given URL.
    ///
    /// - Parameters:
    ///   - url: The target URL. Must use `https` in production.
    ///   - method: The HTTP method. Defaults to `.get`.
    ///   - headers: Additional request headers. Defaults to empty.
    public init(url: URL, method: HTTPMethod = .get, headers: [String: String] = [:])

    /// Executes the request and decodes the response into the inferred type.
    ///
    /// - Parameter session: The URL session to use for the request.
    /// - Returns: The decoded response body.
    /// - Throws: ``NetworkError/unauthorized`` if the server returns 401.
    /// - Throws: ``NetworkError/decodingFailed(_:)`` if the response cannot be decoded.
    public func execute<T: Decodable>(with session: URLSession) async throws -> T
}
```

**DocC Markdown article (`Sources/MyLibrary/MyLibrary.docc/GettingStarted.md`):**
```markdown
# Getting Started with MyLibrary

Learn how to add MyLibrary to your project and make your first request.

## Overview

MyLibrary simplifies network requests by ...

## Add the Package

Add the following to your `Package.swift`:

```swift
.package(url: "https://github.com/org/MyLibrary", from: "2.0.0")
```

## Make Your First Request

@Links(visualStyle: compactGrid) {
    - <doc:Authentication>
    - <doc:ErrorHandling>
}
```

**Tutorial catalog (`Sources/MyLibrary/MyLibrary.docc/Tutorials/table-of-contents.tutorial`):**
```
@Tutorials(name: "MyLibrary") {
    @Intro(title: "Building with MyLibrary") {
        Learn the core concepts in 20 minutes.
    }

    @Chapter(name: "Getting Started") {
        @TutorialReference(tutorial: "doc:CreatingYourFirstRequest")
    }
}
```

**GitHub Pages hosting via DocC plugin:**
```bash
swift package \
    --allow-writing-to-directory ./docs \
    generate-documentation \
    --target MyLibrary \
    --output-path ./docs \
    --transform-for-static-hosting \
    --hosting-base-path MyLibrary
```

### CI Integration

```yaml
# .github/workflows/docs.yml
- name: Generate DocC
  run: |
    swift package \
      --allow-writing-to-directory ./docs \
      generate-documentation \
      --target MyLibrary \
      --output-path ./docs \
      --transform-for-static-hosting \
      --hosting-base-path ${{ github.event.repository.name }}

- name: Deploy to GitHub Pages
  uses: peaceiris/actions-gh-pages@v4
  if: github.ref == 'refs/heads/main'
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
    publish_dir: ./docs
    force_orphan: true
```

## Performance

- DocC analysis is fast (5-15s) for typical Swift packages — it compiles only the documentation, not the full target binary.
- Use `--target MyLibrary` to scope generation to one target rather than the whole package.
- Cache `.build/` via `actions/cache` for SPM dependency resolution, not for DocC output itself (always regenerate).
- `preview-documentation` uses hot-reload — changes in articles and symbol comments reflect immediately without a full rebuild.

## Security

- DocC generates static HTML/JSON — no runtime surface.
- `--transform-for-static-hosting` flattens the archive for GitHub Pages. The output contains all documented symbols as JSON — avoid publishing internal implementation details as public symbols.
- Symbol graphs (`.symbols.json`) embedded in `.doccarchive` are machine-readable; they can expose internal type relationships. For proprietary APIs, prefer hosting on an internal server rather than GitHub Pages.

## Testing

```bash
# Build documentation
swift package generate-documentation --target MyLibrary

# Preview with hot-reload
swift package --disable-sandbox preview-documentation --target MyLibrary

# Static hosting transform (required for GitHub Pages)
swift package \
    --allow-writing-to-directory ./docs \
    generate-documentation \
    --target MyLibrary \
    --output-path ./docs \
    --transform-for-static-hosting

# Verify docs build in CI (no output written)
swift package generate-documentation --target MyLibrary 2>&1 | grep -i "error" && exit 1 || exit 0
```

## Dos

- Create a `.docc` catalog directory under your target's `Sources/` folder to organize articles, tutorials, and resources alongside symbol docs.
- Use `## Topics` sections to group related symbols — they control how the API overview page is organized.
- Write tutorial catalogs for developer-facing SDKs — step-by-step guides dramatically reduce onboarding time.
- Use `--transform-for-static-hosting` when deploying to GitHub Pages or any CDN that cannot execute server-side redirects.
- Use `@Links` and `@SeeAlso` directives to guide readers between related articles and symbols.
- Keep article Markdown files in the `.docc` catalog versioned alongside source — they are first-class documentation, not an afterthought.

## Don'ts

- Don't embed DocC archives (`.doccarchive`) in the git repository — they are large binary outputs. Generate and publish from CI.
- Don't rely solely on symbol comments — write at least one top-level article explaining the framework's concepts and architecture.
- Don't skip `/// - Parameters:` and `/// - Returns:` — Xcode's Quick Help popover uses them directly.
- Don't use `<!-- HTML comments -->` inside DocC Markdown — they are not supported and may appear verbatim in output.
- Don't make internal types public solely for documentation purposes — use articles to describe behavior without exposing implementation types.
- Don't reference symbols with raw identifiers in prose — use ` ``SymbolName`` ` backtick syntax so DocC validates and hyperlinks them.
