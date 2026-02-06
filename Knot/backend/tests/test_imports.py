"""
Step 0.5 Verification: Import Test Script

Tests that all backend dependencies are installed and importable.
Run with: pytest tests/test_imports.py -v
"""


def test_fastapi():
    """FastAPI — Web framework."""
    import fastapi
    assert hasattr(fastapi, "FastAPI")
    print(f"  fastapi {fastapi.__version__}")


def test_uvicorn():
    """Uvicorn — ASGI server."""
    import uvicorn
    assert hasattr(uvicorn, "run")
    print(f"  uvicorn {uvicorn.__version__}")


def test_langgraph():
    """LangGraph — AI orchestration."""
    from langgraph.graph import StateGraph
    assert StateGraph is not None
    print("  langgraph OK (StateGraph importable)")


def test_google_cloud_aiplatform():
    """Google Cloud AI Platform — Gemini 1.5 Pro via Vertex AI."""
    import google.cloud.aiplatform as aiplatform
    assert hasattr(aiplatform, "init")
    print(f"  google-cloud-aiplatform {aiplatform.__version__}")


def test_pydantic():
    """Pydantic — Data validation."""
    from pydantic import BaseModel
    assert BaseModel is not None
    import pydantic
    print(f"  pydantic {pydantic.__version__}")


def test_pydantic_ai():
    """Pydantic AI — AI output validation."""
    import pydantic_ai
    assert hasattr(pydantic_ai, "Agent")
    print(f"  pydantic-ai {pydantic_ai.__version__}")


def test_supabase():
    """Supabase — Database client."""
    from supabase import create_client
    assert create_client is not None
    import supabase
    print(f"  supabase {supabase.__version__}")


def test_pgvector():
    """pgvector — Vector search support."""
    from pgvector import Vector
    assert Vector is not None
    # Verify we can encode a vector for database storage
    vec = Vector([1.0, 2.0, 3.0])
    assert vec is not None
    print("  pgvector OK (Vector type importable)")


def test_httpx():
    """httpx — Async HTTP client for external API integrations."""
    import httpx
    assert hasattr(httpx, "AsyncClient")
    print(f"  httpx {httpx.__version__}")


def test_python_dotenv():
    """python-dotenv — Environment variable management."""
    from dotenv import load_dotenv
    assert load_dotenv is not None
    print("  python-dotenv OK")


def test_pytest_asyncio():
    """pytest-asyncio — Async test support."""
    import pytest_asyncio
    assert pytest_asyncio is not None
    print("  pytest-asyncio OK")
