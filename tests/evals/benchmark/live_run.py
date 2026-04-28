"""Live-run wrapper: extend pipeline executor with Phase 7 injection + model override.

Reuses tests.evals.pipeline.runner.executor primitives (tarball extract,
plugin symlink) but:
  - writes .forge/specs/index.json with AC-B* namespace before /forge run (auto-bootstrap handles init)
  - writes .claude/forge.local.md with model_routing.overrides
  - parses state.intent_verification_results to build ac_breakdown
"""
from __future__ import annotations
import json
import subprocess
import tarfile
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from tests.evals.benchmark.discovery import CorpusEntry
from tests.evals.benchmark.result import BenchmarkResult
from tests.evals.benchmark.scoring import solved, SolveInputs, compute_partial_ac_pct
from tests.evals.benchmark.write_forge_model_overrides import write_overrides

_TIMEOUTS_SEC: dict[str, int] = {"S": 900, "M": 2700, "L": 5400}


def _iso_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _write_spec_injection(target: Path, entry: CorpusEntry) -> None:
    """Phase 7 contract: seed active spec with source='benchmark-injected'."""
    specs_dir = target / ".forge" / "specs"
    specs_dir.mkdir(parents=True, exist_ok=True)
    doc = {
        "version": 1,
        "active_spec_id": entry.entry_id,
        "specs": {
            entry.entry_id: {
                "requirement": entry.requirement,
                "acceptance_criteria": [
                    {"id": ac["id"], "text": ac["description"],
                     "verifier_hint": ac.get("verifier_hint", ac.get("verifiable_via", ""))}
                    for ac in entry.ac_list
                ],
                "source": "benchmark-injected",
            }
        },
    }
    (specs_dir / "index.json").write_text(json.dumps(doc, indent=2), encoding="utf-8")


def _extract_tarball(tarball: Path, target: Path) -> None:
    with tarfile.open(tarball, "r:gz") as tf:
        tf.extractall(target)


def _symlink_plugin(forge_root: Path, target: Path) -> None:
    plug_dir = target / ".claude" / "plugins"
    plug_dir.mkdir(parents=True, exist_ok=True)
    (plug_dir / "forge").symlink_to(forge_root, target_is_directory=True)


def _parse_state(target: Path) -> dict[str, Any]:
    state_path = target / ".forge" / "state.json"
    if not state_path.is_file():
        return {"pipeline_verdict": "ERROR", "score": 0, "cost_usd": 0.0,
                "ac_breakdown": {}, "partial_ac_pct": 0.0, "unverifiable_count": 0,
                "convergence_iterations": 0, "critical_findings": 0, "warning_findings": 0,
                "touched_files_actual": []}
    state = json.loads(state_path.read_text(encoding="utf-8"))
    ivrs = state.get("intent_verification_results", []) or []
    breakdown = {r["ac_id"]: r["status"] for r in ivrs if "ac_id" in r}
    return {
        "pipeline_verdict": state.get("pipeline_verdict", state.get("verdict", "ERROR")),
        "score": int(state.get("score", state.get("pipeline_score", 0))),
        "cost_usd": float(state.get("cost", {}).get("estimated_cost_usd", 0.0)),
        "ac_breakdown": breakdown,
        "partial_ac_pct": compute_partial_ac_pct(breakdown),
        "unverifiable_count": sum(1 for v in breakdown.values() if v == "UNVERIFIABLE"),
        "convergence_iterations": int(state.get("total_iterations", 0)),
        "critical_findings": int(state.get("findings_summary", {}).get("critical", 0)),
        "warning_findings": int(state.get("findings_summary", {}).get("warning", 0)),
        "touched_files_actual": list(state.get("touched_files_actual", [])),
    }


def _count_hook_failures(target: Path) -> int:
    log = target / ".forge" / ".hook-failures.jsonl"
    if not log.is_file():
        return 0
    return sum(1 for _ in log.read_text(encoding="utf-8").splitlines() if _.strip())


def run_one_entry(*, entry: CorpusEntry, forge_root: Path, model: str, os: str) -> BenchmarkResult:
    """Execute one corpus entry end-to-end. Caller writes the result file."""
    started_at = _iso_now()
    mono_start = time.monotonic()
    timeout = _TIMEOUTS_SEC[entry.complexity]

    if entry.requires_docker and os == "windows-latest":
        return BenchmarkResult(
            schema_version=1, entry_id=entry.entry_id, run_date=started_at[:10],
            os=os, model=model, complexity=entry.complexity,
            started_at=started_at, ended_at=_iso_now(),
            duration_s=0, solved=False, partial_ac_pct=0.0, ac_breakdown={},
            unverifiable_count=0, cost_usd=0.0, pipeline_verdict="ERROR", score=0,
            convergence_iterations=0, critical_findings=0, warning_findings=1,
            timeout=False, error="BENCH-DOCKER-SKIPPED",
        )

    with tempfile.TemporaryDirectory(prefix=f"forge-bench-{entry.entry_id}-") as tmp:
        target = Path(tmp)
        _extract_tarball(entry.path / "seed-project.tar.gz", target)
        _symlink_plugin(forge_root, target)
        write_overrides(target, model)
        _write_spec_injection(target, entry)

        import os as _os
        env = {**_os.environ, "FORGE_EVAL": "1", "FORGE_BENCHMARK": "1"}
        timed_out = False
        error: str | None = None
        try:
            # Auto-bootstrap (mega B) runs init implicitly when .claude/forge.local.md is missing,
            # so no explicit /forge invocation is needed here.
            subprocess.run(
                ["claude", "code", "--non-interactive",
                 "/forge", "run", f"--eval-mode={entry.entry_id}", entry.requirement],
                cwd=target, env=env, check=True, timeout=timeout,
            )
        except subprocess.TimeoutExpired:
            timed_out = True
            error = f"timeout after {timeout}s"
        except subprocess.CalledProcessError as e:
            error = f"forge exited {e.returncode}"
        except FileNotFoundError:
            error = "claude cli not installed"

        parsed = _parse_state(target)
        hook_failures = _count_hook_failures(target)

    duration_s = int(time.monotonic() - mono_start)
    partial_pct = parsed["partial_ac_pct"]
    is_solved = (
        not timed_out and error is None
        and solved(SolveInputs(
            pipeline_verdict=parsed["pipeline_verdict"],
            partial_ac_pct=partial_pct,
            critical_findings=parsed["critical_findings"],
        ))
    )

    return BenchmarkResult(
        schema_version=1, entry_id=entry.entry_id, run_date=started_at[:10],
        os=os, model=model, complexity=entry.complexity,
        started_at=started_at, ended_at=_iso_now(),
        duration_s=duration_s, solved=is_solved, partial_ac_pct=partial_pct,
        ac_breakdown=parsed["ac_breakdown"],
        unverifiable_count=parsed["unverifiable_count"],
        cost_usd=parsed["cost_usd"],
        pipeline_verdict=parsed["pipeline_verdict"], score=parsed["score"],
        convergence_iterations=parsed["convergence_iterations"],
        critical_findings=parsed["critical_findings"],
        warning_findings=parsed["warning_findings"],
        timeout=timed_out,
        must_not_touch_violations=[],  # populated by Task 11
        touched_files_actual=parsed["touched_files_actual"],
        hook_failures_count=hook_failures,
        error=error,
    )
