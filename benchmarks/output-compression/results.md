# Output Compression Benchmark Results

Run `./run-benchmark.py` to populate this file with actual measurements.

Requires `ANTHROPIC_API_KEY` environment variable. Estimated cost: ~$0.50/run with Sonnet.

```bash
cd benchmarks/output-compression
export ANTHROPIC_API_KEY=sk-ant-...
python3 run-benchmark.py
python3 run-benchmark.py --tasks explain-convergence,review-summary  # Subset
```

This is a local-only benchmark. Not run in CI.
