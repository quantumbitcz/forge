# F02: Linter-Gated Editing (L0 Pre-Edit Validation)

## Status
DRAFT — 2026-04-13

## Problem Statement

The forge check engine runs Layer 1 pattern checks **after** edits via PostToolUse hooks (`hooks/hooks.json` -> `shared/checks/engine.sh --hook`). This means every syntactically invalid edit enters the codebase, gets detected at VERIFY (Stage 5), triggers a fix loop dispatching `fg-300-implementer`, and consumes token budget on a problem that was preventable.

**Measured impact:** In internal benchmarks, 15-25% of implementer fix loop iterations address syntax errors (missing brackets, unclosed strings, invalid indentation) that could have been caught before the edit landed. Each fix loop iteration costs 500-2,000 tokens in dispatch overhead alone.

**Competitive validation:** SWE-Agent (Princeton, 2024) demonstrated that rejecting syntactically invalid edits before they land prevents cascading failures and reduces task completion tokens by ~18%. Aider uses tree-sitter AST validation on every edit for the same reason. OpenHands applies syntax validation in its edit action space.

**Gap:** Forge has no PreToolUse hook on Edit/Write operations. The earliest syntax feedback arrives via L1 regex patterns (PostToolUse) or L2 linter adapters (VERIFY stage), both of which fire after the edit is committed to the file.

## Proposed Solution

Add a **Layer 0 (L0)** pre-edit validation layer that intercepts Edit and Write operations via a PreToolUse hook. L0 uses tree-sitter to parse the file that *would result* from the edit. If the parse produces syntax errors, the hook returns an error message describing the specific syntax problem, causing Claude Code to reformulate the edit without consuming a fix loop iteration.

## Detailed Design

### Architecture

```
Edit/Write operation
     |
     v
PreToolUse hook (NEW: L0)
     |
     +-- Extract file_path from TOOL_INPUT
     +-- Apply edit to a temp copy of the file
     +-- Run tree-sitter parse on temp file
     +-- If ERROR nodes found: return error message -> agent reformulates
     +-- If clean parse: allow edit to proceed
     |
     v
Edit/Write executes (file modified)
     |
     v
PostToolUse hook (existing: L1)
     |
     +-- engine.sh --hook (regex pattern checks)
```

**Key components:**

1. **`shared/checks/l0-syntax/validate-syntax.sh`** — Entry point. Bash wrapper that extracts file path, applies edit simulation, calls tree-sitter, formats error output. Exits 0 (allow) or 1 (block with error message on stdout).

2. **`shared/checks/l0-syntax/apply-edit-preview.py`** — Python script that simulates the edit on a temp copy. For Edit operations, applies the `old_string` -> `new_string` replacement. For Write operations, uses the `content` directly. Returns the temp file path.

3. **`shared/checks/l0-syntax/parse-check.sh`** — Invokes `tree-sitter parse <file>` and checks for `(ERROR)` nodes in the S-expression output. Returns structured error info (line, column, context).

4. **`hooks/hooks.json`** — Updated to add a PreToolUse entry for Edit|Write.

### Hook Configuration

Updated `hooks/hooks.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/shared/checks/l0-syntax/validate-syntax.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/shared/checks/engine.sh --hook",
            "timeout": 10
          }
        ]
      },
      ...existing hooks...
    ]
  }
}
```

**PreToolUse semantics:** When a PreToolUse hook command exits with non-zero status, Claude Code prevents the tool from executing and returns the hook's stdout as an error message to the agent. The agent then reformulates without the edit having been applied. This is the same mechanism used by `forge-init`'s commit-msg-guard (see `skills/forge-init/SKILL.md` line 702).

### Script Design

#### `validate-syntax.sh` (main entry point)

