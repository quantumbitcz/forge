"""Test fixtures shared across tests/unit/."""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def load_hyphenated_module(rel_path: str, name: str):
    """Load a module whose filename contains a hyphen (Python won't import via `from ...`)."""
    spec = importlib.util.spec_from_file_location(name, REPO_ROOT / rel_path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module
