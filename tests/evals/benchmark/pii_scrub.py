"""PII scrubbing for benchmark corpus entries.

Inherits SEC-SECRET (API keys, private keys) and SEC-PII (email) detection
from shared/data-classification.md. Adds path/hostname/IP/fingerprint patterns
enumerated in spec §Data Model PII scrub.
"""

from __future__ import annotations

import re
from collections.abc import Iterable
from dataclasses import dataclass

# Auto-scrub (silent): tokens deterministically replaced, no user prompt needed.
_AUTO_PATTERNS: tuple[tuple[re.Pattern[str], str], ...] = (
    (re.compile(r"/Users/[^/\s]+"), "<redacted-home>"),
    (re.compile(r"/home/[^/\s]+"), "<redacted-home>"),
    (re.compile(r"C:\\Users\\[^\\]+"), r"<redacted-home>"),
    (re.compile(r"\b[\w-]+\.(?:internal|prod|production|corp|local)\b"), "<internal-host>"),
    (
        re.compile(
            r"\b(?:10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3})\b"
        ),
        "<private-ip>",
    ),
    (re.compile(r"SHA256:[A-Za-z0-9+/]{43}=?"), "<ssh-fp>"),
)

# Interactive (prompt user): patterns we cannot safely auto-redact.
_INTERACTIVE_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    (
        "api_key",
        re.compile(
            r"(?i)(?:api[_-]?key|apikey|secret[_-]?key|token|bearer)\s*[:=]\s*['\"][^'\"]{8,}"
        ),
    ),
    ("password", re.compile(r"(?i)(?:password|passwd)\s*[:=]\s*['\"][^'\"]{4,}")),
    ("private_key", re.compile(r"-----BEGIN (?:RSA |EC |DSA )?PRIVATE KEY-----")),
    ("email", re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b")),
)


@dataclass(frozen=True)
class Hit:
    kind: str
    span: tuple[int, int]
    text: str


def scrub(text: str) -> str:
    """Apply all auto-scrub substitutions. Idempotent."""
    for pat, repl in _AUTO_PATTERNS:
        text = pat.sub(repl, text)
    return text


def scan(text: str) -> Iterable[Hit]:
    """Yield interactive hits for operator-confirmed redaction in curate.py."""
    for kind, pat in _INTERACTIVE_PATTERNS:
        for m in pat.finditer(text):
            yield Hit(kind=kind, span=m.span(), text=m.group(0))
