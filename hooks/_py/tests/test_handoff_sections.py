"""Body section renderers — pure functions over structured inputs."""
from __future__ import annotations

from hooks._py.handoff.sections import (
    SectionInputs,
    render_acceptance_criteria,
    render_active_findings,
    render_convergence_trajectory,
    render_critical_files,
    render_do_not_touch,
    render_goal,
    render_key_decisions,
    render_next_action,
    render_open_questions,
    render_progress,
    render_user_directive,
)


def _inputs() -> SectionInputs:
    return SectionInputs(
        requirement="Add a /health endpoint returning JSON status",
        completed_acs=[{"id": "AC-001", "text": "GET /health returns 200"}],
        implemented_files=["src/routes/health.py"],
        test_status={"passed": 12, "failed": 0, "skipped": 1},
        active_findings=[
            {"file": "src/routes/health.py", "line": 14, "category": "DOC-MISSING", "severity": "WARNING", "message": "missing docstring"},
        ],
        acceptance_criteria=[
            {"id": "AC-001", "status": "PASS", "evidence": "test_health_ok passes"},
            {"id": "AC-002", "status": "PENDING", "evidence": None},
        ],
        decisions=[
            {"ts": "2026-04-21T14:20:00Z", "decision": "Use FastAPI JSONResponse", "rationale": "consistency with /status"},
        ],
        preempt_items=[{"text": "Do not modify auth middleware", "confidence": "HIGH"}],
        user_dont_statements=["don't add rate limiting — out of scope"],
        next_action_description="Re-run quality gate batch 2 after fixing DOC-MISSING",
        convergence_trajectory=[
            {"iteration": 1, "score": 45, "findings": 8},
            {"iteration": 2, "score": 61, "findings": 5},
        ],
        critical_files=["src/routes/health.py", "tests/routes/test_health.py"],
        open_questions=[],
    )


def test_goal_renders_as_paragraph():
    out = render_goal(_inputs(), variant="full")
    assert "## Goal" in out
    assert "Add a /health endpoint returning JSON status" in out


def test_active_findings_sorted_by_severity():
    inp = _inputs()
    inp.active_findings = [
        {"file": "a.py", "line": 1, "category": "X", "severity": "INFO", "message": "info item"},
        {"file": "b.py", "line": 1, "category": "Y", "severity": "CRITICAL", "message": "crit item"},
        {"file": "c.py", "line": 1, "category": "Z", "severity": "WARNING", "message": "warn item"},
    ]
    out = render_active_findings(inp, variant="full")
    crit_pos = out.index("crit item")
    warn_pos = out.index("warn item")
    info_pos = out.index("info item")
    assert crit_pos < warn_pos < info_pos


def test_active_findings_light_top_five():
    inp = _inputs()
    inp.active_findings = [
        {"file": f"f{i}.py", "line": i, "category": "X", "severity": "WARNING", "message": f"m{i}"}
        for i in range(10)
    ]
    out = render_active_findings(inp, variant="light")
    bullet_lines = [line for line in out.splitlines() if line.startswith("- ")]
    assert len(bullet_lines) == 5


def test_do_not_touch_merges_preempt_and_user():
    out = render_do_not_touch(_inputs(), variant="full")
    assert "Do not modify auth middleware" in out
    assert "don't add rate limiting" in out


def test_acceptance_criteria_table_full_only():
    out_full = render_acceptance_criteria(_inputs(), variant="full")
    assert "AC-001" in out_full and "PASS" in out_full
    out_light = render_acceptance_criteria(_inputs(), variant="light")
    assert out_light == ""  # omitted in light variant


def test_user_directive_placeholder_present():
    out = render_user_directive(_inputs(), variant="light")
    assert "## User Directive" in out
    assert "_(empty — fill in before paste)_" in out


def test_next_action_never_truncated():
    inp = _inputs()
    inp.next_action_description = "x" * 10000
    out = render_next_action(inp, variant="light")
    assert out.endswith("x\n") or out.endswith("x")
