---
name: fix-flaky-test
description: Investigate and fix a flaky test
version: "1.0"
mode: bugfix
parameters:
  - name: test_name
    description: Name or pattern of the flaky test
    type: string
    required: true
  - name: test_file
    description: Path to the test file containing the flaky test
    type: string
    required: true
  - name: flaky_behavior
    description: Description of the flaky behavior (e.g., "passes locally, fails in CI", "intermittent timeout")
    type: string
    required: true
  - name: frequency
    description: Approximate failure rate
    type: enum
    default: sometimes
    allowed_values: [rarely, sometimes, often, always_in_ci]
stages:
  skip: []
  focus:
    REVIEWING:
      review_agents: [fg-410-code-reviewer]
review:
  focus_categories: ["TEST-*", "QUAL-*", "PERF-*"]
  min_score: 85
scoring:
  critical_weight: 20
  warning_weight: 5
acceptance_criteria:
  - "GIVEN the test {{test_name}} WHEN run 10 times consecutively THEN it passes every time"
  - "GIVEN the fix WHEN applied THEN the root cause of the flaky behavior ({{flaky_behavior}}) is addressed"
  - "GIVEN the fix WHEN other tests run THEN no existing tests are broken"
  - "GIVEN the investigation WHEN complete THEN a comment documents what caused the flakiness and how it was fixed"
tags: [test, flaky, testing, ci, reliability]
---

## Requirement Template

Investigate and fix the flaky test **{{test_name}}** in `{{test_file}}`.

### Observed Behavior
- **Flaky behavior:** {{flaky_behavior}}
- **Failure frequency:** {{frequency}}

### Investigation Steps
1. Read the test file `{{test_file}}` and understand what **{{test_name}}** is testing
2. Identify the root cause of flakiness. Common causes to check:
   - Shared mutable state between tests (missing cleanup/isolation)
   - Race conditions or timing dependencies (async operations, timeouts)
   - External service dependencies (network, database, file system)
   - Non-deterministic data (random values, timestamps, ordering)
   - Resource leaks (connections, file handles, threads)
   - Environment differences (CI vs local, parallelism settings)
3. Verify the hypothesis by examining test execution patterns

### Fix Requirements
- Address the root cause, not just the symptom (do not simply increase timeouts unless timing is the actual issue)
- Maintain the original test intent -- the fix must not weaken test coverage
- Add a code comment explaining what caused the flakiness and how the fix prevents it
- If the fix involves test isolation, ensure the pattern is consistent with other tests in the file
- If the fix involves async handling, use the project's standard async test utilities
