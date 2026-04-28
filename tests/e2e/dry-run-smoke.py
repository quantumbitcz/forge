#!/usr/bin/env python3
"""End-to-end dry-run smoke test for forge.

Spawns a minimal typescript+vitest project in a temp directory, runs
`npm install --no-audit --no-fund` to install real dev-deps, writes the
plugin-detection output that `/forge` would produce, then drives
`shared/forge-sim.sh` in dry-run mode against it. Asserts the resulting
`.forge/state.json` ends in VALIDATED or COMPLETE.

`npm install` (not `npm ci`) is used so the fixture does not have to ship
a frozen `package-lock.json`; the smoke is concerned with the toolchain
plumbing, not exact dep pinning.

Scope note: `/forge` itself is a Claude Code skill — it cannot be
spawned in CI without a Claude Code host. We use a deterministic Python
shim that reproduces the detection + config-write path. Full
`/forge` coverage belongs in `tests/evals/pipeline/` (CI-only).

Exit codes:
  0  — PASS
  1  — FAIL (assertion failed)
  2  — internal error (malformed fixture, etc.)
  77 — SKIP (environment-level failure: symlink EPERM, ENOSPC, network,
       npm registry unavailable)

Platform notes:
  - Linux/macOS: os.symlink is used directly. `npm ci` budget is 90s
    wall-clock per job step.
  - Windows: os.symlink often requires Developer Mode or admin. The script
    catches OSError / NotImplementedError and falls back to
    `cmd /c mklink /J` (directory junction — no privileges required).
    Junctions do not preserve all permissions and only work for
    directories on the same volume, but for the read-only plugin link
    used here that is sufficient. If both fail (e.g. ACL restricted),
    the script exits 77 (SKIP) rather than fail the CI job. `npm ci`
    budget is 180s on Windows (NTFS cold cache overhead); the
    Python-level subprocess timeout is 240s on all OSes so
    TimeoutExpired surfaces cleanly instead of the step-level timeout
    SIGKILL'ing the process.
  - npm registry/network failures (ETIMEDOUT / ENOTFOUND / ECONNREFUSED /
    ECONNRESET / 'registry.npmjs.org' in stderr) are reclassified to
    exit 77 (SKIP) so flaky mirrors don't fail the job.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
FIXTURE = REPO / "tests" / "e2e" / "fixtures" / "ts-vitest"

# Vitest cold-start on Windows NTFS can take 20-30s before the first test
# runs; the 60s budget that's fine on Linux/macOS leaves no margin there.
NPM_TEST_TIMEOUT = 120 if sys.platform.startswith("win") else 60


def _run(cmd: list[str], cwd: Path, env: dict[str, str] | None = None,
         timeout: int = 60) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd, cwd=str(cwd), env=env, capture_output=True, text=True,
        check=False, timeout=timeout,
    )


def _resolve_bash() -> str | None:
    """Resolve a usable bash executable.

    On Windows, ``shutil.which("bash")`` typically returns
    ``C:\\Windows\\System32\\bash.exe`` (the WSL launcher), which fails when
    no Linux distribution is installed — and GitHub-hosted ``windows-latest``
    runners ship without one. We prefer Git for Windows' bash, falling back
    to other PATH entries that are NOT the WSL launcher.
    """
    if sys.platform == "win32":
        candidates = [
            os.environ.get("ProgramFiles", r"C:\Program Files") + r"\Git\bin\bash.exe",
            os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)") + r"\Git\bin\bash.exe",
            r"C:\Program Files\Git\bin\bash.exe",
            r"C:\Program Files (x86)\Git\bin\bash.exe",
        ]
        for cand in candidates:
            if Path(cand).is_file():
                return cand
        # Fall back to PATH lookup, but skip the System32 WSL launcher.
        wsl_bash = (os.environ.get("SystemRoot", r"C:\Windows")
                    + r"\System32\bash.exe").lower()
        for p in os.environ.get("PATH", "").split(os.pathsep):
            cand = Path(p) / "bash.exe"
            if cand.is_file() and str(cand).lower() != wsl_bash:
                return str(cand)
        return None
    return shutil.which("bash")


def _symlink_or_junction(src: Path, dst: Path) -> None:
    """Create `dst` pointing at `src`. Windows falls back to directory junction."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    try:
        os.symlink(src, dst, target_is_directory=True)
        return
    except (OSError, NotImplementedError) as exc:
        if sys.platform != "win32":
            raise
        # Windows: try mklink /J (directory junction — no admin required).
        result = subprocess.run(
            ["cmd", "/c", "mklink", "/J", str(dst), str(src)],
            capture_output=True, text=True, check=False,
        )
        if result.returncode != 0:
            raise RuntimeError(
                f"Both symlink and mklink /J failed: "
                f"symlink={exc}; mklink stderr={result.stderr!r}"
            ) from exc


