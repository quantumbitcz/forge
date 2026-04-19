"""Frozen semconv attribute names + cardinality budget.

Single source of truth. Do NOT inline attribute strings elsewhere.

Cardinality budget (span-name safety):
  BOUNDED_ATTRS   -- safe to interpolate into span names (low cardinality,
                     stable membership). Backends like Tempo/Honeycomb meter
                     unique span names; keep this list small.
  UNBOUNDED_ATTRS -- attribute-only; NEVER include in span names.
"""

from __future__ import annotations

# gen_ai.* (OTel GenAI semconv 2026)
GEN_AI_AGENT_NAME = "gen_ai.agent.name"
GEN_AI_AGENT_DESCRIPTION = "gen_ai.agent.description"
GEN_AI_AGENT_ID = "gen_ai.agent.id"
GEN_AI_OPERATION_NAME = "gen_ai.operation.name"
GEN_AI_REQUEST_MODEL = "gen_ai.request.model"
GEN_AI_TOKENS_INPUT = "gen_ai.tokens.input"
GEN_AI_TOKENS_OUTPUT = "gen_ai.tokens.output"
GEN_AI_TOKENS_TOTAL = "gen_ai.tokens.total"
GEN_AI_COST_USD = "gen_ai.cost.usd"
GEN_AI_TOOL_CALLS = "gen_ai.tool.calls"
GEN_AI_TOOL_NAME = "gen_ai.tool.name"
GEN_AI_TOOL_CALL_ID = "gen_ai.tool.call.id"
GEN_AI_RESPONSE_FINISH_REASONS = "gen_ai.response.finish_reasons"

# gen_ai.operation.name enum
OP_INVOKE_AGENT = "invoke_agent"
OP_EXECUTE_TOOL = "execute_tool"
OP_CREATE_AGENT = "create_agent"

# forge.* (forge-specific; not semconv)
FORGE_RUN_ID = "forge.run_id"
FORGE_STAGE = "forge.stage"
FORGE_MODE = "forge.mode"
FORGE_SCORE = "forge.score"
FORGE_PHASE_ITERATIONS = "forge.phase_iterations"
FORGE_CONVERGENCE_ITERATIONS = "forge.convergence.iterations"
FORGE_BATCH_SIZE = "forge.batch.size"
FORGE_BATCH_AGENTS = "forge.batch.agents"
FORGE_COST_UNKNOWN = "forge.cost.unknown"

# Cardinality budget.
BOUNDED_ATTRS: tuple[str, ...] = (
    GEN_AI_AGENT_NAME,  # 42 agents + review-batch-<N>, bounded.
    GEN_AI_REQUEST_MODEL,  # pricing-table keyed, bounded.
    GEN_AI_OPERATION_NAME,  # enum: invoke_agent|execute_tool|create_agent.
    FORGE_STAGE,  # 10 pipeline stages + migration sub-states.
    FORGE_MODE,  # enum: standard|bugfix|migration|bootstrap.
)

UNBOUNDED_ATTRS: tuple[str, ...] = (
    FORGE_RUN_ID,  # per-run UUID. ATTRIBUTE ONLY. Never a span name.
    GEN_AI_AGENT_ID,  # per-invocation UUID.
    GEN_AI_TOOL_CALL_ID,  # per-call UUID.
    FORGE_SCORE,  # numeric, not a span-name component.
    FORGE_PHASE_ITERATIONS,
    FORGE_CONVERGENCE_ITERATIONS,
    FORGE_BATCH_SIZE,
    GEN_AI_TOKENS_INPUT,
    GEN_AI_TOKENS_OUTPUT,
    GEN_AI_TOKENS_TOTAL,
    GEN_AI_COST_USD,
    GEN_AI_TOOL_CALLS,
)
