# Agent Defaults

Canonical definitions of sections repeated across agents. Individual agents reference this file and include a compressed inline version to avoid Read tool overhead at runtime.

When updating a rule here, grep for the compressed version across `agents/*.md` and update all instances.

## Standard Reviewer Constraints

These apply to all 10 review agents (fg-410-architecture-reviewer, fg-411-security-reviewer, fg-412-code-quality-reviewer, fg-413-frontend-reviewer, fg-414-frontend-a11y-reviewer, fg-415-frontend-performance-reviewer, fg-416-backend-performance-reviewer, fg-418-docs-consistency-reviewer, fg-419-infra-deploy-reviewer, fg-417-version-compat-reviewer). Note: `fg-610-infra-deploy-verifier` is a Stage 8 (SHIP) verification agent, not a Stage 6 reviewer — it follows the same Forbidden Actions but is dispatched by `fg-600-pr-builder`, not `fg-400-quality-gate`.

### Forbidden Actions

- DO NOT modify source files -- you are read-only
- DO NOT modify shared contracts (scoring.md, stage-contract.md, state-schema.md)
- DO NOT modify conventions files or CLAUDE.md
- DO NOT invent findings -- only report confirmed issues with evidence
- DO NOT delete or disable anything without checking if it was intentional (check git blame, check comments)
- DO NOT hardcode file paths or agent names -- read from config

## UI Contract

Agents with `ui:` section in frontmatter MUST follow `shared/agent-ui.md` for:
- AskUserQuestion format (structured options, never bare yes/no)
- TaskCreate/TaskUpdate lifecycle (create upfront, in_progress/completed transitions)
- Three-level task nesting maximum (orchestrator → coordinator → leaf)
- Autonomous mode behavior (`autonomous: true` in forge-config.md)

### Linear Tracking

Findings from review agents are posted to Linear by the quality gate coordinator (fg-400), not by individual reviewers. You return findings in the standard format; the quality gate handles Linear integration.

You do NOT interact with Linear directly.

### Optional Integrations

If Context7 MCP is available, use it to verify current API patterns and framework best practices.
If unavailable, rely on the conventions file and codebase grep for pattern verification.
Never fail because an optional MCP is down.

## Standard Finding Format

All review agents return findings using the format defined in `shared/checks/output-format.md`:

```
file:line | CATEGORY-CODE | SEVERITY | message | fix_hint
```

One finding per line, sorted by severity (CRITICAL first). If no issues found, return a single PASS line with the score.

**Output Format consolidation:** Reviewer agents reference `shared/checks/output-format.md` instead of duplicating the format definition. Each agent keeps its own category codes and severity rules inline — these are decision rules, not boilerplate.

**Important:** Severity rules (what maps to CRITICAL vs WARNING vs INFO) are agent-specific domain knowledge and must NOT be removed during compression. They tell the agent how to classify findings.

## Common Principles

These apply to ALL agents (pipeline and review):

- **No shared contract modifications** -- scoring.md, stage-contract.md, state-schema.md, frontend-design-theory.md are read-only
- **Evidence-based findings only** -- never invent or speculate
- **Graceful MCP degradation** -- never fail because an optional MCP is unavailable
- **Output budget** -- keep total output under 2,000 tokens unless agent-specific limit differs

## Version Resolution (MANDATORY)

Never hardcode or assume dependency versions. Before writing any version number:
1. Search the internet for the latest release of the package
2. Check compatibility with detected project versions in `state.json.detected_versions`
3. Use the latest compatible version

Rationale: Training data versions are stale. Always resolve at runtime. See `shared/version-resolution.md` for full details.

### Convention Stack Layers

Agents loading conventions for a component resolve these layers in order (most specific wins): variant → framework-binding → framework → language → code-quality → generic-layer → testing. The `code_quality` field is a list; each tool in the list loads its generic file (`modules/code-quality/{tool}.md`) and framework binding (`modules/frameworks/{fw}/code-quality/{tool}.md`) if it exists.
