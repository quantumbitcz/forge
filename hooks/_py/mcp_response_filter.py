"""Forge MCP response filter (prompt-injection hardening).

Stdlib-only. Invoked before external data reaches an agent prompt.
See shared/untrusted-envelope.md for the contract.
"""
from __future__ import annotations

import hashlib
import json
import pathlib
import re
from datetime import datetime, timezone
from typing import Literal, TypedDict, Union

# ---- Constants --------------------------------------------------------------

MAX_ENVELOPE_BYTES = 65536      # 64 KiB
MAX_AGGREGATE_BYTES = 262144    # 256 KiB

_ROOT = pathlib.Path(__file__).resolve().parents[2]
PATTERNS_PATH = _ROOT / "shared" / "prompt-injection-patterns.json"
EVENTS_PATH = _ROOT / ".forge" / "security" / "injection-events.jsonl"

# Tier mapping must match shared/untrusted-envelope.md exactly.
# Loosening is a config error (enforced by the caller + PREFLIGHT).
TIER_TABLE: dict[str, Literal["silent", "logged", "confirmed"]] = {
    "mcp:linear": "logged",
    "mcp:slack": "logged",
    "mcp:figma": "logged",
    "mcp:github": "logged",
    "mcp:github:remote": "confirmed",
    "mcp:playwright": "confirmed",
    "mcp:context7": "silent",
    "wiki": "silent",
    "explore-cache": "logged",
    "plan-cache": "logged",
    "docs-discovery": "logged",
    "cross-project-learnings": "logged",
    "neo4j:project": "silent",
    "neo4j:remote": "confirmed",
    "webfetch": "confirmed",
    "deprecation-refresh": "confirmed",
}

# Sources that consumers are wired to pass through the filter.
# Structural test tier-mapping-complete.bats requires every entry to appear in
# shared/untrusted-envelope.md's Tier Mapping table.
CONSUMER_SOURCES = {
    "mcp:linear",
    "mcp:slack",
    "mcp:figma",
    "mcp:github",
    "mcp:github:remote",
    "mcp:playwright",
    "mcp:context7",
    "wiki",
    "explore-cache",
    "plan-cache",
    "docs-discovery",
    "cross-project-learnings",
    "neo4j:project",
    "neo4j:remote",
    "webfetch",
    "deprecation-refresh",
}


# ---- Types ------------------------------------------------------------------


class Finding(TypedDict):
    id: str           # registry category, e.g. "SEC-INJECTION-OVERRIDE"
    category: str     # pattern library category, e.g. "OVERRIDE"
    severity: str     # "INFO" | "WARNING" | "CRITICAL" | "BLOCK"
    pattern_id: str   # e.g. "INJ-OVERRIDE-001"


class FilterResult(TypedDict):
    action: Literal["wrap", "quarantine"]
    envelope: str | None
    findings: list[Finding]
    hash: str
    truncated: bool
    bytes_after_truncation: int


# ---- Exceptions -------------------------------------------------------------


class UnmappedSourceError(ValueError):
    """Raised when a caller passes a source not present in TIER_TABLE."""


# ---- Pattern loading (cached) -----------------------------------------------

_COMPILED: list[tuple[str, str, str, re.Pattern[str]]] | None = None


def _load_patterns() -> list[tuple[str, str, str, re.Pattern[str]]]:
    global _COMPILED
    if _COMPILED is None:
        data = json.loads(PATTERNS_PATH.read_text(encoding="utf-8"))
        _COMPILED = [
            (p["id"], p["category"], p["severity"], re.compile(p["pattern"]))
            for p in data["patterns"]
        ]
    return _COMPILED


# ---- Category → registry id --------------------------------------------------

