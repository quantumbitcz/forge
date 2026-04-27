"""Extract REVIEW-tier registry slice from shared/agents.md for orchestrator injection."""
from __future__ import annotations

import pathlib
import re

# Section markers in shared/agents.md. Slice is bounded between these to
# avoid matching identical agent rows that appear in earlier tables (e.g.,
# the Tier-4 list at §Tier 4 — None or the §Conditional Agents matrix where
# columns differ). The §Registry table is the canonical source.
_REGISTRY_START = re.compile(r"^##\s+Registry\s*$", re.MULTILINE)
_REGISTRY_END = re.compile(r"^##\s+Tier Definitions\s*$", re.MULTILINE)


def extract_review_tier_slice(agents_md: pathlib.Path) -> list[dict]:
    """Return [{'name': 'fg-411-security-reviewer', 'domain': 'Security'}, ...].

    Scoped strictly to the §Registry section. Each row's 5th column
    (Category) becomes the domain. Returns one entry per fg-41* reviewer.
    """
    text = agents_md.read_text(encoding="utf-8")

    start_match = _REGISTRY_START.search(text)
    if not start_match:
        return []
    end_match = _REGISTRY_END.search(text, start_match.end())
    end_pos = end_match.start() if end_match else len(text)
    section = text[start_match.end():end_pos]

    out: list[dict] = []
    seen: set[str] = set()
    # Registry rows: | fg-NNN-name | Tier | Dispatches? | Stage | Category |
    # Names are bare (no backticks) in §Registry.
    row_re = re.compile(
        r"\|\s*(fg-41\d-[a-z-]+)\s*\|\s*\d+\s*\|\s*[^|]+\|\s*[^|]+\|\s*([^|]+)\|"
    )
    for m in row_re.finditer(section):
        name = m.group(1).strip()
        if name in seen:
            continue
        seen.add(name)
        domain = m.group(2).strip()
        out.append({"name": name, "domain": domain})
    return out