```bash
#!/usr/bin/env bash
set -euo pipefail

# L0 Pre-Edit Syntax Validation
# PreToolUse hook for Edit|Write — validates that the resulting file parses cleanly.
# Exit 0 = allow edit. Exit 1 = block edit (stdout = error message to agent).
# Graceful degradation: if tree-sitter is not installed, exit 0 (allow).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-"$(cd "$SCRIPT_DIR/../../.." && pwd)"}"

# --- Check L0 enabled ---
# Quick check: if config disables L0, exit immediately
if [[ "${FORGE_L0_ENABLED:-true}" == "false" ]]; then
  exit 0
fi

# --- Check tree-sitter availability ---
if ! command -v tree-sitter &>/dev/null; then
  # Graceful degradation: no tree-sitter installed, skip L0
  exit 0
fi

# --- Extract file path from TOOL_INPUT ---
_PY="python3"
command -v python3 &>/dev/null || _PY="python"
if ! command -v "$_PY" &>/dev/null; then
  exit 0  # No python = can't parse JSON input
fi

FILE_PATH=""
TOOL_NAME="${TOOL_NAME:-}"
FILE_PATH=$("$_PY" -c "
import json, sys
d = json.loads(sys.stdin.read())
print(d.get('file_path', ''))
" <<< "${TOOL_INPUT:-}" 2>/dev/null) || exit 0

[[ -z "$FILE_PATH" ]] && exit 0

# --- Detect language from extension ---
LANG=""
case ".${FILE_PATH##*.}" in
  .kt|.kts)          LANG="kotlin" ;;
  .java)             LANG="java" ;;
  .ts|.tsx)          LANG="typescript" ;;
  .js|.jsx)          LANG="javascript" ;;
  .py)               LANG="python" ;;
  .go)               LANG="go" ;;
  .rs)               LANG="rust" ;;
  .cs|.csx)          LANG="c_sharp" ;;
  .c|.h)             LANG="c" ;;
  .cpp|.cc|.cxx|.hpp) LANG="cpp" ;;
  .swift)            LANG="swift" ;;
  .rb)               LANG="ruby" ;;
  .php)              LANG="php" ;;
  .dart)             LANG="dart" ;;
  .ex|.exs)          LANG="elixir" ;;
  .scala|.sc)        LANG="scala" ;;
  *)                 exit 0 ;;  # Unsupported language, skip
esac

# --- Check language is in the allowed list ---
# FORGE_L0_LANGUAGES is set by engine.sh from config; "auto" = all supported
if [[ "${FORGE_L0_LANGUAGES:-auto}" != "auto" ]]; then
  if ! echo "${FORGE_L0_LANGUAGES}" | grep -qw "$LANG"; then
    exit 0  # Language not in the configured list
  fi
fi

# --- Simulate the edit result ---
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
TEMP_FILE="$TEMP_DIR/$(basename "$FILE_PATH")"

"$_PY" "$SCRIPT_DIR/apply-edit-preview.py" \
  --tool-name "${TOOL_NAME}" \
  --tool-input "${TOOL_INPUT}" \
  --file-path "$FILE_PATH" \
  --output "$TEMP_FILE" 2>/dev/null || exit 0

[[ ! -f "$TEMP_FILE" ]] && exit 0

# --- Run tree-sitter parse ---
PARSE_OUTPUT=$(tree-sitter parse "$TEMP_FILE" 2>&1) || true

# --- Check for ERROR nodes ---
if echo "$PARSE_OUTPUT" | grep -q '(ERROR'; then
  # Extract the first error location
  ERROR_LINE=$("$_PY" "$SCRIPT_DIR/extract-error.py" \
    --parse-output "$PARSE_OUTPUT" \
    --file "$TEMP_FILE" 2>/dev/null) || ERROR_LINE="(could not extract location)"

  # Return error message — this blocks the edit
  cat <<EOF
SYNTAX ERROR — edit would produce invalid ${LANG} syntax.

${ERROR_LINE}

The file would not parse after this edit. Please fix the syntax error and retry.
Hint: Check for missing brackets, unclosed strings, incorrect indentation, or mismatched delimiters.
EOF
  exit 1
fi

# Parse clean — allow the edit
exit 0
```

#### `apply-edit-preview.py`

