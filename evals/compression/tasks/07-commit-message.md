---
id: "07"
name: commit-message
prompt: "Generate commit for: JWT refresh rotation, 15min expiry, integration test."
category: shipping
required_facts:
  - "feat"
  - "JWT"
  - "refresh"
  - "15"
  - "test"
---

# Task 07: Commit Message

## Prompt

Generate commit for: JWT refresh rotation, 15min expiry, integration test.

## Required Facts

The response must mention these concepts (substring match):

1. **feat** -- uses conventional commit type (feat, not fix)
2. **JWT** -- names the feature area
3. **refresh** -- mentions refresh token rotation
4. **15** -- includes the expiry duration
5. **test** -- references the integration test

## Evaluation

Accuracy = count of required_facts substrings found in response / 5
