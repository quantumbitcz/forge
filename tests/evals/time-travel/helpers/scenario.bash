# shellcheck shell=bash
# Shared helpers for Phase-14 time-travel eval bats files.
#
# Conventions:
# - PLUGIN_ROOT resolves to the repo root (four levels up from this file:
#     tests/evals/time-travel/helpers/scenario.bash -> repo).
# - PY_CMD is the canonical CLI invocation: `python3 -m hooks._py.time_travel`,
#   prefixed with `PYTHONPATH=$PLUGIN_ROOT` so the package resolves regardless
#   of cwd.
# - scenario_setup() seeds a TMP_ROOT with an empty git worktree at $WT and
#   an empty `.forge/runs/$RUN_ID/` directory at $RUN_DIR.
# - cas_write() invokes the in-process CheckpointStore API to write a
#   checkpoint and prints its sha (no CLI write subcommand exists).

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
export PLUGIN_ROOT

PY_CMD=(env "PYTHONPATH=$PLUGIN_ROOT" python3 -m hooks._py.time_travel)
export PY_CMD

scenario_setup() {
    TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/forge-tt.XXXXXX")"
    export TMP_ROOT
    export RUN_ID="run-$(basename "$TMP_ROOT")"
    export RUN_DIR="$TMP_ROOT/.forge/runs/$RUN_ID"
    export WT="$TMP_ROOT/wt"
    mkdir -p "$RUN_DIR" "$WT"
    git -C "$WT" init -q -b main
    git -C "$WT" config user.email a@b
    git -C "$WT" config user.name a
    git -C "$WT" config commit.gpgsign false
    echo v1 > "$WT/f.txt"
    git -C "$WT" add . && git -C "$WT" commit -q -m c0
}

scenario_teardown() {
    [[ -n "${TMP_ROOT:-}" ]] && rm -rf "$TMP_ROOT"
}

# cas_write <human_id> <stage> <state_json>
# Prints the 64-char sha to stdout. Uses gzip compression so tests do not
# require the optional zstandard dependency.
cas_write() {
    local human_id="$1" stage="$2" state_json="$3"
    PYTHONPATH="$PLUGIN_ROOT" python3 - <<PY
import json, pathlib, sys
from hooks._py.time_travel.cas import CheckpointStore
s = CheckpointStore(
    run_dir=pathlib.Path("$RUN_DIR"),
    worktree_dir=pathlib.Path("$WT"),
    compression="gzip",
)
sha = s.write_checkpoint(
    human_id="$human_id",
    stage="$stage",
    task="-",
    state=json.loads('''$state_json'''),
    events_slice=[],
    memory_files={},
)
print(sha)
PY
}
