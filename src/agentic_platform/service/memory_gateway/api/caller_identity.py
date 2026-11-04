from fastapi import HTTPException, status

from agentic_platform.core.context.request_context import get_auth_context
from agentic_platform.core.models.auth_models import AgenticPlatformAuth


def get_caller_user_id() -> str:
    """
    Return the user_id of the authenticated caller from the request context.

    Memory gateway operations must be scoped to the verified caller, never to a
    user_id supplied in the request body. Fails closed if there is no
    authenticated user on the request.
    """
    auth: AgenticPlatformAuth | None = get_auth_context()
    if auth is None or auth.type != "user" or auth.user is None or not auth.user.user_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="An authenticated user is required to access memory",
        )
    return auth.user.user_id
