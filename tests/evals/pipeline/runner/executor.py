"""Per-scenario execution: isolate worktree, invoke forge, capture state.json.

Contract:
    1. Create a temp directory.
    2. If ``fixtures/starter.tar.gz`` exists in the scenario dir, extract it;
       otherwise ``git init`` an empty repo.
    3. Symlink the current forge checkout into ``.claude/plugins/forge``.
    4. Run ``/forge`` non-interactively to seed config.
    5. Set ``FORGE_EVAL=1`` and run ``/forge run --eval-mode <id>``.
    6. Parse ``.forge/state.json`` post-run.
    7. Return raw metrics (tokens, elapsed, score, verdict, touched files).

No scoring here — scoring lives in scoring.py.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import tarfile
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from tests.evals.pipeline.runner.schema import Scenario


@dataclass
class RawRunMetrics:
    """Raw output of one forge invocation; consumed by scoring module."""

    scenario_id: str
    started_at: str
    ended_at: str
    elapsed_seconds: int
    tokens: int
    pipeline_score: float
    verdict: str
    touched_files_actual: list[str]
    must_not_touch_violations: list[str]
    timed_out: bool
    error: Optional[str]


def _iso_now() -> str:
    import datetime as _dt
    return _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _extract_starter(scenario_dir: Path, target: Path) -> None:
    starter = scenario_dir / "fixtures" / "starter.tar.gz"
    if starter.is_file():
        with tarfile.open(starter, "r:gz") as tf:
            tf.extractall(target)
    else:
        subprocess.run(["git", "init", "-q"], cwd=target, check=True)


def _symlink_plugin(forge_root: Path, target: Path) -> None:
    plugin_dir = target / ".claude" / "plugins"
    plugin_dir.mkdir(parents=True, exist_ok=True)
    (plugin_dir / "forge").symlink_to(forge_root, target_is_directory=True)


def _run_forge_init(target: Path) -> None:
    # Non-interactive: rely on FORGE_EVAL=1 to skip prompts.
    env = {**os.environ, "FORGE_EVAL": "1"}
    subprocess.run(
        ["claude", "code", "--non-interactive", "/forge"],
        cwd=target,
        env=env,
        check=True,
        timeout=180,
    )


def _run_forge_with_eval_mode(
    *,
    scenario: Scenario,
    target: Path,
    dry_run: bool,
    scenario_timeout_seconds: int,
) -> tuple[bool, Optional[str]]:
    """Returns (timed_out, error_message)."""
    env = {**os.environ, "FORGE_EVAL": "1"}
    cmd = [
        "claude", "code", "--non-interactive",
        f"/forge run --eval-mode {scenario.id}",
        scenario.prompt,
    ]
    if dry_run:
        cmd[-2] = cmd[-2] + " --dry-run"
    try:
        subprocess.run(
            cmd,
            cwd=target,
            env=env,
            check=True,
            timeout=scenario_timeout_seconds,
        )
    except subprocess.TimeoutExpired:
        return True, f"timeout after {scenario_timeout_seconds}s"
    except subprocess.CalledProcessError as e:
        return False, f"forge exited {e.returncode}"
    return False, None


def _parse_state(target: Path, scenario: Scenario) -> dict:
    state_path = target / ".forge" / "state.json"
    if not state_path.is_file():
        return {
            "pipeline_score": 0.0,
            "verdict": "ERROR",
            "actual_tokens": 0,
            "touched_files_actual": [],
        }
    return json.loads(state_path.read_text(encoding="utf-8"))


def _detect_must_not_touch(target: Path, patterns: list[str]) -> list[str]:
    """Return globs from ``patterns`` that matched any file modified in target.

    Uses ``git status`` inside the target worktree plus fnmatch over the
    returned paths.
    """
    import fnmatch
    try:
        result = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=target,
            check=True,
            capture_output=True,
            text=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return []
    changed = [
        line[3:].strip()
        for line in result.stdout.splitlines()
        if line.strip()
    ]
    violations: list[str] = []
    for pattern in patterns:
        for path in changed:
            if fnmatch.fnmatch(path, pattern):
                violations.append(pattern)
                break
    return violations


def execute_scenario(
    *,
    scenario: Scenario,
    forge_root: Path,
    dry_run: bool = False,
    scenario_timeout_seconds: int = 900,
) -> RawRunMetrics:
    """Run one scenario end-to-end and return raw metrics."""
    started_at = _iso_now()
    start_mono = time.monotonic()
    with tempfile.TemporaryDirectory(prefix=f"forge-eval-{scenario.id}-") as tmp:
        target = Path(tmp)
        _extract_starter(Path(scenario.path), target)
        _symlink_plugin(forge_root, target)
        try:
            _run_forge_init(target)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
            ended_at = _iso_now()
            return RawRunMetrics(
                scenario_id=scenario.id,
                started_at=started_at,
                ended_at=ended_at,
                elapsed_seconds=int(time.monotonic() - start_mono),
                tokens=0,
                pipeline_score=0.0,
                verdict="ERROR",
                touched_files_actual=[],
                must_not_touch_violations=[],
                timed_out=False,
                error=f"forge-init failed: {e}",
            )

        timed_out, error = _run_forge_with_eval_mode(
            scenario=scenario,
            target=target,
            dry_run=dry_run,
            scenario_timeout_seconds=scenario_timeout_seconds,
        )
        state = _parse_state(target, scenario)
        touched = list(state.get("touched_files_actual", []))
        violations = _detect_must_not_touch(
            target, scenario.expected.must_not_touch
        )
        tokens = int(state.get("tokens", {}).get("total", 0)) if isinstance(
            state.get("tokens"), dict
        ) else int(state.get("actual_tokens", 0))

        return RawRunMetrics(
            scenario_id=scenario.id,
            started_at=started_at,
            ended_at=_iso_now(),
            elapsed_seconds=int(time.monotonic() - start_mono),
            tokens=tokens,
            pipeline_score=float(state.get("pipeline_score", 0.0)),
            verdict=str(state.get("verdict", "CONCERNS")),
            touched_files_actual=touched,
            must_not_touch_violations=violations,
            timed_out=timed_out,
            error=error,
        )
