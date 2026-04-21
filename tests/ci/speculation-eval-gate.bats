#!/usr/bin/env bats

# Speculation eval CI gate.
#
# NOTE ON SYNTHETIC BANDS:
# The runner.sh harness is deterministic-synthetic (seed 42, no live LLM). Its
# metric distributions do not yet reflect production trigger-rate / token-ratio
# distributions. Specifically:
#   - trigger_rate: the corpus deliberately packs "either/or/consider"
#     keywords into all 10 HIGH-ambiguity items so detect_ambiguity fires
#     frequently. Real workloads see 0.20-0.50.
#   - token_ratio: the harness sums baseline + 3 candidates (~4x),
#     whereas production speculation replaces the baseline plan with the
#     winning candidate plus scoring overhead (~1.5-2.5x).
# Bands below are widened to accept the synthetic harness; the live pipeline
# eval harness will re-tighten them to the production thresholds documented
# in shared/speculation.md.

setup() {
  ROOT="$BATS_TEST_DIRNAME/../.."
  cd "$ROOT"
  bash evals/speculation/runner.sh evals/speculation/corpus.json /tmp/spec-results.json >/dev/null
}

@test "quality lift >= 0 (hard floor, no regression)" {
  lift=$(python3 -c 'import json; print(json.load(open("/tmp/spec-results.json"))["quality_lift"])')
  python3 -c "import sys; sys.exit(0 if float('$lift') >= 0 else 1)"
}

@test "token ratio <= 4.5x (synthetic harness ceiling)" {
  ratio=$(python3 -c 'import json; print(json.load(open("/tmp/spec-results.json"))["token_ratio"])')
  python3 -c "import sys; sys.exit(0 if float('$ratio') <= 4.5 else 1)"
}

@test "selection precision >= 0.60 (hard floor)" {
  prec=$(python3 -c 'import json; print(json.load(open("/tmp/spec-results.json"))["selection_precision"])')
  python3 -c "import sys; sys.exit(0 if float('$prec') >= 0.60 else 1)"
}

@test "trigger rate within 0.20-0.85 band (synthetic harness)" {
  rate=$(python3 -c 'import json; print(json.load(open("/tmp/spec-results.json"))["trigger_rate"])')
  python3 -c "import sys; sys.exit(0 if 0.20 <= float('$rate') <= 0.85 else 1)"
}
