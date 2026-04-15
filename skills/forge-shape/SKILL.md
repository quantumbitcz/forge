---
name: forge-shape
description: "Turn a vague idea into a structured spec with stories and acceptance criteria. Use when your requirement is unclear, you're not sure what to build, or you need to think through a feature before implementing. Trigger: /forge-shape, I have an idea, help me think through this, refine my requirements"
allowed-tools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'Agent', 'AskUserQuestion']
ui: { ask: true, plan: true }
---

# /forge-shape -- Feature Shaping Entry Point

## Prerequisites

Before any action, verify:

1. **Git repository:** Run `git rev-parse --show-toplevel 2>/dev/null`. If fails: report "Not a git repository. Navigate to a project directory." and STOP.
2. **Forge initialized:** Check `.claude/forge.local.md` exists. If not: report "Forge not initialized. Run /forge-init first." and STOP.

## What to Expect

After dispatch, fg-010-shaper will:
1. Ask clarifying questions about your requirement (~3-5 questions)
2. Propose epics, stories, and acceptance criteria
3. Iterate based on your feedback until you're satisfied
4. Save the structured spec to `.forge/specs/` for use with `/forge-run --spec`

This is interactive — expect a ~5 minute conversation. The result is a spec file, not code.

## Instructions

1. **Parse input**: The user's argument (everything after `/forge-shape`) is the feature idea -- a free-text description like "Add notification system" or "I want users to share plans". If no input is provided, ask the user: "What feature would you like to shape? Describe your idea, even if it's rough (e.g., 'users should be able to share plans with each other')."

2. **Validate input**: Ensure the input contains enough substance to start shaping. A single word is insufficient. If the input is too terse (fewer than 3 words), prompt: "Could you elaborate a bit? What problem does this feature solve, or who is it for?"

3. **Detect available MCPs**: Detect available MCPs per `shared/mcp-detection.md` detection table. Mark unavailable MCPs as degraded. Build a comma-separated list of detected integrations.

4. **Dispatch the shaper**: Use the Agent tool to invoke `fg-010-shaper` with the following prompt:

   > Shape this feature requirement: `{user_input}`
   >
   > Available MCPs: `{detected_mcps}`

   Where `{user_input}` is the raw text the user provided.

5. **Do nothing else**: Do not plan, implement, or make decisions. The shaper handles all interaction with the user -- it will ask clarifying questions, propose structure, and iterate until the spec is solid.

6. **Relay the result**: When the shaper completes, relay its output (spec location, next steps) back to the user unchanged. The output typically includes a path to the generated spec file and a suggestion to run `/forge-run --spec <path>`.

## Error Handling

| Condition | Action |
|-----------|--------|
| Prerequisites fail | Report specific error message and STOP |
| Empty input | Ask user for feature description before dispatching |
| Shaper agent dispatch fails | Report "Feature shaper failed to start. Check plugin installation and try again." and STOP |
| Shaper returns error | Relay the error unchanged |
| User abandons shaping mid-session | The shaper handles graceful exit. No cleanup needed |

## See Also

- `/forge-run` -- Run the full pipeline after shaping is complete (use `--spec <path>` to pass the shaped spec)
- `/forge-sprint` -- Execute multiple shaped features in parallel
- `/forge-fix` -- For bug reports rather than new features
- `/forge-bootstrap` -- For scaffolding a new project rather than shaping a feature
