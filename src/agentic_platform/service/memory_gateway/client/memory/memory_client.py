from agentic_platform.core.models.memory_models import (
    GetSessionContextRequest,
    GetSessionContextResponse,
    UpsertSessionContextRequest,
    UpsertSessionContextResponse,
    GetMemoriesRequest,
    GetMemoriesResponse,
    CreateMemoryRequest,
    CreateMemoryResponse
)

from agentic_platform.service.memory_gateway.client.memory.pg_memory_client import PGMemoryClient
from agentic_platform.service.memory_gateway.client.memory.bedrock_agentcore_memory_client import BedrockAgentCoreMemoryClient
import os
class MemoryClient:
    @classmethod
    def _get_provider(cls):
        # Get the provider from environment variable
        provider = os.environ.get("MEMORY_PROVIDER")
        if not provider:
            raise ValueError("MEMORY_PROVIDER environment variable must be set")
        if provider == "bedrock_agentcore":
            return BedrockAgentCoreMemoryClient
        return PGMemoryClient

    @classmethod
    def get_session_context(cls, request: GetSessionContextRequest) -> GetSessionContextResponse:
        return cls._get_provider().get_session_context(request)
    
    @classmethod
    def upsert_session_context(cls, request: UpsertSessionContextRequest) -> UpsertSessionContextResponse:
        return cls._get_provider().upsert_session_context(request)
    
    @classmethod
    def get_memories(cls, request: GetMemoriesRequest) -> GetMemoriesResponse:
        return cls._get_provider().get_memories(request)
    
    @classmethod
    def create_memory(cls, request: CreateMemoryRequest) -> CreateMemoryResponse:
        return cls._get_provider().create_memory(request)
