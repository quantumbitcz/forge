# Q05: Hooks System Fixes

## Status
DRAFT — 2026-04-13

## Problem Statement

Hooks scored B+ (83/100) in the system review. Eight specific issues were identified:

1. **`file_changed` trigger unwired.** `shared/automations.md` documents a `file_changed` trigger type with `PostToolUse` hook primitive, but `hooks/hooks.json` has no corresponding hook entry. The automation engine can define `file_changed` automations in config, but they never fire because no hook calls `automation-trigger.sh`.

2. **Silent component indentation fallback.** When `engine.sh` detects non-standard indentation in the `components:` block of `forge.local.md` (tabs or 3+ spaces), it emits a WARNING to stderr and falls back to single-component mode. This is invisible to the user -- the pipeline silently processes a multi-component project as single-component. The warning exists in stderr only, which is not surfaced by Claude Code.

3. **Stale `.forge/.component-cache`.** The component cache (`resolve_component()`) is invalidated only by comparing mtime against `forge.local.md`, but this check is inside `detect_module()`, not `resolve_component()`. Once `.component-cache` is written, changes to the `components:` block in `forge.local.md` may not trigger cache rebuild if the file's overall mtime is not checked in the cache path.

4. **Deferred queue orphaning.** When `FORGE_BATCH_HOOK=1`, files are appended to `$FORGE_HOOK_QUEUE` instead of processed. If the batch session ends without calling `--flush-queue`, the queue file persists with unprocessed entries. No safety net exists to detect or flush orphaned queues.

5. **Fragile `TOOL_INPUT` parsing.** `mode_hook()` tries JSON parsing via Python first, then falls back to regex. The regex fallback (`grep -oE`) does not validate that the extracted path exists before proceeding, and there is no logging of which parsing method succeeded.

6. **Lock contention under concurrency.** The instance lock (`flock`/`mkdir`) silently skips the entire engine when contention occurs. Under high concurrency (many rapid Edit/Write operations), a significant number of checks may be silently dropped with no visibility.

7. **Feedback file race condition.** The `feedback-capture.sh` Stop hook appends to `auto-captured.md` without atomic write semantics. Concurrent Stop events (e.g., parallel sprint orchestrators ending simultaneously) can produce garbled output.

8. **No PreToolUse hooks.** The hooks system only supports PostToolUse and Stop events. There is no mechanism to validate state before an edit occurs (e.g., checking that the target file is within the worktree).

## Target
Hooks B+ -> A (83 -> 93+)

## Detailed Changes

### 1. Wire `file_changed` Trigger into hooks.json

**Current state:** `hooks/hooks.json` has one PostToolUse hook for `Edit|Write` (check engine). The `file_changed` automation trigger documented in `shared/automations.md` has no wiring.

**Change:** Add a second hook entry to the `Edit|Write` PostToolUse matcher that invokes `automation-trigger.sh`:

```json
{
  "matcher": "Edit|Write",
  "hooks": [
    {
      "type": "command",
      "command": "${CLAUDE_PLUGIN_ROOT}/shared/checks/engine.sh --hook",
      "timeout": 10
    },
    {
      "type": "command",
      "command": "${CLAUDE_PLUGIN_ROOT}/hooks/automation-trigger-hook.sh",
      "timeout": 3
    }
  ]
}
```

**New file:** `hooks/automation-trigger-hook.sh`
- Extract `file_path` from `$TOOL_INPUT` using the same JSON-then-regex approach as `engine.sh`
- Check if `.forge/` exists and `automation-trigger.sh` is executable
- Call `${CLAUDE_PLUGIN_ROOT}/hooks/automation-trigger.sh file_changed "$file_path"`
- Exit 0 always (never block the pipeline)
- If `.forge/` does not exist or no automations are configured, exit 0 immediately (sub-millisecond no-op)

**File path extraction:** Factor out the `TOOL_INPUT` parsing logic from `engine.sh mode_hook()` into a shared function in `shared/platform.sh` called `extract_file_path_from_tool_input()`. Both `engine.sh` and `automation-trigger-hook.sh` call this function. This eliminates duplication and consolidates the fragile parsing into one place.

### 2. Log Component Indentation Fallback Visibly

