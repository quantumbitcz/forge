from hooks._py.speculation import detect_ambiguity


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
