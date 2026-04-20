#!/usr/bin/env bats

load 'helpers/scenario.bash'

setup() { scenario_setup; }
teardown() { scenario_teardown; }

@test "dirty worktree aborts rewind with exit 5; zero side effects" {
    sha=$(cas_write "A.-.001" "PLANNING" '{"x":1}')
    # dirty the worktree without committing
    echo dirty > "$WT/f.txt"
    run "${PY_CMD[@]}" rewind \
        --run-dir "$RUN_DIR" --worktree "$WT" --to "$sha" --run-id "$RUN_ID"
    [ "$status" -eq 5 ]
    # worktree contents unchanged
    [ "$(cat "$WT/f.txt")" = "dirty" ]
    # HEAD still points at the latest written sha
    head=$(cat "$RUN_DIR/checkpoints/HEAD")
    [ "$head" = "$sha" ]
    # no .rewind-tx left behind
    [ ! -e "$RUN_DIR/.rewind-tx" ]
}

@test "--force overrides dirty worktree gate (exit 0)" {
    sha=$(cas_write "A.-.001" "PLANNING" '{"x":1}')
    # add a real commit so HEAD before rewind != HEAD after
    echo v2 > "$WT/f.txt"
    git -C "$WT" add . && git -C "$WT" commit -q -m c2
    sha2=$(cas_write "A.-.002" "IMPLEMENTING" '{"x":2}')
    # dirty the worktree
    echo dirty > "$WT/f.txt"
    # seed live state so the commit step has files to replace
    echo '{"x":2,"head_checkpoint":"'"$sha2"'"}' > "$RUN_DIR/state.json"
    : > "$RUN_DIR/events.jsonl"
    run "${PY_CMD[@]}" rewind \
        --run-dir "$RUN_DIR" --worktree "$WT" --to "$sha" \
        --run-id "$RUN_ID" --force
    [ "$status" -eq 0 ]
    head=$(cat "$RUN_DIR/checkpoints/HEAD")
    [ "$head" = "$sha" ]
}