**Current state:** Two `echo ... >&2` calls in `resolve_component()` (lines 347, 353 of `engine.sh`) emit warnings about non-standard indentation, but stderr output from PostToolUse hooks is not reliably visible to users.

**Changes:**

a. **Log to `.forge/.hook-failures.log`:** After each indentation warning `echo` to stderr, also call `handle_failure "component_indent_fallback:$reason" "$file"`. This ensures the failure is recorded in the structured log.

b. **Write one-time warning marker:** Create `.forge/.component-indent-warning` on first detection. Contents: the warning message and a timestamp. This file is checked by `forge-status` to surface the warning:

```
[2026-04-13T10:00:00Z] Multi-component detection disabled: non-standard indentation in forge.local.md components: block. Fix: use 2-space indentation or run /forge-init to regenerate config.
```

c. **Surface in forge-status:** The `forge-status` skill checks for `.forge/.component-indent-warning` and includes it in output when present. The file is deleted when `forge.local.md` is regenerated (by `/forge-init`).

### 3. Component Cache Invalidation on Config Change

**Current state:** `.forge/.component-cache` is written by the orchestrator at PREFLIGHT. The cache file is read by `resolve_component()` without checking whether `forge.local.md` has been modified since the cache was written.

**Change:** Add an mtime check at the start of `resolve_component()`, before reading `.component-cache`:

```bash
# In resolve_component(), after setting cache_file and cfg variables:
if [[ -f "$cache_file" && -f "$cfg" ]]; then
  if [[ "$cfg" -nt "$cache_file" ]]; then
    # Config changed since cache was built — invalidate
    rm -f "$cache_file"
    handle_failure "component_cache_invalidated:config_newer" "${file_path}"
  fi
fi
```

This is consistent with the existing pattern in `detect_module()` (line 169) which already does `[[ "$cache" -nt "$cfg" ]]` for `.module-cache`. The component cache should follow the same invalidation strategy.

**Note:** Cache rebuild happens at next PREFLIGHT. Between invalidation and rebuild, `resolve_component()` falls through to parsing `forge.local.md` directly (path 2), which is correct behavior.

### 4. Deferred Queue Orphan Detection and Auto-Flush

**Current state:** When `FORGE_BATCH_HOOK=1`, files accumulate in `$FORGE_HOOK_QUEUE`. The `--flush-queue` mode processes them. But if the batch session crashes or the caller forgets to flush, the queue file is orphaned.

**Changes:**

a. **Orphan detection in `mode_hook()`:** At the start of `mode_hook()` (before checking `FORGE_BATCH_HOOK`), scan for orphaned queue files:

```bash
# Orphan detection: if a queue file exists, is >60s old, and FORGE_BATCH_HOOK is NOT set,
# auto-flush it before processing the current file.
if [[ -z "${FORGE_BATCH_HOOK:-}" && -d ".forge" ]]; then
  for orphan in .forge/.hook-queue-*; do
    [[ -f "$orphan" ]] || continue
    local age_threshold=60
    local file_age
    file_age=$(( $(date +%s) - $(stat -f%m "$orphan" 2>/dev/null || stat -c%Y "$orphan" 2>/dev/null || echo 0) ))
    if [[ $file_age -gt $age_threshold && -s "$orphan" ]]; then
      handle_failure "orphan_queue_flushed:age_${file_age}s" "$orphan"
      # Auto-flush: process queued files with Layer 1
      local project_root
      project_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
      "$0" --flush-queue --queue-file "$orphan" --project-root "$project_root" 2>/dev/null || true
    fi
  done
fi
```

b. **Queue file naming convention:** Document that `FORGE_HOOK_QUEUE` should follow the pattern `.forge/.hook-queue-{PID}` so orphan detection can glob for them.

c. **Log orphan flushes:** Each auto-flush appends to `.forge/.hook-failures.log` with reason `orphan_queue_flushed`.

### 5. Improved TOOL_INPUT Parsing

**Current state:** `mode_hook()` tries Python JSON parsing, then falls back to regex grep. Neither approach validates the extracted path, and there is no logging of which method was used.

**Changes:**

a. **Validate extracted path:** After extraction (both methods), add validation:

