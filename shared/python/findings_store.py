"""Helper API for the findings store. See shared/findings-store.md."""
from __future__ import annotations

import json
import pathlib
import sys
from typing import Callable, Iterable

try:  # Optional dependency. When absent, schema validation is skipped silently.
    import jsonschema as _jsonschema  # type: ignore[import-untyped]
except ImportError:  # pragma: no cover - exercised on minimal environments
    _jsonschema = None  # type: ignore[assignment]


_SCHEMA_PATH = (
    pathlib.Path(__file__).resolve().parents[1]
    / "checks"
    / "findings-schema.json"
)


def _load_validator() -> Callable[[dict], None] | None:
    """Return a validator callable bound to findings-schema.json, or None.

    The callable raises jsonschema.ValidationError on schema-invalid input.
    Returns None when jsonschema is missing or the schema cannot be loaded;
    callers must treat that as "validation skipped".
    """
    if _jsonschema is None or not _SCHEMA_PATH.exists():
        return None
    try:
        schema = json.loads(_SCHEMA_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):  # pragma: no cover
        return None
    validator = _jsonschema.Draft202012Validator(schema)
    return validator.validate


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


_SEV_ORDER = {"CRITICAL": 3, "WARNING": 2, "INFO": 1}
_CONF_ORDER = {"HIGH": 3, "MEDIUM": 2, "LOW": 1}


def _sev_rank(finding: dict) -> int:
    """Severity rank, defaulting to INFO for missing or unknown values."""
    return _SEV_ORDER.get(finding.get("severity", "INFO"), _SEV_ORDER["INFO"])


def _conf_rank(finding: dict) -> int:
    """Confidence rank, defaulting to LOW for missing or unknown values."""
    return _CONF_ORDER.get(finding.get("confidence", "LOW"), _CONF_ORDER["LOW"])


def _tiebreak(a: dict, b: dict) -> dict:
    """Winner between two findings with the same dedup_key.

    Tolerates missing or unknown severity/confidence values by treating them
    as the lowest priority bucket (INFO/LOW). This keeps the reducer alive
    on schema-loose lines that still validated as JSON; schema enforcement
    happens in reduce_findings via jsonschema (when available).
    """
    a_sev, b_sev = _sev_rank(a), _sev_rank(b)
    if a_sev != b_sev:
        return a if a_sev > b_sev else b
    a_conf, b_conf = _conf_rank(a), _conf_rank(b)
    if a_conf != b_conf:
        return a if a_conf > b_conf else b
    return a if a.get("reviewer", "") <= b.get("reviewer", "") else b


def reduce_findings(root: pathlib.Path, writer_glob: str = "*.jsonl") -> list[dict]:
    """Reduce all lines matching writer_glob under root into a canonical list.

    See shared/findings-store.md §8 for the reducer contract.

    Schema-invalid lines are skipped with a stderr WARNING (per fg-400.md §5.1b)
    when jsonschema is available. When it isn't, validation is silently skipped
    and only structurally required fields (dedup_key, reviewer) gate inclusion.
    """
    if not root.exists():
        return []
    validate = _load_validator()
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
            if validate is not None:
                try:
                    validate(f)
                except _jsonschema.ValidationError as exc:  # type: ignore[union-attr]
                    print(
                        f"WARNING findings-store schema-invalid line "
                        f"reviewer={path.stem} line {lineno}: {exc.message}",
                        file=sys.stderr,
                    )
                    continue
            if "dedup_key" not in f or "reviewer" not in f:
                print(
                    f"WARNING findings-store missing required field "
                    f"reviewer={path.stem} line {lineno}: dedup_key/reviewer absent",
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
