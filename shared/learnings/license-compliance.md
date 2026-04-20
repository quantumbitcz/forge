# License Compliance Learnings

Per-project cumulative learnings for `fg-414-license-reviewer`.

## Discovered patterns

(auto-populated by `fg-700-retrospective`)

## Policy calibration

| SPDX bucket | Default behavior | Override path |
|---|---|---|
| `allow` | No finding | `.forge/license-policy.json` |
| `warn` | `LICENSE-POLICY-VIOLATION` @ WARNING | Promote to CRITICAL via project policy |
| `deny` | `LICENSE-POLICY-VIOLATION` @ CRITICAL | Cannot be lowered without policy edit |
| Unknown SPDX | `LICENSE-UNKNOWN` @ WARNING | Add SPDX to a bucket to silence |

## Common false positives

- Transitive dep declares no SPDX but is on npm registry with a known license → use the `licensee`/`license-checker` fallback heuristic before flagging unknown.
- Dual-licensed deps (`MIT OR Apache-2.0`) → treat as the most permissive match.
