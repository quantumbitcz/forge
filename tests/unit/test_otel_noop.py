from hooks._py import otel


def test_init_disabled_is_noop(tmp_path):
    state = otel.init({"enabled": False})
    assert state.enabled is False
    # All calls must be safe when disabled.
    with otel.pipeline_span(run_id="r1", mode="standard"):
        with otel.stage_span("EXPLORING"):
            with otel.agent_span(
                name="fg-100-orchestrator",
                model="sonnet",
                description="orchestrator",
            ):
                otel.record_agent_result(
                    {
                        "tokens_input": 1,
                        "tokens_output": 2,
                        "cost_usd": 0.01,
                        "tool_calls": 0,
                    }
                )
    otel.shutdown()


def test_replay_is_documented_as_authoritative(tmp_path):
    # replay() exists, accepts events.jsonl path, is the authoritative
    # recovery path (the live stream is best-effort).
    events = tmp_path / "events.jsonl"
    events.write_text("")  # empty file
    # Disabled config -> no-op replay must not raise and must return 0.
    n = otel.replay(events_path=str(events), config={"enabled": False})
    assert n == 0
    assert "authoritative" in (otel.replay.__doc__ or "").lower()
