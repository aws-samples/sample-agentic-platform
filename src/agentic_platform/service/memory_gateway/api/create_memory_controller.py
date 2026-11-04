from agentic_platform.core.models.memory_models import (
    CreateMemoryRequest,
    CreateMemoryResponse
)
from agentic_platform.service.memory_gateway.client.memory.memory_client import MemoryClient
from agentic_platform.service.memory_gateway.api.caller_identity import get_caller_user_id

class CreateMemoryController:
    @staticmethod
    def create_memory(request: CreateMemoryRequest) -> CreateMemoryResponse:
        # Scope to the authenticated caller; ignore any user_id in the body.
        user_id = get_caller_user_id()
        session_context = request.session_context.model_copy(update={"user_id": user_id})
        scoped_request = request.model_copy(update={"user_id": user_id, "session_context": session_context})
        return MemoryClient.create_memory(scoped_request)
