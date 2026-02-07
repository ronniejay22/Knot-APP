"""
Security — Authentication and authorization middleware.

Validates Bearer tokens against Supabase Auth and extracts
the authenticated user's ID for use in route handlers.

Usage in route handlers:
    from app.core.security import get_current_user_id

    @router.get("/protected")
    async def protected_route(user_id: str = Depends(get_current_user_id)):
        return {"user_id": user_id}
"""

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
import httpx

from app.core.config import SUPABASE_URL

# HTTPBearer extracts the Bearer token from the Authorization header.
# auto_error=False so we can return a custom 401 message instead of
# FastAPI's default 403 for missing credentials.
_bearer_scheme = HTTPBearer(auto_error=False)


async def get_current_user_id(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer_scheme),
) -> str:
    """
    FastAPI dependency that validates the Supabase JWT and returns the user ID.

    Extracts the Bearer token from the Authorization header, sends it to
    Supabase Auth's /auth/v1/user endpoint for validation, and returns
    the authenticated user's UUID string.

    Raises:
        HTTPException(401): If the token is missing, invalid, or expired.

    Returns:
        str: The authenticated user's UUID (from auth.users.id).
    """
    # --- 1. Check that a token was provided ---
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing authentication token. Provide a Bearer token in the Authorization header.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    token = credentials.credentials

    # --- 2. Validate the token against Supabase Auth ---
    # The /auth/v1/user endpoint returns the authenticated user's profile
    # when called with a valid access token. If the token is invalid or
    # expired, Supabase returns a 401 error.
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{SUPABASE_URL}/auth/v1/user",
                headers={
                    "Authorization": f"Bearer {token}",
                    "apikey": _get_apikey(),
                },
                timeout=10.0,
            )
    except httpx.RequestError as exc:
        # Network error — Supabase unreachable
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication service unavailable. Please try again.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc

    # --- 3. Handle the response ---
    if response.status_code != 200:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired authentication token.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        user_data = response.json()
    except (ValueError, KeyError):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication service returned an invalid response.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    user_id = user_data.get("id")

    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication token — no user ID found.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return user_id


def _get_apikey() -> str:
    """
    Returns the Supabase anon key for API requests.

    The apikey header is required by Supabase's API gateway (Kong)
    for all requests, including authenticated ones. The anon key is
    safe to use here — actual access control is enforced by the
    Bearer token (JWT) and RLS policies.

    Lazy import to avoid circular dependency with config module.
    """
    from app.core.config import SUPABASE_ANON_KEY
    return SUPABASE_ANON_KEY
