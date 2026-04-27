"""One-shot migration: shared/learnings/*.md hybrid-v1 → schema v2.

Runs once, committed, then deleted in a follow-up commit (per forge no-shim
policy). Idempotent: re-running on a v2 file is a no-op.

Usage:
    python scripts/migrate_learnings_schema.py --path shared/learnings
    python scripts/migrate_learnings_schema.py --path ~/.claude/forge-learnings
"""
from __future__ import annotations

import argparse
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

CONFIDENCE_MAP = {"HIGH": 0.85, "MEDIUM": 0.65, "LOW": 0.45}
# Legacy legend drift: the existing shared/learnings/spring.md frontmatter carries an
# in-file comment block claiming `HIGH → 0.95, MEDIUM → 0.75, LOW → 0.5, ARCHIVED → 0.3`.
# That legend predates Phase 4; the current canonical mapping is CONFIDENCE_MAP above
# (HIGH=0.85, MEDIUM=0.65, LOW=0.45). The migrator rewrites the ENTIRE frontmatter block
# (see `_parse_file_frontmatter` + the v2 composition at the bottom of `migrate_file`),
# so the stale legend comment is dropped on migration. Downstream v2 files carry no
# human-readable legend at all — the mapping lives in code only.
#
# If a legacy comment survives migration (e.g., because a human kept a hybrid file that
# the migrator could not parse), the migrator emits a WARNING naming the file.
HALF_LIFE_BY_TIER = {
    "auto-discovered": 14,
    "cross-project": 30,
    "canonical": 90,
}
DEFAULT_APPLIES_TO = ["planner", "implementer", "reviewer.code"]

FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)
ITEM_HEADING_RE = re.compile(r"^### (.+?)$", re.MULTILINE)
TOKEN_ID_RE = re.compile(r"^([A-Z][A-Z0-9-]+-\d+):\s*(.+)$")
FIELD_RE = re.compile(r"^\s*[-*]\s+\*\*(\w[\w\s]*)\*\*:\s*(.+)$", re.MULTILINE)


def _iso(ts: float) -> str:
    return datetime.fromtimestamp(ts, tz=timezone.utc).isoformat().replace(
        "+00:00", "Z"
    )


def _slug(text: str) -> str:
    s = text.lower().strip()
    s = re.sub(r"[^a-z0-9]+", "-", s)
    return s.strip("-")


def _parse_confidence(text: str) -> float | None:
    m = re.search(r"\*\*Confidence:\*\*\s*(HIGH|MEDIUM|LOW)", text, re.IGNORECASE)
    if not m:
        return None
    return CONFIDENCE_MAP[m.group(1).upper()]


def _parse_hit_count(text: str) -> int:
    m = re.search(r"\*\*Hit count:\*\*\s*(\d+)", text, re.IGNORECASE)
    return int(m.group(1)) if m else 0


def _parse_domain(text: str) -> str | None:
    m = re.search(r"\*\*Domain:\*\*\s*(\S+)", text, re.IGNORECASE)
    return m.group(1).strip().rstrip(",") if m else None


def _parse_file_frontmatter(raw: str) -> tuple[dict, str]:
    m = FRONTMATTER_RE.match(raw)
    if not m:
        return ({}, raw)
    fm_text = m.group(1)
    rest = raw[m.end():]
    fm: dict = {}
    for line in fm_text.splitlines():
        if ":" not in line or line.strip().startswith("#"):
            continue
        key, _, value = line.partition(":")
        fm[key.strip()] = value.strip().strip('"').strip("'")
    return (fm, rest)


def _already_v2(fm: dict) -> bool:
    return fm.get("schema_version") in ("2", 2)


def _derive_id(heading: str) -> tuple[str, str]:
    """Return (id, display_heading_text)."""
    m = TOKEN_ID_RE.match(heading.strip())
    if m:
        return (m.group(1).lower(), heading)
    return (_slug(heading), heading)


def _domain_tags(domain_line: str | None, filename_stem: str) -> list[str]:
    tags: list[str] = []
    if domain_line:
        tags.append(domain_line.lower())
    for part in filename_stem.split("-"):
        if part and part.lower() not in tags:
            tags.append(part.lower())
    # de-dup, preserve order
    seen: set[str] = set()
    out: list[str] = []
    for t in tags:
        if t not in seen:
            seen.add(t)
            out.append(t)
    return out


def _render_item(item: dict) -> str:
    def _q(v) -> str:
        if v is None:
            return "null"
        if isinstance(v, bool):
            return "true" if v else "false"
        if isinstance(v, (int, float)):
            return str(v)
        if isinstance(v, list):
            return "[" + ", ".join(_q(x) for x in v) + "]"
        return f'"{v}"'

    lines = [
        f"  - id: {_q(item['id'])}",
        f"    base_confidence: {_q(item['base_confidence'])}",
        f"    half_life_days: {_q(item['half_life_days'])}",
        f"    applied_count: {_q(item['applied_count'])}",
        f"    last_applied: {_q(item['last_applied'])}",
        f"    first_seen: {_q(item['first_seen'])}",
        f"    false_positive_count: {_q(item['false_positive_count'])}",
        f"    last_false_positive_at: {_q(item['last_false_positive_at'])}",
        f"    pre_fp_base: {_q(item['pre_fp_base'])}",
        f"    applies_to: {_q(item['applies_to'])}",
        f"    domain_tags: {_q(item['domain_tags'])}",
        f"    source: {_q(item['source'])}",
        f"    archived: {_q(item['archived'])}",
        f"    body_ref: {_q(item['body_ref'])}",
    ]
    return "\n".join(lines)


