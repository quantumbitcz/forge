#!/usr/bin/env python3
"""Measure input compression effectiveness by applying compression rules
from shared/input-compression.md programmatically via regex transforms.

Measures before/after word count and estimated token count (word * 1.3)
for each file type category. Outputs markdown table to stdout.

Usage:
    python3 measure.py [--repo-root PATH] [--output results.md]
    python3 measure.py --file path/to/file.md
"""

import argparse
import os
import re
import sys

MULTIPLIER = 1.3

# --- Compression rules from input-compression.md ---

# Articles to remove
ARTICLES = re.compile(r"\b(?:a|an|the)\b", re.IGNORECASE)

# Filler words to remove
FILLER = re.compile(
    r"\b(?:just|really|basically|actually|simply|essentially|generally)\b",
    re.IGNORECASE,
)

# Pleasantries to remove
PLEASANTRIES = re.compile(
    r"\b(?:sure|certainly|of course|happy to|I'd recommend)\b",
    re.IGNORECASE,
)

# Hedging phrases to remove
HEDGING = re.compile(
    r"\b(?:it might be worth|you could consider|it would be good to|perhaps|might)\b",
    re.IGNORECASE,
)

# Connective fluff to remove
CONNECTIVES = re.compile(
    r"\b(?:however|furthermore|additionally|in addition)\b",
    re.IGNORECASE,
)

# Imperative softeners to remove
SOFTENERS = re.compile(
    r"\b(?:you should|make sure to|remember to)\b",
    re.IGNORECASE,
)

# Redundant phrasing replacements
REDUNDANT_REPLACEMENTS = [
    (re.compile(r"\bin order to\b", re.IGNORECASE), "to"),
    (re.compile(r"\bmake sure to\b", re.IGNORECASE), "ensure"),
    (re.compile(r"\bthe reason is because\b", re.IGNORECASE), "because"),
    (re.compile(r"\bat the end of the day\b", re.IGNORECASE), ""),
]

# Synonym compression (short synonyms)
SYNONYM_REPLACEMENTS = [
    (re.compile(r"\bextensive\b", re.IGNORECASE), "big"),
    (re.compile(r"\bimplement a solution for\b", re.IGNORECASE), "fix"),
    (re.compile(r"\butilize\b", re.IGNORECASE), "use"),
    (re.compile(r"\bexecute\b", re.IGNORECASE), "run"),
    (re.compile(r"\bverify and validate\b", re.IGNORECASE), "check"),
]

# Regions to preserve (code blocks, frontmatter)
CODE_BLOCK_RE = re.compile(r"```[\s\S]*?```")
INLINE_CODE_RE = re.compile(r"`[^`]+`")
FRONTMATTER_RE = re.compile(r"^---[\s\S]*?---", re.MULTILINE)
URL_RE = re.compile(r"https?://\S+")
MARKDOWN_LINK_RE = re.compile(r"\[[^\]]*\]\([^)]+\)")


def _extract_preserved(text: str) -> tuple:
    """Extract preserved regions, replacing with placeholders."""
    placeholders = {}
    counter = [0]

    def _replace(match):
        key = f"__PRESERVE_{counter[0]}__"
        placeholders[key] = match.group(0)
        counter[0] += 1
        return key

    # Order matters: frontmatter first, then code blocks, then inline code
    for pattern in [FRONTMATTER_RE, CODE_BLOCK_RE, INLINE_CODE_RE, MARKDOWN_LINK_RE, URL_RE]:
        text = pattern.sub(_replace, text)

    return text, placeholders


def _restore_preserved(text: str, placeholders: dict) -> str:
    """Restore preserved regions from placeholders."""
    for key, value in placeholders.items():
        text = text.replace(key, value)
    return text


