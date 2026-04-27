"""Marker-protocol parser tests. Phase 4 §3.1."""
from __future__ import annotations

from hooks._py.learnings_markers import parse_markers


def test_applied_marker():
    text = "Some notes.\nLEARNING_APPLIED: spring-tx-scope-leak\nMore."
    out = parse_markers(text)
    assert out == [("applied", "spring-tx-scope-leak", None)]


def test_fp_marker_with_reason():
    text = "LEARNING_FP: r2dbc-col-update reason=applies only to R2DBC"
    out = parse_markers(text)
    assert out == [("fp", "r2dbc-col-update", "applies only to R2DBC")]


def test_vindicated_marker():
    text = "LEARNING_VINDICATED: foo reason=user correction"
    out = parse_markers(text)
    assert out == [("vindicated", "foo", "user correction")]


def test_preempt_skipped_treated_as_fp_when_has_reason():
    text = "PREEMPT_SKIPPED: foo reason=not relevant in this task"
    out = parse_markers(text)
    assert out == [("fp", "foo", "not relevant in this task")]


def test_preempt_applied_treated_as_applied():
    text = "PREEMPT_APPLIED: foo"
    out = parse_markers(text)
    assert out == [("applied", "foo", None)]


def test_multiple_markers_in_order():
    text = (
        "LEARNING_APPLIED: a\n"
        "LEARNING_FP: b reason=nope\n"
        "LEARNING_APPLIED: c\n"
    )
    out = parse_markers(text)
    assert [kind for kind, _, _ in out] == ["applied", "fp", "applied"]


def test_no_markers_returns_empty():
    assert parse_markers("just prose") == []
