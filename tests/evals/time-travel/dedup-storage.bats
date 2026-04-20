#!/usr/bin/env bats

load 'helpers/scenario.bash'

setup() { scenario_setup; }
teardown() { scenario_teardown; }

@test "dedup: 10 writes with 3 identical states yield 8 unique bundles" {
    for i in 0 1 2 3 4 5 6 7 8 9; do
        # entries 3, 5, 7 share the state {x:99}; the rest are distinct.
        state='{"x":'"$i"'}'
        case "$i" in 3|5|7) state='{"x":99}';; esac
        cas_write "A.-.$(printf %03d "$i")" "PLANNING" "$state" >/dev/null
    done
    count=$(find "$RUN_DIR/checkpoints/by-hash" -name manifest.json | wc -l | tr -d ' ')
    [ "$count" -eq 8 ]
}

@test "dedup: identical four-tuple writes do not duplicate the bundle dir" {
    sha_a=$(cas_write "A.-.001" "PLANNING" '{"x":1}')
    sha_b=$(cas_write "A.-.001b" "PLANNING" '{"x":1}')
    [ "$sha_a" = "$sha_b" ]
    count=$(find "$RUN_DIR/checkpoints/by-hash" -name manifest.json | wc -l | tr -d ' ')
    [ "$count" -eq 1 ]
}
