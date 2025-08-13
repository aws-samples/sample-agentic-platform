from agentic_platform.core.models.memory_models import (
    GetSessionContextRequest,
    GetSessionContextResponse,
    UpsertSessionContextRequest,
    UpsertSessionContextResponse,
    GetMemoriesRequest,
    GetMemoriesResponse,
    CreateMemoryRequest,
    CreateMemoryResponse,
    SessionContext,
    Memory,
    Message,
    TextContent
)
from bedrock_agentcore.memory import MemoryClient
import os
import logging
import json
import uuid
from datetime import datetime
from typing import List, Dict, Any, Optional

logger = logging.getLogger(__name__)
if not logger.handlers:
    # Add basic configuration if none exists
    logging.basicConfig(level=logging.INFO)

class BedrockAgentCoreMemoryClient:
    _client = None
    _memory_id = None
    
    @classmethod
    def _get_client(cls):
        if cls._client is None:
            region = os.environ.get("AWS_DEFAULT_REGION")
            cls._client = MemoryClient(region_name=region)
        return cls._client
    
    @classmethod
    def _get_memory_id(cls):
        if cls._memory_id is None:
            # Get memory ID from environment variable
            # This should be set in the configmap in memory-gateway-values.yaml
            # or provided during deployment
            cls._memory_id = os.environ.get("BEDROCK_AGENTCORE_MEMORY_ID")
            if not cls._memory_id:
                # List existing memories and use the first one if available
                memories = cls._get_client().list_memories()
                if memories:
                    cls._memory_id = memories[0].get("id")
                else:
                    # Create a new memory resource if none exists
                    memory = cls._get_client().create_memory(
                        name="AgenticPlatformMemory",
                        description="Memory for agentic platform conversations"
                    )
                    cls._memory_id = memory.get("id")
        return cls._memory_id
    
    @classmethod
    def get_session_context(cls, request: GetSessionContextRequest) -> GetSessionContextResponse:
        """
        Retrieves session contexts based on user_id or session_id using Bedrock AgentCore Memory.
        """
        logger.info(f"Getting session context for request: {request}")
        
        if not request.session_id:
            # If no session_id is provided, we can't retrieve the context
            return GetSessionContextResponse(results=[])
        
        # Use actor_id as user_id if provided, otherwise use a default
        actor_id = request.user_id if request.user_id else "default_user"
        
        try:
            # List events from Bedrock AgentCore Memory
            events = cls._get_client().list_events(
                memory_id=cls._get_memory_id(),
                actor_id=actor_id,
                session_id=request.session_id
            )
            
            if not events:
                return GetSessionContextResponse(results=[])
            
            # Convert events to session context
            messages = []
            for event in events:
                for payload in event.get("payload", []):
                    if "Conversational" in payload:
                        conv = payload["Conversational"]
                        role = conv.get("role", "").lower()
                        if role in ["user", "assistant"]:
                            messages.append(Message.from_text(
                                role=role,
                                text=conv.get("content", "")
                            ))
            
            # Create a session context from the messages
            session_context = SessionContext(
                session_id=request.session_id,
                user_id=actor_id,
                agent_id=None,  # Agent ID is not stored in Bedrock AgentCore Memory
                messages=messages,
                system_prompt=None,  # System prompt is not stored in Bedrock AgentCore Memory
                session_metadata={}
            )
            
            return GetSessionContextResponse(results=[session_context])
        except Exception as e:
            logger.error(f"Error getting session context: {e}")
            return GetSessionContextResponse(results=[])
    
    @classmethod
    def upsert_session_context(cls, request: UpsertSessionContextRequest) -> UpsertSessionContextResponse:
        """
        Upserts a session context using Bedrock AgentCore Memory.
        """
        logger.info(f"Upserting session context")
        
        session_context = request.session_context
        
        # Use actor_id as user_id if provided, otherwise use a default
        actor_id = session_context.user_id if session_context.user_id else "default_user"
        
        try:
            # Convert messages to Bedrock AgentCore Memory format
            messages = []
            for msg in session_context.messages:
                role = msg.role.upper()  # Bedrock AgentCore Memory uses uppercase roles
                text = msg.text if msg.text else ""
                messages.append((text, role))
            
            # Create event in Bedrock AgentCore Memory
            if messages:
                cls._get_client().create_event(
                    memory_id=cls._get_memory_id(),
                    actor_id=actor_id,
                    session_id=session_context.session_id,
                    messages=messages
                )
            
            return UpsertSessionContextResponse(session_context=session_context)
        except Exception as e:
            logger.error(f"Error upserting session context: {e}")
            raise
    
    @classmethod
    def get_memories(cls, request: GetMemoriesRequest) -> GetMemoriesResponse:
        """
        Retrieves memories based on user_id, session_id, or agent_id using Bedrock AgentCore Memory.
        """
        logger.info(f"Getting memories for request: {request}")
        
        if not request.session_id:
            # If no session_id is provided, we can't retrieve memories
            return GetMemoriesResponse(memories=[])
        
        # Use actor_id as user_id if provided, otherwise use a default
        actor_id = request.user_id if request.user_id else "default_user"
        
        try:
            # List events from Bedrock AgentCore Memory
            events = cls._get_client().list_events(
                memory_id=cls._get_memory_id(),
                actor_id=actor_id,
                session_id=request.session_id,
                max_results=request.limit if hasattr(request, 'limit') else 10
            )
            
            if not events:
                return GetMemoriesResponse(memories=[])
            
            # Convert events to memories
            memories = []
            for event in events:
                # Combine all conversational content into a single string
                content = []
                for payload in event.get("payload", []):
                    if "Conversational" in payload:
                        conv = payload["Conversational"]
                        content.append(f"{conv.get('role', '')}: {conv.get('content', '')}")
                
                content_str = "\n".join(content)
                
                memory = Memory(
                    memory_id=str(uuid.uuid4()),
                    session_id=request.session_id,
                    user_id=actor_id,
                    agent_id=request.agent_id if request.agent_id else "default_agent",
                    content=content_str,
                    embedding_model="bedrock_agentcore",
                    created_at=datetime.fromtimestamp(event.get("eventTimestamp", 0) / 1000) if event.get("eventTimestamp") else datetime.now(),
                    updated_at=datetime.fromtimestamp(event.get("eventTimestamp", 0) / 1000) if event.get("eventTimestamp") else datetime.now()
                )
                
                memories.append(memory)
            
            return GetMemoriesResponse(memories=memories)
        except Exception as e:
            logger.error(f"Error getting memories: {e}")
            return GetMemoriesResponse(memories=[])
    
    @classmethod
    def create_memory(cls, request: CreateMemoryRequest) -> CreateMemoryResponse:
        """
        Creates a memory using Bedrock AgentCore Memory.
        """
        logger.info(f"Creating memory for request: {request}")
        
        # Use actor_id as user_id if provided, otherwise use a default
        actor_id = request.user_id if request.user_id else "default_user"
        
        try:
            # Convert messages to Bedrock AgentCore Memory format
            messages = []
            for msg in request.session_context.messages:
                role = msg.role.upper()  # Bedrock AgentCore Memory uses uppercase roles
                text = msg.text if msg.text else ""
                messages.append((text, role))
            
            # Create event in Bedrock AgentCore Memory
            event = cls._get_client().create_event(
                memory_id=cls._get_memory_id(),
                actor_id=actor_id,
                session_id=request.session_id,
                messages=messages
            )
            
            # Create a Memory object to return
            # Combine all messages into a single content string
            content = []
            for msg in request.session_context.messages:
                content.append(f"{msg.role}: {msg.text if msg.text else ''}")
            
            content_str = "\n".join(content)
            
            memory = Memory(
                memory_id=str(uuid.uuid4()),
                session_id=request.session_id,
                user_id=actor_id,
                agent_id=request.agent_id,
                content=content_str,
                embedding_model="bedrock_agentcore",
                created_at=datetime.now(),
                updated_at=datetime.now()
            )
            
            return CreateMemoryResponse(memory=memory)
        except Exception as e:
            logger.error(f"Error creating memory: {e}")
            raise
