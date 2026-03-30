# scaladoc

## Overview

Scaladoc is the built-in Scala documentation generator. Run via the `sbt doc` task. In Scala 2, comments use a Javadoc-style `/** */` syntax with `@param`, `@return`, `@throws`, and `@tparam` tags. Scala 3 (Dotty) Scaladoc adds full Markdown support inside `/** */` blocks, `@define` macros, and improved rendering. Published libraries are automatically hosted on `javadoc.io` or can be deployed to GitHub Pages.

## Architecture Patterns

### Installation & Setup

Scaladoc is bundled with the Scala compiler — no extra dependency needed.

**sbt configuration (`build.sbt`):**
```scala
// Scala 3 Scaladoc settings
Compile / doc / scalacOptions ++= Seq(
  "-project", "My Library",
  "-project-version", version.value,
  "-project-url", "https://github.com/org/my-library",
  "-source-links:github://org/my-library",
  "-Ygenerate-inkuire"            // Enable type-based search
)

// Scala 2 Scaladoc settings
Compile / doc / scalacOptions ++= Seq(
  "-doc-title", "My Library",
  "-doc-version", version.value,
  "-doc-source-url",
    s"https://github.com/org/my-library/tree/main€{FILE_PATH}.scala#L€{FILE_LINE}"
)
```

**sbt tasks:**
```bash
sbt doc            # Generate Scaladoc to target/scala-<version>/api/
sbt packageDoc     # Package docs into a jar (for Maven Central)
sbt publishLocal   # Includes docs jar
```

### Rule Categories

| Category | Pattern | Pipeline Severity |
|---|---|---|
| Missing class/object doc | Public class/object/trait without `/** */` | WARNING |
| Missing `@param` | Type or method param without `@param` or `@tparam` | INFO |
| Missing `@return` | Public method with non-Unit return without `@return` | INFO |
| Missing `@throws` | Method throwing a documented exception without `@throws` | WARNING |
| Broken `[[link]]` | `[[Symbol]]` cross-reference to undefined element | WARNING |

### Configuration Patterns

**Scala 3 Scaladoc (Markdown inside `/** */`):**
```scala
/** Fetches users matching the given criteria.
  *
  * Uses the [[UserRepository]] to query the persistence layer.
  * Results are sorted by creation date, newest first.
  *
  * ## Example
  *
  * ```scala
  * val users = userService.find(UserFilter(role = "admin"))
  * users.foreach(u => println(u.email))
  * ```
  *
  * @param filter    Criteria for filtering users. Use [[UserFilter.all]] for no restrictions.
  * @tparam F        The effect type (e.g. `IO` or `Future`).
  * @return          A collection of matching [[User]] instances, possibly empty.
  * @throws NotFoundError if the underlying repository is unavailable.
  * @since 2.0
  */
def find[F[_]](filter: UserFilter): F[List[User]]
```

**Scala 2 Scaladoc:**
```scala
/**
 * Parses a raw JSON string into a typed value.
 *
 * Returns [[scala.util.Right]] on success and [[scala.util.Left]] with
 * a [[ParseError]] on failure.
 *
 * {{{
 * val result = JsonParser.parse[User]("""{"name":"Alice"}""")
 * result match {
 *   case Right(user) => println(user.name)
 *   case Left(err)   => println(s"Failed: $err")
 * }
 * }}}
 *
 * @param json  The raw JSON string.
 * @tparam A    The target type. Must have an implicit [[Decoder]] in scope.
 * @return      Either a parse error or the decoded value.
 */
def parse[A: Decoder](json: String): Either[ParseError, A]
```

**Package-level documentation (`package.scala`):**
```scala
/** Provides HTTP client abstractions for the `mylib` library.
  *
  * Entry point: [[mylib.http.HttpClient]].
  *
  * @note All clients are thread-safe and designed for long-lived use.
  */
package object http
```

**Inherited documentation with `@inheritdoc`:**
```scala
/** @inheritdoc
  *
  * Additionally validates that the user is active before returning.
  */
override def findById(id: Long): Option[User]
```

### CI Integration

```yaml
# .github/workflows/docs.yml
- name: Set up JDK
  uses: actions/setup-java@v4
  with:
    java-version: '21'
    distribution: 'temurin'

- name: Generate Scaladoc
  run: sbt doc

- name: Upload Scaladoc artifact
  uses: actions/upload-artifact@v4
  with:
    name: scaladoc
    path: target/scala-3.*/api/

- name: Deploy to GitHub Pages
  if: github.ref == 'refs/heads/main'
  uses: peaceiris/actions-gh-pages@v4
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
    publish_dir: target/scala-3.3/api
```

## Performance

- `sbt doc` runs a full compile pass — it is as slow as `sbt compile` (10-120s depending on project size). Run only on publish branches.
- Use sbt's incremental compilation: the `~doc` watch task only regenerates docs for changed files.
- In multi-project builds, run `sbt subproject/doc` to scope generation to one subproject rather than `sbt doc` at the root.
- Cache the sbt build directory in CI (`~/.sbt`, `~/.ivy2`, `~/.cache/coursier`) to avoid re-downloading dependencies.

## Security

- Scaladoc generates static HTML — no runtime security surface.
- `[[PrivateClass]]` cross-references to private/internal types appear in generated output if the class is in scope. Use `private[pkg]` visibility to exclude implementation details.
- Avoid embedding credentials, stack traces, or environment-specific details in `/** */` doc examples.

## Testing

```bash
# Generate Scaladoc
sbt doc

# Generate and open (macOS)
sbt doc && open target/scala-3.3/api/index.html

# Watch mode — regenerate on source change
sbt ~doc

# Package docs jar for publishing
sbt packageDoc

# Verify docs compile as part of full build
sbt "+doc"   # Cross-build across Scala versions
```

## Dos

- Use Scala 3 Scaladoc's Markdown support for richly formatted documentation — code blocks, headings, and lists render correctly.
- Write `/** */` triple-slash on every public `class`, `trait`, `object`, and `def` — undocumented API is invisible to IDEs.
- Use `[[Symbol]]` cross-references — they are resolved at compile time and rendered as hyperlinks in the generated output.
- Set `"-source-links"` in Scaladoc options so readers can navigate from a doc page directly to the corresponding source line.
- Use `@tparam` tags for type parameters — they document type bounds and variance that the signature alone does not explain.
- Document `@throws` on methods that can fail — Scala does not enforce checked exceptions, so `@throws` is the only contract signal.

## Don'ts

- Don't skip `/** */` on traits that define public contracts — traits are often the primary API surface for library users.
- Don't use HTML tags in Scala 3 Scaladoc — use Markdown syntax; HTML is only partially supported and is not portable.
- Don't generate docs in the default sbt `compile` lifecycle on every build — gate it to the `doc` and `publishLocal` tasks.
- Don't mix Scala 2 `{{{ }}}` code fences with Scala 3 Markdown ``` fences in the same project — pick one style.
- Don't leave `@define` macros undocumented — they produce invisible substitutions that confuse contributors.
- Don't rely on `@inheritdoc` alone for complex overrides — add documentation specific to the overriding behavior.
