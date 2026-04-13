# Context Condensation Prompt Template

This prompt is used by the orchestrator to request LLM-powered condensation of convergence loop iteration history.

## Prompt

```
Summarize the following convergence loop context into a structured summary.
Target length: ~{target_tokens} tokens.

Preserve:
- The current goal and acceptance criteria
- All unresolved CRITICAL and WARNING findings (exact text)
- Current test status (pass/fail counts, specific failures)
- Files changed so far
- What has been tried and what worked/didn't

Discard:
- Verbose tool output from previous iterations
- Resolved findings
- Intermediate reasoning that led to completed fixes

Format:
## Goal
[What we're trying to achieve]

## Progress
[What's been done, files changed, tests passing]

## Remaining
[What still needs to happen]

## Active Findings
[Unresolved findings, severity, file:line]

## Test Status
[Pass/fail/skip counts, specific failures]
```

## Extended Prompt (with convergence context)

Used when the orchestrator has convergence trajectory data available:

```
# Context Condensation

You are condensing the iteration history of a development pipeline convergence loop.
Your job is to produce a structured summary that preserves all information an
implementer or reviewer would need to continue working effectively.

## Input
The following sections contain iteration history from iterations {from} to {to}
of a {phase} convergence phase targeting score {target_score}.

{condensable_content}

## Tagged Content (preserved separately -- do not summarize)
The following content is preserved verbatim and will be appended to your summary.
Do not duplicate it.

{tagged_content_list}

## Output Requirements
Produce a summary with EXACTLY these sections:

### Goal
One sentence: what is being built or fixed.

### Progress
Bullet list: files changed, tests passing/failing, build status, lint status.

### Remaining Work
Bullet list: what still needs to happen (unresolved findings, missing tests).

### Convergence Trajectory
One line per iteration: iteration number, score, finding counts (CRITICAL/WARNING/INFO).

### Key Decisions
Bullet list of significant implementation decisions made during condensed iterations
(approach changes, trade-offs, user feedback incorporated).

Target length: {target_tokens} tokens. Be precise and factual. Do not editorialize.
```

## Template Variables

| Variable | Source | Description |
|---|---|---|
| `{target_tokens}` | `condensation.summary_target_tokens` config | Target summary length in tokens (default: 2000) |
| `{from}` | First condensable iteration number | Start of condensed range |
| `{to}` | Last condensable iteration number | End of condensed range |
| `{phase}` | `state.convergence.phase` | Current convergence phase (correctness/perfection) |
| `{target_score}` | `convergence.target_score` config | Score target for convergence |
| `{condensable_content}` | Iteration history sections | Content from old iterations to be condensed |
| `{tagged_content_list}` | Extracted tagged blocks | Summary of tagged content preserved separately |

## Output Markers

The condensed output is wrapped with markers for downstream transparency:

```markdown
<!-- CONDENSED at iteration {current_iteration} (covering iterations {from}-{to}) -->

{summary_output}

<!-- END CONDENSED -->
```

These markers tell agents they are working with summarized history. No agent modification is required -- agents already work with whatever context the orchestrator provides.
