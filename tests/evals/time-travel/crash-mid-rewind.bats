#!/usr/bin/env bats

load 'helpers/scenario.bash'

setup() { scenario_setup; }
teardown() { scenario_teardown; }

# Stage a tx dir mimicking the on-disk shape of a half-finished rewind.
# $1 = stage marker ("staged" or "committing"), $2 = sha1 (target), $3 = sha2 (head_before).
_seed_partial_tx() {
    local stage_marker="$1" sha1="$2" sha2="$3"
    local tx="$RUN_DIR/.rewind-tx"
    mkdir -p "$tx/memory"
    cp "$RUN_DIR/checkpoints/by-hash/${sha1:0:2}/${sha1:2}/state.json" "$tx/state.json"
    : > "$tx/events.jsonl.new"
    echo "$sha1" > "$tx/target.sha"
    git -C "$WT" rev-parse HEAD~1 > "$tx/worktree.sha"
    echo "$sha2" > "$tx/head_before.sha"
    echo "$RUN_ID" > "$tx/run_id"
    echo 0 > "$tx/forced"
    echo "[]" > "$tx/dirty_paths.json"
    echo user > "$tx/triggered_by"
    echo "$stage_marker" > "$tx/stage"
}

@test "crash after staging (before committing) -> full rollback" {
    sha1=$(cas_write "A.-.001" "PLANNING" '{"x":1}')
    echo v2 > "$WT/f.txt"
    git -C "$WT" add . && git -C "$WT" commit -q -m c2
    sha2=$(cas_write "A.-.002" "IMPLEMENTING" '{"x":2}')
    _seed_partial_tx staged "$sha1" "$sha2"

    run "${PY_CMD[@]}" repair \
        --run-dir "$RUN_DIR" --worktree "$WT" --run-id "$RUN_ID"
    [ "$status" -eq 0 ]
    [ ! -e "$RUN_DIR/.rewind-tx" ]
    head=$(cat "$RUN_DIR/checkpoints/HEAD")
    [ "$head" = "$sha2" ]   # rollback succeeded — HEAD untouched
}

@test "crash during commit -> roll forward" {
    sha1=$(cas_write "A.-.001" "PLANNING" '{"x":1}')
    echo v2 > "$WT/f.txt"
    git -C "$WT" add . && git -C "$WT" commit -q -m c2
    sha2=$(cas_write "A.-.002" "IMPLEMENTING" '{"x":2}')
    _seed_partial_tx committing "$sha1" "$sha2"

    run "${PY_CMD[@]}" repair \
        --run-dir "$RUN_DIR" --worktree "$WT" --run-id "$RUN_ID"
    [ "$status" -eq 0 ]
    [ ! -e "$RUN_DIR/.rewind-tx" ]
    head=$(cat "$RUN_DIR/checkpoints/HEAD")
    [ "$head" = "$sha1" ]   # rolled forward to target
}
