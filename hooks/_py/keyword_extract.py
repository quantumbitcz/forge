"""Deterministic keyword extraction from requirement text.

No NLTK, spaCy, or other NLP deps. Embedded stopwords list.
"""
from __future__ import annotations

import re
from collections import OrderedDict

# Hard-coded English stopwords. ~180 words. Intentionally inline (no external file).
_STOPWORDS = frozenset("""
a about above after again against all am an and any are as at be because been before being
below between both but by could did do does doing down during each few for from further had
has have having he her here hers herself him himself his how i if in into is it its itself
just me more most my myself no nor not now of off on once only or other our ours ourselves
out over own same she should so some such than that the their theirs them themselves then
there these they this those through to too under until up very was we were what when where
which while who whom why will with you your yours yourself yourselves also can would might
may must shall should need needs needed make makes making made get gets got getting go goes
went going come comes came coming see sees saw seeing know knows knew want wants wanted
take takes took taken give gives gave given use uses used using say says said tell tells told
think thinks thought find finds found thing things way ways lot lots new old big small
""".split())

_TOKEN_RE = re.compile(r"[a-z0-9]+")


def extract_keywords(text: str, top_n: int = 20) -> list[str]:
    """Return up to `top_n` keywords by frequency, ties broken by first occurrence.

    Pipeline: lowercase -> tokenize on [a-z0-9]+ -> drop stopwords,
    len<3, and pure numerics -> keep top-N by (count desc, first-pos asc).
    """
    if not text or not text.strip():
        return []
    tokens = _TOKEN_RE.findall(text.lower())
    counts: OrderedDict[str, int] = OrderedDict()
    for t in tokens:
        if len(t) < 3:
            continue
        if t.isdigit():
            continue
        if t in _STOPWORDS:
            continue
        counts[t] = counts.get(t, 0) + 1
    # Sort by (-count, first-occurrence-index). OrderedDict preserves insertion order.
    ranked = sorted(counts.items(), key=lambda kv: (-kv[1], list(counts).index(kv[0])))
    return [k for k, _ in ranked[:top_n]]
