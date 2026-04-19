from hooks._py import otel_attributes as attrs


def test_gen_ai_attribute_names_match_semconv():
    assert attrs.GEN_AI_AGENT_NAME == "gen_ai.agent.name"
    assert attrs.GEN_AI_AGENT_DESCRIPTION == "gen_ai.agent.description"
    assert attrs.GEN_AI_AGENT_ID == "gen_ai.agent.id"
    assert attrs.GEN_AI_OPERATION_NAME == "gen_ai.operation.name"
    assert attrs.GEN_AI_REQUEST_MODEL == "gen_ai.request.model"
    assert attrs.GEN_AI_TOKENS_INPUT == "gen_ai.tokens.input"
    assert attrs.GEN_AI_TOKENS_OUTPUT == "gen_ai.tokens.output"
    assert attrs.GEN_AI_TOKENS_TOTAL == "gen_ai.tokens.total"
    assert attrs.GEN_AI_COST_USD == "gen_ai.cost.usd"
    assert attrs.GEN_AI_TOOL_CALLS == "gen_ai.tool.calls"
    assert attrs.GEN_AI_RESPONSE_FINISH_REASONS == "gen_ai.response.finish_reasons"
    assert attrs.OP_INVOKE_AGENT == "invoke_agent"
    assert attrs.OP_EXECUTE_TOOL == "execute_tool"


def test_forge_attribute_names():
    assert attrs.FORGE_RUN_ID == "forge.run_id"
    assert attrs.FORGE_STAGE == "forge.stage"
    assert attrs.FORGE_MODE == "forge.mode"
    assert attrs.FORGE_SCORE == "forge.score"


def test_cardinality_lists_are_disjoint_and_complete():
    # Every forge.* / gen_ai.* attribute must be classified.
    bounded = set(attrs.BOUNDED_ATTRS)
    unbounded = set(attrs.UNBOUNDED_ATTRS)
    assert bounded.isdisjoint(unbounded)
    # run_id is attribute-only, never a span name.
    assert attrs.FORGE_RUN_ID in unbounded
    # agent name + stage + mode are low cardinality, safe for names.
    assert attrs.GEN_AI_AGENT_NAME in bounded
    assert attrs.FORGE_STAGE in bounded
    assert attrs.FORGE_MODE in bounded
    # tool call id and agent id are per-invocation -> unbounded.
    assert attrs.GEN_AI_TOOL_CALL_ID in unbounded
    assert attrs.GEN_AI_AGENT_ID in unbounded
