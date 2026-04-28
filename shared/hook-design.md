# Hook Design

Defines the hook execution model, event types, ordering guarantees, and script contract.

## Hook Types

Hooks are event-based interceptors that run automatically when specific events occur during a Claude Code session. They are declared in `hooks/hooks.json` and installed by `/forge`. All hooks are **Python 3.10+** entry scripts; bash is no longer required.

## Event Types and Execution Order

### PreToolUse

Fires **before** a tool invocation is executed. Can block the operation.

| Hook | Trigger | Purpose |
|---|---|---|
| L0 syntax validation | `Edit\|Write` | Block syntactically invalid edits via tree-sitter AST |

### PostToolUse

Fires **after** a tool invocation completes successfully.

| Hook | Trigger | Purpose |
|---|---|---|
| Check engine | `Edit\|Write` | Run L1-L3 checks on modified files |
| Automation trigger | `Edit\|Write` | Dispatch event-driven automations |

### Skill

Fires when a skill (slash command) is invoked.

| Hook | Trigger | Purpose |
|---|---|---|
| Checkpoint | `Skill` | Save pipeline state checkpoint |

### Stop

Fires when the conversation ends or the user stops the agent.

| Hook | Trigger | Purpose |
|---|---|---|
| Feedback capture | `Stop` | Capture user satisfaction signal |

### Agent

Fires when an agent subagent call completes.

| Hook | Trigger | Purpose |
|---|---|---|
| Compaction check | `Agent` | Suggest context compaction if token usage is high |

### SessionStart

Fires once when a new session begins.

| Hook | Trigger | Purpose |
|---|---|---|
| Session start | `SessionStart` | Initialize session state, load caches |

## Ordering Guarantees

1. **PreToolUse hooks run before PostToolUse hooks** for the same tool invocation.
2. **Multiple hooks on the same event** run in the order declared in `hooks.json`.
3. **PreToolUse blocks are synchronous** -- the tool invocation does not proceed until the hook completes.
4. **PostToolUse hooks are non-blocking** -- tool result is already committed.

## Timeout Behavior

- Each hook has an implicit timeout (configurable per hook in `hooks.json`).
- **PreToolUse timeout**: The edit proceeds (fail-open). A skip counter is incremented in `.forge/.check-engine-skipped`.
- **PostToolUse timeout**: The hook is skipped silently. No retry.
- Timeout events are logged to `.forge/.hook-failures.jsonl`.

## Script Contract

Hook entry scripts (`.py` files referenced from `hooks.json`) must follow these 8 rules:

1. **Shebang**: `#!/usr/bin/env python3`. Python 3.10+ is guaranteed by `shared/check_prerequisites.py`.
2. **Thin entry shims**: Each entry script is ≤10 LOC. All real logic lives under `hooks/_py/` (e.g., `hooks._py.check_engine.engine`, `hooks._py.check_engine.automation_trigger`, `hooks._py.io_utils`). The entry script imports the module and calls a single `main()` function.
3. **Stdin carries the payload**: The tool input (or event payload) arrives on stdin as a JSON object. Parse it via `hooks._py.io_utils.parse_tool_input`. Do not rely on environment variables or `argv` for the payload — Claude Code's hook contract is stdin-based.
4. **Exit codes follow Claude Code's hook contract**:
   - `0` = allow / no-op (all event kinds).
   - `2` = block the tool invocation (PreToolUse only; stderr is surfaced to the user as the block reason).
   - Any other non-zero = warning/error per event kind (PostToolUse, Stop, SessionStart, Agent log it; none of them can block).
5. **Never crash**: Every entry script wraps its `main()` body in a top-level `try/except Exception` that appends a JSON line to `.forge/.hook-failures.jsonl` and exits `0`. A crashing hook must not break the user's session. The only intentional non-zero exit is a deliberate PreToolUse block (exit 2).
6. **No interactive input**: Do not call `input()` or any TTY prompt. All context comes from the stdin payload, `.forge/` state files, and environment variables set by the Claude Code runtime.
7. **Stdout is user-visible**: Keep it short and actionable. Machine-readable diagnostics go to stderr or the hook failure log.
8. **Idempotent and fast**: Hooks may fire many times per session. They must be safe to re-run and should return in under a second for L0/L1 paths; long-running work must be offloaded (async, background, deferred).

## Failure Behavior

| Event Type | Hook Fails | Result |
|---|---|---|
| PreToolUse | Exit non-zero | Tool invocation is **blocked**. Error message shown to user. |
| PreToolUse | Timeout | Tool invocation **proceeds** (fail-open). Skip counter incremented. |
| PostToolUse | Exit non-zero | Logged to `.forge/.hook-failures.jsonl`. No retry. |
| PostToolUse | Timeout | Skipped silently. No retry. |
| Stop | Exit non-zero | Logged. Session ends normally. |
| SessionStart | Exit non-zero | Logged. Session proceeds. |

## Failure logging

Every hook entry script imports `hooks/_py/failure_log.py` and calls
`record_failure(hook_name, matcher, exit_code, stderr_excerpt, duration_ms, cwd)`
on:

- any uncaught exception in the wrapped `main()`, and
- any non-zero exit from the wrapped `main()` other than the deliberate
  PreToolUse block (exit 2), which is a legitimate tool-block signal.

The log at `.forge/.hook-failures.jsonl` contains one JSON object per line
matching `shared/schemas/hook-failures.schema.json`. `hooks/session_start.py`
calls `failure_log.rotate()` once per session: files older than 7 days are
gzipped to `.forge/.hook-failures-YYYYMMDD.jsonl.gz`; gzip archives older
than 30 days are deleted.

Claude Code's upstream hook timeouts (the `timeout` field in
`hooks/hooks.json`) are enforced by the runtime, not the hook. A hook that
exceeds its timeout is killed and leaves no trace in the failure log —
it is visible only in the live Claude Code transcript.

## Adding New Hooks

1. Add the real logic as a module under `hooks/_py/` (e.g., `hooks/_py/my_feature.py` with a `main()` entrypoint).
2. Create a thin entry shim in `hooks/` (e.g., `hooks/my_feature.py`, ≤10 LOC) that imports and calls the module — this is the file referenced from `hooks.json`.
3. Add the hook entry to `hooks/hooks.json` with:
   - `event`: The event type (`PreToolUse`, `PostToolUse`, `Stop`, `Skill`, `Agent`, `SessionStart`)
   - `pattern`: Tool name pattern to match (regex, e.g., `Edit|Write`)
   - `command`: Invocation string, typically `python3 ${CLAUDE_PLUGIN_ROOT}/hooks/<entry>.py`
4. Run `/forge` in consuming projects to install the new hook.
5. Test the hook with `./tests/validate-plugin.sh` (structural) and add unit coverage under `tests/unit/hooks/`.

## Related

- `hooks/hooks.json` -- Hook declarations
- `hooks/_py/` -- Hook implementation modules (Python)
- `hooks/_py/io_utils.py` -- Stdin parsing (`parse_tool_input`), atomic JSON writes, path normalization
- `shared/checks/` -- Check engine implementation (L0-L3)
- `shared/automations.md` -- Automation trigger system
- `hooks/_py/check_engine/automation_trigger.py` -- Automation dispatch module (invoked from `post_tool_use.py`)
