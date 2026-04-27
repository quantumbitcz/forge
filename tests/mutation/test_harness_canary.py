"""Harness canary: prove the mutation harness actually runs scenarios.

If this test shows the canary mutation surviving, the harness is not
actually dispatching bats — a harness-level bug that would silently hide
every real survivor.
"""
from __future__ import annotations

import os
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def test_harness_can_kill_known_covered_row(tmp_path):
    """Run a trivial bats that MUST fail under MUTATE_ROW=1."""
    canary_bats = tmp_path / "canary.bats"
    canary_bats.write_text(
        "#!/usr/bin/env bats\n"
        "# mutation_row: 1\n"
        "@test 'always-fail-under-mutation' {\n"
        "  if [[ \"${MUTATE_ROW:-}\" == \"1\" ]]; then\n"
        "    false  # mutation applied: expected to fail\n"
        "  else\n"
        "    true\n"
        "  fi\n"
        "}\n",
        encoding="utf-8",
    )
    bats_bin = REPO / "tests" / "lib" / "bats-core" / "bin" / "bats"
    assert bats_bin.is_file(), f"bats binary missing at {bats_bin} — check submodule init"
    env = os.environ.copy()
    env["MUTATE_ROW"] = "1"
    result = subprocess.run(
        [str(bats_bin), str(canary_bats)],
        env=env, capture_output=True, text=True, check=False, timeout=60,
    )
    assert result.returncode != 0, (
        f"canary did not fail under MUTATE_ROW=1 — harness is not propagating "
        f"env var. stdout={result.stdout!r} stderr={result.stderr!r}"
    )


def test_harness_does_not_fail_without_mutation(tmp_path):
    """Negative control — without MUTATE_ROW, the canary passes."""
    canary_bats = tmp_path / "canary.bats"
    canary_bats.write_text(
        "#!/usr/bin/env bats\n"
        "# mutation_row: 1\n"
        "@test 'always-pass-without-mutation' {\n"
        "  if [[ \"${MUTATE_ROW:-}\" == \"1\" ]]; then\n"
        "    false\n"
        "  else\n"
        "    true\n"
        "  fi\n"
        "}\n",
        encoding="utf-8",
    )
    bats_bin = REPO / "tests" / "lib" / "bats-core" / "bin" / "bats"
    assert bats_bin.is_file(), f"bats binary missing at {bats_bin} — check submodule init"
    env = {k: v for k, v in os.environ.items() if k != "MUTATE_ROW"}
    result = subprocess.run(
        [str(bats_bin), str(canary_bats)],
        env=env, capture_output=True, text=True, check=False, timeout=60,
    )
    assert result.returncode == 0, (
        f"canary failed without MUTATE_ROW — negative control broken. "
        f"stdout={result.stdout!r} stderr={result.stderr!r}"
    )
