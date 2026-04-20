#!/usr/bin/env bats

load 'helpers/scenario.bash'

setup() { scenario_setup; }
teardown() { scenario_teardown; }

@test "rewind then replay identical writes converges to same HEAD sha" {
    sha1=$(cas_write "A.-.001" "PLANNING" '{"x":1}')
    echo v2 > "$WT/f.txt"; git -C "$WT" add . && git -C "$WT" commit -q -m c2
    sha2=$(cas_write "A.-.002" "IMPLEMENTING" '{"x":2}')

    # Seed live state.json + events.jsonl for the rewind commit step.
    echo '{"x":2,"head_checkpoint":"'"$sha2"'"}' > "$RUN_DIR/state.json"
    : > "$RUN_DIR/events.jsonl"

    run "${PY_CMD[@]}" rewind \
        --run-dir "$RUN_DIR" --worktree "$WT" --to "$sha1" --run-id "$RUN_ID"
    [ "$status" -eq 0 ]
    head=$(cat "$RUN_DIR/checkpoints/HEAD")
    [ "$head" = "$sha1" ]

    # Replay the same write as before the rewind. CAS hash is independent
    # of parents, so the bundle must dedup to the original sha2.
    echo v2 > "$WT/f.txt"; git -C "$WT" add . && git -C "$WT" commit -q -m c2
    sha2b=$(cas_write "A.-.002b" "IMPLEMENTING" '{"x":2}')

    [ "$sha2b" = "$sha2" ]
}