```bash
# After file_path extraction:
if [[ -n "$file" && ! -f "$file" ]]; then
  handle_failure "file_path_not_found:${file}" "TOOL_INPUT_parse"
  file=""  # Clear so we skip processing
fi
```

b. **Log parsing method:** Add a variable tracking which method succeeded:

```bash
local parse_method="none"
file="$(echo "${TOOL_INPUT:-}" | "$py_cmd" -c "..." 2>/dev/null)" && parse_method="json"
if [[ -z "$file" ]]; then
  file="$(echo "${TOOL_INPUT:-}" | grep -oE '...' ...)" && parse_method="regex"
fi
```

When `parse_method` is `regex`, log an INFO-level entry to `.hook-failures.log`:

```
{timestamp} | engine.sh | parse_fallback:regex | {file}
```

This makes it visible when JSON parsing consistently fails, which may indicate a Claude Code API change.

c. **Factor into shared function:** As described in change 1, move the extraction logic to `shared/platform.sh` as `extract_file_path_from_tool_input()` to be reused by the new automation trigger hook.

### 6. Replace flock with Atomic mkdir Locking + Exponential Backoff

**Current state:** The instance lock (lines 588-601) uses `flock -n` (non-blocking) or `mkdir` as fallback. On contention, the engine exits immediately (`exit 0`), silently skipping all checks for that file.

**Change:** Replace the binary lock-or-skip with a retry loop using exponential backoff:

```bash
_acquire_lock() {
  local lock_target="$1"
  local max_retries=3
  local delay_ms=100  # 100ms, 200ms, 400ms

  for ((i=0; i<max_retries; i++)); do
    if command -v flock &>/dev/null; then
      exec 200>"$lock_target"
      if flock -n 200; then
        return 0
      fi
      exec 200>&- 2>/dev/null
    else
      if mkdir "${lock_target}.d" 2>/dev/null; then
        return 0
      fi
    fi
    # Exponential backoff (bash sleep supports fractional seconds)
    local sleep_sec
    sleep_sec="$(echo "scale=3; $delay_ms / 1000 * (2 ^ $i)" | bc 2>/dev/null || echo "0.1")"
    sleep "$sleep_sec" 2>/dev/null || true
  done

  # All retries exhausted — log and skip
  handle_failure "lock_contention_exhausted:${max_retries}_retries" "${_CURRENT_FILE:-unknown}"
  return 1
}

if [[ -d "$_LOCK_DIR" ]]; then
  LOCK_FILE="${_LOCK_DIR}/.engine.lock"
  if ! _acquire_lock "$LOCK_FILE"; then
    exit 0
  fi
  # Set up cleanup trap based on which lock method succeeded
  if command -v flock &>/dev/null; then
    trap 'exec 200>&- 2>/dev/null' EXIT
  else
    trap 'rmdir "$LOCK_FILE.d" 2>/dev/null' EXIT
  fi
fi
```

**Impact:** Instead of immediately skipping on first contention, the engine retries 3 times with 100ms/200ms/400ms delays (total worst case: 700ms, well within the 10s hook timeout). Lock contention that persists past 3 retries is logged, making it visible for diagnosis.

### 7. Atomic Feedback File Writes

**Current state:** `feedback-capture.sh` appends to `auto-captured.md` directly. Concurrent Stop hooks can interleave writes.

**Change:** Use atomic write-then-rename for the feedback entry:

```bash
# In feedback-capture.sh, replace direct append with atomic write:
_feedback_file="$FORGE_DIR/feedback/auto-captured.md"
_tmp_entry="$FORGE_DIR/feedback/.auto-captured-$$.tmp"

# Write entry to temp file
echo "$entry" > "$_tmp_entry"

# Atomic append: use flock if available, else mkdir lock
if command -v flock &>/dev/null; then
  (
    flock -w 2 9 || { cat "$_tmp_entry" >> "$_feedback_file" 2>/dev/null; rm -f "$_tmp_entry"; exit 0; }
    cat "$_tmp_entry" >> "$_feedback_file"
    rm -f "$_tmp_entry"
  ) 9>"${_feedback_file}.lock"
else
  local lock_dir="${_feedback_file}.lockdir"
  if mkdir "$lock_dir" 2>/dev/null; then
    cat "$_tmp_entry" >> "$_feedback_file"
    rm -f "$_tmp_entry"
    rmdir "$lock_dir" 2>/dev/null
  else
    # Contention fallback: direct append (best-effort)
    cat "$_tmp_entry" >> "$_feedback_file" 2>/dev/null
    rm -f "$_tmp_entry"
  fi
fi
```

