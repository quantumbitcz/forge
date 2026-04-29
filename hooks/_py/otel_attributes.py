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
FORGE_AGENT_NAME = "forge.agent.name"
FORGE_SCORE = "forge.score"
FORGE_PHASE_ITERATIONS = "forge.phase_iterations"
FORGE_CONVERGENCE_ITERATIONS = "forge.convergence.iterations"
FORGE_BATCH_SIZE = "forge.batch.size"
FORGE_BATCH_AGENTS = "forge.batch.agents"
FORGE_COST_UNKNOWN = "forge.cost.unknown"
FORGE_LEARNING_ID = "forge.learning.id"
FORGE_LEARNING_CONFIDENCE_NOW = "forge.learning.confidence_now"
FORGE_LEARNING_APPLIED_COUNT = "forge.learning.applied_count"
FORGE_LEARNING_SOURCE_PATH = "forge.learning.source_path"
FORGE_LEARNING_REASON = "forge.learning.reason"

# forge.cost.* (Phase 6)
FORGE_RUN_BUDGET_TOTAL_USD = "forge.run.budget_total_usd"
FORGE_RUN_BUDGET_REMAINING_USD = "forge.run.budget_remaining_usd"
FORGE_AGENT_TIER_ESTIMATE_USD = "forge.agent.tier_estimate_usd"
FORGE_AGENT_TIER_ORIGINAL = "forge.agent.tier_original"
FORGE_AGENT_TIER_USED = "forge.agent.tier_used"
FORGE_COST_THROTTLE_REASON = "forge.cost.throttle_reason"

# Enum values for FORGE_COST_THROTTLE_REASON.
THROTTLE_NONE = "none"
THROTTLE_SOFT_20PCT = "soft_20pct"
THROTTLE_SOFT_10PCT = "soft_10pct"
THROTTLE_CEILING_BREACH = "ceiling_breach"
THROTTLE_DYNAMIC_DOWNGRADE = "dynamic_downgrade"

# Cardinality budget.
BOUNDED_ATTRS: tuple[str, ...] = (
    GEN_AI_AGENT_NAME,  # 42 agents + review-batch-<N>, bounded.
    FORGE_AGENT_NAME,  # same set as GEN_AI_AGENT_NAME — used on forge.* event mirrors.
    GEN_AI_REQUEST_MODEL,  # pricing-table keyed, bounded.
    GEN_AI_OPERATION_NAME,  # enum: invoke_agent|execute_tool|create_agent.
    FORGE_STAGE,  # 10 pipeline stages + migration sub-states.
    FORGE_MODE,  # enum: standard|bugfix|migration|bootstrap.
    FORGE_AGENT_TIER_ORIGINAL,  # enum: fast|standard|premium
    FORGE_AGENT_TIER_USED,  # enum: fast|standard|premium
    FORGE_COST_THROTTLE_REASON,  # enum (5)
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
    FORGE_LEARNING_ID,  # per-item; bounded ~500, never safe as span name.
    FORGE_LEARNING_CONFIDENCE_NOW,
    FORGE_LEARNING_APPLIED_COUNT,
    FORGE_LEARNING_SOURCE_PATH,
    FORGE_LEARNING_REASON,
)

# Phase 7 F35 — intent verification
INTENT_AC_ID = "forge.intent.ac_id"
INTENT_AC_VERDICT = "forge.intent.ac_verdict"
INTENT_PROBE_TIER = "forge.intent.probe_tier"
INTENT_PROBES_ISSUED = "forge.intent.probes_issued"
INTENT_DURATION_MS = "forge.intent.duration_ms"

# Phase 7 F36 — implementer voting
IMPL_VOTE_SAMPLE_ID = "forge.impl_vote.sample_id"
IMPL_VOTE_TRIGGER = "forge.impl_vote.trigger"
IMPL_VOTE_VERDICT = "forge.impl_vote.verdict"
IMPL_VOTE_AST_FINGERPRINT = "forge.impl_vote.ast_fingerprint"
IMPL_VOTE_DEGRADED = "forge.impl_vote.degraded"
