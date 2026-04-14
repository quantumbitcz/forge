---
id: "10"
name: deployment-strategy
prompt: "Spring Boot 3.4.1 to k8s with zero downtime. Describe rolling update."
category: deployment
required_facts:
  - "rolling"
  - "readiness"
  - "health"
  - "replica"
  - "zero downtime"
  - "k8s"
  - "Spring Boot"
---

# Task 10: Deployment Strategy

## Prompt

Spring Boot 3.4.1 to k8s with zero downtime. Describe rolling update.

## Required Facts

The response must mention these concepts (substring match):

1. **rolling** -- names the rolling update strategy
2. **readiness** -- references readiness probes
3. **health** -- mentions health checks (liveness/readiness)
4. **replica** -- discusses replica management during rollout
5. **zero downtime** -- confirms zero-downtime goal
6. **k8s** -- references Kubernetes
7. **Spring Boot** -- mentions Spring Boot actuator or framework context

## Evaluation

Accuracy = count of required_facts substrings found in response / 7
