---
id: "08"
name: architecture-decision
prompt: "Why does forge use a staged pipeline instead of single-pass review?"
category: architecture
required_facts:
  - "stage"
  - "convergence"
  - "quality"
  - "score"
  - "iteration"
  - "review"
  - "agent"
---

# Task 08: Architecture Decision

## Prompt

Why does forge use a staged pipeline instead of single-pass review?

## Required Facts

The response must mention these concepts (substring match):

1. **stage** -- references the multi-stage design
2. **convergence** -- mentions iterative convergence toward quality target
3. **quality** -- quality improvement is the goal
4. **score** -- scoring drives the convergence loop
5. **iteration** -- multiple passes improve results
6. **review** -- multi-agent review catches more issues than single pass
7. **agent** -- specialized agents per stage/concern

## Evaluation

Accuracy = count of required_facts substrings found in response / 7
