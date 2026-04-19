"""Baseline fetch (from GitHub Actions artifact) + regression gate.

Baseline storage contract (resolves spec open-question Q1 / review I3):
    - CI workflow ``.github/workflows/evals.yml`` uploads
      ``eval-results.jsonl`` as workflow artifact named
      ``eval-baseline-master-<sha>`` on every push to master.
    - 90-day retention (default GitHub artifact retention).
    - On PR runs, this module calls the GitHub REST API to list artifacts for
      the master branch, downloads the most recent one, and parses it.

Missing-baseline contract:
    - First-ever master run → no baseline exists → compute_gate() returns
      passed=True plus an EVAL-BASELINE-UNAVAILABLE WARNING finding. CI
      job passes; the job log contains the warning.
    - Artifact retention expired, fetch failure, or fetch timeout → same
      behavior: warn, skip, pass.
    - Never fail-closed on baseline fetch problems (that would block
      unrelated PRs on an infra hiccup).
"""
from __future__ import annotations

import json
import os
from dataclasses import dataclass
from typing import Optional

import requests

from tests.evals.pipeline.runner.schema import Finding


BASELINE_FETCH_TIMEOUT_SECONDS = 30
GITHUB_API = "https://api.github.com"


class BaselineUnavailable(Exception):
    """Raised internally by fetch; compute_gate() translates to a WARNING finding."""


@dataclass(frozen=True)
class GateDecision:
    passed: bool
    delta: float
    baseline_mean: Optional[float]
    current_mean: float
    finding: Optional[Finding]


def _mean_composite(records: list[dict]) -> float:
    if not records:
        return 0.0
    return sum(float(r["composite"]) for r in records) / len(records)


def compute_gate(
    *,
    current: list[dict],
    baseline: Optional[list[dict]],
    tolerance: float,
) -> GateDecision:
    """Compare current-run mean composite to baseline mean composite.

    Args:
        current: list of Result dicts (composite key required) from this run.
        baseline: Same shape, from stored master artifact; None if unavailable.
        tolerance: composite-point drop that trips EVAL-REGRESSION.

    Returns:
        GateDecision.passed is False only when baseline is available AND
        delta < -tolerance. Missing-baseline is a pass-with-warning.
    """
    current_mean = _mean_composite(current)

    if baseline is None:
        return GateDecision(
            passed=True,
            delta=0.0,
            baseline_mean=None,
            current_mean=current_mean,
            finding=Finding(
                category="EVAL-BASELINE-UNAVAILABLE",
                severity="WARNING",
                message=(
                    "No master baseline artifact available (first run, "
                    "retention expired, or fetch failed). Regression gate skipped."
                ),
            ),
        )

    baseline_mean = _mean_composite(baseline)
    delta = current_mean - baseline_mean

    if delta < -tolerance:
        return GateDecision(
            passed=False,
            delta=delta,
            baseline_mean=baseline_mean,
            current_mean=current_mean,
            finding=Finding(
                category="EVAL-REGRESSION",
                severity="CRITICAL",
                message=(
                    f"Composite mean dropped {abs(delta):.2f} points "
                    f"(current={current_mean:.2f}, baseline={baseline_mean:.2f}, "
                    f"tolerance={tolerance})."
                ),
            ),
        )

    return GateDecision(
        passed=True,
        delta=delta,
        baseline_mean=baseline_mean,
        current_mean=current_mean,
        finding=None,
    )


def fetch_baseline_from_github(
    *,
    repo: str,
    branch: str = "master",
    token: Optional[str] = None,
) -> list[dict]:
    """Download and parse the most recent ``eval-baseline-<branch>-*`` artifact.

    Args:
        repo: "owner/name" e.g. "quantumbitcz/forge".
        branch: branch name whose artifacts are the baseline.
        token: GitHub token; defaults to env GITHUB_TOKEN.

    Returns:
        Parsed list of Result-shaped dicts (one per scenario).

    Raises:
        BaselineUnavailable: on any failure — caller translates to WARNING.
    """
    token = token or os.environ.get("GITHUB_TOKEN")
    if not token:
        raise BaselineUnavailable("no GITHUB_TOKEN in environment")

    headers = {
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {token}",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    prefix = f"eval-baseline-{branch}-"
    try:
        resp = requests.get(
            f"{GITHUB_API}/repos/{repo}/actions/artifacts",
            params={"per_page": 100, "name": None},
            headers=headers,
            timeout=BASELINE_FETCH_TIMEOUT_SECONDS,
        )
        resp.raise_for_status()
    except requests.RequestException as e:
        raise BaselineUnavailable(f"list artifacts failed: {e}") from e

    data = resp.json()
    candidates = [
        a for a in data.get("artifacts", [])
        if a.get("name", "").startswith(prefix) and not a.get("expired", False)
    ]
    if not candidates:
        raise BaselineUnavailable(
            f"no unexpired artifact matching {prefix}* on repo {repo}"
        )
    latest = max(candidates, key=lambda a: a.get("created_at", ""))

    try:
        archive = requests.get(
            latest["archive_download_url"],
            headers=headers,
            timeout=BASELINE_FETCH_TIMEOUT_SECONDS,
            allow_redirects=True,
        )
        archive.raise_for_status()
    except requests.RequestException as e:
        raise BaselineUnavailable(f"download artifact failed: {e}") from e

    import io
    import zipfile

    try:
        with zipfile.ZipFile(io.BytesIO(archive.content)) as zf:
            names = [n for n in zf.namelist() if n.endswith("eval-results.jsonl")]
            if not names:
                raise BaselineUnavailable(
                    "artifact archive missing eval-results.jsonl"
                )
            with zf.open(names[0]) as f:
                lines = f.read().decode("utf-8").splitlines()
    except zipfile.BadZipFile as e:
        raise BaselineUnavailable(f"artifact is not a zip: {e}") from e

    records: list[dict] = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError as e:
            raise BaselineUnavailable(
                f"malformed JSONL in baseline artifact: {e}"
            ) from e
    return records
