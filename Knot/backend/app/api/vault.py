"""
Vault API — Partner Vault CRUD operations.

Handles creation, retrieval, and updates of the Partner Vault,
including interests, milestones, vibes, budgets, and love languages.
"""

from fastapi import APIRouter

router = APIRouter(prefix="/api/v1/vault", tags=["vault"])
