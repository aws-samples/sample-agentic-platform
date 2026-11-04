from agentic_platform.core.models.memory_models import (
    GetMemoriesRequest,
    GetMemoriesResponse
)
from agentic_platform.service.memory_gateway.client.memory.memory_client import MemoryClient
from agentic_platform.service.memory_gateway.api.caller_identity import get_caller_user_id

class GetMemoriesController:
    @staticmethod
    def get_memories(request: GetMemoriesRequest) -> GetMemoriesResponse:
        # Scope to the authenticated caller; ignore any user_id in the body.
        scoped_request = request.model_copy(update={"user_id": get_caller_user_id()})
        return MemoryClient.get_memories(scoped_request)
