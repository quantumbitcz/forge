# shared/bootstrap-detect.py
"""Project stack detection + atomic forge.local.md writer.

Used by:
  - skills/forge/SKILL.md (auto-bootstrap branch when forge.local.md is absent)
  - skills/forge-admin/SKILL.md (config wizard)
  - agents/fg-050-project-bootstrapper.md (greenfield bootstrap)

Spec: docs/superpowers/specs/2026-04-27-skill-consolidation-design.md §2 (commit 660dbef7).
Atomic-write contract: AC-S027 — target file is either absent or fully written.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import TypedDict


class StackResult(TypedDict):
    language: str | None
    framework: str | None
    testing: str | None
    build: str | None
    ambiguous: bool
    reason: str


_TEMP_SUFFIX = ".tmp"


def _file_contains(path: Path, needle: str) -> bool:
    try:
        return needle in path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False


def _detect_kotlin(root: Path) -> StackResult | None:
    gradle_kts = root / "build.gradle.kts"
    if not gradle_kts.exists():
        return None
    is_spring = _file_contains(gradle_kts, "org.springframework.boot")
    return {
        "language": "kotlin",
        "framework": "spring" if is_spring else None,
        "testing": "junit5" if is_spring else "kotest",
        "build": "gradle",
        "ambiguous": False,
        "reason": "build.gradle.kts present" + (" (Spring Boot detected)" if is_spring else ""),
    }


def _detect_typescript(root: Path) -> StackResult | None:
    pkg = root / "package.json"
    if not pkg.exists():
        return None
    try:
        data = json.loads(pkg.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    deps = {**data.get("dependencies", {}), **data.get("devDependencies", {})}
    next_config_present = (
        (root / "next.config.js").exists()
        or (root / "next.config.mjs").exists()
        or (root / "next.config.ts").exists()
        or (root / "next.config.cjs").exists()
    )
    is_next = "next" in deps or next_config_present
    has_ts = "typescript" in deps or (root / "tsconfig.json").exists()
    if not has_ts and not is_next:
        return None
    reasons: list[str] = []
    if next_config_present:
        reasons.append("next.config detected")
    if (root / "tsconfig.json").exists():
        reasons.append("tsconfig.json")
    if "next" in deps and not reasons:
        reasons.append("'next' in package.json deps")
    return {
        "language": "typescript",
        "framework": "nextjs" if is_next else None,
        "testing": "vitest" if "vitest" in deps else ("jest" if "jest" in deps else None),
        "build": "npm",
        "ambiguous": False,
        "reason": "package.json + " + " + ".join(reasons),
    }


def _detect_python(root: Path) -> StackResult | None:
    pyproject = root / "pyproject.toml"
    if not pyproject.exists():
        return None
    body = pyproject.read_text(encoding="utf-8", errors="replace")
    is_fastapi = "fastapi" in body.lower()
    is_django = "django" in body.lower()
    framework: str | None = None
    if is_fastapi and not is_django:
        framework = "fastapi"
    elif is_django and not is_fastapi:
        framework = "django"
    return {
        "language": "python",
        "framework": framework,
        "testing": "pytest" if "pytest" in body.lower() else None,
        "build": "uv" if (root / "uv.lock").exists() else "pip",
        "ambiguous": is_fastapi and is_django,
        "reason": "pyproject.toml present"
        + (" (ambiguous: both fastapi and django referenced)" if is_fastapi and is_django else ""),
    }


def detect_stack(repo_root: Path) -> StackResult:
    """Detect language/framework/testing/build for the project at repo_root.

    Probes are deterministic and ordered. The first non-None probe wins.
    Returns ambiguous: True when no single stack can be picked confidently.
    """
    if not isinstance(repo_root, Path):
        repo_root = Path(repo_root)

    probes = (_detect_kotlin, _detect_typescript, _detect_python)
    hits = [r for r in (p(repo_root) for p in probes) if r is not None]

    if not hits:
        return {
            "language": None,
            "framework": None,
            "testing": None,
            "build": None,
            "ambiguous": True,
            "reason": "no recognized build manifest at repo root",
        }
    if len(hits) > 1:
        return {
            "language": None,
            "framework": None,
            "testing": None,
            "build": None,
            "ambiguous": True,
            "reason": f"multiple stacks detected: {[h['language'] for h in hits]}",
        }
    return hits[0]


def write_forge_local_md(stack: StackResult, target_path: Path) -> None:
    """Atomically write forge.local.md.

    Contract (AC-S027):
      - Target is either absent or fully written; never partial.
      - Implementation: write to <target>.tmp in the same parent dir, then Path.replace.
        Path.replace is atomic on Windows ≥ Vista (replaces silently) and POSIX.
      - On any error during write, the temp file is removed and the exception propagates.
    """
    if not isinstance(target_path, Path):
        target_path = Path(target_path)
    if stack["ambiguous"]:
        raise ValueError(
            f"refusing to write forge.local.md: stack detection ambiguous ({stack['reason']})"
        )

    target_path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = target_path.with_suffix(target_path.suffix + _TEMP_SUFFIX)

    body = _render_forge_local_md(stack)
    try:
        temp_path.write_text(body, encoding="utf-8")
        temp_path.replace(target_path)
    except Exception:
        if temp_path.exists():
            try:
                temp_path.unlink()
            except OSError:
                pass
        raise


def _render_forge_local_md(stack: StackResult) -> str:
    lines = [
        "---",
        "# Auto-generated by shared/bootstrap-detect.py.",
        "# Edit freely — `/forge-admin config` re-reads this file.",
        f"language: {stack['language'] or 'null'}",
        f"framework: {stack['framework'] or 'null'}",
        f"testing: {stack['testing'] or 'null'}",
        f"build: {stack['build'] or 'null'}",
        "autonomous: false",
        "---",
        "",
        "# Project configuration (forge)",
        "",
        f"Detected stack: **{stack['language']}** / **{stack['framework']}**.",
        f"Reason: {stack['reason']}.",
        "",
    ]
    return "\n".join(lines)
