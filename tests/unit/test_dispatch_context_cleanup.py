"""Unit test: state-integrity.sh references .forge/dispatch-contexts/ lifecycle."""
from __future__ import annotations

from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent.parent
SCRIPT = (REPO_ROOT / "shared" / "state-integrity.sh").read_text()


def test_dispatch_contexts_in_cleanup_list():
    assert ".forge/dispatch-contexts" in SCRIPT or "dispatch-contexts" in SCRIPT
