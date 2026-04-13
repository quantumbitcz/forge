#!/usr/bin/env python3
"""Simulate an Edit or Write operation on a temp copy of the target file.

Used by the L0 pre-edit syntax validation hook to produce the file content
that *would* result from the edit, so tree-sitter can parse it before the
edit is actually applied.

Exit 0 with output file written = success.
Exit 0 without output file    = skip (let the edit through).
"""
import argparse
import json
import os
import sys


def main():
    parser = argparse.ArgumentParser(
        description="Simulate Edit/Write tool operation on a temp file."
    )
    parser.add_argument("--tool-name", required=True, help="Tool name: Edit or Write")
    parser.add_argument("--tool-input", required=True, help="JSON string of tool input")
    parser.add_argument("--file-path", required=True, help="Original file path")
    parser.add_argument("--output", required=True, help="Output temp file path")
    args = parser.parse_args()

    try:
        tool_input = json.loads(args.tool_input)
    except (json.JSONDecodeError, TypeError):
        # Cannot parse tool input — let the edit through
        sys.exit(0)

    tool_name = args.tool_name

    if tool_name == "Write":
        # Write: entire file content is in tool_input.content
        content = tool_input.get("content", "")
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(content)

    elif tool_name == "Edit":
        # Edit: apply old_string -> new_string replacement
        if not os.path.isfile(args.file_path):
            # New file via Edit (shouldn't happen, but handle gracefully)
            sys.exit(0)

        with open(args.file_path, "r", encoding="utf-8") as f:
            content = f.read()

        old_string = tool_input.get("old_string", "")
        new_string = tool_input.get("new_string", "")

        if not old_string:
            # No old_string — nothing to replace, skip
            sys.exit(0)

        if old_string not in content:
            # Edit would fail anyway (old_string not found), let it through
            sys.exit(0)

        if tool_input.get("replace_all", False):
            result = content.replace(old_string, new_string)
        else:
            result = content.replace(old_string, new_string, 1)

        with open(args.output, "w", encoding="utf-8") as f:
            f.write(result)

    else:
        # Unknown tool — let it through
        sys.exit(0)


if __name__ == "__main__":
    main()
