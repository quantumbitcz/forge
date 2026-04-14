---
id: "03"
name: finding-category
prompt: "Explain what SEC-INJECTION means and how to fix it."
category: finding-categories
required_facts:
  - "SEC-INJECTION"
  - "injection"
  - "SQL"
  - "parameterized"
  - "CRITICAL"
  - "input"
---

# Task 03: Finding Category

## Prompt

Explain what SEC-INJECTION means and how to fix it.

## Required Facts

The response must mention these concepts (substring match):

1. **SEC-INJECTION** -- names the finding category
2. **injection** -- explains the vulnerability class
3. **SQL** -- mentions SQL injection as a common example
4. **parameterized** -- recommends parameterized queries as fix
5. **CRITICAL** -- notes the typical severity level
6. **input** -- references input validation/sanitization

## Evaluation

Accuracy = count of required_facts substrings found in response / 6
