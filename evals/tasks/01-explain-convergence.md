---
id: "01"
name: explain-convergence
prompt: "Explain how the forge convergence engine decides when to stop iterating."
category: pipeline-concepts
required_facts:
  - "score_history"
  - "plateau_threshold"
  - "plateau_patience"
  - "max_iterations"
  - "PLATEAUED"
  - "phase_iterations"
  - "target_score"
  - "diminishing"
---

# Task 01: Explain Convergence

## Prompt

Explain how the forge convergence engine decides when to stop iterating.

## Required Facts

The response must mention these concepts (substring match):

1. **score_history** -- convergence tracks score progression across iterations
2. **plateau_threshold** -- minimum score improvement to count as progress
3. **plateau_patience** -- number of iterations without improvement before plateau
4. **max_iterations** -- hard ceiling on iteration count
5. **PLATEAUED** -- convergence state when improvement stalls
6. **phase_iterations** -- per-phase counter that resets on safety gate restart
7. **target_score** -- score the engine aims to reach (within pass_threshold..100)
8. **diminishing** -- diminishing returns detection

## Evaluation

Accuracy = count of required_facts substrings found in response / 8
