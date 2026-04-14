---
id: "05"
name: recovery-strategy
prompt: "Neo4j MCP timed out during graph indexing. Describe recovery."
category: error-recovery
required_facts:
  - "MCP"
  - "timeout"
  - "graceful"
  - "degraded"
  - "skip"
  - "INFO"
  - "recovery"
---

# Task 05: Recovery Strategy

## Prompt

Neo4j MCP timed out during graph indexing. Describe recovery.

## Required Facts

The response must mention these concepts (substring match):

1. **MCP** -- identifies the failure domain
2. **timeout** -- names the error type
3. **graceful** -- describes graceful degradation behavior
4. **degraded** -- mentions degraded mode (MCP marked as degraded for run)
5. **skip** -- graph indexing is skipped, pipeline continues
6. **INFO** -- MCP failures logged as INFO (not blocking)
7. **recovery** -- references the recovery engine

## Evaluation

Accuracy = count of required_facts substrings found in response / 7
