---
name: agent-reset
description: Detects and recovers from agent loops, malformed output, and stalled agents by saving partial results and dispatching a fresh agent.
---

# Agent Reset Strategy

Handles situations where a dispatched agent is stuck in a loop, producing malformed output, or has stopped making progress. Preserves partial work and attempts recovery with a simplified dispatch.

---

## 1. Detection Criteria

An agent is considered failed when any of these conditions is met:

| Condition | Threshold | Detection Method |
|-----------|-----------|------------------|
| Tool call loop | >20 same tool calls (same tool name + same or near-identical arguments) | Monitor tool call log |
| Time without progress | >10 minutes since last new file written or meaningful output | Timestamp comparison |
| Malformed output | Agent returns non-structured output when structured output was expected | Output validation |
| Recursive dispatch | Agent dispatches itself (directly or indirectly) | Agent name in dispatch chain |

---

## 2. Save Partial Results

Before resetting, preserve everything the agent has done so far:

1. **Scan for partial file changes:**
   - Run `git diff --name-only` to find modified files.
   - Run `git ls-files --others --exclude-standard` to find new untracked files.
   - Capture the list of files the agent has created or modified.

2. **Save partial results to checkpoint:**
   - Write `.pipeline/partial-{agent_name}-{timestamp}.json`:
     ```json
     {
       "agent": "pl-300-implementer",
       "task": "task description",
       "files_modified": ["src/Foo.kt", "src/Bar.kt"],
       "files_created": ["src/Baz.kt"],
       "last_tool_call": "Bash: ./gradlew build",
       "loop_count": 22,
       "elapsed_minutes": 12,
       "partial_output": "last meaningful output if available"
     }
     ```

3. **Stage partial files:**
   - `git add -A && git stash push -m "recovery: partial results from {agent_name}"`
   - This preserves work without committing potentially broken code.

---

## 3. Recovery: Fresh Agent Dispatch

### 3.1 First Reset Attempt

Dispatch a fresh instance of the same agent type with:

1. **Simplified prompt:** Reduce the original dispatch prompt to its essential elements:
   - Task description (what to do)
   - File paths (where to do it)
   - Constraints (must-follow rules)
   - Remove: verbose context, exploration results, long PREEMPT lists

2. **Partial results context:** Include a summary of what the previous agent accomplished:
   ```
   Previous attempt completed partial work:
   - Modified: [file list]
   - Created: [file list]
   - Stashed as: recovery: partial results from {agent_name}

   Continue from where the previous agent left off. Apply stash with:
   git stash pop

   Do NOT redo work that is already complete.
   ```

3. **Anti-loop instruction:** Add explicit guard:
   ```
   IMPORTANT: If you find yourself repeating the same action more than 3 times,
   stop and report what is blocking you instead of retrying.
   ```

### 3.2 Second Reset Attempt (Scope Reduction)

If the first reset also fails (same detection criteria triggered again):

1. **Reduce scope:** Split the task into smaller sub-tasks. If the original task was "implement feature X with tests", split into:
   - Sub-task A: "implement the core logic only (no tests)"
   - Sub-task B: "write tests for the core logic"

2. **Dispatch sub-tasks sequentially** (not in parallel — reduce complexity).

3. **Pop the stash** before dispatching: `git stash pop` to restore partial work.

### 3.3 Maximum Resets

- **Max resets per agent per task:** 2
- After 2 resets, return `ESCALATE` with:
  - What the agent was trying to do
  - What partial work was saved (stash reference)
  - What appears to be blocking (loop pattern, error pattern)
  - Suggestion for manual intervention

---

## 4. Stash Management

- Stashes created by recovery are prefixed with `recovery:` for identification.
- On successful recovery: the stash is consumed (popped) by the fresh agent.
- On escalation: stash is preserved for user to inspect.
- After pipeline completion: retrospective agent should note any remaining recovery stashes.

---

## 5. Output

Return to recovery engine:

```json
{
  "result": "RECOVERED | ESCALATE",
  "details": "Description of what happened and recovery action taken",
  "reset_count": 1,
  "partial_results_ref": "recovery: partial results from pl-300-implementer",
  "scope_reduced": false,
  "files_preserved": ["src/Foo.kt", "src/Bar.kt"]
}
```
