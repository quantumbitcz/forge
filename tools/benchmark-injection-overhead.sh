#!/usr/bin/env bash
# benchmark-injection-overhead.sh — measures injection-hardening overhead.
# Approximate token-overhead of the injection-hardening policy block.
# Strategy: measure byte-size of the canonical Untrusted Data Policy block per
# agent, multiply by typical dispatched-agent count, convert to tokens with the
# stable 4-bytes-per-token heuristic.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Pick an agent that we know has the header (fg-020 always carries it).
sample="$ROOT/agents/fg-020-bug-investigator.md"
if [ ! -f "$sample" ]; then
  echo "benchmark-injection-overhead: sample agent not found at $sample" >&2
  exit 1
fi

# Extract the policy block: heading + paragraph (stop at blank line after content).
block_bytes="$(awk '
  /^## Untrusted Data Policy$/ { capture=1; saw_content=0; print; next }
  !capture { next }
  capture && /^[[:space:]]*$/ { if (saw_content) exit; print; next }
  capture { print; saw_content=1; next }
' "$sample" | wc -c | tr -d ' ')"

agents="$(find "$ROOT/agents" -maxdepth 1 -name 'fg-*.md' -type f | wc -l | tr -d ' ')"
total_block_bytes=$((block_bytes * agents))
estimated_tokens=$((total_block_bytes / 4))

# Reference: a typical hello-world run dispatches ~18 agents on average.
typical_dispatched=18
per_run_tokens=$((block_bytes * typical_dispatched / 4))

cat <<OUT
benchmark-injection-overhead:
  block bytes (one agent):    $block_bytes
  agents carrying block:      $agents
  total bytes (all agents):   $total_block_bytes
  estimated tokens if all:    $estimated_tokens
  typical per-run (18 dispatched avg): ~$per_run_tokens tokens
OUT