def apply_compression(text: str, level: int = 2) -> str:
    """Apply input compression rules at the given level.

    Level 1 (conservative): Remove articles, filler, pleasantries
    Level 2 (aggressive): Level 1 + hedging, connectives, softeners, synonyms
    Level 3 (ultra): Level 2 + more aggressive reduction
    """
    # Extract preserved regions
    text, placeholders = _extract_preserved(text)

    # Level 1: conservative
    text = ARTICLES.sub("", text)
    text = FILLER.sub("", text)
    text = PLEASANTRIES.sub("", text)
    for pattern, replacement in REDUNDANT_REPLACEMENTS:
        text = pattern.sub(replacement, text)

    # Level 2: aggressive
    if level >= 2:
        text = HEDGING.sub("", text)
        text = CONNECTIVES.sub("", text)
        text = SOFTENERS.sub("", text)
        for pattern, replacement in SYNONYM_REPLACEMENTS:
            text = pattern.sub(replacement, text)

    # Level 3: ultra (more aggressive whitespace and structural cleanup)
    if level >= 3:
        # Remove leading whitespace lines
        text = re.sub(r"\n\s*\n\s*\n", "\n\n", text)

    # Clean up double spaces left by removals
    text = re.sub(r"  +", " ", text)
    # Clean up space before punctuation
    text = re.sub(r" ([.,;:!?])", r"\1", text)
    # Clean up leading spaces on lines
    text = re.sub(r"(?m)^ +", "", text)

    # Restore preserved regions
    text = _restore_preserved(text, placeholders)

    return text


def count_words(text: str) -> int:
    return len(text.split())


def estimate_tokens(text: str) -> int:
    return round(count_words(text) * MULTIPLIER)


def find_files(repo_root: str) -> dict:
    """Find files to benchmark, grouped by category."""
    categories = {
        "agents": [],
        "conventions": [],
        "shared-core": [],
        "skills": [],
        "config-templates": [],
    }

    agents_dir = os.path.join(repo_root, "agents")
    if os.path.isdir(agents_dir):
        for f in sorted(os.listdir(agents_dir)):
            if f.endswith(".md"):
                categories["agents"].append(os.path.join(agents_dir, f))

    frameworks_dir = os.path.join(repo_root, "modules", "frameworks")
    if os.path.isdir(frameworks_dir):
        for fw in sorted(os.listdir(frameworks_dir)):
            conv = os.path.join(frameworks_dir, fw, "conventions.md")
            if os.path.isfile(conv):
                categories["conventions"].append(conv)
            cfg = os.path.join(frameworks_dir, fw, "forge-config-template.md")
            if os.path.isfile(cfg):
                categories["config-templates"].append(cfg)

    shared_dir = os.path.join(repo_root, "shared")
    if os.path.isdir(shared_dir):
        for f in sorted(os.listdir(shared_dir)):
            if f.endswith(".md"):
                categories["shared-core"].append(os.path.join(shared_dir, f))

    skills_dir = os.path.join(repo_root, "skills")
    if os.path.isdir(skills_dir):
        for skill in sorted(os.listdir(skills_dir)):
            skill_md = os.path.join(skills_dir, skill, "SKILL.md")
            if os.path.isfile(skill_md):
                categories["skills"].append(skill_md)

    return categories


def measure_category(files: list, level: int) -> dict:
    """Measure compression for a list of files at the given level."""
    total_before_words = 0
    total_after_words = 0
    total_before_tokens = 0
    total_after_tokens = 0
    file_count = 0

    for path in files:
        try:
            with open(path, "r", encoding="utf-8") as f:
                text = f.read()
        except (OSError, UnicodeDecodeError):
            continue

        before_words = count_words(text)
        before_tokens = estimate_tokens(text)
        compressed = apply_compression(text, level)
        after_words = count_words(compressed)
        after_tokens = estimate_tokens(compressed)

        total_before_words += before_words
        total_after_words += after_words
        total_before_tokens += before_tokens
        total_after_tokens += after_tokens
        file_count += 1

    reduction_pct = 0.0
    if total_before_tokens > 0:
        reduction_pct = (1 - total_after_tokens / total_before_tokens) * 100

    return {
        "files": file_count,
        "before_words": total_before_words,
        "after_words": total_after_words,
        "before_tokens": total_before_tokens,
        "after_tokens": total_after_tokens,
        "reduction_pct": reduction_pct,
    }


