"""Tests for shared LLM latency-tuning parameters.

Verifies fast_generation_params disables thinking on every model and adds
output_config.effort only for effort-capable models — the exact split that
prevents a 400 on models (Haiku 4.5, Opus 4.0/4.1, older) that reject the
effort parameter.

Run with: pytest tests/test_llm_tuning.py -v
"""

import pytest

from app.services.llm_tuning import fast_generation_params


def test_thinking_disabled_on_every_model():
    for model in ("claude-haiku-4-5", "claude-sonnet-4-6", "claude-opus-4-8"):
        params = fast_generation_params(model)
        assert params["thinking"] == {"type": "disabled"}


@pytest.mark.parametrize(
    "model",
    ["claude-sonnet-4-6", "claude-opus-4-5", "claude-opus-4-6", "claude-opus-4-7", "claude-opus-4-8"],
)
def test_effort_added_for_effort_capable_models(model):
    params = fast_generation_params(model)
    assert params["output_config"] == {"effort": "low"}


@pytest.mark.parametrize(
    "model",
    [
        "claude-haiku-4-5",      # Haiku rejects effort
        "claude-sonnet-4-5",     # Sonnet 4.5 rejects effort
        "claude-opus-4-0",       # Opus 4.0/4.1 reject effort despite the "opus-4" family
        "claude-opus-4-1",
        "claude-3-5-haiku-20241022",
    ],
)
def test_effort_omitted_for_non_effort_capable_models(model):
    params = fast_generation_params(model)
    assert "output_config" not in params
