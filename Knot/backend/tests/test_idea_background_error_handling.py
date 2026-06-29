"""
Tests for error handling in the background idea-generation webhook
(`generate_ideas_background` in app.api.ideas).

Security focus (CodeQL py/stack-trace-exposure): when idea generation or the
database insert fails, the webhook response must return a generic reason and
must NOT leak raw exception text / stack-trace detail to the caller. The full
detail still goes to the server logs.

Run with: pytest tests/test_idea_background_error_handling.py -v
"""

import json
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.api.ideas import generate_ideas_background


# A sentinel string that, if it ever appears in the HTTP response, proves the
# raw exception text leaked out of the handler.
SECRET_EXC_TEXT = "postgres://admin:s3cret@db.internal:5432 connection refused"


def _fake_request(payload: dict):
    """Minimal stand-in for a Starlette Request the webhook needs."""
    request = MagicMock()
    request.body = AsyncMock(return_value=json.dumps(payload).encode())
    request.headers = MagicMock()
    request.headers.get = MagicMock(return_value="sig")
    request.url = "http://testserver/api/v1/ideas/background"
    return request


@pytest.mark.asyncio
async def test_generation_failure_returns_generic_reason():
    """A failure inside generate_ideas must surface a generic reason only."""
    request = _fake_request({"user_id": "user-123", "vault_id": "vault-456"})

    with patch("app.core.config.is_qstash_configured", return_value=True), \
         patch("app.services.qstash.verify_qstash_signature", return_value={}), \
         patch("app.api.ideas.load_vault_data",
               new=AsyncMock(return_value=(MagicMock(), None))), \
         patch("app.api.ideas._load_recent_hints", new=AsyncMock(return_value=[])), \
         patch("app.api.ideas.generate_ideas",
               new=AsyncMock(side_effect=Exception(SECRET_EXC_TEXT))):
        result = await generate_ideas_background(request)

    assert result == {"status": "error", "reason": "generation_failed"}
    assert SECRET_EXC_TEXT not in json.dumps(result)


@pytest.mark.asyncio
async def test_db_insert_failure_returns_generic_reason():
    """A failure inserting recommendations must not leak exception text."""
    request = _fake_request({"user_id": "user-123", "vault_id": "vault-456"})

    fake_idea = {"title": "Picnic", "description": "A picnic", "content_sections": []}
    failing_client = MagicMock()
    failing_client.table.side_effect = Exception(SECRET_EXC_TEXT)

    with patch("app.core.config.is_qstash_configured", return_value=True), \
         patch("app.services.qstash.verify_qstash_signature", return_value={}), \
         patch("app.api.ideas.load_vault_data",
               new=AsyncMock(return_value=(MagicMock(), None))), \
         patch("app.api.ideas._load_recent_hints", new=AsyncMock(return_value=[])), \
         patch("app.api.ideas.generate_ideas",
               new=AsyncMock(return_value=[fake_idea])), \
         patch("app.api.ideas.get_service_client", return_value=failing_client):
        result = await generate_ideas_background(request)

    assert result == {"status": "error", "reason": "db_insert_failed"}
    assert SECRET_EXC_TEXT not in json.dumps(result)
