# Eval Results Summary

Run `../run-evals.py` to populate results, then `../measure.py` to generate this summary.

Requires `ANTHROPIC_API_KEY` environment variable. Estimated cost: ~$0.50/run with Sonnet.

```bash
cd evals
export ANTHROPIC_API_KEY=sk-ant-...
python3 run-evals.py                    # Run all 10 tasks x 3 arms
python3 run-evals.py --tasks 01,02,03   # Subset
python3 measure.py                      # Analyze cached results
```

This is a local-only eval. Not run in CI.
