---
id: "04"
name: quality-gate-result
prompt: "Pipeline scored 72 (CONCERNS). 0 CRITICAL, 5 WARNING, 12 INFO. What happens next?"
category: pipeline-flow
required_facts:
  - "CONCERNS"
  - "72"
  - "WARNING"
  - "fix"
  - "iterate"
  - "pass_threshold"
  - "80"
---

# Task 04: Quality Gate Result

## Prompt

Pipeline scored 72 (CONCERNS). 0 CRITICAL, 5 WARNING, 12 INFO. What happens next?

## Required Facts

The response must mention these concepts (substring match):

1. **CONCERNS** -- identifies the score band (60-79)
2. **72** -- references the actual score
3. **WARNING** -- identifies warnings as the primary deduction
4. **fix** -- describes the fix cycle that follows
5. **iterate** -- mentions re-iteration/convergence loop
6. **pass_threshold** -- references the pass threshold concept
7. **80** -- mentions 80 as the PASS threshold

## Evaluation

Accuracy = count of required_facts substrings found in response / 7
