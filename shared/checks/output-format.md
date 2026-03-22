# Check Engine Output Format

All three layers (fast patterns, linter bridge, agent intelligence) emit findings in this format.

## Finding Format

One finding per line:

```
file:line | CATEGORY-CODE | SEVERITY | message | fix_hint
```

### Field definitions

- `file` — project-relative path (e.g., `src/main/kotlin/domain/User.kt`)
- `line` — 1-based line number. `0` for file-level findings (e.g., file too large).
- `CATEGORY-CODE` — from scoring.md taxonomy: `ARCH-*`, `SEC-*`, `PERF-*`, `QUAL-*`, `CONV-*`, `DOC-*`, `TEST-*`. Module-specific: `HEX-*`, `THEME-*`. Subcategories: `QUAL-NULL`, `QUAL-READ`, `PERF-BLOCK`, `PERF-ASYNC`. (Reserved for Phase 2: `CONTRACT-BREAK`, `CONTRACT-CHANGE`, `CONTRACT-ADD`.)
- `SEVERITY` — exactly one of: `CRITICAL`, `WARNING`, `INFO`.
- `message` — human-readable description.
- `fix_hint` — one-line suggested fix. Empty string if no hint.

### Delimiter

Pipe `|` with spaces. If message or hint contains `|`, escape as `\|`.

### Deduplication

Deduplication key: `(file, line, category)`. When duplicates exist across layers, keep the finding with the highest severity and the longest description.

### Multi-line findings

Emit one line per finding location. Group in post-processing.

### JSON metadata keys

Underscore-prefixed keys (`_match_order`, `_severity_map`, `_note`) in any JSON config file are documentation/metadata. Parsers must skip keys starting with `_`.
