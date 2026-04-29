"""sc-retrospective-intent-metrics - fg-700 renders intent_verification and impl_voting sections."""


def render_retrospective(state: dict) -> str:
    """Re-implement the section 2j renderer minimally for scenario coverage."""
    results = state.get("intent_verification_results", [])
    history = state.get("impl_vote_history", [])
    total = len(results)
    verified = sum(1 for r in results if r["verdict"] == "VERIFIED")
    partial = sum(1 for r in results if r["verdict"] == "PARTIAL")
    missed = sum(1 for r in results if r["verdict"] == "MISSED")
    unverif = sum(1 for r in results if r["verdict"] == "UNVERIFIABLE")
    verified_pct = (verified / total * 100) if total else 0
    unverifiable_pct = (unverif / total * 100) if total else 0

    dispatches = sum(1 for h in history if not h.get("skipped_reason"))
    diverged = sum(1 for h in history if h.get("judge_verdict") == "DIVERGES")
    cost_skipped = sum(1 for h in history if h.get("skipped_reason") == "cost")

    return f"""
intent_verification:
  total_acs: {total}
  verified: {verified}
  partial: {partial}
  missed: {missed}
  unverifiable: {unverif}
  verified_pct: {verified_pct:.2f}
  unverifiable_pct: {unverifiable_pct:.2f}

impl_voting:
  dispatches: {dispatches}
  diverged: {diverged}
  cost_skipped: {cost_skipped}
  divergence_rate: {(diverged / dispatches * 100) if dispatches else 0:.2f}
""".strip()


def test_renders_both_sections():
    state = {
        "intent_verification_results": [
            {"ac_id": "AC-001", "verdict": "VERIFIED"},
            {"ac_id": "AC-002", "verdict": "MISSED"},
            {"ac_id": "AC-003", "verdict": "UNVERIFIABLE"},
        ],
        "impl_vote_history": [
            {"task_id": "t1", "judge_verdict": "SAME", "skipped_reason": None},
            {"task_id": "t2", "judge_verdict": "DIVERGES", "skipped_reason": None},
            {"task_id": "t3", "skipped_reason": "cost"},
        ],
    }
    out = render_retrospective(state)
    assert "total_acs: 3" in out
    assert "verified: 1" in out
    assert "missed: 1" in out
    assert "unverifiable: 1" in out
    assert "verified_pct: 33.33" in out
    assert "unverifiable_pct: 33.33" in out
    assert "dispatches: 2" in out
    assert "diverged: 1" in out
    assert "cost_skipped: 1" in out
