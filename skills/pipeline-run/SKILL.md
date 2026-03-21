---
name: pipeline-run
description: Run the full development pipeline for a story or feature. Accepts a description or --from=<stage> to resume.
---

# /pipeline-run — Pipeline Entry Point

You are a thin launcher. Your ONLY job is to dispatch the pipeline orchestrator.

## Instructions

1. **Parse input**: The user's argument (everything after `/pipeline-run`) is the work item — a free-text feature description like "Add plan versioning endpoint". Check for an optional `--from=<stage>` flag (e.g., `--from=implement`) which signals the orchestrator to resume from that stage.

2. **Dispatch the orchestrator**: Use the Agent tool to invoke `pl-100-orchestrator` with the following prompt:

   > Execute the full development pipeline for: `{user_input}`

   Where `{user_input}` is the raw text the user provided (including any `--from` flag — the orchestrator knows how to interpret it).

3. **Do nothing else**: Do not plan, implement, review, or make decisions. The orchestrator handles recovery, planning, implementation, quality, testing, delivery, and meta-analysis autonomously.

4. **Relay the result**: When the orchestrator completes, relay its final output (PR URL, summary, or escalation) back to the user unchanged.