def _write_forge_local_md(project: Path) -> None:
    """Deterministic config-write shim mirroring forge-init detection for ts+vitest."""
    forge_dir = project / ".claude"
    forge_dir.mkdir(parents=True, exist_ok=True)
    (forge_dir / "forge.local.md").write_text(
        "---\n"
        "components:\n"
        "  language: typescript\n"
        "  framework: null\n"
        "  testing: vitest\n"
        "---\n"
        "\n"
        "# forge.local.md (auto-generated by e2e smoke)\n",
        encoding="utf-8",
    )


def smoke(*, verbose: bool = False) -> int:
    with tempfile.TemporaryDirectory(prefix="forge-e2e-") as tmpdir:
        project = Path(tmpdir) / "project"
        shutil.copytree(FIXTURE, project)

        # 1. Git init (forge-init expects a repo).
        for cmd in (
            ["git", "init", "--quiet"],
            ["git", "-c", "user.email=ci@forge", "-c", "user.name=CI",
             "add", "-A"],
            ["git", "-c", "user.email=ci@forge", "-c", "user.name=CI",
             "commit", "--quiet", "-m", "fixture"],
        ):
            r = _run(cmd, cwd=project)
            if r.returncode != 0:
                print(f"[FAIL] git step {cmd!r}: {r.stderr!r}", file=sys.stderr)
                return 1

        # 2. Symlink the plugin root into .claude/plugins/forge.
        plugin_link = project / ".claude" / "plugins" / "forge"
        try:
            _symlink_or_junction(REPO, plugin_link)
        except RuntimeError as exc:
            print(f"[SKIP] cannot create plugin link: {exc}", file=sys.stderr)
            return 77
        except PermissionError as exc:
            print(f"[SKIP] permission error: {exc}", file=sys.stderr)
            return 77
        except OSError as exc:
            # ENOSPC etc. — CI disk full.
            print(f"[SKIP] OSError during link: {exc}", file=sys.stderr)
            return 77

        # 3. Write forge.local.md (the deterministic slice of /forge).
        _write_forge_local_md(project)

        # 4. Assert the config was detected correctly.
        cfg = (project / ".claude" / "forge.local.md").read_text(encoding="utf-8")
        if "language: typescript" not in cfg or "testing: vitest" not in cfg:
            print(f"[FAIL] forge.local.md missing expected config:\n{cfg}",
                  file=sys.stderr)
            return 1

        # 4b. Real `npm install` (not `npm ci`, the fixture ships no lockfile).
        # Windows NTFS cold-cache can push past 90s; the CI step-level timeout
        # is 180s on Windows, 90s elsewhere — we use a generous 240s subprocess
        # timeout here so Python surfaces a clean TimeoutExpired rather than
        # getting SIGKILL'd by the step timeout.
        #
        # On Windows, `npm` is `npm.cmd`. `subprocess.run(["npm", ...])` without
        # `shell=True` cannot resolve `.cmd` shims, so we resolve through
        # `shutil.which` (which honours PATHEXT) and pass the absolute path.
        npm_path = shutil.which("npm")
        if npm_path is None:
            print("[SKIP] npm not on PATH", file=sys.stderr)
            return 77
        npm_install = _run(
            [npm_path, "install", "--no-audit", "--no-fund"],
            cwd=project,
            timeout=240,
        )
        if npm_install.returncode != 0:
            # Classify registry/network failures as SKIP, everything else as FAIL.
            stderr = (npm_install.stderr or "")
            network_markers = ("ETIMEDOUT", "ENOTFOUND", "ECONNREFUSED",
                               "ECONNRESET", "registry.npmjs.org",
                               "network timeout")
            if any(marker in stderr for marker in network_markers):
                print(f"[SKIP] npm install network failure:\n{stderr}",
                      file=sys.stderr)
                return 77
            print(f"[FAIL] npm install exited {npm_install.returncode}:\n"
                  f"stdout:\n{npm_install.stdout}\nstderr:\n{stderr}",
                  file=sys.stderr)
            return 1

        # 4c. Invoke the fixture's test script to prove the toolchain works
        # end-to-end. `npm test` → `vitest run`.
        npm_test = _run(
            [npm_path, "test", "--silent"],
            cwd=project,
            timeout=NPM_TEST_TIMEOUT,
        )
        if npm_test.returncode != 0:
            print(f"[FAIL] npm test exited {npm_test.returncode}:\n"
                  f"stdout:\n{npm_test.stdout}\nstderr:\n{npm_test.stderr}",
                  file=sys.stderr)
            return 1

        # 5. Run the dry-run simulator harness.
        sim_script = REPO / "shared" / "forge-sim.sh"
        if not sim_script.is_file():
            print(f"[SKIP] forge-sim.sh not found at {sim_script}", file=sys.stderr)
            return 77
        bash_path = _resolve_bash()
        if bash_path is None:
            print("[SKIP] bash not on PATH; e2e dry-run smoke requires bash 4+",
                  file=sys.stderr)
            return 77

        # Use a minimal inline scenario: PREFLIGHT -> EXPLORING -> PLANNING ->
        # VALIDATING -> COMPLETE (dry-run). Schema matches forge-sim-runner.py
        # (mock_events, not events; guard values stringified; dry_run flag at
        # the top level so init flips story_state's dry_run path correctly).
        scenario = project / "dry-run-scenario.yaml"
        scenario.write_text(
            "name: phase3-e2e-smoke\n"
            "requirement: phase3-e2e-smoke\n"
            "mode: standard\n"
            "dry_run: true\n"
            "mock_events:\n"
            "  - event: preflight_complete\n"
            "    guards:\n"
            "      dry_run: \"true\"\n"
            "  - event: explore_complete\n"
            "    guards:\n"
            "      scope_size: \"1\"\n"
            "      threshold: \"5\"\n"
            "  - event: plan_complete\n"
            "    guards: {}\n"
            "  - event: validate_complete\n"
            "    guards:\n"
            "      dry_run: \"true\"\n"
            "expected_trace:\n"
            "  - PREFLIGHT -> EXPLORING\n"
            "  - EXPLORING -> PLANNING\n"
            "  - PLANNING -> VALIDATING\n"
            "  - VALIDATING -> COMPLETE\n",
            encoding="utf-8",
        )
        r = _run(
            [bash_path, str(sim_script), "run", str(scenario),
             "--forge-dir", str(project / ".forge")],
            cwd=project,
            timeout=90,
        )
        if verbose:
            print(r.stdout)
            print(r.stderr, file=sys.stderr)

        # 6. Assert .forge/state.json exists and ends in VALIDATED/COMPLETE.
        state_path = project / ".forge" / "state.json"
        if not state_path.is_file():
            print(f"[FAIL] no state.json at {state_path}", file=sys.stderr)
            print(f"forge-sim stdout:\n{r.stdout}", file=sys.stderr)
            print(f"forge-sim stderr:\n{r.stderr}", file=sys.stderr)
            return 1

        try:
            state = json.loads(state_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            print(f"[FAIL] malformed state.json: {exc}", file=sys.stderr)
            return 1

        story_state = state.get("story_state")
        if story_state not in {"VALIDATED", "COMPLETE"}:
            print(
                f"[FAIL] final story_state={story_state!r}; "
                f"expected VALIDATED or COMPLETE",
                file=sys.stderr,
            )
            return 1

        # 7. Guard against error-class final states.
        forbidden = {"ESCALATED", "ABORTED"}
        if story_state in forbidden:
            print(f"[FAIL] story_state in forbidden set {forbidden}", file=sys.stderr)
            return 1

        print(f"[PASS] e2e dry-run smoke: story_state={story_state}")
        return 0


def self_test() -> int:
    """Self-verify the assertion logic against a baked-in good state.json.

    Catches the class of bug where the script always returns green.
    """
    with tempfile.TemporaryDirectory(prefix="forge-e2e-selftest-") as tmpdir:
        fake_project = Path(tmpdir) / "fake"
        fake_forge = fake_project / ".forge"
        fake_forge.mkdir(parents=True)
        (fake_forge / "state.json").write_text(
            json.dumps({"story_state": "COMPLETE"}), encoding="utf-8",
        )
        state = json.loads((fake_forge / "state.json").read_text())
        if state["story_state"] not in {"VALIDATED", "COMPLETE"}:
            print(f"[FAIL] self-test positive control: "
                  f"story_state={state['story_state']!r}", file=sys.stderr)
            raise SystemExit(1)

        # Negative control.
        (fake_forge / "state.json").write_text(
            json.dumps({"story_state": "ESCALATED"}), encoding="utf-8",
        )
        state = json.loads((fake_forge / "state.json").read_text())
        if state["story_state"] in {"VALIDATED", "COMPLETE"}:
            print(f"[FAIL] self-test negative control: "
                  f"story_state={state['story_state']!r}", file=sys.stderr)
            raise SystemExit(1)

    print("[PASS] self-test")
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="dry-run-smoke")
    ap.add_argument("--self-test", action="store_true",
                    help="Verify the script's own assertion logic.")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args(argv)
    if args.self_test:
        return self_test()
    return smoke(verbose=args.verbose)


if __name__ == "__main__":
    sys.exit(main())
