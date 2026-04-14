#!/usr/bin/env bash
# Measures estimated token savings from caveman compression modes.
# Usage: bash caveman-benchmark.sh [sample_file]
# If no file given, uses .forge/forge-log.md as sample (reads entire file).
# Must be run from project root (uses relative paths for .forge/).
set -uo pipefail

_py=""
command -v python3 >/dev/null 2>&1 && _py="python3"
[ -z "$_py" ] && command -v python >/dev/null 2>&1 && _py="python"
if [ -z "$_py" ]; then
  echo "ERROR: python3 required for benchmark"
  exit 1
fi

SAMPLE_FILE="${1:-}"
if [ -z "$SAMPLE_FILE" ]; then
  if [ -f ".forge/forge-log.md" ]; then
    SAMPLE_FILE=".forge/forge-log.md"
  else
    echo "ERROR: No sample file provided and .forge/forge-log.md not found"
    echo "Usage: bash caveman-benchmark.sh [sample_file.md]"
    exit 1
  fi
fi

if [ ! -f "$SAMPLE_FILE" ]; then
  echo "ERROR: File not found: $SAMPLE_FILE"
  exit 1
fi

"$_py" - "$SAMPLE_FILE" << 'PYEOF'
import sys, re, json, os

sample_file = sys.argv[1]

def estimate_tokens(text):
    """Rough token estimate: word count * 1.3 (standard approximation)."""
    words = len(text.split())
    return int(words * 1.3)

def apply_lite(text):
    """Drop filler/hedging, keep grammar and articles."""
    fillers = [
        r'\bjust\b', r'\breally\b', r'\bbasically\b', r'\bsimply\b',
        r'\bperhaps\b', r'\bmight\b', r'\byou could consider\b',
        r'\bsure\b', r'\bcertainly\b', r"\bI'd be happy to\b",
        r'\bas you mentioned\b', r'\bmoving on to\b',
        r'\bin order to\b', r'\bit is important to note that\b',
        r'\bmake sure to\b', r'\bplease ensure\b',
    ]
    result = text
    for filler in fillers:
        result = re.sub(filler, '', result, flags=re.IGNORECASE)
    result = re.sub(r'  +', ' ', result)
    return result.strip()

def apply_full(text):
    """Drop articles + fillers, allow fragments."""
    text = apply_lite(text)
    articles = [r'\bthe\b', r'\ban\b', r'\ba\b']
    for art in articles:
        text = re.sub(art, '', text, flags=re.IGNORECASE)
    text = re.sub(r'  +', ' ', text)
    return text.strip()

def apply_ultra(text):
    """Drop articles + fillers + abbreviate common terms."""
    text = apply_full(text)
    abbrevs = {
        'database': 'DB', 'authentication': 'auth', 'request': 'req',
        'response': 'res', 'implementation': 'impl', 'configuration': 'config',
        'function': 'fn', 'variable': 'var', 'dependency': 'dep',
        'package': 'pkg', 'repository': 'repo', 'environment': 'env',
    }
    for word, abbrev in abbrevs.items():
        text = re.sub(r'\b' + word + r'\b', abbrev, text, flags=re.IGNORECASE)
    return text.strip()

with open(sample_file) as f:
    original = f.read()

# Skip code blocks (preserve them unchanged)
# Using hex \x60 for backtick to avoid bash heredoc conflicts
code_blocks = re.findall(r'\x60\x60\x60.*?\x60\x60\x60', original, re.DOTALL)
prose_only = re.sub(r'\x60\x60\x60.*?\x60\x60\x60', '', original, flags=re.DOTALL)

orig_tokens = estimate_tokens(original)
code_tokens = sum(estimate_tokens(cb) for cb in code_blocks)
lite_tokens = estimate_tokens(apply_lite(prose_only)) + code_tokens
full_tokens = estimate_tokens(apply_full(prose_only)) + code_tokens
ultra_tokens = estimate_tokens(apply_ultra(prose_only)) + code_tokens

print('## Caveman Benchmark')
print()
print(f'Sample: {sample_file} ({len(original)} chars, {len(original.splitlines())} lines)')
print()
print('| Mode     | Est. Tokens | Reduction | Notes |')
print('|----------|-------------|-----------|-------|')
print(f'| original | {orig_tokens:>11,} |       0%  | Baseline |')
if orig_tokens > 0:
    lite_pct = int(100 * (1 - lite_tokens / orig_tokens))
    full_pct = int(100 * (1 - full_tokens / orig_tokens))
    ultra_pct = int(100 * (1 - ultra_tokens / orig_tokens))
    print(f'| lite     | {lite_tokens:>11,} | {lite_pct:>6}%  | Drop filler, keep grammar |')
    print(f'| full     | {full_tokens:>11,} | {full_pct:>6}%  | Drop articles + filler |')
    print(f'| ultra    | {ultra_tokens:>11,} | {ultra_pct:>6}%  | Abbreviate + drop all |')
print()
print('Note: Code blocks preserved unchanged. Token estimate = word_count * 1.3.')

result = {
    'file': sample_file,
    'original_tokens': orig_tokens,
    'lite_tokens': lite_tokens,
    'full_tokens': full_tokens,
    'ultra_tokens': ultra_tokens,
}
print()
print('JSON: ' + json.dumps(result, separators=(',', ':')))
PYEOF

exit 0
