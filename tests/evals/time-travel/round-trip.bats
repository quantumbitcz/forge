#!/usr/bin/env bats

load 'helpers/scenario.bash'

setup() { scenario_setup; }
teardown() { scenario_teardown; }

@test "round-trip: write then list-checkpoints surfaces the sha" {
    sha=$(cas_write "A.-.001" "PLANNING" '{"x":1}')
    [ "${#sha}" -eq 64 ]
    run "${PY_CMD[@]}" list-checkpoints \
        --run-dir "$RUN_DIR" --worktree "$WT" --json
    [ "$status" -eq 0 ]
    [[ "$output" == *"$sha"* ]]
    [[ "$output" == *"\"HEAD\""* ]]
}

@test "round-trip: write twice updates HEAD to the most recent sha" {
    sha1=$(cas_write "A.-.001" "PLANNING" '{"x":1}')
    sha2=$(cas_write "A.-.002" "PLANNING" '{"x":2}')
    [ "$sha1" != "$sha2" ]
    head=$(cat "$RUN_DIR/checkpoints/HEAD")
    [ "$head" = "$sha2" ]
}
