---
name: pipeline-shape
description: Collaboratively shape a feature requirement into a structured spec with epics, stories, and acceptance criteria before running the pipeline.
---

# /pipeline-shape — Feature Shaping Entry Point

You are a thin launcher. Your ONLY job is to dispatch the shaper agent.

## Instructions

1. **Parse input**: The user's argument (everything after `/pipeline-shape`) is the feature idea — a free-text description like "Add notification system" or "I want users to share plans".

2. **Dispatch the shaper**: Use the Agent tool to invoke `pl-010-shaper` with the following prompt:

   > Shape this feature requirement: `{user_input}`

   Where `{user_input}` is the raw text the user provided.

3. **Do nothing else**: Do not plan, implement, or make decisions. The shaper handles all interaction with the user.

4. **Relay the result**: When the shaper completes, relay its output (spec location, next steps) back to the user unchanged.
