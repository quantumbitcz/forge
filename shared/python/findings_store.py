"""Helper API for the findings store. See shared/findings-store.md."""
from __future__ import annotations

import json
import pathlib
import sys
from typing import Iterable


def _ensure_dir(root: pathlib.Path) -> None:
    root.mkdir(parents=True, exist_ok=True)


def append_finding(root: pathlib.Path, reviewer: str, finding: dict) -> None:
    """Append one finding to <root>/<reviewer>.jsonl. LF line endings."""
    _ensure_dir(root)
    path = root / f"{reviewer}.jsonl"
    line = json.dumps(finding, separators=(",", ":"), ensure_ascii=False)
    with path.open("a", encoding="utf-8", newline="\n") as fh:
        fh.write(line + "\n")


def _decode_text(path: pathlib.Path) -> str:
    """Read file as UTF-8 with replacement, so non-UTF-8 bytes degrade to malformed lines."""
    return path.read_bytes().decode("utf-8", errors="replace")


def read_peers(root: pathlib.Path, exclude_reviewer: str) -> Iterable[dict]:
    """Yield parsed findings from every *.jsonl in root except <exclude_reviewer>.jsonl.

    Malformed lines are skipped with a stderr warning.
    """
    if not root.exists():
        return
    for path in sorted(root.glob("*.jsonl")):
        if path.stem == exclude_reviewer:
            continue
        for lineno, raw in enumerate(_decode_text(path).splitlines(), 1):
            if not raw.strip():
                continue
            try:
                yield json.loads(raw)
            except json.JSONDecodeError as exc:
                print(
                    f"WARNING findings-store malformed line "
                    f"reviewer={path.stem} line {lineno}: {exc}",
                    file=sys.stderr,
                )


def _tiebreak(a: dict, b: dict) -> dict:
    """Winner between two findings with the same dedup_key."""
    sev_order = {"CRITICAL": 3, "WARNING": 2, "INFO": 1}
    conf_order = {"HIGH": 3, "MEDIUM": 2, "LOW": 1}
    if sev_order[a["severity"]] != sev_order[b["severity"]]:
        return a if sev_order[a["severity"]] > sev_order[b["severity"]] else b
    if conf_order[a["confidence"]] != conf_order[b["confidence"]]:
        return a if conf_order[a["confidence"]] > conf_order[b["confidence"]] else b
    return a if a["reviewer"] <= b["reviewer"] else b


def reduce_findings(root: pathlib.Path, writer_glob: str = "*.jsonl") -> list[dict]:
    """Reduce all lines matching writer_glob under root into a canonical list.

    See shared/findings-store.md §8 for the reducer contract.
    """
    if not root.exists():
        return []
    by_key: dict[str, dict] = {}
    seen_by: dict[str, set[str]] = {}
    for path in sorted(root.glob(writer_glob)):
        for lineno, raw in enumerate(_decode_text(path).splitlines(), 1):
            if not raw.strip():
                continue
            try:
                f = json.loads(raw)
            except json.JSONDecodeError as exc:
                print(
                    f"WARNING findings-store malformed line "
                    f"reviewer={path.stem} line {lineno}: {exc}",
                    file=sys.stderr,
                )
                continue
            key = f["dedup_key"]
            sb = seen_by.setdefault(key, set())
            sb.update(f.get("seen_by", []))
            sb.add(f["reviewer"])
            if key not in by_key:
                by_key[key] = f
            else:
                by_key[key] = _tiebreak(by_key[key], f)
    out = []
    for key, f in by_key.items():
        f = dict(f)
        f["seen_by"] = sorted(seen_by[key] - {f["reviewer"]})
        out.append(f)
    return out
