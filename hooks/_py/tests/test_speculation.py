import tempfile
from pathlib import Path

from hooks._py.speculation import (
    check_diversity,
    compute_selection_score,
    derive_seed,
    detect_ambiguity,
    estimate_cost,
    persist_candidate,
    pick_winner,
)


def test_high_confidence_never_triggers():
    r = detect_ambiguity("either REST or GraphQL approach works well here please", "HIGH", 3, 1, 0.45)
    assert r["triggered"] is False


def test_low_confidence_never_triggers():
    r = detect_ambiguity("either REST or GraphQL approach works well here please", "LOW", 3, 1, 0.45)
    assert r["triggered"] is False


def test_cache_hit_above_threshold_suppresses():
    r = detect_ambiguity("consider either approach please for this requirement here", "MEDIUM", 0, 0, 0.72)
    assert r["triggered"] is False
    assert "plan_cache_hit>=0.60" in r["reasons"]


def test_shaper_elevated_first():
    r = detect_ambiguity(
        "consider either a REST or a GraphQL flavored API design with paged responses for the new service surface",
        "MEDIUM",
        shaper_alternatives=2,
        shaper_delta=3,
        plan_cache_sim=0.45,
    )
    assert r["triggered"] is True
    assert r["reasons"][0] == "shaper_alternatives>=2"


def test_keyword_only_triggers():
    r = detect_ambiguity(
        "we could consider multiple approaches for storing user preferences data including encrypted blobs and structured rows",
        "MEDIUM",
        0,
        0,
        0.0,
    )
    assert r["triggered"] is True
    assert "keyword_hit" in r["reasons"]
    assert "shaper_alternatives>=2" not in r["reasons"]


def test_short_requirement_suppresses():
    r = detect_ambiguity("add auth", "MEDIUM", 2, 2, 0.0)
    assert r["triggered"] is False
    assert "requirement_too_short" in r["reasons"]


def test_derive_seed_determinism():
    assert derive_seed("r1", "cand-1") == derive_seed("r1", "cand-1")


def test_derive_seed_varies():
    assert derive_seed("r1", "cand-1") != derive_seed("r1", "cand-2")


def test_derive_seed_int32_safe():
    s = derive_seed("long-run-id-xyz", "candidate-42")
    assert 0 <= s < 2 ** 31


def test_estimate_cost_cold_start():
    r = estimate_cost(baseline=4000, n=3, ceiling=2.5, recent_tokens=[])
    assert r["per_candidate_mean"] == 4500
    assert r["estimated"] == 4000 + 4500 * 3
    assert r["abort"] is True


def test_estimate_cost_under_ceiling():
    r = estimate_cost(baseline=4000, n=2, ceiling=2.5, recent_tokens=[2800])
    assert r["estimated"] == 4000 + 2800 * 2
    assert r["abort"] is False


def test_estimate_cost_window_caps_at_10():
    tokens = [9999] * 5 + [3000] * 5
    r = estimate_cost(baseline=4000, n=3, ceiling=2.5, recent_tokens=tokens)
    assert r["window_used"] == 10


def test_estimate_cost_with_history_uses_mean():
    tokens = [3000, 3200, 3100, 3050, 3150, 3100, 3000, 3100, 3100, 3200]
    r = estimate_cost(baseline=4000, n=3, ceiling=2.5, recent_tokens=tokens)
    assert r["window_used"] == 10
    # mean is 3100 (sum=31000, //10 = 3100); estimated = 4000 + 3100*3 = 13300
    assert r["per_candidate_mean"] == 3100
    assert r["estimated"] == 13300


def test_diversity_identical_plans():
    r = check_diversity(["alpha beta gamma delta"] * 2, min_diversity_score=0.15)
    assert r["degraded"] is True
    assert r["diversity"] == 0.0


def test_diversity_distinct_plans():
    r = check_diversity(
        ["alpha beta gamma delta", "epsilon zeta eta theta"],
        min_diversity_score=0.15,
    )
    assert r["degraded"] is False


def test_diversity_three_plans_max_overlap_dominates():
    r = check_diversity(
        [
            "alpha beta gamma delta",
            "alpha beta gamma delta",
            "entirely different plan corpus",
        ],
        min_diversity_score=0.15,
    )
    # identical pair drives max overlap to 1.0 -> diversity 0.0 -> degraded
    assert r["degraded"] is True
    assert r["diversity"] == 0.0


