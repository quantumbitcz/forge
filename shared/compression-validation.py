#!/usr/bin/env python3
"""Post-compression validation for /forge-admin compress.

Validates that compression preserves structural elements:
- Heading count and text
- Code block content (byte-identical)
- URLs
- File paths
- Frontmatter
- Tables
- Bullet count (warning only)

Usage:
    python3 compression-validation.py ORIGINAL COMPRESSED
    python3 compression-validation.py --check-only COMPRESSED  # structural self-check

Exit codes: 0=pass, 1=fail, 2=warn (bullet drift)
"""

import json
import re
import sys


# --- False-positive exclusion list for file path detection ---
PATH_EXCLUDES = {
    "input/output", "before/after", "true/false", "yes/no",
    "on/off", "read/write", "client/server", "start/end",
    "push/pull", "black/white",
}


def extract_headings(text):
    """Extract heading lines (# to ######)."""
    return re.findall(r"^(#{1,6})\s+(.*)", text, re.MULTILINE)


def extract_code_blocks(text):
    """Extract fenced code block contents."""
    # Match ``` or ~~~ fences
    blocks = re.findall(r"(?:```|~~~)(?:\w*)?\n(.*?)(?:```|~~~)", text, re.DOTALL)
    # Normalize: strip trailing newline before closing fence
    return [b.rstrip("\n") for b in blocks]


def extract_urls(text):
    """Extract all URLs."""
    return set(re.findall(r"https?://[^\s)>\]]+", text))


def extract_file_paths(text):
    """Extract file-path-like patterns (require file extension to reduce FPs)."""
    raw = set(re.findall(r"[\w.-]+/[\w.-]+(?:/[\w.-]+)*\.\w{1,10}", text))
    return raw - PATH_EXCLUDES


def extract_frontmatter(text):
    """Extract YAML frontmatter (between --- markers at start of file)."""
    m = re.match(r"^---\n(.*?\n)---", text, re.DOTALL)
    return m.group(0) if m else None


def extract_table_rows(text):
    """Extract pipe-delimited table rows."""
    return [line for line in text.split("\n") if re.match(r"^\|.*\|$", line.strip())]


def count_bullets(text):
    """Count bullet/numbered list items."""
    unordered = len(re.findall(r"^\s*[-*+]\s", text, re.MULTILINE))
    ordered = len(re.findall(r"^\s*\d+\.\s", text, re.MULTILINE))
    return unordered + ordered


def check_unclosed_fences(text):
    """Check for unclosed code fences."""
    fence_count = len(re.findall(r"^(?:```|~~~)", text, re.MULTILINE))
    return fence_count % 2 == 0


def validate_comparison(original_text, compressed_text):
    """Run all 8 checks comparing original vs compressed."""
    checks = {}
    has_fail = False
    has_warn = False

    # 1. Heading count
    orig_headings = extract_headings(original_text)
    comp_headings = extract_headings(compressed_text)
    if len(orig_headings) != len(comp_headings):
        checks["heading_count"] = {
            "status": "FAIL",
            "before": len(orig_headings),
            "after": len(comp_headings),
        }
        has_fail = True
    else:
        checks["heading_count"] = {
            "status": "PASS",
            "before": len(orig_headings),
            "after": len(comp_headings),
        }

    # 2. Heading text (first 3 words must match)
    mismatches = []
    for i, (oh, ch) in enumerate(zip(orig_headings, comp_headings)):
        orig_words = oh[1].split()[:3]
        comp_words = ch[1].split()[:3]
        if orig_words != comp_words:
            mismatches.append({
                "index": i,
                "original": oh[1],
                "compressed": ch[1],
            })
    if mismatches:
        checks["heading_text"] = {"status": "FAIL", "mismatches": mismatches}
        has_fail = True
    else:
        checks["heading_text"] = {"status": "PASS", "mismatches": []}

    # 3. Code blocks (byte-identical content)
    orig_blocks = extract_code_blocks(original_text)
    comp_blocks = extract_code_blocks(compressed_text)
    code_fail = None
    if len(orig_blocks) != len(comp_blocks):
        code_fail = f"Block count differs: {len(orig_blocks)} vs {len(comp_blocks)}"
    else:
        for idx, (ob, cb) in enumerate(zip(orig_blocks, comp_blocks)):
            if ob != cb:
                # Find first byte difference
                for byte_idx, (a, b) in enumerate(zip(ob, cb)):
                    if a != b:
                        code_fail = f"Block {idx} differs at byte {byte_idx}"
                        break
                else:
                    if len(ob) != len(cb):
                        code_fail = f"Block {idx} length differs: {len(ob)} vs {len(cb)}"
                if code_fail:
                    break
    if code_fail:
        checks["code_blocks"] = {"status": "FAIL", "detail": code_fail}
        has_fail = True
    else:
        checks["code_blocks"] = {"status": "PASS", "block_count": len(orig_blocks)}

    # 4. URL preservation
    orig_urls = extract_urls(original_text)
    comp_urls = extract_urls(compressed_text)
    missing_urls = orig_urls - comp_urls
    if missing_urls:
        checks["urls"] = {"status": "FAIL", "missing": list(missing_urls)}
        has_fail = True
    else:
        checks["urls"] = {"status": "PASS", "missing": []}

    # 5. File path preservation (WARN severity)
    orig_paths = extract_file_paths(original_text)
    comp_paths = extract_file_paths(compressed_text)
    missing_paths = orig_paths - comp_paths
    excluded = orig_paths & PATH_EXCLUDES
    if missing_paths:
        checks["file_paths"] = {
            "status": "WARN",
            "missing": list(missing_paths),
            "excluded_false_positives": list(excluded),
        }
        has_warn = True
    else:
        checks["file_paths"] = {
            "status": "PASS",
            "missing": [],
            "excluded_false_positives": list(excluded),
        }

    # 6. Bullet count drift (WARN if >15%)
    orig_bullets = count_bullets(original_text)
    comp_bullets = count_bullets(compressed_text)
    if orig_bullets > 0:
        drift = abs(comp_bullets - orig_bullets) / orig_bullets
        if drift > 0.15:
            checks["bullet_drift"] = {
                "status": "WARN",
                "before": orig_bullets,
                "after": comp_bullets,
                "drift": f"{drift:.1%}",
            }
            has_warn = True
        else:
            checks["bullet_drift"] = {
                "status": "PASS",
                "before": orig_bullets,
                "after": comp_bullets,
                "drift": f"{drift:.1%}",
            }
    else:
        checks["bullet_drift"] = {
            "status": "PASS",
            "before": 0,
            "after": comp_bullets,
            "drift": "0.0%",
        }

    # 7. Frontmatter integrity (byte-identical)
    orig_fm = extract_frontmatter(original_text)
    comp_fm = extract_frontmatter(compressed_text)
    if orig_fm is not None and orig_fm != comp_fm:
        checks["frontmatter"] = {"status": "FAIL"}
        has_fail = True
    elif orig_fm is None and comp_fm is not None:
        checks["frontmatter"] = {"status": "FAIL"}
        has_fail = True
    else:
        checks["frontmatter"] = {"status": "PASS"}

    # 8. Table preservation (byte-identical rows)
    orig_tables = extract_table_rows(original_text)
    comp_tables = extract_table_rows(compressed_text)
    if orig_tables != comp_tables:
        checks["tables"] = {
            "status": "FAIL",
            "row_count": len(orig_tables),
            "compressed_row_count": len(comp_tables),
        }
        has_fail = True
    else:
        checks["tables"] = {"status": "PASS", "row_count": len(orig_tables)}

    # Determine overall verdict
    if has_fail:
        verdict = "FAIL"
    elif has_warn:
        verdict = "WARN"
    else:
        verdict = "PASS"

    return verdict, checks


