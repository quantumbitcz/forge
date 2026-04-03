---
name: bootstrap-project
description: Scaffold a new project with production-grade structure, build system, architecture, CI/CD, and tooling. Supports Gradle composite builds, Maven, npm workspaces, Cargo, Go modules, and more.
---

# /bootstrap-project -- Project Scaffolding Entry Point

You are a thin launcher. Your ONLY job is to dispatch the project bootstrapper agent.

## Instructions

1. **Parse input**: The user's argument (everything after `/bootstrap-project`) is the project description -- a free-text string like "Kotlin Spring Boot REST API with PostgreSQL" or "React Vite frontend with shared component library".

2. **Dispatch the bootstrapper**: Use the Agent tool to invoke `fg-050-project-bootstrapper` with the following prompt:

   > Bootstrap a new project: `{user_input}`

   Where `{user_input}` is the raw text the user provided.

3. **Do nothing else**: Do not scaffold, generate files, or make architecture decisions. The bootstrapper handles requirements gathering, scaffolding, validation, and pipeline initialization autonomously.

4. **Relay the result**: When the bootstrapper completes, relay its final output (project summary, validation results, or escalation) back to the user unchanged.
