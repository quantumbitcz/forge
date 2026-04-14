---
id: "06"
name: code-review-report
prompt: "Reviewed 8 Spring Boot files. Found SQL injection, missing @Transactional, test gap."
category: review-output
required_facts:
  - "SEC-INJECTION"
  - "CRITICAL"
  - "@Transactional"
  - "WARNING"
  - "test"
  - "Spring Boot"
  - "score"
  - "fix"
---

# Task 06: Code Review Report

## Prompt

Reviewed 8 Spring Boot files. Found SQL injection, missing @Transactional, test gap.

## Required Facts

The response must mention these concepts (substring match):

1. **SEC-INJECTION** -- categorizes the SQL injection finding
2. **CRITICAL** -- SQL injection is CRITICAL severity
3. **@Transactional** -- references the missing annotation
4. **WARNING** -- missing @Transactional and test gaps are WARNING
5. **test** -- references the test coverage gap
6. **Spring Boot** -- names the framework context
7. **score** -- computes or mentions the quality score
8. **fix** -- recommends fixes for findings

## Evaluation

Accuracy = count of required_facts substrings found in response / 8
