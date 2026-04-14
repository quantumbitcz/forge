# Compression Eval Harness

Measures the accuracy/token trade-off of forge's output compression system across three compression arms.

## Design

**Three-arm comparison:**

| Arm | Description | Compression Level |
|-----|-------------|-------------------|
| verbose | No compression instructions | Level 0 |
| terse | Terse mode (drop articles, filler, hedging) | Level 2 |
| caveman-full | Full caveman mode compression | Custom |

**10 eval tasks** covering pipeline concepts, quality gate output, finding categories, recovery, review, shipping, architecture, verification, and deployment. Each task defines 5-8 `required_facts` as substring matches.

**Accuracy metric:** `count(facts found in response) / total facts`. No NLP -- pure substring matching (case-insensitive).

**Token metric:** Actual output token count from Anthropic API usage stats.

## Running

```bash
# Prerequisites
pip install anthropic
export ANTHROPIC_API_KEY=sk-ant-...

# Run all 10 tasks x 3 arms (30 API calls, ~$0.50)
python3 run-evals.py

# Run subset
python3 run-evals.py --tasks 01,02,03

# Dry run (no API calls)
python3 run-evals.py --dry-run

# Analyze cached results
python3 measure.py

# Custom model
python3 run-evals.py --model claude-sonnet-4-20250514
```

## Cost Estimate

- 30 API calls (10 tasks x 3 arms)
- ~150 input tokens per call (system prompt + task prompt)
- ~500 output tokens per call (average)
- Estimated total: **~$0.50** with Sonnet

This is a **local-only** eval. Not run in CI.

## Output

- `results/eval-results.json` -- raw results (gitignored)
- `results/summary.md` -- markdown summary (committed)

## Task Definitions

Tasks are in `tasks/*.md` with YAML frontmatter:

```yaml
---
id: "01"
name: explain-convergence
prompt: "Explain how the forge convergence engine decides when to stop iterating."
required_facts:
  - "score_history"
  - "plateau_threshold"
  - "max_iterations"
---
```

Each task has 5-8 manually authored required_facts. Accuracy = substring matches / total.

## Adding Tasks

1. Create `tasks/NN-task-name.md` with frontmatter
2. Include 5-10 `required_facts` as substring matches
3. Run `python3 run-evals.py --tasks NN` to test
4. Run `python3 measure.py` to update summary
