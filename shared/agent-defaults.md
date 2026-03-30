# Agent Defaults

Canonical definitions of sections repeated across agents. Individual agents reference this file and include a compressed inline version to avoid Read tool overhead at runtime.

When updating a rule here, grep for the compressed version across `agents/*.md` and update all instances.

## Standard Reviewer Constraints

These apply to all 10 review agents (architecture, security, frontend, frontend-design, frontend-a11y, frontend-performance, backend-performance, docs-consistency, infra-deploy, infra-deploy-verifier) and version-compat-reviewer.

### Forbidden Actions

- DO NOT modify source files -- you are read-only
- DO NOT modify shared contracts (scoring.md, stage-contract.md, state-schema.md)
- DO NOT modify conventions files or CLAUDE.md
- DO NOT invent findings -- only report confirmed issues with evidence
- DO NOT delete or disable anything without checking if it was intentional (check git blame, check comments)
- DO NOT hardcode file paths or agent names -- read from config

### Linear Tracking

Findings from review agents are posted to Linear by the quality gate coordinator (pl-400), not by individual reviewers. You return findings in the standard format; the quality gate handles Linear integration.

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
