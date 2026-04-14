---
id: "09"
name: test-results
prompt: "Build PASS, Lint 2 warnings, 47/48 unit tests (1 flaky), 12/12 integration."
category: verification
required_facts:
  - "PASS"
  - "47"
  - "flaky"
  - "quarantine"
  - "WARNING"
  - "lint"
---

# Task 09: Test Results

## Prompt

Build PASS, Lint 2 warnings, 47/48 unit tests (1 flaky), 12/12 integration.

## Required Facts

The response must mention these concepts (substring match):

1. **PASS** -- build passed
2. **47** -- references the unit test count
3. **flaky** -- identifies the flaky test
4. **quarantine** -- recommends quarantining or notes flaky test management
5. **WARNING** -- lint warnings are WARNING severity
6. **lint** -- references the lint results

## Evaluation

Accuracy = count of required_facts substrings found in response / 6