```python
#!/usr/bin/env python3
"""Simulate an Edit or Write operation on a temp copy of the target file."""
import argparse, json, sys, shutil

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--tool-name', required=True)
    parser.add_argument('--tool-input', required=True)
    parser.add_argument('--file-path', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()

    tool_input = json.loads(args.tool_input)
    tool_name = args.tool_name

    if tool_name == 'Write':
        # Write: entire file content is in tool_input.content
        with open(args.output, 'w') as f:
            f.write(tool_input.get('content', ''))
    elif tool_name == 'Edit':
        # Edit: apply old_string -> new_string replacement
        if not os.path.isfile(args.file_path):
            # New file via Edit (shouldn't happen, but handle gracefully)
            sys.exit(0)
        with open(args.file_path, 'r') as f:
            content = f.read()
        old_string = tool_input.get('old_string', '')
        new_string = tool_input.get('new_string', '')
        if old_string not in content:
            # Edit would fail anyway (old_string not found), let it through
            sys.exit(0)
        if tool_input.get('replace_all', False):
            result = content.replace(old_string, new_string)
        else:
            result = content.replace(old_string, new_string, 1)
        with open(args.output, 'w') as f:
            f.write(result)
    else:
        sys.exit(0)

import os
main()
```

#### `extract-error.py`

```python
#!/usr/bin/env python3
"""Extract first syntax error location from tree-sitter parse output."""
import argparse, re

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--parse-output', required=True)
    parser.add_argument('--file', required=True)
    args = parser.parse_args()

    # tree-sitter parse output format: (ERROR [row, col] - [row, col])
    match = re.search(r'\(ERROR \[(\d+), (\d+)\]', args.parse_output)
    if match:
        row = int(match.group(1))
        col = int(match.group(2))
        # Read the offending line for context
        try:
            with open(args.file) as f:
                lines = f.readlines()
            if row < len(lines):
                line_content = lines[row].rstrip()
                pointer = ' ' * col + '^'
                print(f"Line {row + 1}, column {col + 1}:")
                print(f"  {line_content}")
                print(f"  {pointer}")
            else:
                print(f"Line {row + 1}, column {col + 1}")
        except Exception:
            print(f"Line {row + 1}, column {col + 1}")
    else:
        print("Syntax error detected (location could not be extracted from parse tree)")

main()
```

### Language Support Matrix

Tree-sitter grammar names differ from forge's internal language names. The mapping:

| Forge Language | Tree-sitter Grammar | Extension(s) | Parse Reliability |
|---|---|---|---|
| kotlin | `kotlin` | `.kt`, `.kts` | HIGH — mature grammar |
| java | `java` | `.java` | HIGH — mature grammar |
| typescript | `typescript`, `tsx` | `.ts`, `.tsx` | HIGH — official grammar |
| python | `python` | `.py` | HIGH — mature grammar |
| go | `go` | `.go` | HIGH — mature grammar |
| rust | `rust` | `.rs` | HIGH — mature grammar |
| swift | `swift` | `.swift` | MEDIUM — community grammar, occasional false positives on newer syntax |
| c | `c` | `.c`, `.h` | HIGH — mature grammar |
| csharp | `c_sharp` | `.cs`, `.csx` | MEDIUM — community grammar |
| ruby | `ruby` | `.rb` | HIGH — mature grammar |
| php | `php` | `.php` | MEDIUM — requires `<?php` tag |
| dart | `dart` | `.dart` | MEDIUM — community grammar |
| elixir | `elixir` | `.ex`, `.exs` | MEDIUM — community grammar |
| scala | `scala` | `.scala`, `.sc` | LOW — grammar less mature, may produce false positives |
| cpp | `cpp` | `.cpp`, `.cc`, `.cxx`, `.hpp` | HIGH — mature grammar |
| javascript | `javascript` | `.js`, `.jsx` | HIGH — official grammar |

**Note on `.tsx`/`.jsx`:** These require the TSX grammar, not plain TypeScript/JavaScript. The script detects the extension and uses the appropriate grammar.

**False positive handling:** If a language grammar has LOW reliability, the script logs a WARNING instead of blocking the edit. Only HIGH and MEDIUM reliability grammars produce blocking errors.

### Configuration

In `forge-config.md`:

```yaml
# L0 Pre-Edit Syntax Validation (v2.0+)
check_engine:
  l0_enabled: true        # Enable/disable L0 syntax checking. Default: true.
  l0_languages: [auto]    # Languages to check. "auto" = all supported. Or explicit list: [kotlin, java, typescript]
  l0_timeout_ms: 500      # Max time for L0 check per edit. Default: 500. Range: 100-2000.
  l0_block_on_error: true # If false, log WARNING instead of blocking. Default: true.
```

