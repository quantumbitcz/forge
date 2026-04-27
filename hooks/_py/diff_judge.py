"""Structural AST diff for Phase 7 F36 voting.

Two implementations compared via (a) stdlib `ast` for Python and (b)
`tree-sitter-language-pack` 1.6.3+ for the supported set. Falls back to
whitespace-normalized textual diff for unsupported languages or on parse
failure.

Pure functions — no IO beyond reading the two sample files. Orchestrator
wires up the agent dispatch; this module is the engine.
"""
from __future__ import annotations

import ast
import dataclasses
import hashlib
import logging
import re
from pathlib import Path
from typing import Any

log = logging.getLogger(__name__)

# Extension -> tree-sitter language name mapping.
# NOTE: DO NOT hardcode the full list; feature-detect via get_language() at
# call time. The spec's 2026-04-22 footnote (§6) says grammar coverage is
# versioned with the pack — what parses today may expand.
_TS_EXT_TO_LANG: dict[str, str] = {
    ".ts": "typescript", ".tsx": "tsx",
    ".js": "javascript", ".jsx": "javascript",
    ".kt": "kotlin", ".kts": "kotlin",
    ".go": "go",
    ".rs": "rust",
    ".java": "java",
    ".c": "c", ".h": "c",
    ".cpp": "cpp", ".cc": "cpp", ".hpp": "cpp",
    ".rb": "ruby",
    ".php": "php",
    ".swift": "swift",
}


@dataclasses.dataclass
class FileDiff:
    path: str
    verdict: str                  # SAME | DIVERGES
    mode: str                     # ast | tree-sitter | degraded
    subtree_hint: str | None = None


@dataclasses.dataclass
class JudgeResult:
    verdict: str                  # SAME | DIVERGES
    confidence: str               # HIGH | MEDIUM | LOW
    divergences: list[dict]
    ast_fingerprint_sample_a: str
    ast_fingerprint_sample_b: str
    degraded_files: list[str]


def _sha(b: bytes) -> str:
    return "sha256:" + hashlib.sha256(b).hexdigest()


def _python_fingerprint(src: str) -> str | None:
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return None
    dumped = ast.dump(tree, annotate_fields=False, indent=None)
    return _sha(dumped.encode())


def _tree_sitter_fingerprint(src: bytes, ext: str) -> tuple[str | None, str]:
    """Return (fingerprint_or_none, mode). mode is 'tree-sitter' or 'degraded'."""
    lang_name = _TS_EXT_TO_LANG.get(ext)
    if not lang_name:
        return None, "degraded"
    try:
        from tree_sitter import Parser  # type: ignore[import-not-found]
        from tree_sitter_language_pack import get_language  # type: ignore[import-not-found]
    except ImportError:
        return None, "degraded"
    try:
        lang = get_language(lang_name)
    except (LookupError, AttributeError):
        return None, "degraded"
    parser = Parser()
    parser.language = lang
    try:
        root = parser.parse(src).root_node
    except Exception:  # noqa: BLE001
        return None, "degraded"

    def tup(node) -> Any:
        return (node.type, tuple(tup(c) for c in node.children))

    return _sha(repr(tup(root)).encode()), "tree-sitter"


_WS_RE = re.compile(r"\s+")
_PY_COMMENT_RE = re.compile(r"#[^\n]*")
_C_LINE_COMMENT_RE = re.compile(r"//[^\n]*")
_C_BLOCK_COMMENT_RE = re.compile(r"/\*.*?\*/", re.DOTALL)


def _degraded_fingerprint(src: str, ext: str) -> str:
    s = src
    if ext in (".py",):
        s = _PY_COMMENT_RE.sub("", s)
    elif ext in _TS_EXT_TO_LANG or ext in (".java", ".cs", ".scala", ".dart"):
        s = _C_BLOCK_COMMENT_RE.sub("", s)
        s = _C_LINE_COMMENT_RE.sub("", s)
    s = _WS_RE.sub(" ", s).strip()
    return _sha(s.encode())


def judge(sample_a_root: Path, sample_b_root: Path,
          touched_files: list[str]) -> JudgeResult:
    """Compare two implementer samples.

    sample_{a,b}_root are the sub-worktree roots
    (e.g. .forge/votes/<task_id>/sample_1). touched_files are repo-relative.
    """
    diffs: list[FileDiff] = []
    degraded: list[str] = []
    agg_a, agg_b = hashlib.sha256(), hashlib.sha256()

    for rel in sorted(touched_files):
        a = sample_a_root / rel
        b = sample_b_root / rel
        if a.exists() != b.exists():
            diffs.append(FileDiff(rel, "DIVERGES", "file-presence",
                                  f"file present in only one sample: {rel}"))
            continue
        if not a.exists():
            continue
        ext = a.suffix.lower()
        src_a = a.read_bytes()
        src_b = b.read_bytes()

        fa: str | None
        fb: str | None
        mode: str
        if ext == ".py":
            fa = _python_fingerprint(src_a.decode(errors="replace"))
            fb = _python_fingerprint(src_b.decode(errors="replace"))
            mode = "ast"
            if fa is None or fb is None:
                # parse failure -> degraded
                fa = _degraded_fingerprint(src_a.decode(errors="replace"), ext)
                fb = _degraded_fingerprint(src_b.decode(errors="replace"), ext)
                mode = "degraded"
                degraded.append(rel)
        elif ext in _TS_EXT_TO_LANG:
            fa, tsmode_a = _tree_sitter_fingerprint(src_a, ext)
            fb, tsmode_b = _tree_sitter_fingerprint(src_b, ext)
            if fa is None or fb is None or tsmode_a == "degraded" or tsmode_b == "degraded":
                fa = _degraded_fingerprint(src_a.decode(errors="replace"), ext)
                fb = _degraded_fingerprint(src_b.decode(errors="replace"), ext)
                mode = "degraded"
                degraded.append(rel)
            else:
                mode = "tree-sitter"
        else:
            fa = _degraded_fingerprint(src_a.decode(errors="replace"), ext)
            fb = _degraded_fingerprint(src_b.decode(errors="replace"), ext)
            mode = "degraded"
            degraded.append(rel)

        verdict = "SAME" if fa == fb else "DIVERGES"
        diffs.append(FileDiff(rel, verdict, mode,
                              None if verdict == "SAME" else f"{mode} fingerprint mismatch"))
        agg_a.update((rel + ":" + (fa or "")).encode())
        agg_b.update((rel + ":" + (fb or "")).encode())

    overall = "SAME" if all(d.verdict == "SAME" for d in diffs) else "DIVERGES"
    all_degraded = degraded and len(degraded) == len(diffs)
    confidence = "LOW" if all_degraded else ("MEDIUM" if degraded else "HIGH")

    return JudgeResult(
        verdict=overall,
        confidence=confidence,
        divergences=[
            {"file": d.path,
             "subtree": d.subtree_hint or "",
             "severity": "structural" if d.mode != "degraded" else "textual"}
            for d in diffs if d.verdict == "DIVERGES"
        ],
        ast_fingerprint_sample_a="sha256:" + agg_a.hexdigest(),
        ast_fingerprint_sample_b="sha256:" + agg_b.hexdigest(),
        degraded_files=degraded,
    )
