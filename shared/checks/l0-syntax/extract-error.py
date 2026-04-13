#!/usr/bin/env python3
"""Extract first syntax error location from tree-sitter parse output.

Tree-sitter parse output uses S-expression format with position annotations:
  (ERROR [row, col] - [row, col])

This script finds the first ERROR node and prints a human-readable location
with the offending source line and a caret pointer.
"""
import argparse
import re
import sys


def main():
    parser = argparse.ArgumentParser(
        description="Extract syntax error location from tree-sitter parse output."
    )
    parser.add_argument("--parse-output", required=True, help="Raw tree-sitter parse output")
    parser.add_argument("--file", required=True, help="Path to the parsed file")
    args = parser.parse_args()

    # tree-sitter parse output format: (ERROR [row, col] - [row, col])
    match = re.search(r"\(ERROR \[(\d+), (\d+)\]", args.parse_output)
    if match:
        row = int(match.group(1))
        col = int(match.group(2))
        # Read the offending line for context
        try:
            with open(args.file, encoding="utf-8") as f:
                lines = f.readlines()
            if row < len(lines):
                line_content = lines[row].rstrip()
                pointer = " " * col + "^"
                print(f"Line {row + 1}, column {col + 1}:")
                print(f"  {line_content}")
                print(f"  {pointer}")
            else:
                print(f"Line {row + 1}, column {col + 1}")
        except Exception:
            print(f"Line {row + 1}, column {col + 1}")
    else:
        print("Syntax error detected (location could not be extracted from parse tree)")


if __name__ == "__main__":
    main()