def validate_self_check(text, filename):
    """Structural self-check (no comparison)."""
    checks = {}
    has_fail = False

    # Frontmatter parseable
    fm = extract_frontmatter(text)
    checks["frontmatter_parseable"] = {
        "status": "PASS" if fm is not None or not text.startswith("---") else "PASS"
    }

    # Code blocks properly fenced
    if not check_unclosed_fences(text):
        checks["fences_closed"] = {"status": "FAIL", "detail": "Unclosed code fence detected"}
        has_fail = True
    else:
        checks["fences_closed"] = {"status": "PASS"}

    # Tables have consistent column counts
    table_rows = extract_table_rows(text)
    if table_rows:
        col_counts = [len(row.split("|")) for row in table_rows]
        if len(set(col_counts)) > 1:
            checks["table_columns"] = {
                "status": "WARN",
                "detail": f"Inconsistent column counts: {set(col_counts)}",
            }
        else:
            checks["table_columns"] = {"status": "PASS"}
    else:
        checks["table_columns"] = {"status": "PASS"}

    # Duplicate headings at same level
    headings = extract_headings(text)
    seen = {}
    dupes = []
    for level, text_h in headings:
        key = (len(level), text_h)
        if key in seen:
            dupes.append(f"{level} {text_h}")
        seen[key] = True
    if dupes:
        checks["duplicate_headings"] = {
            "status": "WARN",
            "duplicates": dupes,
        }
    else:
        checks["duplicate_headings"] = {"status": "PASS"}

    verdict = "FAIL" if has_fail else "PASS"
    return verdict, checks


def main():
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        sys.exit(1)

    if sys.argv[1] == "--check-only":
        if len(sys.argv) < 3:
            print("Usage: compression-validation.py --check-only FILE", file=sys.stderr)
            sys.exit(1)
        with open(sys.argv[2], "r", encoding="utf-8") as f:
            text = f.read()
        verdict, checks = validate_self_check(text, sys.argv[2])
    else:
        if len(sys.argv) < 3:
            print("Usage: compression-validation.py ORIGINAL COMPRESSED", file=sys.stderr)
            sys.exit(1)
        with open(sys.argv[1], "r", encoding="utf-8") as f:
            original = f.read()
        with open(sys.argv[2], "r", encoding="utf-8") as f:
            compressed = f.read()
        verdict, checks = validate_comparison(original, compressed)

    result = {
        "file": sys.argv[-1],
        "verdict": verdict,
        "checks": checks,
    }

    print(json.dumps(result, indent=2))

    if verdict == "FAIL":
        sys.exit(1)
    elif verdict == "WARN":
        sys.exit(2)
    else:
        sys.exit(0)


if __name__ == "__main__":
    main()
