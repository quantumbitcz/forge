"""Live-run helper seeds .forge/specs/index.json per Phase 7 injection contract."""
from __future__ import annotations
import json
from pathlib import Path
from unittest.mock import patch
from tests.evals.benchmark.discovery import CorpusEntry
from tests.evals.benchmark.live_run import _write_spec_injection, _parse_state


def test_spec_injection_uses_B_namespace(tmp_path: Path) -> None:
    entry = CorpusEntry(
        entry_id="2026-01-01-demo",
        path=tmp_path / "src",
        requirement="# Requirement\nBuild X.\n",
        ac_list=[
            {"id": "AC-B001", "description": "endpoint", "verifiable_via": "http"},
            {"id": "AC-B002", "description": "response shape", "verifiable_via": "http"},
        ],
        expected={}, metadata={"complexity": "S", "requires_docker": False},
    )
    target = tmp_path / "project"
    (target / ".forge" / "specs").mkdir(parents=True)
    _write_spec_injection(target, entry)
    doc = json.loads((target / ".forge" / "specs" / "index.json").read_text())
    assert doc["active_spec_id"] == "2026-01-01-demo"
    ids = [ac["id"] for ac in doc["specs"]["2026-01-01-demo"]["acceptance_criteria"]]
    assert all(i.startswith("AC-B") for i in ids)
    assert doc["specs"]["2026-01-01-demo"]["source"] == "benchmark-injected"


def test_parse_state_computes_partial_ac_pct(tmp_path: Path) -> None:
    state_path = tmp_path / ".forge" / "state.json"
    state_path.parent.mkdir(parents=True)
    state_path.write_text(json.dumps({
        "pipeline_verdict": "SHIP",
        "score": 90,
        "cost": {"estimated_cost_usd": 0.42},
        "intent_verification_results": [
            {"ac_id": "AC-B001", "status": "PASS"},
            {"ac_id": "AC-B002", "status": "FAIL"},
            {"ac_id": "AC-B003", "status": "UNVERIFIABLE"},
        ],
        "tokens": {"total": 12345},
    }))
    parsed = _parse_state(tmp_path)
    assert parsed["ac_breakdown"] == {"AC-B001": "PASS", "AC-B002": "FAIL", "AC-B003": "UNVERIFIABLE"}
    assert abs(parsed["partial_ac_pct"] - (1/3)) < 1e-9
    assert parsed["unverifiable_count"] == 1
    assert parsed["pipeline_verdict"] == "SHIP"
    assert parsed["cost_usd"] == 0.42
