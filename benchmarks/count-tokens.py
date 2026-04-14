#!/usr/bin/env python3
"""Estimate token count for text files using word_count * 1.3.

Zero external dependencies. Uses word-count heuristic calibrated for
Claude's tokenizer (not tiktoken, which targets GPT models).

Usage:
    python3 count-tokens.py FILE [FILE ...]
    python3 count-tokens.py --stdin < file.md
    echo "some text" | python3 count-tokens.py --stdin
"""

import argparse
import sys

MULTIPLIER = 1.3


def count_words(text: str) -> int:
    """Count whitespace-delimited words in text."""
    return len(text.split())


def estimate_tokens(text: str) -> int:
    """Estimate Claude token count as word_count * 1.3 (rounded)."""
    return round(count_words(text) * MULTIPLIER)


def process_file(path: str) -> dict:
    """Read file and return stats dict."""
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    words = count_words(text)
    tokens = round(words * MULTIPLIER)
    return {
        "file": path,
        "words": words,
        "estimated_tokens": tokens,
        "chars": len(text),
        "lines": text.count("\n") + (1 if text and not text.endswith("\n") else 0),
    }


def main():
    parser = argparse.ArgumentParser(
        description="Estimate Claude token count via word_count * 1.3"
    )
    parser.add_argument("files", nargs="*", help="Files to analyze")
    parser.add_argument(
        "--stdin", action="store_true", help="Read from stdin instead of files"
    )
    parser.add_argument(
        "--json", action="store_true", help="Output as JSON"
    )
    parser.add_argument(
        "--total-only", action="store_true", help="Print only the total token count"
    )
    args = parser.parse_args()

    if not args.files and not args.stdin:
        parser.print_help()
        sys.exit(1)

    results = []

    if args.stdin:
        text = sys.stdin.read()
        words = count_words(text)
        tokens = round(words * MULTIPLIER)
        results.append({
            "file": "<stdin>",
            "words": words,
            "estimated_tokens": tokens,
            "chars": len(text),
            "lines": text.count("\n") + (1 if text and not text.endswith("\n") else 0),
        })
    else:
        for path in args.files:
            try:
                results.append(process_file(path))
            except (OSError, UnicodeDecodeError) as e:
                print(f"ERROR: {path}: {e}", file=sys.stderr)
                sys.exit(1)

    total_words = sum(r["words"] for r in results)
    total_tokens = sum(r["estimated_tokens"] for r in results)

    if args.total_only:
        print(total_tokens)
        return

    if args.json:
        import json
        output = {
            "method": "word_count * 1.3",
            "multiplier": MULTIPLIER,
            "files": results,
            "total_words": total_words,
            "total_estimated_tokens": total_tokens,
        }
        print(json.dumps(output, indent=2))
        return

    # Table output
    if len(results) > 1:
        print(f"{'File':<60} {'Words':>8} {'Est Tokens':>12}")
        print("-" * 82)
        for r in results:
            print(f"{r['file']:<60} {r['words']:>8} {r['estimated_tokens']:>12}")
        print("-" * 82)
        print(f"{'TOTAL':<60} {total_words:>8} {total_tokens:>12}")
    else:
        r = results[0]
        print(f"File:             {r['file']}")
        print(f"Lines:            {r['lines']}")
        print(f"Characters:       {r['chars']}")
        print(f"Words:            {r['words']}")
        print(f"Estimated tokens: {r['estimated_tokens']}")
        print(f"Method:           word_count * {MULTIPLIER}")


if __name__ == "__main__":
    main()