def test_diversity_threshold_configurable():
    # Share one token ("shared") so diversity is strictly < 1.0, then 0.99 threshold rejects.
    r = check_diversity(
        ["alpha beta gamma shared", "epsilon zeta eta shared"],
        min_diversity_score=0.99,
    )
    assert r["degraded"] is True


def test_diversity_single_plan_returns_ok():
    r = check_diversity(["alpha beta gamma"], min_diversity_score=0.15)
    assert r["degraded"] is False
    assert r["diversity"] == 1.0


def test_no_go_is_eliminated():
    r = compute_selection_score(80, "NO-GO", 1000, 1000)
    assert r["eliminated"] is True
    assert r["selection_score"] is None


def test_revise_penalty():
    r = compute_selection_score(80, "REVISE", 1000, 1000)
    assert r["selection_score"] == 65.0


def test_efficiency_tiebreaker():
    r = compute_selection_score(80, "GO", 500, 1000)
    assert r["selection_score"] == 85.0


def test_no_efficiency_advantage_matches_validator():
    r = compute_selection_score(80, "GO", 1000, 1000)
    assert r["selection_score"] == 80.0


def test_pick_winner_decisive():
    cands = [
        {"id": "cand-1", "validator_score": 85, "verdict": "GO", "tokens": 4000},
        {"id": "cand-2", "validator_score": 75, "verdict": "GO", "tokens": 4000},
    ]
    r = pick_winner(cands, auto_pick_threshold_delta=5, mode="interactive")
    assert r["winner_id"] == "cand-1"
    assert r["needs_confirmation"] is False


def test_pick_winner_tie_interactive():
    cands = [
        {"id": "cand-1", "validator_score": 85, "verdict": "GO", "tokens": 4000},
        {"id": "cand-2", "validator_score": 82, "verdict": "GO", "tokens": 4000},
    ]
    r = pick_winner(cands, auto_pick_threshold_delta=5, mode="interactive")
    assert r["needs_confirmation"] is True


def test_pick_winner_tie_autonomous():
    cands = [
        {"id": "cand-1", "validator_score": 85, "verdict": "GO", "tokens": 4000},
        {"id": "cand-2", "validator_score": 82, "verdict": "GO", "tokens": 4000},
    ]
    r = pick_winner(cands, auto_pick_threshold_delta=5, mode="autonomous")
    assert r["needs_confirmation"] is False
    assert r["winner_id"] == "cand-1"


def test_pick_winner_all_no_go():
    cands = [{"id": "c", "validator_score": 40, "verdict": "NO-GO", "tokens": 100}]
    r = pick_winner(cands, 5, "autonomous")
    assert r["winner_id"] is None
    assert r["escalate"] == "all_no_go"


def test_pick_winner_all_below_60():
    cands = [
        {"id": "cand-1", "validator_score": 55, "verdict": "GO", "tokens": 4000},
        {"id": "cand-2", "validator_score": 50, "verdict": "GO", "tokens": 4000},
    ]
    r = pick_winner(cands, 5, "autonomous")
    assert r["winner_id"] is None
    assert r["escalate"] == "all_below_60"


def _cand(run_id: str, cand_id: str = "cand-1") -> dict:
    seq = int(run_id.split("-")[-1])
    return {
        "run_id": run_id,
        "candidate_id": cand_id,
        "emphasis_axis": "a",
        "exploration_seed": 1,
        "plan_hash": "h",
        "plan_content": "x",
        "validator_verdict": "GO",
        "validator_score": 80,
        "selection_score": 80.0,
        "selected": False,
        "tokens": {"planner": 100, "validator": 50},
        "created_at": f"2026-04-19T12:00:{seq:02d}Z",
    }


def test_persist_writes_file_and_index():
    with tempfile.TemporaryDirectory() as d:
        persist_candidate(d, "run-1", _cand("run-1"))
        assert (Path(d) / "plans/candidates/run-1/cand-1.json").exists()
        assert (Path(d) / "plans/candidates/index.json").exists()


def test_fifo_eviction_at_21st_run():
    with tempfile.TemporaryDirectory() as d:
        for i in range(1, 23):
            persist_candidate(d, f"run-{i}", _cand(f"run-{i}"))
        assert not (Path(d) / "plans/candidates/run-1").exists()
        assert not (Path(d) / "plans/candidates/run-2").exists()
        assert (Path(d) / "plans/candidates/run-3").exists()
        assert (Path(d) / "plans/candidates/run-22").exists()
