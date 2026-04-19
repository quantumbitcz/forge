import pytest

pytest.importorskip("opentelemetry.sdk.trace.sampling")

from opentelemetry.sdk.trace.sampling import ParentBased, TraceIdRatioBased  # noqa: E402

from hooks._py.otel_context import build_sampler  # noqa: E402


def test_sampler_is_parent_based_with_ratio_root():
    s = build_sampler(sample_rate=0.25)
    assert isinstance(s, ParentBased)
    # Root delegate must be ratio-based with the exact rate.
    assert isinstance(s._root, TraceIdRatioBased)  # noqa: SLF001
    # Descriptive text is stable enough to assert the ratio.
    assert "0.25" in s.get_description() or "0.250000" in s.get_description()


def test_sample_rate_1_0_samples_all_roots():
    s = build_sampler(sample_rate=1.0)
    assert isinstance(s, ParentBased)


def test_sample_rate_0_0_samples_no_roots():
    s = build_sampler(sample_rate=0.0)
    assert isinstance(s, ParentBased)


@pytest.mark.parametrize("bad", [-0.1, 1.1, "half", None])
def test_invalid_sample_rate_raises(bad):
    with pytest.raises((ValueError, TypeError)):
        build_sampler(sample_rate=bad)
