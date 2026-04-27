"""Extract REVIEW-tier registry slice from shared/agents.md for orchestrator injection."""
from __future__ import annotations

import pathlib
import re


def extract_review_tier_slice(agents_md: pathlib.Path) -> list[dict]:
    """Return [{'name': 'fg-411-security-reviewer', 'domain': 'security ...'}, ...]."""
    text = agents_md.read_text(encoding="utf-8")
    out = []
    # Match rows in §Registry whose name begins with fg-41
    for m in re.finditer(r"\|\s*`(fg-41\d-[a-z-]+)`\s*\|\s*([^|]+)\|", text):
        name = m.group(1).strip()
        domain = m.group(2).strip()
        out.append({"name": name, "domain": domain})
    return out
