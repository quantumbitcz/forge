"""Redaction wrapper — pipes handoff text through data-classification rules before write.

Covered secret classes:
- Anthropic API keys (sk-ant-*)
- Bearer tokens
- Email addresses
- password: / password= assignments
- GitHub tokens (ghp_/gho_/ghs_/ghu_)
- AWS access keys (AKIA*) and secret access keys
- JWTs (three-segment base64url)
- Slack tokens (xoxb/xoxp/xoxa/xoxr/xoxs)
- Private-key blocks (RSA, OpenSSH, EC, DSA, generic PRIVATE KEY)
- Generic env-style SECRET/TOKEN/API_KEY assignments

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
    # AWS access keys (AKIA... 20 chars total)
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "[REDACTED:aws_access_key]"),
    # AWS secret access keys (40 chars base64-ish) — matches env assignments to avoid false positives
    (re.compile(r"(?i)aws[_-]?secret[_-]?access[_-]?key\s*[:=]\s*[A-Za-z0-9/+=]{40}"), "aws_secret_access_key=[REDACTED:aws_secret]"),
    # JWTs (header.payload.signature, base64url)
    (re.compile(r"\beyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"), "[REDACTED:jwt]"),
    # Slack tokens (xoxb/xoxp/xoxa/xoxr/xoxs + dash + 10+ chars)
    (re.compile(r"xox[baprs]-[A-Za-z0-9-]{10,}"), "[REDACTED:slack_token]"),
    # Private-key blocks (RSA, OpenSSH, EC, DSA, generic PRIVATE KEY)
    (re.compile(r"-----BEGIN[ A-Z]+PRIVATE KEY-----[\s\S]*?-----END[ A-Z]+PRIVATE KEY-----"), "[REDACTED:private_key_block]"),
    # Generic SECRET/TOKEN/API_KEY env-style assignments (catches DATABASE_SECRET=foo, API_TOKEN=bar,
    # bare API_KEY=foo, etc.). Prefix before the base keyword is optional and must end in `_`.
    # Negative lookahead on `[REDACTED:` so this pattern does not re-redact values already
    # replaced by a more specific rule earlier in the pass (e.g. `Token: eyJ...` → JWT first).
    (re.compile(r"\b((?:[A-Z][A-Z0-9_]*_)?(?:SECRET|TOKEN|API[_-]?KEY|PASSWD))\s*[:=]\s*(?!\[REDACTED:)\S+"), r"\1=[REDACTED:generic_secret]"),
]


def _redact_impl(text: str) -> str:
    out = text
    for pat, repl in _PATTERNS:
        out = pat.sub(repl, out)
    return out


def redact_handoff_text(text: str) -> str:
    """Apply redaction. Raises on redactor failure — writer is expected to fail-closed."""
    return _redact_impl(text)
