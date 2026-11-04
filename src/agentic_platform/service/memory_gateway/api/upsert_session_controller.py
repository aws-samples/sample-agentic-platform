from fastapi import HTTPException, status

from agentic_platform.core.models.memory_models import (
    UpsertSessionContextRequest,
    UpsertSessionContextResponse
)
from agentic_platform.service.memory_gateway.client.memory.memory_client import MemoryClient
from agentic_platform.service.memory_gateway.api.caller_identity import get_caller_user_id

class UpsertSessionContextController:
    @staticmethod
    def upsert_session_context(request: UpsertSessionContextRequest) -> UpsertSessionContextResponse:
        # Scope to the authenticated caller; ignore any user_id in the body.
        session_context = request.session_context.model_copy(update={"user_id": get_caller_user_id()})
        scoped_request = request.model_copy(update={"session_context": session_context})
        try:
            return MemoryClient.upsert_session_context(scoped_request)
        except PermissionError:
            # Don't reveal whether the session exists for someone else.
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Forbidden")
