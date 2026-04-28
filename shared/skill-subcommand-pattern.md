# Skill Subcommand Dispatch Pattern

Standard pattern for skills that expose multiple modes via subcommands (git-style).
Adopted for `/forge review`, `/forge-admin graph`, `/forge verify`.

## 1. Dispatch algorithm

Every skill that uses this pattern places **one** `## Subcommand dispatch` section
at the top of its SKILL.md body. That section MUST describe the following steps:

1. Read `$ARGUMENTS` (the raw arg string).
2. Split into tokens: `SUB="$1"; shift; REST="$*"`.
3. If `$SUB` is empty OR `$SUB` matches `-*` (a flag, not a subcommand):
   → treat as the default subcommand (skill-specific; see `## Default subcommand`).
4. If `$SUB == --help` OR `$SUB == help`:
   → print the usage block and exit 0.
5. If `$SUB` is in the subcommand allow-list: dispatch to the matching
   `### Subcommand: <name>` section with `$REST` as its arguments.
6. Otherwise: print
   `Unknown subcommand '<SUB>'. Valid: <list>. Try /<skill> --help.`
   and exit 2 (invalid arguments; see `shared/skill-contract.md` §3).

## 2. Default subcommand

Each skill MAY declare a default subcommand used when `$ARGUMENTS` is empty
or starts with a flag. Skills that touch destructive state (e.g. `/forge-admin graph`
whose `rebuild` subcommand deletes nodes) MUST NOT declare a default; a bare
invocation prints help and exits 2.

Current defaults:

| Skill | Default | Rationale |
|---|---|---|
| `/forge review` | `changed` (i.e. `--scope=changed` with `--fix` on) | Preserves old `/forge review` muscle memory. |
| `/forge-admin graph` | none — explicit subcommand required | Safer than silently invoking `rebuild`. |
| `/forge verify` | `build` | Matches old `/forge verify` default. |

## 3. Arg-parsing helper (inlined per skill)

The Claude Code skill runtime reads one `.md` per skill and expects all logic
inline. Rather than sourcing a shared script, each skill inlines this bash
helper verbatim:

```bash
parse_args() {
  SUB=""
  FLAGS=()
  POSITIONAL=()
  for tok in "$@"; do
    case "$tok" in
      --help|-h) echo "__HELP__"; return 0 ;;
      --*)       FLAGS+=("$tok") ;;
      *)         if [ -z "$SUB" ]; then SUB="$tok"; else POSITIONAL+=("$tok"); fi ;;
    esac
  done
}
```

## 4. Section layout contract

A SKILL.md that adopts this pattern MUST contain:

1. Exactly ONE `## Subcommand dispatch` section (duplicated sections fail the
   structural test in `tests/structural/skill-consolidation.bats`).
2. One `### Subcommand: <name>` section per allowed subcommand, in the order
   listed in the dispatch allow-list.
3. Each subcommand section owns its own Prerequisites, Instructions, Error
   Handling, and Exit-code rows. Shared material (e.g. "forge.local.md must
   exist") MAY be factored once at the top of the SKILL body and referenced.

## 5. Unknown subcommand → exit 2

Following the standard exit-code table in `shared/skill-contract.md` §3:
- `0` — success
- `1` — user error (bad args, missing config)
- `2` — pipeline failure OR **unknown subcommand** (this pattern extends this code
  to cover dispatch-table misses)
- `3` — recovery needed
- `4` — user aborted

The "Unknown subcommand" path falls under exit `2` because the user supplied
a value the skill could not act on — semantically closer to pipeline failure
than to a missing required flag.

## 6. When to adopt this pattern

- NEW skill needs ≥ 3 modes whose setup/prerequisites overlap.
- Existing skills that are obvious modes of each other (audit found: review,
  graph, verify).
- DO NOT adopt for single-mode skills (`/forge-ask status`, `/forge-admin abort`).
