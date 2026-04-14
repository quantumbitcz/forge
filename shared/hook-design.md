# Hook Design

Defines the hook execution model, event types, ordering guarantees, and script contract.

## Hook Types

Hooks are prompt-based interceptors that run automatically when specific events occur during a Claude Code session. They are declared in `hooks/hooks.json` and installed by `/forge-init`.

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
- Timeout events are logged to `.forge/.hook-failures.log`.

## Script Contract

Hook scripts (`.sh` files referenced from `hooks.json`) must follow these 8 rules:

1. **Shebang**: `#!/usr/bin/env bash`
2. **Executable**: `chmod +x` is required.
3. **Bash 4+**: Scripts may use associative arrays and other bash 4+ features. macOS users need `brew install bash`.
4. **No interactive input**: Scripts must not use `read` or any interactive prompt. They receive context via environment variables and arguments.
5. **Exit codes**: `0` = success/allow. Non-zero = block (PreToolUse) or log failure (PostToolUse).
6. **Stdout**: Hook output is captured and may be displayed to the user. Keep it concise.
7. **Stderr**: Logged to `.forge/.hook-failures.log`. Use for diagnostics.
8. **Idempotent**: Hooks may be called multiple times for the same logical operation. Must be safe to re-run.

## Failure Behavior

| Event Type | Hook Fails | Result |
|---|---|---|
| PreToolUse | Exit non-zero | Tool invocation is **blocked**. Error message shown to user. |
| PreToolUse | Timeout | Tool invocation **proceeds** (fail-open). Skip counter incremented. |
| PostToolUse | Exit non-zero | Logged to `.forge/.hook-failures.log`. No retry. |
| PostToolUse | Timeout | Skipped silently. No retry. |
| Stop | Exit non-zero | Logged. Session ends normally. |
| SessionStart | Exit non-zero | Logged. Session proceeds. |

## Adding New Hooks

1. Create the hook script in `hooks/` following the script contract.
2. Add the hook entry to `hooks/hooks.json` with:
   - `event`: The event type (`PreToolUse`, `PostToolUse`, `Stop`, `Skill`, `Agent`, `SessionStart`)
   - `pattern`: Tool name pattern to match (regex, e.g., `Edit|Write`)
   - `script`: Path to the hook script (use `${CLAUDE_PLUGIN_ROOT}` prefix)
3. Run `/forge-init` in consuming projects to install the new hook.
4. Test the hook with `./tests/validate-plugin.sh` to verify structural integrity.

## Related

- `hooks/hooks.json` -- Hook declarations
- `shared/checks/` -- Check engine implementation (L0-L3)
- `shared/automations.md` -- Automation trigger system
- `hooks/automation-trigger.sh` -- Automation dispatch script