def _inject_anchors(body: str, ids_by_heading: dict[str, str]) -> str:
    out_lines: list[str] = []
    for line in body.splitlines(keepends=True):
        stripped = line.rstrip("\n")
        m = ITEM_HEADING_RE.match(stripped)
        if m and m.group(1) in ids_by_heading:
            out_lines.append(line)
            # avoid re-injecting anchor on idempotent run
            anchor = f'<a id="{ids_by_heading[m.group(1)]}"></a>\n'
            next_idx = len(out_lines)
            out_lines.append(anchor)
            continue
        out_lines.append(line)
    # Collapse duplicate adjacent anchors (idempotency):
    text = "".join(out_lines)
    text = re.sub(
        r'(<a id="([^"]+)"></a>\n)(?:<a id="\2"></a>\n)+',
        r"\1",
        text,
    )
    return text


def migrate_file(path: Path) -> bool:
    raw = path.read_text(encoding="utf-8")
    fm, body = _parse_file_frontmatter(raw)
    if _already_v2(fm):
        return False  # no-op

    tier = fm.get("decay_tier", "cross-project")
    default_base = float(fm.get("default_base_confidence", "0.75"))
    last_success = fm.get("last_success_at") or None
    last_fp = fm.get("last_false_positive_at") or None
    if last_fp == "null":
        last_fp = None

    first_seen_iso = _iso(path.stat().st_mtime)

    # Split body into item blocks by ### headings.
    headings = list(ITEM_HEADING_RE.finditer(body))
    items_out: list[dict] = []
    ids_by_heading: dict[str, str] = {}
    for idx, m in enumerate(headings):
        heading_text = m.group(1)
        start = m.end()
        end = headings[idx + 1].start() if idx + 1 < len(headings) else len(body)
        block = body[start:end]
        item_id, display = _derive_id(heading_text)
        ids_by_heading[heading_text] = item_id

        conf = _parse_confidence(block)
        base_conf = conf if conf is not None else default_base
        applied = _parse_hit_count(block)
        domain = _parse_domain(block)
        tags = _domain_tags(domain, path.stem)

        archived = "(archived)" in heading_text.lower() or tier == "archived"
        last_applied_val = last_success if applied > 0 else None
        last_fp_val = last_fp if (applied == 0 and last_fp) else None

        items_out.append({
            "id": item_id,
            "base_confidence": base_conf,
            "half_life_days": HALF_LIFE_BY_TIER.get(tier, 30),
            "applied_count": applied,
            "last_applied": last_applied_val,
            "first_seen": first_seen_iso,
            "false_positive_count": 0,
            "last_false_positive_at": last_fp_val,
            "pre_fp_base": None,
            "applies_to": list(DEFAULT_APPLIES_TO),
            "domain_tags": tags,
            "source": tier,
            "archived": archived,
            "body_ref": f"#{item_id}",
        })

    body_with_anchors = _inject_anchors(body, ids_by_heading)

    # Compose v2 frontmatter, preserving recognised file-level keys.
    fm_lines = ["---", "schema_version: 2"]
    for key in ("decay_tier", "default_base_confidence",
                "last_success_at", "last_false_positive_at"):
        if key in fm:
            val = fm[key]
            quoted = f'"{val}"' if key.endswith("_at") and val != "null" else val
            fm_lines.append(f"{key}: {quoted}")
    fm_lines.append("items:")
    for it in items_out:
        fm_lines.append(_render_item(it))
    fm_lines.append("---")
    new_frontmatter = "\n".join(fm_lines) + "\n"

    path.write_text(new_frontmatter + body_with_anchors, encoding="utf-8")
    return True


LEGACY_LEGEND_RE = re.compile(r"HIGH\s*[→\->]+\s*0\.9[05]")  # matches HIGH→0.95 or HIGH→0.90


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Migrate learnings files to schema v2.")
    p.add_argument("--path", required=True,
                   help="Directory containing *.md learnings files.")
    args = p.parse_args(argv)
    root = Path(args.path).expanduser()
    if not root.is_dir():
        print(f"not a directory: {root}", file=sys.stderr)
        return 2
    count = 0
    legend_drift: list[Path] = []
    for md in sorted(root.glob("*.md")):
        if md.name == "README.md":
            continue
        if migrate_file(md):
            count += 1
            print(f"migrated: {md}")
        # Post-migration legend sanity: any surviving "HIGH→0.95" style mapping in the
        # file body is drift (the v2 frontmatter rewrites drop the legend; a surviving
        # instance means the legend was in the body, not the frontmatter).
        if LEGACY_LEGEND_RE.search(md.read_text(encoding="utf-8")):
            legend_drift.append(md)
    print(f"total migrated: {count}")
    if legend_drift:
        print(
            "WARNING: legacy HIGH→0.95 legend survives migration in "
            f"{len(legend_drift)} file(s); canonical mapping is HIGH=0.85. "
            "Update manually:",
            file=sys.stderr,
        )
        for p_ in legend_drift:
            print(f"  - {p_}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
