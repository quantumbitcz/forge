# `trigger:` Expression Grammar

Every agent frontmatter MAY carry a `trigger:` key. The value is a boolean expression evaluated by the dispatcher (`fg-100-orchestrator`) before calling the agent. When the expression evaluates to `false`, the agent is skipped silently and a `DISPATCH-SKIPPED` debug event is emitted to `.forge/events.jsonl`.

## 1. Absence == `always`

An agent with no `trigger:` key is equivalent to `trigger: always`. Phase 08's dispatch-graph generator flags omissions on conditionally-dispatched agents as warnings, but runtime behavior preserves the current "dispatch unconditionally" default.

## 2. Namespaces

Three top-level namespaces are visible to the evaluator:

- `config.*` — effective config after `forge-config.md > forge.local.md > defaults` resolution. Matches the YAML structure in `forge-config-template.md`.
- `state.*` — the subset of `.forge/state.json` that `fg-100-orchestrator` passes to dispatch. Always includes: `mode`, `frontend_files_present` (bool), `infra_files_present` (bool), `preview.url_available` (bool), `downstreams` (array).
- `always` — literal `true`.

Accessing an undefined path evaluates to `null`. Any operator applied to `null` evaluates to `false` (short-circuits safely; no dispatch).

## 3. EBNF

```ebnf
expr       = or ;
or         = and { "||" and } ;
and        = not { "&&" not } ;
not        = [ "!" ] primary ;
primary    = literal
           | path
           | "(" expr ")"
           | comparison ;
comparison = path op rhs ;
op         = "==" | "!=" | ">=" | "<=" | ">" | "<" ;
rhs        = literal | path ;
literal    = boolean | string | number ;
boolean    = "true" | "false" | "always" ;
string     = '"' { any-char-except-quote } '"' ;
number     = digit { digit } [ "." digit { digit } ] ;
path       = identifier { "." identifier } ;
identifier = letter { letter | digit | "_" } ;
```

## 4. Operators

- Equality: `==`, `!=` — strict type and value equality.
- Ordering: `<`, `<=`, `>`, `>=` — numeric only; string compares are a type error → `false`.
- Logical: `&&`, `||`, `!` — short-circuit.
- Parentheses: `(`, `)`.

No arithmetic, no function calls, no regexes, no glob globs. Keep expressions boring on purpose.

## 5. Evaluator

Implemented in-band by `fg-100-orchestrator`. Reference implementation will land in Phase 08 alongside the dispatch-graph generator. Until then, orchestrator prose uses human-language mirrors of the same expressions — the machine-readable `trigger:` field is the source of truth, and Phase 08 generates matching prose.

## 6. Error handling

- Parse error in a `trigger:` → `fg-100-orchestrator` emits CRITICAL `DISPATCH-TRIGGER-PARSE-ERROR`, skips that agent only, and continues the stage.
- Reference to an unknown top-level namespace → WARNING `DISPATCH-TRIGGER-UNKNOWN-NAMESPACE`, expression evaluates `false` (skip).
- Reference to an unknown path inside a known namespace → silent `false` (per §2).

## 7. Canonical examples (used in Phase 07 agents)

| Agent | Expression |
|---|---|
| `fg-155-i18n-validator` | `config.agents.i18n_validator.enabled == true` |
| `fg-143-observability-bootstrap` | `config.agents.observability_bootstrap.enabled == true` |
| `fg-506-migration-verifier` | `state.mode == "migration" && config.agents.migration_verifier.enabled == true` |
| `fg-555-resilience-tester` | `config.agents.resilience_testing.enabled == true` |
| `fg-414-license-reviewer` | `always` |
| `fg-320-frontend-polisher` | `config.frontend_polish.enabled == true && state.frontend_files_present == true` |
| `fg-515-property-test-generator` | `config.property_testing.enabled == true` |
| `fg-610-infra-deploy-verifier` | `state.infra_files_present == true` |
| `fg-620-deploy-verifier` | `config.deployment.strategy != "none"` |
| `fg-650-preview-validator` | `state.preview.url_available == true` |

## 8. Related

- `shared/agent-role-hierarchy.md` — dispatch graph (consumer)
- `shared/agent-ui.md` — UI-tier rules (peer contract)
- `shared/state-schema.md` — `state.*` namespace definitions
- `shared/config-schema.json` — `config.*` namespace definitions
