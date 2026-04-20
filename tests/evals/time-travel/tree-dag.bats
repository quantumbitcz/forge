#!/usr/bin/env bats

load 'helpers/scenario.bash'

setup() { scenario_setup; }
teardown() { scenario_teardown; }

@test "tree-dag: 2 linear checkpoints render the golden output" {
    sha1=$(cas_write "A.-.001" "PLANNING" '{"x":1}')
    sha2=$(cas_write "A.-.002" "PLANNING" '{"x":2}')
    run "${PY_CMD[@]}" list-checkpoints \
        --run-dir "$RUN_DIR" --worktree "$WT"
    [ "$status" -eq 0 ]

    # Strip trailing newline from $output (bats `run` already does this);
    # strip trailing newline from golden as well to compare equally.
    golden="$(cat "$BATS_TEST_DIRNAME/fixtures/tree-dag.golden.txt")"
    golden="${golden//<SHA1>/${sha1:0:8}}"
    golden="${golden//<SHA2>/${sha2:0:8}}"
    [ "$output" = "$golden" ]
}
