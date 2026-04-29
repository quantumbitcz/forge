#!/usr/bin/env python3
"""Probe for optional CLI tools that enhance Forge capabilities.

Emits JSON on stdout with the same schema previously produced by the
retired shared/check-environment.sh. Always exits 0 — informational only.

Schema: {"platform": str, "tools": [{"name","available","version","tier","purpose","install"}]}
"""
from __future__ import annotations

import json
import platform
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Optional


def detect_platform() -> str:
    sysname = sys.platform
    if sysname == "darwin":
        return "darwin"
    if sysname.startswith("linux"):
        proc_version = Path("/proc/version")
        if proc_version.exists():
            try:
                text = proc_version.read_text(encoding="utf-8", errors="ignore").lower()
                if "microsoft" in text or "wsl" in text:
                    return "wsl"
            except OSError:
                pass
        return "linux"
    if sysname.startswith(("win32", "cygwin", "msys")):
        # Detect Git Bash (MINGW/MSYS) vs native Windows pwsh/cmd.
        release = platform.release() or ""
        if "MINGW" in release or "MSYS" in release or sysname in ("cygwin", "msys"):
            return "gitbash"
        return "windows"
    return "unknown"


def _run(cmd: list[str]) -> Optional[str]:
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    out = (result.stdout or result.stderr or "").strip()
    return out or None


def _probe(name: str, tier: str, purpose: str, install: str) -> dict:
    if not shutil.which(name):
        return {
            "name": name,
            "available": False,
            "version": "",
            "tier": tier,
            "purpose": purpose,
            "install": install,
        }
    version = ""
    if name == "python3":
        version = (_run(["python3", "--version"]) or "").replace("Python", "").strip()
    elif name == "bash":
        raw = _run(["bash", "--version"])
        version = raw.splitlines()[0] if raw else ""
    elif name == "git":
        raw = _run(["git", "--version"]) or ""
        version = raw.replace("git version", "").strip()
    elif name == "jq":
        version = (_run(["jq", "--version"]) or "").replace("jq-", "").strip()
    elif name == "docker":
        raw = _run(["docker", "--version"]) or ""
        version = raw.split()[2].rstrip(",") if len(raw.split()) >= 3 else ""
    elif name == "tree-sitter":
        version = (_run(["tree-sitter", "--version"]) or "").strip()
    elif name == "gh":
        raw = _run(["gh", "--version"]) or ""
        lines = raw.splitlines()
        version = lines[0].split()[2] if lines and len(lines[0].split()) >= 3 else ""
    elif name == "sqlite3":
        raw = _run(["sqlite3", "--version"])
        version = raw.split()[0] if raw else ""
    elif name == "node":
        version = (_run(["node", "--version"]) or "").lstrip("v")
    elif name == "cargo":
        raw = _run(["cargo", "--version"]) or ""
        version = raw.split()[1] if len(raw.split()) >= 2 else ""
    elif name == "go":
        raw = _run(["go", "version"]) or ""
        version = raw.split()[2].lstrip("go") if len(raw.split()) >= 3 else ""
    return {
        "name": name,
        "available": True,
        "version": version,
        "tier": tier,
        "purpose": purpose,
        "install": install,
    }


def _hints(platform_name: str) -> dict[str, str]:
    if platform_name == "darwin":
        return {
            "jq": "brew install jq",
            "docker": "brew install --cask docker",
            "tree-sitter": "brew install tree-sitter",
            "gh": "brew install gh",
            "sqlite3": "brew install sqlite3",
        }
    if platform_name == "linux":
        return {
            "jq": "sudo apt install jq",
            "docker": "sudo apt install docker.io",
            "tree-sitter": "npm install -g tree-sitter-cli",
            "gh": "sudo apt install gh",
            "sqlite3": "sudo apt install sqlite3",
        }
    if platform_name == "wsl":
        return {
            "jq": "sudo apt install jq",
            "docker": "Install Docker Desktop for Windows + enable WSL2 backend",
            "tree-sitter": "npm install -g tree-sitter-cli",
            "gh": "sudo apt install gh",
            "sqlite3": "sudo apt install sqlite3",
        }
    if platform_name == "gitbash":
        return {
            "jq": "scoop install jq",
            "docker": "Install Docker Desktop from docker.com",
            "tree-sitter": "npm install -g tree-sitter-cli",
            "gh": "scoop install gh",
            "sqlite3": "scoop install sqlite",
        }
    if platform_name == "windows":
        return {
            "jq": "winget install jqlang.jq",
            "docker": "winget install Docker.DockerDesktop",
            "tree-sitter": "npm install -g tree-sitter-cli",
            "gh": "winget install GitHub.cli",
            "sqlite3": "winget install SQLite.SQLite",
        }
    return {
        "jq": "https://jqlang.github.io/jq/",
        "docker": "https://docs.docker.com/get-docker/",
        "tree-sitter": "npm install -g tree-sitter-cli",
        "gh": "https://cli.github.com/",
        "sqlite3": "Install sqlite3 via your package manager",
    }


def main() -> int:
    platform_name = detect_platform()
    hints = _hints(platform_name)
    tools: list[dict] = [
        _probe("bash", "required", "Shell runtime for Forge scripts", ""),
        _probe("python3", "required", "State management, JSON processing, check engine", ""),
        _probe("git", "required", "Version control, worktree isolation", ""),
        _probe("jq", "recommended", "JSON processing for state management and hooks", hints["jq"]),
        _probe("docker", "recommended", "Required for Neo4j knowledge graph", hints["docker"]),
        _probe("tree-sitter", "recommended", "L0 AST-based syntax validation (PreToolUse hook)", hints["tree-sitter"]),
        _probe("gh", "recommended", "GitHub CLI for cross-repo discovery and PR creation", hints["gh"]),
        _probe("sqlite3", "recommended", "SQLite code graph (zero-dependency alternative to Neo4j)", hints["sqlite3"]),
    ]
    cwd = Path.cwd()
    if (cwd / "package.json").exists() or (cwd / "tsconfig.json").exists():
        tools.append(_probe("node", "optional", "Node.js runtime (JS/TS project detected)", ""))
    if (cwd / "Cargo.toml").exists():
        tools.append(_probe("cargo", "optional", "Rust toolchain (Rust project detected)", ""))
    if (cwd / "go.mod").exists():
        tools.append(_probe("go", "optional", "Go toolchain (Go project detected)", ""))
    sys.stdout.write(json.dumps({"platform": platform_name, "tools": tools}, separators=(",", ":")))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
