# Agent Defaults

Canonical definitions of sections repeated across agents. Individual agents reference this file and include a compressed inline version to avoid Read tool overhead at runtime.

When updating a rule here, grep for the compressed version across `agents/*.md` and update all instances.

## Standard Reviewer Constraints

These apply to all 9 review agents (fg-410-code-reviewer, fg-411-security-reviewer, fg-412-architecture-reviewer, fg-413-frontend-reviewer, fg-416-backend-performance-reviewer, fg-417-version-compat-reviewer, fg-418-docs-consistency-reviewer, fg-419-infra-deploy-reviewer, fg-420-dependency-reviewer). Note: `fg-610-infra-deploy-verifier` is a Stage 8 (SHIP) verification agent, not a Stage 6 reviewer — it follows the same Forbidden Actions but is dispatched by `fg-600-pr-builder`, not `fg-400-quality-gate`.

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

## Model Routing

When the orchestrator dispatches an agent with a `model` parameter (via `Agent(model: "haiku")`), the agent runs on the specified model tier. Agents do not control their own model selection.

### Agent Responsibilities

- **Do not** attempt to override or change the model assignment
- **Do not** adjust behavior based on perceived model capability (the orchestrator chose the tier based on the agent's task complexity)
- **Do** record the model assignment in stage notes if producing diagnostic output
- **Do** report if the task requires capabilities the assigned model may lack (e.g., a haiku-tier agent encountering a task that requires deep architectural reasoning should note this in stage notes, not silently produce lower-quality output)

### Orchestrator Responsibilities

- Resolve model tier from `forge-config.md` `model_routing` section per `shared/model-routing.md`
- Pass `model` parameter on every `Agent(...)` dispatch when `model_routing.enabled`
- Handle fallbacks when a model is unavailable
- Track token usage per agent per model via `shared/forge-token-tracker.sh`

## Confidence Reporting

All review agents MUST include the `confidence` field in every finding. The field is the 6th pipe-delimited value in the standard finding format (see `shared/checks/output-format.md`).

### When to Use Each Level

| Confidence | When to Use |
|------------|------------|
| `confidence:HIGH` | Strong evidence: pattern clearly violates convention, security flaw confirmed by multiple signals, test gap verified by analysis |
| `confidence:MEDIUM` | Likely issue but context-dependent: convention might not apply here, pattern could be intentional, fix has trade-offs |
| `confidence:LOW` | Uncertain: might be a false positive, edge case behavior unclear, limited context about the code's purpose |

### Rules

- Default to `confidence:HIGH` when certain. Do not over-use LOW to hedge — LOW findings receive half scoring weight and are excluded from fix cycles.
- If two or more reviewers independently flag the same issue, the quality gate promotes the finding's confidence to HIGH regardless of individual agent assessments.
- The confidence field applies to all categories including SCOUT-* (though SCOUT findings are already zero-scored).

## Deliberation Response Format

When the quality gate detects conflicting findings at the same `(file, line)` and `quality_gate.deliberation` is enabled, it re-dispatches both originating reviewers with a narrow deliberation prompt. Each reviewer responds with one of:

| Response | Meaning | Effect |
|----------|---------|--------|
| `MAINTAIN` | Keep finding as-is, add reasoning | Finding survives with original severity |
| `REVISE` | Adjust severity, explain why | Finding updated with new severity |
| `WITHDRAW` | Concede to other agent's perspective | Finding removed |

### Deliberation Prompt Format (received by reviewers)

    Your finding conflicts with another reviewer's finding at the same location.

    YOUR FINDING:
      file:line | CATEGORY | SEVERITY | CONFIDENCE | description | fix_hint

    CONFLICTING FINDING (from {other_agent}):
      file:line | CATEGORY | SEVERITY | CONFIDENCE | description | fix_hint

    Review both findings and respond with exactly one of:
    - MAINTAIN: {reasoning why your finding should stand}
    - REVISE severity to {WARNING|INFO}: {reasoning for downgrade}
    - WITHDRAW: {reasoning why the other finding is more appropriate}

### Constraints

- Max 1 deliberation round per conflict (no back-and-forth)
- Only triggered for conflicts involving at least one WARNING or CRITICAL finding
- 60-second timeout per reviewer response. On timeout, original finding stands unchanged.
- Deliberation is disabled by default (`quality_gate.deliberation: false`)
