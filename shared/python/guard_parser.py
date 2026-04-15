#!/usr/bin/env python3
"""Parse key=value guard arguments into typed JSON dict."""
import json
import sys


def parse_guards(args):
    """Parse key=value strings with type coercion: bool > int > float > str."""
    guards = {}
    for arg in args:
        if '=' not in arg:
            print(f"ERROR: malformed guard (no '='): {arg}", file=sys.stderr)
            sys.exit(1)
        k, v = arg.split('=', 1)
        if v.lower() == 'true':
            guards[k] = True
        elif v.lower() == 'false':
            guards[k] = False
        else:
            try:
                guards[k] = int(v)
            except ValueError:
                try:
                    guards[k] = float(v)
                except ValueError:
                    guards[k] = v
    return guards


if __name__ == '__main__':
    result = parse_guards(sys.argv[1:])
    print(json.dumps(result))
