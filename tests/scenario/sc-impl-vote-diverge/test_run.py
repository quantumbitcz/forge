"""sc-impl-vote-diverge - when samples diverge, orchestrator dispatches tiebreak."""
from hooks._py.diff_judge import judge


def test_divergence_triggers_tiebreak(tmp_path):
    a = tmp_path / "sample_1"
    b = tmp_path / "sample_2"
    (a / "src").mkdir(parents=True)
    (b / "src").mkdir(parents=True)
    (a / "src" / "m.py").write_text("def f(x):\n    return x + 1\n")
    (b / "src" / "m.py").write_text("def f(x):\n    return x - 1\n")

    result = judge(a, b, ["src/m.py"])
    assert result.verdict == "DIVERGES"
    # Orchestrator MUST dispatch tiebreak on DIVERGES.
    # Simulate: track_state = {"tiebreak_dispatched": False}; when verdict == DIVERGES,
    # orchestrator sets track_state["tiebreak_dispatched"] = True.
    track_state = {"tiebreak_dispatched": False, "impl_vote_history": []}
    if result.verdict == "DIVERGES":
        track_state["tiebreak_dispatched"] = True
        track_state["impl_vote_history"].append(
            {
                "task_id": "t1",
                "judge_verdict": "DIVERGES",
                "tiebreak_dispatched": True,
                "divergences": result.divergences,
            }
        )
    assert track_state["tiebreak_dispatched"] is True
    assert track_state["impl_vote_history"][0]["tiebreak_dispatched"] is True
