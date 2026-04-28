"""Structural AST diff for Phase 7 F36 voting.

Two implementations compared via (a) stdlib `ast` for Python and (b)
`tree-sitter-language-pack` 1.6.3+ for the supported set. Falls back to
whitespace-normalized textual diff for unsupported languages or on parse
failure.

Pure functions — no IO beyond reading the two sample files. Orchestrator
wires up the agent dispatch; this module is the engine.

NOTE on diff semantics: this judge compares STRUCTURE, not behavior. For
Python that means comparing ``ast.dump(annotate_fields=False, indent=None)``
output of the two trees; for tree-sitter languages it means comparing the
serialized concrete-syntax tree. Two implementations that are logically
equivalent but differ in operand order, import order, or
present/absent docstrings WILL register as ``DIVERGES`` — by design. The
F36 voting gate uses this signal to trigger a tiebreak; the tiebreak
reconciles benign rewrites without any further judgment from this module.
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

# Defensive fallback: when the primary tree-sitter language for an extension
# is unavailable (e.g. the pack ships ``typescript`` but not the separate
# ``tsx`` grammar on a given platform), retry with the listed alternative.
_TS_LANG_FALLBACK: dict[str, str] = {
    "tsx": "typescript",
    "kotlin": "kotlin",
}


@dataclasses.dataclass(frozen=True)
class FileDiff:
    path: str
    verdict: str                  # SAME | DIVERGES
    mode: str                     # ast | tree-sitter | degraded | file-presence | io-error
    subtree_hint: str | None = None


@dataclasses.dataclass(frozen=True)
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


def _resolve_ts_language(lang_name: str) -> Any:
    """Look up a tree-sitter grammar; on failure retry the configured
    fallback (``tsx`` -> ``typescript``, etc.) before giving up."""
    from tree_sitter_language_pack import get_language  # type: ignore[import-not-found]

    try:
        return get_language(lang_name)
    except (LookupError, AttributeError):
        fallback = _TS_LANG_FALLBACK.get(lang_name)
        if fallback and fallback != lang_name:
            try:
                return get_language(fallback)
            except (LookupError, AttributeError):
                return None
        return None


def _tree_sitter_fingerprint(src: bytes, ext: str) -> tuple[str | None, str]:
    """Return (fingerprint_or_none, mode). mode is 'tree-sitter' or 'degraded'."""
    lang_name = _TS_EXT_TO_LANG.get(ext)
    if not lang_name:
        return None, "degraded"
    try:
        from tree_sitter import Parser  # type: ignore[import-not-found]
    except ImportError:
        return None, "degraded"
    lang = _resolve_ts_language(lang_name)
    if lang is None:
        return None, "degraded"
    try:
        # Constructor form (tree-sitter >= 0.22) — avoids the deprecated
        # ``parser.language = lang`` property assignment that raises
        # AttributeError on the newer API surface.
        parser = Parser(lang)
    except (TypeError, AttributeError):
        # Older API: fall back to property assignment.
        try:
            parser = Parser()
            parser.language = lang  # type: ignore[assignment]
        except (TypeError, AttributeError):
            log.debug("tree_sitter_parser_init_failed", extra={"ext": ext})
            return None, "degraded"
    try:
        root = parser.parse(src).root_node
    except Exception:  # noqa: BLE001 — third-party C-extension parse can raise broadly
        log.debug("tree_sitter_parse_failed", extra={"ext": ext})
        return None, "degraded"

    # Tree-sitter grammars vary in whether comments and similar trivia are
    # exposed as ``extras`` on the parent or threaded inline as children.
    # tree-sitter-language-pack 1.6.2 (the current floor) inlines TS/JS
    # comments under ``program``; 1.6.3+ filters them. Normalize across
    # versions by stripping a small set of trivia node types ourselves so
    # the structural fingerprint is stable across pack versions.
    _TRIVIA_TYPES = frozenset({"comment", "line_comment", "block_comment"})

    def tup(node: Any) -> tuple:
        """Iterative DFS serialization of the CST.

        Recursion blows the Python stack on deeply-nested files (e.g. long
        chained method calls in generated code); the iterative form uses
        the heap and tolerates arbitrarily deep trees.
        """
        # Postorder traversal via explicit stack: a sentinel marker
        # distinguishes the "enter" visit (push children, schedule exit) from
        # the "exit" visit (collect children's results into a tuple).
        sentinel = object()
        results: list[Any] = []
        order: list[tuple[Any, Any]] = [(node, sentinel)]
        while order:
            current, marker = order.pop()
            if marker is sentinel:
                # First visit: schedule the exit then queue children for entry.
                # Strip trivia so whitespace-only / comment-only edits hash equal.
                children = [c for c in current.children if c.type not in _TRIVIA_TYPES]
                order.append((current, children))
                # Push children in reverse so leftmost is processed first.
                for child in reversed(children):
                    order.append((child, sentinel))
            else:
                children = marker
                # Pop one result per child (in original order — they were
                # appended left-to-right because of the reverse-push trick).
                child_count = len(children)
                if child_count:
                    child_tuples = results[-child_count:]
                    del results[-child_count:]
                else:
                    child_tuples = []
                results.append((current.type, tuple(child_tuples)))
        return results[-1]

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

    Diff is **syntactic** (post-``ast.parse`` for Python; CST hash for
    tree-sitter languages), NOT semantic. Logically equivalent code with
    reordered operands, reordered imports, or added/removed docstrings WILL
    register as ``DIVERGES`` — this is acceptable because the F36 tiebreak
    reconciles benign rewrites.
    """
    if not touched_files:
        raise ValueError("judge() requires at least one touched file")
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
        try:
            src_a = a.read_bytes()
            src_b = b.read_bytes()
        except OSError as e:
            log.debug("diff_judge_io_error", extra={"file": rel, "error": str(e)})
            diffs.append(FileDiff(rel, "DIVERGES", "io-error", str(e)))
            continue

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
    # Confidence rules:
    #   - all comparisons were file-presence-only (we never opened a single
    #     file) -> LOW; the verdict above is structurally meaningful but the
    #     judge has no opinion on the contents that ARE present.
    #   - any degraded comparison -> MEDIUM (or LOW if every file was degraded).
    #   - otherwise -> HIGH.
    file_presence_only = all(d.mode == "file-presence" for d in diffs) if diffs else False
    if file_presence_only:
        confidence = "LOW"
    elif degraded and len(degraded) == len([d for d in diffs if d.mode != "file-presence"]):
        confidence = "LOW"
    elif degraded:
        confidence = "MEDIUM"
    else:
        confidence = "HIGH"

    return JudgeResult(
        verdict=overall,
        confidence=confidence,
        divergences=[
            {"file": d.path,
             "subtree": d.subtree_hint or "",
             "severity": "structural" if d.mode not in ("degraded", "io-error", "file-presence") else "textual"}
            for d in diffs if d.verdict == "DIVERGES"
        ],
        ast_fingerprint_sample_a=_sha(agg_a.digest()),
        ast_fingerprint_sample_b=_sha(agg_b.digest()),
        degraded_files=degraded,
    )