This ensures each entry is written completely to a temp file before being appended, preventing partial-line interleaving.

### 8. PreToolUse Hook Consideration (Deferred)

**Analysis:** Claude Code's hook system supports `PreToolUse` events (the `hooks.json` schema allows it). However, adding PreToolUse hooks introduces latency before every edit operation and creates a risk of blocking the pipeline if the hook fails.

**Decision:** Defer PreToolUse hooks to a future spec (potentially F02 linter-gated editing). Document the decision in `shared/decision-log.md` with rationale: the current PostToolUse model with fast Layer 1 checks provides sufficient coverage, and the remaining hooks fixes in this spec address the observability gap that PreToolUse would partially solve.

**What we DO add now:** The `automation-trigger-hook.sh` (change 1) and the improved lock/parsing (changes 5-6) collectively improve the hooks' reliability enough to close the gap without PreToolUse.

## Testing Approach

1. **Structural test (bats):** Validate `hooks/hooks.json` has entries for all documented trigger types:
   - PostToolUse `Edit|Write`: check engine + automation trigger
   - PostToolUse `Skill`: checkpoint
   - PostToolUse `Agent`: compaction check
   - Stop: feedback capture

2. **Unit test:** `automation-trigger-hook.sh` extracts file paths correctly from sample `TOOL_INPUT` payloads (JSON and malformed).

3. **Unit test:** Orphan queue detection — create a queue file older than 60s, invoke `engine.sh --hook`, verify it was flushed.

4. **Unit test:** Component cache invalidation — set `.component-cache` mtime to before `forge.local.md` mtime, invoke `resolve_component()`, verify cache is rebuilt.

5. **Integration test:** Lock contention — launch two `engine.sh --hook` invocations in parallel, verify both complete (one immediately, one after retry) and no entries are logged as `lock_contention_exhausted`.

6. **Manual test:** Multi-component project with tab indentation in `forge.local.md` — verify `.forge/.component-indent-warning` is created and `forge-status` surfaces it.

## Acceptance Criteria

- [ ] `hooks/hooks.json` includes automation trigger hook on `Edit|Write`
- [ ] `automation-trigger-hook.sh` exists, is executable, and extracts file paths from `TOOL_INPUT`
- [ ] Component indentation fallback is logged to `.forge/.hook-failures.log` and `.forge/.component-indent-warning`
- [ ] `.forge/.component-cache` is invalidated when `forge.local.md` is newer
- [ ] Orphaned queue files (>60s old) are auto-flushed on next `engine.sh --hook` invocation
- [ ] `TOOL_INPUT` parsing validates extracted file path exists and logs parsing method on regex fallback
- [ ] Instance lock uses exponential backoff (3 retries, 100/200/400ms) before skipping
- [ ] Lock contention exhaustion is logged to `.hook-failures.log`
- [ ] Feedback capture uses atomic write (temp file + locked append)
- [ ] All existing `validate-plugin.sh` checks continue to pass
- [ ] New bats tests cover automation trigger hook wiring and orphan queue detection

## Effort Estimate

Medium (3-4 days). Changes are localized to `hooks/` and `shared/checks/engine.sh`. No agent changes. No state schema changes.

- hooks.json + automation-trigger-hook.sh: 0.5 day
- engine.sh changes (cache, orphan, parsing, locking): 2 days
- feedback-capture.sh atomic write: 0.5 day
- Tests: 1 day

## Dependencies

- `shared/platform.sh` must be updated with `extract_file_path_from_tool_input()` function
- `hooks/automation-trigger.sh` must already exist and handle `file_changed` events (it does, per `shared/automations.md`)
- `forge-status` skill must be updated to check for `.forge/.component-indent-warning`
- No dependency on other Q-series specs
