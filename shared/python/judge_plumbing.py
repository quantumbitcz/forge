"""Judge verdict / loop-counter plumbing for fg-205 and fg-301."""
from __future__ import annotations

PLAN_JUDGE_BOUND = 2
IMPL_JUDGE_BOUND = 2

PLAN_JUDGE_VERDICTS = ("PROCEED", "REVISE", "ESCALATE")
IMPL_JUDGE_VERDICTS = ("PROCEED", "REVISE")


def record_plan_judge_verdict(state: dict, verdict: str, dispatch_seq: int, timestamp: str) -> dict:
    if verdict not in PLAN_JUDGE_VERDICTS:
        raise ValueError(
            f"invalid plan judge verdict: {verdict!r} (expected one of {PLAN_JUDGE_VERDICTS})"
        )
    state.setdefault("plan_judge_loops", 0)
    state.setdefault("judge_verdicts", [])
    state["judge_verdicts"].append({
        "judge_id": "fg-205-plan-judge",
        "verdict": verdict,
        "dispatch_seq": dispatch_seq,
        "timestamp": timestamp,
    })
    if verdict == "REVISE":
        state["plan_judge_loops"] += 1
    return state


def plan_judge_bound_reached(state: dict) -> bool:
    return state.get("plan_judge_loops", 0) >= PLAN_JUDGE_BOUND


def reset_plan_judge_loops_on_new_plan(state: dict, new_plan_sha: str) -> dict:
    if state.get("current_plan_sha") != new_plan_sha:
        state["plan_judge_loops"] = 0
        state["current_plan_sha"] = new_plan_sha
    return state


def record_impl_judge_verdict(state: dict, task_id: str, verdict: str, dispatch_seq: int, timestamp: str) -> dict:
    if verdict not in IMPL_JUDGE_VERDICTS:
        raise ValueError(
            f"invalid impl judge verdict: {verdict!r} (expected one of {IMPL_JUDGE_VERDICTS})"
        )
    state.setdefault("impl_judge_loops", {})
    state.setdefault("judge_verdicts", [])
    state["impl_judge_loops"].setdefault(task_id, 0)
    state["judge_verdicts"].append({
        "judge_id": "fg-301-implementer-judge",
        "verdict": verdict,
        "dispatch_seq": dispatch_seq,
        "timestamp": timestamp,
        "task_id": task_id,
    })
    if verdict == "REVISE":
        state["impl_judge_loops"][task_id] += 1
    return state


def impl_judge_bound_reached(state: dict, task_id: str) -> bool:
    return state.get("impl_judge_loops", {}).get(task_id, 0) >= IMPL_JUDGE_BOUND
