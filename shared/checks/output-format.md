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

Pipe `|` with spaces (` | `). Escaping rules:
- Literal `|` in message or fix_hint: escape as `\|`
- Literal `\` in message or fix_hint: escape as `\\`
- Literal newline in message or fix_hint: replace with `\n` (backslash + 'n')

Parsing: split on ` | `, then for message and fix_hint fields:
1. Replace `\\` → `\` (backslash first)
2. Replace `\|` → `|` (pipe second)
3. Replace `\n` → newline (newline third)

Note: the literal two-character sequence `\n` (backslash + letter n) in source text cannot be losslessly round-tripped — it will decode as a newline. This is acceptable because `\n` does not occur naturally in finding messages or fix hints.

### Empty Findings

If a check layer finds no issues: output nothing to stdout and exit 0. Do NOT emit a special "clean" finding.

### Missing Fields

All five fields are required in every finding line. If a check cannot determine a field:
- `file`: use `?` if unknown
- `line`: use `0` for file-level or unknown
- `CATEGORY-CODE`: use a linter-default category (e.g., `TS-LINT-ESLINT`)
- `SEVERITY`: use mapped default or `INFO`
- `fix_hint`: use empty string `""` if no suggestion available

### Deduplication

The check engine deduplicates findings across its three layers using the key `(file, line, category)`. When duplicates exist across layers, keep the finding with the highest severity and the longest description.

Note: This is layer-level deduplication — it merges findings from Layer 1, 2, and 3 for the same file. The quality gate performs a second deduplication pass at scoring time with component awareness: `(component, file, line, category)` in multi-component projects. See `scoring.md` for scoring-level deduplication rules.

### Multi-line findings

Emit one line per finding location. Group in post-processing.

### JSON metadata keys

Underscore-prefixed keys (`_match_order`, `_severity_map`, `_note`) in any JSON config file are documentation/metadata. Parsers must skip keys starting with `_`.
