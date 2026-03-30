# doxygen

## Overview

Doxygen is the de-facto documentation generator for C and C++ (also supports Java, Python, Fortran, IDL). It reads `/** */` block comments and `///` line comments and generates HTML, LaTeX, XML, and man-page output. A `Doxyfile` configuration file controls all behavior. Doxygen integrates with Graphviz to produce call graphs, dependency diagrams, and inheritance trees. Run `doxygen -g` to generate a default `Doxyfile`, then customize it.

## Architecture Patterns

### Installation & Setup

```bash
# macOS
brew install doxygen graphviz

# Ubuntu/Debian
apt-get install -y doxygen graphviz

# Generate a default Doxyfile
doxygen -g Doxyfile

# Run documentation generation
doxygen Doxyfile
```

**Key `Doxyfile` settings:**
```ini
# Project metadata
PROJECT_NAME           = "My C++ Library"
PROJECT_NUMBER         = 1.0.0
PROJECT_BRIEF          = "High-performance matrix operations"
OUTPUT_DIRECTORY       = docs/api

# Input/output
INPUT                  = src/ include/
FILE_PATTERNS          = *.c *.cpp *.h *.hpp
RECURSIVE              = YES
EXCLUDE_PATTERNS       = */internal/* */generated/* *_test.cpp

# Documentation extraction
EXTRACT_ALL            = NO        # Only document commented code
EXTRACT_PRIVATE        = NO
EXTRACT_STATIC         = YES
EXTRACT_ANON_NSPACES   = NO

# Output formats
GENERATE_HTML          = YES
GENERATE_LATEX         = NO        # Enable for PDF output
GENERATE_XML           = YES       # Enables Sphinx breathe/exhale integration
GENERATE_MAN           = NO

# Graphs (requires Graphviz)
HAVE_DOT               = YES
CALL_GRAPH             = YES
CALLER_GRAPH           = YES
CLASS_DIAGRAMS         = YES
COLLABORATION_GRAPH    = YES
DOT_IMAGE_FORMAT       = svg

# Source browsing
SOURCE_BROWSER         = YES
INLINE_SOURCES         = NO
REFERENCED_BY_RELATION = YES
REFERENCES_RELATION    = YES

# Warnings — treat as errors in CI
WARN_IF_UNDOCUMENTED   = YES
WARN_AS_ERROR          = NO        # Set to YES in CI
WARN_LOGFILE           = doxygen-warnings.txt
```

### Rule Categories

| Category | Pattern | Pipeline Severity |
|---|---|---|
| Undocumented public function | Public function without `/** */` or `///` | WARNING |
| Missing `@param` | Function param without `@param` doc | WARNING |
| Missing `@return` | Non-void function without `@return` | WARNING |
| Undocumented struct members | Public struct members without `///< ` comment | INFO |
| Broken `@ref` | `@ref Symbol` pointing to undefined entity | WARNING |

### Configuration Patterns

**Standard Doxygen comment — function:**
```c
/**
 * @brief Computes the Euclidean distance between two 3D points.
 *
 * Uses the standard formula: sqrt((x2-x1)^2 + (y2-y1)^2 + (z2-z1)^2).
 * For performance-critical paths where precision is not critical, prefer
 * fast_distance() which avoids the sqrt call.
 *
 * @param[in] a   Pointer to the first point. Must not be NULL.
 * @param[in] b   Pointer to the second point. Must not be NULL.
 * @return        The Euclidean distance as a double. Always non-negative.
 *
 * @see fast_distance()
 * @note The function does not modify the input points.
 * @warning Passing NULL pointers results in undefined behavior.
 */
double euclidean_distance(const Point3D* a, const Point3D* b);
```

**C++ class documentation:**
```cpp
/**
 * @class ConnectionPool
 * @brief Thread-safe pool of reusable database connections.
 *
 * Manages a bounded set of connections that are leased to callers
 * and returned on RAII destruction. The pool blocks on @ref acquire()
 * if all connections are in use.
 *
 * @tparam Conn  The connection type. Must satisfy the @ref Connectable concept.
 *
 * @example
 * @code{.cpp}
 * ConnectionPool<PgConn> pool(config, 10);
 * auto conn = pool.acquire();
 * conn->execute("SELECT 1");
 * // conn is returned to pool on destruction
 * @endcode
 */
template<typename Conn>
class ConnectionPool {
public:
    /**
     * @brief Acquires a connection from the pool.
     *
     * Blocks indefinitely if the pool is exhausted. Use @ref try_acquire()
     * for a non-blocking variant.
     *
     * @return A RAII lease wrapping an active @p Conn instance.
     * @throws std::runtime_error if the pool has been shut down.
     */
    [[nodiscard]] Lease<Conn> acquire();
};
```

