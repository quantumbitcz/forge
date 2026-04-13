---
name: bootstrap-project
description: "Scaffold a new project with production-grade structure, build system, architecture, CI/CD, and tooling. Use when starting a new project from scratch, creating a greenfield application, or scaffolding a new service in a multi-repo setup."
---

# /bootstrap-project -- Project Scaffolding Entry Point

## Prerequisites

Before any action, verify:

1. **Git repository:** Run `git rev-parse --show-toplevel 2>/dev/null`. If fails: report "Not a git repository. Initialize with `git init` first." and STOP.
2. **Forge initialized:** Check `.claude/forge.local.md` exists. If not: report "Forge not initialized. Run /forge-init first." and STOP.
3. **Project is empty or near-empty:** Check that the project has no existing source code (only config files like `.gitignore`, `README.md`, `LICENSE`). If the project already has source code, warn: "This project already has source code. Bootstrap is designed for empty projects. Use /forge-run for existing projects." and ask the user to confirm before proceeding.

## Instructions

1. **Parse input**: The user's argument (everything after `/bootstrap-project`) is the project description -- a free-text string like "Kotlin Spring Boot REST API with PostgreSQL" or "React Vite frontend with shared component library". If no input is provided, ask the user: "What kind of project would you like to scaffold? Describe the tech stack and purpose (e.g., 'Kotlin Spring Boot REST API with PostgreSQL')."

2. **Validate input**: Ensure the description contains at least a language or framework reference. If the description is too vague (e.g., just "a web app"), ask for clarification: "Could you specify the tech stack? For example: language, framework, database, or a template like 'React Vite TypeScript frontend'."

3. **Detect available MCPs**: Detect available MCPs per `shared/mcp-detection.md` detection table. Mark unavailable MCPs as degraded. Build a comma-separated list of detected integrations.

4. **Dispatch the bootstrapper**: Use the Agent tool to invoke `fg-050-project-bootstrapper` with the following prompt:

   > Bootstrap a new project: `{user_input}`
   >
   > Available MCPs: `{detected_mcps}`

   Where `{user_input}` is the raw text the user provided.

5. **Do nothing else**: Do not scaffold, generate files, or make architecture decisions. The bootstrapper handles requirements gathering, tech stack selection, scaffolding, validation, and pipeline initialization autonomously.

6. **Relay the result**: When the bootstrapper completes, relay its final output (project summary, validation results, or escalation) back to the user unchanged.

## Error Handling

| Condition | Action |
|-----------|--------|
| Prerequisites fail | Report specific error message and STOP |
| Empty input | Ask user for project description before dispatching |
| Bootstrapper agent dispatch fails | Report "Project bootstrapper failed to start. Check plugin installation and try again." and STOP |
| Bootstrapper returns error | Relay the error unchanged. Suggest `/forge-diagnose` if state was partially created |
| State corruption after partial bootstrap | Run `/repair-state` to fix state, then retry or use `/forge-reset` to start fresh |

## See Also

- `/forge-init` -- Configure an existing project for the forge (use instead when the project already has code)
- `/forge-run` -- Run the full pipeline after bootstrapping is complete
- `/migration` -- Upgrade or migrate frameworks in an existing project
- `/forge-shape` -- Shape a vague idea into a structured spec before building
