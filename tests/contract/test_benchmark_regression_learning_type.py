"""Phase 4 coordination: benchmark.regression must be registered in the learning-type allowlist."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def test_learning_type_documented_in_readme() -> None:
    readme = (ROOT / "shared" / "learnings" / "README.md").read_text()
    assert "benchmark.regression" in readme, "Phase 8 must document new learning type"


def test_registry_includes_benchmark_regression() -> None:
    """If the type registry is enumerated anywhere, it must include our new type."""
    # Phase 4 registry path (confirm-in-place when Phase 4 ships):
    registry_candidates = [
        ROOT / "shared" / "learnings" / "types.json",
        ROOT / "shared" / "checks" / "learning-types.json",
    ]
    for path in registry_candidates:
        if path.is_file():
            types = json.loads(path.read_text())
            if isinstance(types, list):
                assert "benchmark.regression" in types
            elif isinstance(types, dict):
                assert (
                    "benchmark.regression" in types.get("types", [])
                    or "benchmark.regression" in types
                )
            return
    # If no registry exists yet (Phase 4 not shipped), test is a noop (documented by README test above)
