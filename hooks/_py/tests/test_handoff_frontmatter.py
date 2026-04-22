"""Frontmatter build + parse roundtrip."""
from __future__ import annotations

from datetime import datetime, timezone

from hooks._py.handoff.frontmatter import (
    FrontmatterInput,
    build_frontmatter,
    parse_frontmatter,
)


def _sample() -> FrontmatterInput:
    return FrontmatterInput(
        run_id="20260421-a3f2",
        parent_run_id=None,
        stage="REVIEWING",
        substage="quality_gate_batch_2",
        mode="standard",
        autonomous=False,
        background=False,
        score=82,
        score_history=[45, 61, 74, 82],
        convergence_phase="perfection",
        convergence_counters={
            "total_iterations": 7,
            "phase_iterations": 3,
            "verify_fix_count": 1,
        },
        checkpoint_sha="7af9c3d",
        checkpoint_path=".forge/runs/20260421-a3f2/checkpoints/7af9c3d",
        branch_name="feat/FG-142-add-health",
        worktree_path=".forge/worktree",
        git_head="abd3d25a",
        commits_since_base=3,
        open_askuserquestion=None,
        previous_handoff=None,
        trigger_level="soft",
        trigger_reason="context_soft_50pct",
        trigger_threshold_pct=52,
        trigger_tokens=104000,
        created_at=datetime(2026, 4, 21, 14, 30, 22, tzinfo=timezone.utc),
    )


def test_schema_version_is_one():
    fm = build_frontmatter(_sample())
    assert fm.startswith("---\n")
    assert "schema_version: 1.0" in fm
    assert "handoff_version: 1.0" in fm
    assert fm.endswith("---\n")


def test_iso8601_created_at():
    fm = build_frontmatter(_sample())
    assert "created_at: 2026-04-21T14:30:22Z" in fm


def test_roundtrip_parse():
    fm = build_frontmatter(_sample())
    parsed = parse_frontmatter(fm)
    assert parsed.schema_version == "1.0"
    assert parsed.handoff_version == "1.0"
    assert parsed.run_id == "20260421-a3f2"
    assert parsed.stage == "REVIEWING"
    assert parsed.mode == "standard"
    assert parsed.autonomous is False
    assert parsed.score == 82
    assert parsed.score_history == [45, 61, 74, 82]
    assert parsed.checkpoint_sha == "7af9c3d"
    assert parsed.branch_name == "feat/FG-142-add-health"
    assert parsed.git_head == "abd3d25a"
    assert parsed.commits_since_base == 3
    assert parsed.trigger_level == "soft"
    assert parsed.trigger_reason == "context_soft_50pct"
    assert parsed.created_at == "2026-04-21T14:30:22Z"
    # raw is the full parsed mapping — spot-check a representative key
    assert parsed.raw.get("convergence_phase") == "perfection"


def test_parse_rejects_unknown_schema_version():
    fm = "---\nschema_version: 2.0\n---\n"
    import pytest
    with pytest.raises(ValueError, match="schema_version"):
        parse_frontmatter(fm)


def test_injection_in_string_field_is_safe():
    from hooks._py.handoff.frontmatter import parse_frontmatter
    s = _sample()
    # Attempt newline + closing marker injection via branch_name
    object.__setattr__(s, "branch_name", "evil\n---\ninjected: pwned")
    fm = build_frontmatter(s)
    parsed = parse_frontmatter(fm)
    # injected field did NOT become a real key
    assert "injected" not in parsed.raw


def test_build_is_deterministic():
    a = build_frontmatter(_sample())
    b = build_frontmatter(_sample())
    assert a == b


def test_roundtrip_with_empty_optionals():
    inp = _sample()
    # Reset every optional to None/empty
    for field_name in (
        "parent_run_id", "substage", "checkpoint_sha", "checkpoint_path",
        "branch_name", "worktree_path", "git_head",
        "open_askuserquestion", "previous_handoff",
        "trigger_threshold_pct", "trigger_tokens",
    ):
        object.__setattr__(inp, field_name, None)
    object.__setattr__(inp, "score_history", [])
    object.__setattr__(inp, "convergence_counters", {})
    fm = build_frontmatter(inp)
    parsed = parse_frontmatter(fm)
    assert parsed.run_id == "20260421-a3f2"
    assert parsed.score_history == []
    assert parsed.branch_name is None


def test_parse_handles_empty_body():
    import pytest
    # Missing schema_version in body → ValueError about schema, not about framing
    with pytest.raises(ValueError, match="schema_version"):
        parse_frontmatter("---\n---\n")


def test_convergence_phase_is_safe_wrapped():
    from hooks._py.handoff.frontmatter import parse_frontmatter
    s = _sample()
    object.__setattr__(s, "convergence_phase", "evil\n---\ninjected: pwned")
    fm = build_frontmatter(s)
    parsed = parse_frontmatter(fm)
    assert "injected" not in parsed.raw
