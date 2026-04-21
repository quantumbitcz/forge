#!/usr/bin/env bats
# CI-gating assertions on the consistency eval results.
# Runs the offline eval harness (deterministic), then asserts on accuracy
# lift, adversarial low-consensus rate, latency, and cache correctness.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  RESULTS_DIR="${REPO_ROOT}/evals/pipeline/results"

  # Produce fresh results (offline mode — deterministic).
  "${REPO_ROOT}/evals/pipeline/consistency-eval.sh" --offline >/dev/null

  SHAPER="${RESULTS_DIR}/consistency-shaper_intent.json"
  VALID="${RESULTS_DIR}/consistency-validator_verdict.json"
  PRRJ="${RESULTS_DIR}/consistency-pr_rejection_classification.json"
}

assert_py() {
  run python3 -c "$1"
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "unanimity rate > 95 percent on the easy subset" {
  assert_py "
import json, sys
for f in ['$SHAPER','$VALID','$PRRJ']:
    d = json.load(open(f))
    easy = [r for r in d['results'] if r['difficulty'] == 'easy' and r.get('voted') is not None]
    unan = [r for r in easy if not r['low_consensus']]
    if not easy or len(unan) / len(easy) <= 0.95:
        print(f'FAIL {f} rate={len(unan)/max(1,len(easy)):.3f}'); sys.exit(1)
print('OK')
"
}

@test "adversarial prompts trigger low_consensus at least 80 percent" {
  assert_py "
import json, sys
for f in ['$SHAPER','$VALID','$PRRJ']:
    d = json.load(open(f))
    adv = [r for r in d['results'] if r['difficulty'] == 'adversarial']
    flagged = [r for r in adv if r['low_consensus'] or r.get('error')]
    if not adv or len(flagged) / len(adv) < 0.80:
        print(f'FAIL {f} rate={len(flagged)/max(1,len(adv)):.3f}'); sys.exit(1)
print('OK')
"
}

@test "voted accuracy exceeds single-sample by at least 5 percentage points" {
  assert_py "
import json, sys
for f in ['$SHAPER','$VALID','$PRRJ']:
    d = json.load(open(f))
    rs = [r for r in d['results'] if r.get('voted') is not None]
    voted_acc = sum(1 for r in rs if r['voted'] == r['gold']) / max(1, len(rs))
    single_acc = sum(1 for r in rs if r['single'] == r['gold']) / max(1, len(rs))
    if voted_acc - single_acc < 0.05:
        print(f'FAIL {f} voted={voted_acc:.3f} single={single_acc:.3f}'); sys.exit(1)
print('OK')
"
}

@test "cache correctness: second pass with cache enabled yields identical labels" {
  assert_py "
import asyncio, json, sys, tempfile, os
sys.path.insert(0, '$REPO_ROOT')
from hooks._py import consistency as C
import random, hashlib
labels = ['GO','REVISE','NO-GO']
async def smp(p, lbls, tier, seed):
    rng = random.Random(hashlib.sha256(f'{p}|{seed}'.encode()).digest())
    return {'label': lbls[rng.randrange(len(lbls))], 'confidence': 0.8}
with tempfile.TemporaryDirectory() as tmp:
    cp = os.path.join(tmp, 'c.jsonl')
    prompts = ['p1','p2','p3','p4','p5']
    first = [asyncio.run(C.vote_async(decision_point='validator_verdict',
        prompt=p, labels=labels, state_mode='eval', n=3, tier='fast',
        cache_enabled=True, cache_path=__import__('pathlib').Path(cp),
        sampler=smp)) for p in prompts]
    second = [asyncio.run(C.vote_async(decision_point='validator_verdict',
        prompt=p, labels=labels, state_mode='eval', n=3, tier='fast',
        cache_enabled=True, cache_path=__import__('pathlib').Path(cp),
        sampler=smp)) for p in prompts]
    for a, b in zip(first, second):
        if a.label != b.label or not b.cache_hit:
            print('FAIL cache mismatch'); sys.exit(1)
print('OK')
"
}

@test "p95 elapsed time per decision point is under 2500 ms" {
  assert_py "
import json, sys
for f in ['$SHAPER','$VALID','$PRRJ']:
    d = json.load(open(f))
    xs = sorted(r['elapsed_ms'] for r in d['results'])
    if not xs: sys.exit(1)
    p95 = xs[max(0, int(len(xs)*0.95)-1)]
    if p95 >= 2500:
        print(f'FAIL {f} p95={p95}ms'); sys.exit(1)
print('OK')
"
}