**Inline member documentation with `///<`:**
```c
typedef struct {
    float x;  ///< X coordinate in world space (metres).
    float y;  ///< Y coordinate in world space (metres).
    float z;  ///< Z coordinate in world space (metres).
} Point3D;
```

**Sphinx integration via `breathe` (when `GENERATE_XML = YES`):**
```rst
.. doxygenfunction:: euclidean_distance
   :project: MyLib
```

### CI Integration

```yaml
# .github/workflows/docs.yml
- name: Install Doxygen and Graphviz
  run: sudo apt-get install -y doxygen graphviz

- name: Generate Doxygen docs
  run: doxygen Doxyfile

- name: Fail on documentation warnings
  run: |
    [ ! -f doxygen-warnings.txt ] || (cat doxygen-warnings.txt && exit 1)

- name: Upload docs artifact
  uses: actions/upload-artifact@v4
  with:
    name: doxygen-html
    path: docs/api/html/
```

## Performance

- Doxygen with `HAVE_DOT = YES` and `CALL_GRAPH = YES` is significantly slower — Graphviz renders one SVG per function. Disable call graphs for libraries with thousands of functions.
- Use `EXCLUDE_PATTERNS` aggressively to skip test files, generated code, and third-party headers.
- `GENERATE_LATEX = NO` saves significant time when PDF output is not needed.
- Parse-only mode (`doxygen -w html header.html footer.html stylesheet.css`) generates no output — useful for configuration validation.

## Security

- Doxygen generates static HTML — no runtime security surface.
- Graphviz renders from `.dot` graph data extracted from your code — no external input is processed.
- `SOURCE_BROWSER = YES` embeds full source code in the generated HTML. For proprietary codebases, disable before publishing externally.
- Avoid adding `@warning` or `@note` tags that disclose internal architecture vulnerabilities in publicly distributed headers.

## Testing

```bash
# Generate docs
doxygen Doxyfile

# Check warnings without generating output (not officially supported; use WARN_LOGFILE)
doxygen Doxyfile 2>doxygen-warnings.txt; cat doxygen-warnings.txt

# Validate Doxyfile syntax
doxygen -x Doxyfile   # Prints diff against defaults

# Open generated HTML
open docs/api/html/index.html

# Generate updated default config for comparison
doxygen -g Doxyfile.default
```

## Dos

- Enable `WARN_IF_UNDOCUMENTED = YES` and check `WARN_LOGFILE` in CI — it catches all public symbols missing doc comments.
- Use `@brief` for the one-line summary and the full description below — `@brief` is used in index listings and tooltips.
- Enable `HAVE_DOT = YES` with `CLASS_DIAGRAMS = YES` — inheritance and composition diagrams are invaluable for understanding C++ codebases.
- Use `@param[in]`, `@param[out]`, `@param[in,out]` directionality — it clarifies pointer semantics that types alone do not express.
- Set `GENERATE_XML = YES` to enable Sphinx `breathe` integration — publish C/C++ API docs alongside narrative documentation.
- Keep `Doxyfile` in version control and diff it against `doxygen -g` defaults to understand every changed setting.

## Don'ts

- Don't use `EXTRACT_ALL = YES` in published docs — it documents uncommented private internals and pollutes the API surface.
- Don't enable `CALL_GRAPH = YES` on large codebases without profiling first — Graphviz call graph generation can take tens of minutes.
- Don't skip `@warning` annotations on functions with undefined behavior on bad input — C/C++ callers rely on them for safe usage.
- Don't put Doxygen HTML output in the repository — it is large and changes with every source edit.
- Don't mix `//!` (Qt style) and `/** */` (Javadoc style) in the same project — pick one and enforce it in style guides.
- Don't use `\param` (backslash) and `@param` (at-sign) inconsistently — both are valid but mixing them hurts readability.
