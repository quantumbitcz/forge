---
id: "02"
name: review-summary
prompt: "Quality gate found 1 CRITICAL, 2 WARNING, 1 INFO in auth/middleware.ts. Summarize."
category: quality-gate
required_facts:
  - "CRITICAL"
  - "WARNING"
  - "INFO"
  - "auth/middleware.ts"
  - "score"
  - "CONCERNS"
  - "fix"
---

# Task 02: Review Summary

## Prompt

Quality gate found 1 CRITICAL, 2 WARNING, 1 INFO in auth/middleware.ts. Summarize.

## Required Facts

The response must mention these concepts (substring match):

1. **CRITICAL** -- references the critical finding
2. **WARNING** -- references the warning findings
3. **INFO** -- references the info finding
4. **auth/middleware.ts** -- identifies the affected file
5. **score** -- mentions scoring impact (score = 100 - 20*1 - 5*2 - 2*1 = 68)
6. **CONCERNS** -- score 68 falls in CONCERNS range (60-79)
7. **fix** -- recommends fixing the critical finding

## Evaluation

Accuracy = count of required_facts substrings found in response / 7
