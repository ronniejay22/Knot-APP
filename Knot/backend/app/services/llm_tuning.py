"""Shared latency-tuning parameters for Claude generation calls.

Sonnet 4.6 defaults to deliberative high-effort thinking, which roughly doubles
generation latency versus the retired Sonnet 4 (`claude-sonnet-4-20250514`) the
recommendation pipeline was originally tuned against. The pipeline does
structured content generation, not deep reasoning, so we disable thinking and
run at low effort to keep latency near the ~30s target.

`output_config.effort` is only accepted by effort-capable models — Sonnet 4.6
and Opus 4.5+ support it; Sonnet 4.5, Haiku 4.5, Opus 4.0/4.1, and older return
a 400 if it is sent — so it is added conditionally.
"""

# Model-ID prefixes that accept the `output_config.effort` parameter. Listed
# explicitly rather than as a broad "claude-opus-4" prefix because Opus 4.0 and
# 4.1 do NOT support effort and would 400.
_EFFORT_CAPABLE_PREFIXES = (
    "claude-sonnet-4-6",
    "claude-opus-4-5",
    "claude-opus-4-6",
    "claude-opus-4-7",
    "claude-opus-4-8",
)


def fast_generation_params(model: str) -> dict:
    """Return create() kwargs that keep structured generation fast.

    Disables thinking on every model, and adds `effort: "low"` only for models
    that support the effort parameter.
    """
    params: dict = {"thinking": {"type": "disabled"}}
    if any(model.startswith(prefix) for prefix in _EFFORT_CAPABLE_PREFIXES):
        params["output_config"] = {"effort": "low"}
    return params
