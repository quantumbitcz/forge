#!/usr/bin/env bash
# consistency-eval.sh — runs the labeled datasets through hooks/_py/consistency.py
# and emits evals/pipeline/results/consistency-{decision}.json for CI assertions.
#
# Invoked by:
#   - .github/workflows/eval.yml (CI)
#   - manually: ./evals/pipeline/consistency-eval.sh [--live|--offline]
#
# Default is --offline (uses a deterministic stub sampler). CI uses --offline as
# well today; --live degrades to offline until a live sampler is wired
# (follow-up — see shared/consistency/voting.md §1.1).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RESULTS_DIR="${REPO_ROOT}/evals/pipeline/results"
DATASET_DIR="${REPO_ROOT}/tests/consistency/datasets"

mkdir -p "${RESULTS_DIR}"

MODE="${1:---offline}"

run_one() {
  local decision="$1"
  local dataset="$2"
  local out="${RESULTS_DIR}/consistency-${decision}.json"
  echo "=== Running ${decision} (${MODE}) ==="
  python3 - "$decision" "$dataset" "$out" "$MODE" "$REPO_ROOT" <<'PY'
import json, pathlib, sys, time, hashlib, asyncio, random
decision, dataset_path, out_path, mode, repo_root = sys.argv[1:6]
sys.path.insert(0, repo_root)
from hooks._py import consistency as C

labels_map = {
    "shaper_intent": ["bugfix","migration","bootstrap","multi-feature","vague",
                      "testing","documentation","refactor","performance","single-feature"],
    "validator_verdict": ["GO","REVISE","NO-GO"],
    "pr_rejection_classification": ["design","implementation","other"],
}
labels = labels_map[decision]

with open(dataset_path) as fh:
    items = [json.loads(l) for l in fh if l.strip()]

def render_prompt(rec):
    if decision == "shaper_intent":
        return rec["prompt"]
    if decision == "validator_verdict":
        return "FINDINGS:\n" + "\n".join(
            f"- {f['category']} [{f['severity']}] {f['summary']}" for f in rec["findings"]
        )
    return rec["comment"]

# ---- Decision-aware deterministic offline samplers ----
# Each sampler maps a prompt to a label using a small heuristic that mirrors the
# real classifier's high-signal cues. Adversarial inputs are intentionally
# constructed to be ambiguous, so the sampler injects disagreement on those.

INTENT_KEYWORDS = {
    "bugfix": ["fix","bug","crash","broken","regression","null","nullpointer","exception","error","404","500","stack trace"],
    "migration": ["migrate","upgrade","move from","switch","replace","transition","update node","update spring"],
    "bootstrap": ["bootstrap","scaffold","new project","new microservice","initialize","create new","start from scratch","greenfield","new typescript","new go","new fastapi","new vue","new rust"],
    "multi-feature": ["1.","2.","3.",", and ","plus","also add","on top of","subsystems","auth, billing","auth and billing"],
    "vague": ["maybe","could we","what if","something like","explore options","think about","probably"],
    "testing": ["add tests","test coverage","integration tests","unit tests","e2e tests","property-based tests","jest tests","write integration","write unit"],
    "documentation": ["adr","openapi","document","write docs","readme","changelog","architecture docs","runbook"],
    "refactor": ["refactor","extract","reduce duplication","consolidate","clean up technical debt","clean up","restructure"],
    "performance": ["optimize","reduce bundle","reduce memory","n+1","latency","slow query","cache the","under 100ms","under 200ms","p95","p99","faster"],
}

VERDICT_RULES = [
    ("NO-GO", ["CRITICAL"]),
    ("REVISE", ["WARNING"]),
    ("GO", ["INFO"]),
]

PR_KEYWORDS = {
    "design":         ["microservice","bounded context","domain event","cqrs","abstraction","architecture","port","adapter","aggregate","cyclic","split it","schema should","strategy pattern","api contract","use-case layer","event-sourcing","crud","public api","dto","internal model","responsibility belongs","schema","contract is wrong","layer instead","crud for","domain"],
    "implementation": ["null-check","index should","async/await","blocking io","return 404","cache key","reuse","magic number","badrequest","userrepository","httpclient","stream + reduce","close()","validate input","auth check","role-based","wrong layer","move it","use case","for-loop","stream","optional"],
    "other":          ["nit:","docstring","rebase","squash","blank line","screenshot","whitespace","changelog entry","ticket","template","squash these"],
}

def offline_pick_label(prompt: str, labels, rng):
    p = prompt.lower()
    if decision == "shaper_intent":
        # Score each label by keyword hits; pick max, break ties first-seen.
        best_lab, best_score = None, 0
        for lab in labels:
            kws = INTENT_KEYWORDS.get(lab, [])
            score = sum(1 for kw in kws if kw in p)
            if score > best_score:
                best_lab, best_score = lab, score
        if best_lab is None:
            best_lab = "single-feature"
        return best_lab, 0.85
    if decision == "validator_verdict":
        # Verdict is driven by highest severity present.
        for verdict, severities in VERDICT_RULES:
            for sev in severities:
                if f"[{sev}]" in prompt:
                    return verdict, 0.85
        return "GO", 0.85
    # pr_rejection_classification
    best_lab, best_score = None, 0
    for lab in labels:
        kws = PR_KEYWORDS.get(lab, [])
        score = sum(1 for kw in kws if kw in p)
        if score > best_score:
            best_lab, best_score = lab, score
    if best_lab is None:
        best_lab = "other"
    return best_lab, 0.85

def make_sampler(difficulty: str):
    """Build a per-item sampler closure parameterised by the gold difficulty.

    The eval harness owns ground-truth difficulty (from the dataset). A real
    Claude sampler would arrive at the same disagreement by reasoning. Here we
    bake difficulty into the closure so the deterministic stub mirrors the
    expected real-world per-item entropy: easy => high agreement & confidence,
    adversarial => lower confidence + frequent inter-sample drift.
    """
    async def sampler(prompt, labels, tier, seed):
        rng = random.Random(hashlib.sha256(f"{prompt}|{seed}|{difficulty}".encode()).digest())
        chosen, conf_base = offline_pick_label(prompt, labels, rng)
        if difficulty == "adversarial":
            # ~70% per-sample drift to a random label, plus low confidence so
            # mean(winning group) < min_consensus_confidence (0.5) frequently.
            if rng.random() < 0.70:
                chosen = labels[rng.randrange(len(labels))]
            conf_base = 0.40
        else:
            # Easy: ~25% per-sample drift. Most majorities still hold (3 samples,
            # >=2 agree most of the time), giving voting a measurable lift over
            # any single random sample.
            if rng.random() < 0.25:
                chosen = labels[rng.randrange(len(labels))]
                conf_base = 0.55
        conf = max(0.0, min(1.0, conf_base + rng.uniform(-0.1, 0.1)))
        return {"label": chosen, "confidence": conf}
    return sampler

# Live sampler stub: CI wires this to the Claude SDK in a later PR. For now,
# the "live" mode degrades to offline.
def make_live_sampler(difficulty: str):
    return make_sampler(difficulty)

results = []
start = time.time()
for rec in items:
    prompt = render_prompt(rec)
    difficulty = rec.get("difficulty", "easy")
    sampler = make_sampler(difficulty) if mode == "--offline" else make_live_sampler(difficulty)
    t0 = time.time()
    try:
        vr = asyncio.run(C.vote_async(
            decision_point=decision, prompt=prompt, labels=labels,
            state_mode="eval", n=3, tier="fast",
            cache_enabled=False,
            sampler=sampler,
        ))
        elapsed_ms = int((time.time() - t0) * 1000)
        # Pull a single-sample baseline (seed=0) for accuracy-lift comparison.
        async def _one():
            return await sampler(prompt, labels, "fast", 0)
        s = asyncio.run(_one())
        single = s["label"]
        results.append({
            "id": rec["id"],
            "gold": rec["label"],
            "voted": vr.label,
            "single": single,
            "confidence": vr.confidence,
            "low_consensus": vr.low_consensus,
            "difficulty": rec.get("difficulty", "easy"),
            "elapsed_ms": elapsed_ms,
        })
    except C.ConsistencyError:
        results.append({
            "id": rec["id"], "gold": rec["label"], "voted": None,
            "single": None, "confidence": 0.0, "low_consensus": True,
            "difficulty": rec.get("difficulty", "easy"),
            "elapsed_ms": int((time.time() - t0) * 1000),
            "error": "ConsistencyError",
        })

total_ms = int((time.time() - start) * 1000)
out = {
    "decision": decision, "mode": mode, "total_ms": total_ms,
    "n_items": len(items), "results": results,
}
pathlib.Path(out_path).write_text(json.dumps(out, indent=2))
print(f"wrote {out_path} ({len(items)} items, {total_ms} ms)")
PY
}

run_one "shaper_intent" "${DATASET_DIR}/shaper_intent.jsonl"
run_one "validator_verdict" "${DATASET_DIR}/validator_verdict.jsonl"
run_one "pr_rejection_classification" "${DATASET_DIR}/pr_rejection.jsonl"

echo "=== consistency-eval done ==="
