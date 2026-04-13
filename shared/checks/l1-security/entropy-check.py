#!/usr/bin/env python3
"""
Shannon entropy-based secret detection for forge L1 check engine.

Called as a post-filter on L1 regex matches. Processes candidate strings
already flagged by L1 patterns and filters out false positives using
entropy analysis and known non-secret pattern exclusions.

Usage:
    python3 entropy-check.py <file_path> <candidate1> [candidate2] ...

Output (pipe-delimited, one line per finding):
    <file_path>|<line_hint>|SEC-ENTROPY|WARNING|High-entropy string detected (entropy={value:.2f}, length={length})|Verify this is not an obfuscated secret

Exit code 0 always. Findings on stdout, errors on stderr.
"""

import math
import re
import sys
from collections import Counter

# --- Configuration ---
ENTROPY_THRESHOLD = 4.5
MIN_LENGTH = 16

# --- Exclusion patterns (known non-secret high-entropy strings) ---

# UUIDs: 8-4-4-4-12 hex format
UUID_RE = re.compile(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
)

# SHA-1 hashes (40 hex chars) and SHA-256 hashes (64 hex chars)
SHA_HASH_RE = re.compile(r'^[0-9a-fA-F]{40}$|^[0-9a-fA-F]{64}$')

# Package integrity hashes (SRI format)
INTEGRITY_HASH_RE = re.compile(r'^sha(?:256|384|512)-[A-Za-z0-9+/=]+$')

# CSS/HTML hex color codes
HEX_COLOR_RE = re.compile(r'^#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?$')

# Known test/fixture patterns
TEST_PATTERNS = [
    'test', 'mock', 'fake', 'dummy', 'example', 'sample', 'fixture',
    'placeholder', 'lorem', 'ipsum', 'foobar', 'abcdef', 'xxxxx',
]

# Test/fixture file path patterns
TEST_PATH_RE = re.compile(
    r'(?:^|/)'
    r'(?:test|tests|__tests__|spec|specs|fixture|fixtures|testdata|__fixtures__|mock|mocks)'
    r'(?:/|$)',
    re.IGNORECASE,
)


def entropy(s: str) -> float:
    """Shannon entropy of a string. O(n) time, no external dependencies."""
    if not s:
        return 0.0
    counts = Counter(s)
    length = len(s)
    return -sum((c / length) * math.log2(c / length) for c in counts.values())


def is_excluded(candidate: str) -> bool:
    """Return True if the candidate matches a known non-secret pattern."""
    stripped = candidate.strip()

    # UUID
    if UUID_RE.match(stripped):
        return True

    # SHA hashes
    if SHA_HASH_RE.match(stripped):
        return True

    # SRI integrity hashes
    if INTEGRITY_HASH_RE.match(stripped):
        return True

    # Hex color codes
    if HEX_COLOR_RE.match(stripped):
        return True

    # Known test/placeholder strings
    lower = stripped.lower()
    for pattern in TEST_PATTERNS:
        if pattern in lower:
            return True

    return False


def is_test_context(file_path: str) -> bool:
    """Return True if the file path indicates test/fixture context."""
    return bool(TEST_PATH_RE.search(file_path))


def check_candidate(file_path, candidate):
    """
    Check a single candidate string for high entropy.

    Returns a pipe-delimited finding string or None.
    """
    # Skip short strings
    if len(candidate) < MIN_LENGTH:
        return None

    # Skip known non-secret patterns
    if is_excluded(candidate):
        return None

    # Skip if in test/fixture context
    if is_test_context(file_path):
        return None

    # Compute entropy
    ent = entropy(candidate)
    if ent <= ENTROPY_THRESHOLD:
        return None

    return (
        f"{file_path}|0|SEC-ENTROPY|WARNING|"
        f"High-entropy string detected (entropy={ent:.2f}, length={len(candidate)})|"
        f"Verify this is not an obfuscated secret"
    )


def main() -> None:
    if len(sys.argv) < 3:
        print(
            f"Usage: {sys.argv[0]} <file_path> <candidate1> [candidate2] ...",
            file=sys.stderr,
        )
        sys.exit(0)

    file_path = sys.argv[1]
    candidates = sys.argv[2:]

    for candidate in candidates:
        finding = check_candidate(file_path, candidate)
        if finding:
            print(finding)


if __name__ == "__main__":
    main()