def format_markdown(results: dict, level: int) -> str:
    """Format results as markdown table."""
    level_names = {1: "conservative", 2: "aggressive", 3: "ultra"}
    lines = [
        f"# Input Compression Benchmark Results",
        f"",
        f"Compression level: **{level_names.get(level, str(level))}** (level {level})",
        f"Token estimation method: word_count * {MULTIPLIER}",
        f"",
        f"| Category | Files | Before (tokens) | After (tokens) | Reduction |",
        f"|----------|------:|----------------:|---------------:|----------:|",
    ]

    total_before = 0
    total_after = 0
    total_files = 0

    for category, data in sorted(results.items()):
        if data["files"] == 0:
            continue
        lines.append(
            f"| {category} | {data['files']} | "
            f"{data['before_tokens']:,} | {data['after_tokens']:,} | "
            f"{data['reduction_pct']:.1f}% |"
        )
        total_before += data["before_tokens"]
        total_after += data["after_tokens"]
        total_files += data["files"]

    overall_pct = 0.0
    if total_before > 0:
        overall_pct = (1 - total_after / total_before) * 100

    lines.append(
        f"| **TOTAL** | **{total_files}** | "
        f"**{total_before:,}** | **{total_after:,}** | "
        f"**{overall_pct:.1f}%** |"
    )
    lines.append("")
    lines.append("## Notes")
    lines.append("")
    lines.append("- Token counts are estimates (word_count * 1.3), not exact Claude tokenizer counts")
    lines.append("- Compression is regex-based, applying rules from `shared/input-compression.md`")
    lines.append("- Code blocks, inline code, URLs, and frontmatter are preserved")
    lines.append("- Results vary by content density and writing style")
    lines.append("")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="Measure input compression effectiveness"
    )
    parser.add_argument(
        "--repo-root",
        default=None,
        help="Path to forge repo root (default: auto-detect)",
    )
    parser.add_argument(
        "--file",
        default=None,
        help="Measure a single file instead of full repo scan",
    )
    parser.add_argument(
        "--level",
        type=int,
        default=2,
        choices=[1, 2, 3],
        help="Compression level: 1=conservative, 2=aggressive, 3=ultra (default: 2)",
    )
    parser.add_argument(
        "--output",
        default=None,
        help="Write results to file (default: stdout)",
    )
    args = parser.parse_args()

    if args.file:
        # Single file mode
        try:
            with open(args.file, "r", encoding="utf-8") as f:
                text = f.read()
        except (OSError, UnicodeDecodeError) as e:
            print(f"ERROR: {args.file}: {e}", file=sys.stderr)
            sys.exit(1)

        before_words = count_words(text)
        before_tokens = estimate_tokens(text)
        compressed = apply_compression(text, args.level)
        after_words = count_words(compressed)
        after_tokens = estimate_tokens(compressed)
        reduction = (1 - after_tokens / before_tokens) * 100 if before_tokens else 0

        print(f"File:             {args.file}")
        print(f"Level:            {args.level}")
        print(f"Before:           {before_words} words / {before_tokens} tokens")
        print(f"After:            {after_words} words / {after_tokens} tokens")
        print(f"Reduction:        {reduction:.1f}%")
        return

    # Full repo scan
    repo_root = args.repo_root
    if repo_root is None:
        # Auto-detect: walk up from script location
        script_dir = os.path.dirname(os.path.abspath(__file__))
        repo_root = os.path.dirname(os.path.dirname(script_dir))
        if not os.path.isfile(os.path.join(repo_root, "CLAUDE.md")):
            print("ERROR: Could not auto-detect repo root. Use --repo-root.", file=sys.stderr)
            sys.exit(1)

    categories = find_files(repo_root)
    level_map = {
        "agents": args.level,
        "conventions": max(1, args.level - 1),  # conventions get lighter treatment
        "shared-core": args.level,
        "skills": max(1, args.level - 1),
        "config-templates": max(1, args.level - 1),
    }

    results = {}
    for category, files in categories.items():
        cat_level = level_map.get(category, args.level)
        results[category] = measure_category(files, cat_level)

    output = format_markdown(results, args.level)

    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(output)
        print(f"Results written to {args.output}")
    else:
        print(output)


if __name__ == "__main__":
    main()
