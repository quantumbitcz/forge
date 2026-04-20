from hooks._py.speculation import (
    derive_seed,
    detect_ambiguity,
    estimate_cost,
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
