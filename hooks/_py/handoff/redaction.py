"""Redaction wrapper — pipes handoff text through data-classification rules before write.

Fail-closed: any redactor exception propagates. The writer must NOT write an
unredacted file; it must abort and log ERROR.
"""
from __future__ import annotations

import re

# Minimal inline rules so this module is self-contained and testable without
# a running data-classification service. Full integration with
# shared/data-classification.md can replace these patterns once the shared
# runtime exposes a Python entrypoint.
_PATTERNS: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"sk-[a-zA-Z0-9_-]{16,}"), "[REDACTED:api_key]"),
    (re.compile(r"Bearer\s+[A-Za-z0-9._-]{16,}"), "Bearer [REDACTED:token]"),
    (re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"), "[REDACTED:email]"),
    (re.compile(r"(?i)password\s*[:=]\s*\S+"), "password: [REDACTED:password]"),
    (re.compile(r"\b(?:ghp|gho|ghs|ghu)_[A-Za-z0-9]{20,}"), "[REDACTED:gh_token]"),
]


def _redact_impl(text: str) -> str:
    out = text
    for pat, repl in _PATTERNS:
        out = pat.sub(repl, out)
    return out


def redact_handoff_text(text: str) -> str:
    """Apply redaction. Raises on redactor failure — writer is expected to fail-closed."""
    return _redact_impl(text)
