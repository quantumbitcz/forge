# Synthetic state-transitions table (test fixture)

This is a 4-row fixture for the coverage-reporter canary in
`tests/mutation/test_coverage_canary.py`. Two scenarios cover three of
the four rows; the canary asserts the reporter prints 75.0%.

| id | current | event | guard | next | actions |
| --- | --- | --- | --- | --- | --- |
| 1 | `STATE_A` | `event_one` | — | `STATE_B` | act one |
| 2 | `STATE_B` | `event_two` | — | `STATE_C` | act two |
| 3 | `STATE_C` | `event_three` | — | `STATE_D` | act three |
| 4 | `STATE_D` | `event_four` | — | `STATE_E` | act four |