CATEGORY_TO_REGISTRY = {
    "OVERRIDE": "SEC-INJECTION-OVERRIDE",
    "ROLE_HIJACK": "SEC-INJECTION-OVERRIDE",
    "SYSTEM_SPOOF": "SEC-INJECTION-OVERRIDE",
    "PROMPT_LEAK": "SEC-INJECTION-OVERRIDE",
    "EXFIL": "SEC-INJECTION-EXFIL",
    "TOOL_COERCION": "SEC-INJECTION-TOOL-MISUSE",
    "CREDENTIAL_SHAPED": "SEC-INJECTION-BLOCKED",
}


# ---- Public API -------------------------------------------------------------


def filter_response(
    source: str,
    origin: str | None,
    content: Union[str, bytes],
    run_id: str,
    agent: str,
) -> FilterResult:
    """Filter one ingress of external data; see module docstring."""
    if source not in TIER_TABLE:
        raise UnmappedSourceError(f"source not in tier table: {source!r}")

    raw_bytes = content.encode("utf-8") if isinstance(content, str) else bytes(content)
    raw_text = raw_bytes.decode("utf-8", errors="replace")
    digest = "sha256:" + hashlib.sha256(raw_bytes).hexdigest()

    findings: list[Finding] = []
    block_hit = False
    for pid, cat, sev, rx in _load_patterns():
        if rx.search(raw_text):
            findings.append({
                "id": CATEGORY_TO_REGISTRY[cat],
                "category": cat,
                "severity": sev,
                "pattern_id": pid,
            })
            if sev == "BLOCK":
                block_hit = True

    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    if block_hit:
        result: FilterResult = {
            "action": "quarantine",
            "envelope": None,
            "findings": findings,
            "hash": digest,
            "truncated": False,
            "bytes_after_truncation": len(raw_bytes),
        }
        _append_event(source, origin, digest, TIER_TABLE[source], findings,
                      "quarantine", agent, run_id, ts)
        return result

    # Truncate (on bytes, then re-decode)
    truncated = False
    if len(raw_bytes) > MAX_ENVELOPE_BYTES:
        elided = len(raw_bytes) - MAX_ENVELOPE_BYTES
        raw_text = raw_bytes[:MAX_ENVELOPE_BYTES].decode("utf-8", errors="replace")
        raw_text += f"\n[truncated, {elided} bytes elided]"
        truncated = True
        findings.append({
            "id": "SEC-INJECTION-TRUNCATED",
            "category": "TRUNCATED",
            "severity": "INFO",
            "pattern_id": "INJ-TRUNCATED-000",
        })

    escaped = raw_text.replace("</untrusted>", "</untrusted\u200B>")
    tier = TIER_TABLE[source]
    flags = sorted({x["category"].lower() for x in findings
                    if x["category"] not in ("TRUNCATED",)})
    attrs = [
        f'source="{source}"',
        f'origin="{origin or ""}"',
        f'classification="{tier}"',
        f'hash="{digest}"',
        f'ingress_ts="{ts}"',
    ]
    if flags:
        attrs.append(f'flags="{",".join(flags)}"')
    envelope = "<untrusted " + " ".join(attrs) + ">\n" + escaped + "\n</untrusted>"

    _append_event(source, origin, digest, tier, findings, "wrap", agent, run_id, ts)

    return {
        "action": "wrap",
        "envelope": envelope,
        "findings": findings,
        "hash": digest,
        "truncated": truncated,
        "bytes_after_truncation": min(len(raw_bytes), MAX_ENVELOPE_BYTES),
    }


def _append_event(source, origin, digest, tier, findings, action, agent, run_id, ts):
    EVENTS_PATH.parent.mkdir(parents=True, exist_ok=True)
    record = {
        "ts": ts,
        "source": source,
        "origin": origin or "",
        "hash": digest,
        "tier": tier,
        "findings": [
            {"id": fd["id"], "category": fd["category"], "severity": fd["severity"],
             "pattern_id": fd["pattern_id"]}
            for fd in findings
        ],
        "action": action,
        "agent": agent,
        "run_id": run_id,
    }
    with EVENTS_PATH.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(record, separators=(",", ":"), sort_keys=True) + "\n")
