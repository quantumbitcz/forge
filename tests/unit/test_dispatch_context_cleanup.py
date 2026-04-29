"""Unit test: orchestrator PREFLIGHT cleans .forge/dispatch-contexts/.

Phase 7 dispatch contexts are ephemeral (per state-schema.md). The orchestrator
PREFLIGHT prose MUST instruct destructive cleanup (rm -rf or shutil.rmtree).
state-integrity.sh keeps a stale-detection block as defense-in-depth.
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).parent.parent.parent


def test_orchestrator_preflight_cleans_dispatch_contexts():
    """Orchestrator PREFLIGHT prose must instruct removal of .forge/dispatch-contexts/."""
    text = (ROOT / "agents" / "fg-100-orchestrator.md").read_text(encoding="utf-8")
    # Look for an explicit destructive cleanup directive (rm -rf or shutil.rmtree)
    # alongside the dispatch-contexts path in the PREFLIGHT context.
    assert re.search(
        r"(rm\s+-rf|shutil\.rmtree).{0,80}dispatch-contexts",
        text,
        re.DOTALL,
    ), "orchestrator must instruct destructive cleanup of .forge/dispatch-contexts/"


def test_state_integrity_still_detects_stale():
    """state-integrity.sh keeps stale-detection block as a defense-in-depth."""
    text = (ROOT / "shared" / "state-integrity.sh").read_text(encoding="utf-8")
    assert "dispatch-contexts" in text