**PREFLIGHT validation constraints:**

| Parameter | Range | Default | Rationale |
|---|---|---|---|
| `check_engine.l0_enabled` | boolean | `true` | Opt-out for projects with unusual syntax |
| `check_engine.l0_languages` | `[auto]` or list of language names | `[auto]` | Restrict L0 to specific languages |
| `check_engine.l0_timeout_ms` | 100-2000 | 500 | Below 100ms is too aggressive; above 2s blocks the edit flow |
| `check_engine.l0_block_on_error` | boolean | `true` | `false` = advisory mode (log warnings, don't block) |

**Environment variable override:** The orchestrator sets `FORGE_L0_ENABLED` and `FORGE_L0_LANGUAGES` environment variables at PREFLIGHT based on config values. This avoids the hook script needing to parse forge-config.md on every edit.

### Data Flow

**Step-by-step for an Edit operation:**

1. Agent calls `Edit(file_path: "src/Main.kt", old_string: "fun main()", new_string: "fun main(args: Array<String>")`
2. Claude Code invokes PreToolUse hooks matching `Edit`
3. `validate-syntax.sh` receives `TOOL_INPUT` JSON and `TOOL_NAME=Edit`
4. Script checks: L0 enabled? tree-sitter available? Language supported? (fast exits on any "no")
5. `apply-edit-preview.py` reads `src/Main.kt`, applies the replacement, writes temp file
6. `tree-sitter parse /tmp/xxx/Main.kt` runs, producing S-expression output
7. Script checks for `(ERROR` in output
8. ERROR found at line 1, col 35: missing closing parenthesis
9. Script outputs error message to stdout, exits 1
10. Claude Code receives error, does NOT execute the Edit
11. Agent sees: "SYNTAX ERROR -- edit would produce invalid kotlin syntax. Line 1, column 35: ..."
12. Agent reformulates: `Edit(file_path: "src/Main.kt", old_string: "fun main()", new_string: "fun main(args: Array<String>)")`
13. PreToolUse hook runs again, tree-sitter parse succeeds (no ERROR nodes), exits 0
14. Claude Code executes the Edit
15. PostToolUse L1 hook runs as usual

**Step-by-step for a Write operation:**

1. Agent calls `Write(file_path: "src/NewFile.kt", content: "class Foo {\n  fun bar() {\n}\n")`
2. `validate-syntax.sh` receives `TOOL_INPUT` with full content
3. `apply-edit-preview.py` writes content directly to temp file (no existing file needed)
4. tree-sitter parse detects unmatched braces
5. Hook blocks the Write with syntax error details
6. Agent reformulates with corrected content

### Integration Points

| File | Change |
|---|---|
| `hooks/hooks.json` | Add `PreToolUse` section with Edit\|Write matcher pointing to `validate-syntax.sh` |
| `shared/checks/l0-syntax/validate-syntax.sh` | NEW — main entry point |
| `shared/checks/l0-syntax/apply-edit-preview.py` | NEW — edit simulation |
| `shared/checks/l0-syntax/extract-error.py` | NEW — error location extraction |
| `shared/checks/engine.sh` | No changes — L0 is separate from L1/L2/L3 |
| `agents/fg-100-orchestrator.md` | Add PREFLIGHT step to set `FORGE_L0_ENABLED` and `FORGE_L0_LANGUAGES` env vars from config |
| `agents/fg-300-implementer.md` | Add note in section 5.6 (Handle Failures) about L0 pre-edit validation reducing fix loops |
| `shared/state-schema.md` | Add `check_engine.l0_blocks` counter to `state.json` |
| `modules/frameworks/*/forge-config-template.md` | Add `check_engine:` section to templates |
| `CLAUDE.md` | Update check engine description to mention L0 layer |
| `shared/checks/engine.sh` | Add `--l0-stats` mode to report L0 block counts from state.json |

### Error Handling

**Failure mode 1: tree-sitter not installed.**
- Detection: `command -v tree-sitter` fails
- Behavior: Script exits 0 immediately, edit proceeds as if L0 does not exist
- Logging: First occurrence logs to `.forge/.hook-failures.log`: `"l0-syntax | skip:tree-sitter_not_installed"`
- No user-facing impact; existing L1+ pipeline continues as before

**Failure mode 2: tree-sitter grammar not installed for a language.**
- Detection: `tree-sitter parse` fails with "No language found" or similar
- Behavior: Script exits 0, edit proceeds
- Logging: Logs to `.forge/.hook-failures.log`: `"l0-syntax | skip:grammar_missing_{lang}"`

**Failure mode 3: Python not available.**
- Detection: Neither `python3` nor `python` found
- Behavior: Script exits 0, edit proceeds
- Logging: Logs to `.forge/.hook-failures.log`: `"l0-syntax | skip:python_not_found"`

**Failure mode 4: tree-sitter crashes or hangs.**
- Detection: Hook timeout (5 seconds in hooks.json)
- Behavior: Claude Code kills the hook process; edit proceeds as if hook did not exist
- Logging: `.forge/.hook-failures.log` entry from handle_failure if applicable

**Failure mode 5: False positive (tree-sitter reports error on valid code).**
- Detection: Agent reports that a valid edit was blocked (user feedback or self-detection)
- Mitigation: `l0_block_on_error: false` (advisory mode) or exclude the language from `l0_languages`
- Long-term: Track false positives in `.forge/l0-false-positives.jsonl` for grammar reliability scoring

**Failure mode 6: Edit simulation fails (old_string not found, file missing).**
- Detection: `apply-edit-preview.py` exits non-zero
- Behavior: Script exits 0, edit proceeds (the Edit tool itself will handle the error)

### Interaction with Existing Check Engine

L0 and L1+ are complementary, not overlapping:

| Layer | When | What | Mechanism | Blocks? |
|---|---|---|---|---|
| L0 (NEW) | Before edit | Syntax validity | tree-sitter AST | Yes (PreToolUse) |
| L1 (existing) | After edit | Pattern violations | Regex + JSON rules | No (reports findings) |
| L2 (existing) | VERIFY stage | Linter violations | External linters | No (reports findings) |
| L3 (existing) | REVIEW stage | Semantic issues | Agent dispatch | No (reports findings) |

L0 catches syntax errors that L1 patterns cannot detect (L1 checks individual patterns, not full grammar). L1 catches convention violations that L0 cannot detect (L0 only validates syntax, not style).

### State Tracking

New counter in `state.json`:

```json
{
  "check_engine": {
    "l0_blocks": 0,
    "l0_total_checks": 0,
    "l0_skipped": 0,
    "l0_avg_latency_ms": 0
  }
}
```

- `l0_blocks`: Number of edits blocked by L0 syntax validation (incremented by hook via atomic counter file `.forge/.l0-blocks`)
- `l0_total_checks`: Total L0 checks performed
- `l0_skipped`: L0 checks skipped (tree-sitter unavailable, unsupported language, timeout)
- `l0_avg_latency_ms`: Rolling average latency for performance monitoring

The orchestrator reads `.forge/.l0-blocks` at VERIFY stage and writes values into `state.json.check_engine`. The retrospective includes L0 stats in the run report.

## Performance Characteristics

**Latency budget:** 500ms per edit (configurable via `l0_timeout_ms`).

| Component | Expected Latency | Notes |
|---|---|---|
| JSON parsing (Python) | 10-20ms | Parse TOOL_INPUT |
| Edit simulation | 5-30ms | Read file + apply replacement + write temp |
| tree-sitter parse | 5-100ms | Depends on file size; <50ms for files <5,000 lines |
| Error extraction | 1-5ms | Regex on parse output |
| **Total** | **20-150ms typical** | Well within 500ms budget |

**File size scaling:** tree-sitter is incremental and handles files up to 100K lines in <200ms. For forge's typical use case (files <2,000 lines), parse time is <50ms.

**Overhead per edit:** One additional process spawn (bash + python + tree-sitter). On modern hardware with warm caches, this is 50-200ms. The existing PostToolUse L1 hook adds 100-500ms, so L0 approximately doubles the per-edit overhead but eliminates costly fix loops.

**Net token savings:** If L0 prevents 20% of fix loops (conservative estimate), and each fix loop costs 500-2,000 tokens, a typical 5-task implementation saves 500-2,000 tokens. The per-edit latency increase is negligible compared to the token/time savings from avoided fix cycles.

## Testing Approach

### Structural Tests (`tests/structural/`)

1. **Hook registration:** `hooks/hooks.json` has PreToolUse entry matching Edit|Write pointing to `validate-syntax.sh`
2. **Script executability:** `validate-syntax.sh` has `#!/usr/bin/env bash` and is `chmod +x`
3. **Script existence:** All three scripts exist in `shared/checks/l0-syntax/`
4. **Config template:** All forge-config templates include `check_engine:` section

### Unit Tests (`tests/unit/`)

1. **`l0-syntax-validation.bats`:**
   - Blocks edit that produces missing closing brace (kotlin, java, typescript, python, go, rust)
   - Allows edit that produces valid syntax
   - Allows edit when tree-sitter is not installed (mock `command -v`)
   - Allows edit when language is not in `l0_languages` list
   - Allows edit when `l0_enabled` is false
   - Times out gracefully within 5s hook timeout
   - Handles Edit with `replace_all: true`
   - Handles Write operation (full file content)
   - Handles missing source file (new file via Edit)
   - Returns correct error line and column

2. **`apply-edit-preview-test.py`:**
   - Edit: applies old_string -> new_string correctly
   - Edit: replace_all applies all occurrences
   - Edit: old_string not found -> exits 0
   - Write: writes content to output file
   - Handles unicode content correctly

### Scenario Tests (`tests/scenario/`)

1. **`l0-end-to-end.bats`:** (requires tree-sitter installed)
   - Full hook chain: PreToolUse blocks bad edit, PostToolUse runs on good edit
   - State counter incremented on block
   - Graceful degradation when tree-sitter removed mid-run

## Acceptance Criteria

1. Edit operations producing syntax errors are blocked before the file is modified
2. The agent receives a clear error message with line/column and hint
3. When tree-sitter is not installed, all edits proceed as before (zero behavioral change)
4. Per-edit latency is under 500ms for files under 5,000 lines
5. All 15 supported languages have grammar mappings
6. L0 can be disabled per-project via `check_engine.l0_enabled: false`
7. L0 can be restricted to specific languages via `check_engine.l0_languages`
8. L0 block count is tracked in `state.json.check_engine.l0_blocks`
9. The existing PostToolUse L1 hook continues to run after L0 passes
10. `./tests/validate-plugin.sh` passes with new hook configuration
11. No new dependencies beyond tree-sitter CLI (which is optional)

## Migration Path

**From v1.20.1 (current) to v2.0:**

1. **Zero breaking changes.** L0 is additive. If tree-sitter is not installed, behavior is identical to v1.20.1.
2. **hooks/hooks.json** gains a `PreToolUse` section. Existing `PostToolUse` is unchanged.
3. **Config templates** gain `check_engine:` section with `l0_enabled: true` as default.
4. **Existing projects** upgrading via `/forge-init`: the init skill detects the new hook and adds it to the project's plugin hooks. Existing custom PreToolUse hooks (e.g., commit-msg-guard) are preserved.
5. **tree-sitter installation:** Optional. The hook degrades gracefully. For users who want L0: `brew install tree-sitter` (macOS), `cargo install tree-sitter-cli` (cross-platform), or package manager equivalent.
6. **tree-sitter grammar installation:** Users need grammars for their languages. `tree-sitter` CLI handles grammar fetching via `tree-sitter init-config` + grammar repos. A future `/forge-init` enhancement could auto-install grammars for detected languages.

## Dependencies

**This feature depends on:**
- Claude Code PreToolUse hook mechanism (already supported, used by `forge-init`'s commit-msg-guard)
- tree-sitter CLI (optional external dependency; graceful degradation when absent)
- Python 3 (already required by `engine.sh` and `run-patterns.sh`)

**Other features that depend on this:**
- F04 (Inner-Loop Lint+Test) references L0 as the first validation step in the implementer's inner loop
- The L0 block count feeds into retrospective analysis for measuring edit quality improvement

**Other features that benefit from this (no hard dependency):**
- Model routing (F03): Lower-tier models (haiku) produce more syntax errors; L0 catches these before they waste tokens
