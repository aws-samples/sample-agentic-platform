from agentic_platform.core.db.postgres import PostgresDB, write_postgres_db, read_postgres_db
from agentic_platform.core.models.memory_models import (
    SessionContext, 
    Memory,
    GetSessionContextRequest,
    GetSessionContextResponse,
    GetMemoriesRequest,
    GetMemoriesResponse,
    CreateMemoryRequest,
    CreateMemoryResponse,
    UpsertSessionContextRequest,
    UpsertSessionContextResponse
)
from agentic_platform.service.memory_gateway.prompt.create_memory_prompt import CreateMemoryPrompt
from agentic_platform.core.models.llm_models import LLMRequest, LLMResponse, Message
from agentic_platform.core.models.embedding_models import EmbedRequest, EmbedResponse
from agentic_platform.core.formatter.extract_regex_formatter import ExtractRegexFormatter
from agentic_platform.core.client.llm_gateway.llm_gateway_client import LLMGatewayClient
from agentic_platform.core.context.request_context import set_auth_token, get_auth_token
import os

from sqlalchemy import MetaData, Table, Column, Text, select, insert, DateTime, func
from sqlalchemy import Result
from pgvector.sqlalchemy import Vector
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy import and_, desc
import uuid
import json
from typing import List
from sqlalchemy.dialects.postgresql import insert
import logging

# Note: WARNING
# Bad things will happen if you change this without migrating existing embeddings to the new embedding space.
EMBEDDING_MODEL: str = "amazon.titan-embed-text-v2:0"

logger = logging.getLogger(__name__)
if not logger.handlers:
    # Add basic configuration if none exists
    logging.basicConfig(level=logging.INFO)

SESSION_CONTEXT_TABLE_NAME: str = 'session_context'
MEMORY_TABLE_NAME: str = 'memory'

metadata = MetaData()
SESSION_CONTEXT_TABLE: Table = Table(
    "session_context", metadata,
    Column('session_id', UUID(as_uuid=True), primary_key=True, default=uuid.uuid4),
    Column('user_id', Text, nullable=True),
    Column('agent_id', Text, nullable=True),
    Column('system_prompt', Text),
    Column('messages', JSONB, nullable=False),
    Column('session_metadata', JSONB),
    Column('created_at', DateTime(timezone=True), server_default='now()'),
    Column('updated_at', DateTime(timezone=True), server_default='now()'),
)

MEMORY_TABLE: Table = Table(
    "memory", metadata,
    Column('memory_id', UUID(as_uuid=True), primary_key=True, default=uuid.uuid4),
    Column('session_id', UUID(as_uuid=True)),
    Column('user_id', Text, nullable=True),
    Column('agent_id', UUID(as_uuid=True), nullable=True),
    Column('memory_type', Text, nullable=False, default='general'),
    Column('content', Text, nullable=False),
    Column('embedding_model', Text, nullable=False),
    Column('embedding', Vector(1024)),
    Column('created_at', DateTime(timezone=True), server_default='now()'),
    Column('updated_at', DateTime(timezone=True), server_default='now()'),
)

read_db: PostgresDB = read_postgres_db
write_db: PostgresDB = write_postgres_db

class PGMemoryClient:

    @classmethod
    def get_session_context(cls, request: GetSessionContextRequest) -> GetSessionContextResponse:
        """
        Retrieves session contexts based on user_id or session_id using SQLAlchemy Core.
        """
        logger.info(f"Getting session context for request: {request}")

        # Start with a base query selecting all columns
        query = select(SESSION_CONTEXT_TABLE)
        # Build conditions list
        conditions = []
        # Add conditions based on request parameters
        if request.session_id:
            conditions.append(SESSION_CONTEXT_TABLE.c.session_id == request.session_id)
        
        if request.user_id:
            conditions.append(SESSION_CONTEXT_TABLE.c.user_id == request.user_id)
        
        # Add all conditions to the query if any exist
        query = query.where(and_(*conditions))
        # Add ordering
        query = query.order_by(desc(SESSION_CONTEXT_TABLE.c.created_at))
        
        # Add limit if specified
        if hasattr(request, 'limit') and request.limit:
            query = query.limit(request.limit)
        
        # Execute the query
        with read_db.connect() as conn:
            result = conn.execute(query)
            session_contexts = [dict(row._mapping) for row in result]

        logger.debug(session_contexts)

        # Convert UUID objects to strings
        for context in session_contexts:
            if 'session_id' in context and isinstance(context['session_id'], uuid.UUID):
                context['session_id'] = str(context['session_id'])

        contexts: List[SessionContext] = [SessionContext(**c) for c in session_contexts]
        return GetSessionContextResponse(results=contexts)
    
    @classmethod
    def upsert_session_context(cls, request: UpsertSessionContextRequest) -> UpsertSessionContextResponse:
        """
        Upserts a session context using SQLAlchemy's PostgreSQL dialect.
        Updates all non-primary key fields on conflict.
        """
        # Get data as a JSON-serializable dict
        data = json.loads(request.session_context.model_dump_json())
        logger.info(f"Upserting session context: {data}")
        
        with write_db.connect() as conn:
            # Create the upsert statement in one clean chain
            stmt = insert(SESSION_CONTEXT_TABLE).values(data)
            
            # Set up on_conflict to update all fields except primary key and created_at
            stmt = stmt.on_conflict_do_update(
                index_elements=['session_id'],
                set_={
                    'user_id': data.get('user_id'),
                    'agent_id': data.get('agent_id'),
                    'system_prompt': data.get('system_prompt'),
                    'messages': data.get('messages'),
                    'session_metadata': data.get('session_metadata'),
                    'updated_at': func.now()
                },
                # Only the owner of an existing session may update it. Without this,
                # anyone who knows a session_id could overwrite (and take over) it.
                where=SESSION_CONTEXT_TABLE.c.user_id == data.get('user_id')
            )

            result = conn.execute(stmt)
            if result.rowcount == 0:
                # Conflict on session_id with a row owned by a different user.
                conn.rollback()
                raise PermissionError("Session context belongs to a different user")
            conn.commit()
            logger.info(f"Executed stmt: {stmt}")
        
        return UpsertSessionContextResponse(session_context=request.session_context)

    @classmethod
    def get_memories(cls, request: GetMemoriesRequest) -> GetMemoriesResponse:
        """
        Retrieves memories based on user_id, session_id, or agent_id using SQLAlchemy Core.
        """
        # Start with a base query selecting all columns
        if request.embedding:
            # Use raw SQL expression for cosine distance calculation
            from sqlalchemy.sql import text
            
            # Create a properly aliased similarity expression with parameters
            from sqlalchemy import label
            similarity_expr = text("1 - (memory.embedding <=> :embedding)").bindparams(embedding=str(request.embedding))
            # Use the label function from sqlalchemy instead of as a method
            query = select(MEMORY_TABLE, label('similarity', similarity_expr))
        else:
            query = select(MEMORY_TABLE)

        # Build conditions list
        conditions = []
        if request.session_id:
            conditions.append(MEMORY_TABLE.c.session_id == request.session_id)
        if request.user_id:
            conditions.append(MEMORY_TABLE.c.user_id == request.user_id)
        if request.agent_id:
            # Convert agent_id to UUID if it's not already a UUID
            agent_id = request.agent_id
            if agent_id and not isinstance(agent_id, uuid.UUID):
                try:
                    agent_id = uuid.UUID(agent_id)
                except ValueError:
                    # If agent_id is not a valid UUID string, generate a new UUID based on the string
                    agent_id = uuid.uuid5(uuid.NAMESPACE_DNS, agent_id)
            conditions.append(MEMORY_TABLE.c.agent_id == agent_id)

        # Add memory_type condition if present
        if hasattr(request, 'memory_type') and request.memory_type:
            conditions.append(MEMORY_TABLE.c.memory_type == request.memory_type)
        
        # Add all conditions to the query if any exist
        query = query.where(and_(*conditions))
        # Add ordering
        if request.embedding:
            # Use the desc function directly instead of as a method
            query = query.order_by(desc(text('similarity')))
        else:
            query = query.order_by(desc(MEMORY_TABLE.c.created_at))
        
        # Add limit if specified    
        if hasattr(request, 'limit') and request.limit:
            query = query.limit(request.limit)
        
        # Execute the query
        with read_db.connect() as conn:
            print(f"Executing query {query}")
            result = conn.execute(query)
            memories = [dict(row._mapping) for row in result]
        
        # Convert UUID objects to strings
        for memory in memories:
            if 'memory_id' in memory and isinstance(memory['memory_id'], uuid.UUID):
                memory['memory_id'] = str(memory['memory_id'])
            if 'session_id' in memory and isinstance(memory['session_id'], uuid.UUID):
                memory['session_id'] = str(memory['session_id'])
            if 'agent_id' in memory and isinstance(memory['agent_id'], uuid.UUID):
                memory['agent_id'] = str(memory['agent_id'])
        
        memory_objects = [Memory(**m) for m in memories]
        return GetMemoriesResponse(memories=memory_objects)

    @classmethod
    def create_memory(cls, request: CreateMemoryRequest) -> CreateMemoryResponse:
        """
        This class is interesting. We first need to call an LLM to get something "embeddable" from the history.
        Then we need to store the history, and then we need to embed the history and store the embedding.
        """
        logger.info(f"Creating memory for request: {request}")

        # Get the session context from the request
        session_context: SessionContext = request.session_context
        if not request.session_context.get_messages():
            raise ValueError("No messages found in session context")
        
        # Convert the messages to a JSON string
        # First convert Message objects to dictionaries using model_dump()
        messages_dict = [message.model_dump() for message in request.session_context.get_messages()]
        interaction_json: str = json.dumps(messages_dict)
        logger.info(f"Interaction JSON: {interaction_json}")

        # Construct our memory prompt from our prompt library.
        # Note: This prompt returns XML which we need to regex out before embedding it.
        memory_prompt: CreateMemoryPrompt = CreateMemoryPrompt(
            inputs={"interaction_json": interaction_json}
        )
        logger.info(f"Memory prompt: {memory_prompt}")
        
        llm_request: LLMRequest = LLMRequest(
            model_id=memory_prompt.model_id,
            system_prompt=memory_prompt.system_prompt,
            messages=[Message(role="user", text=memory_prompt.user_prompt)],
            hyperparams=memory_prompt.hyperparams
        )

        # Generate the memory from the LLM.
        memory_response: LLMResponse = LLMGatewayClient.chat_invoke(llm_request)
        logger.info(f"Memory response: {memory_response}")

        # Extract the memory from the LLM response.
        memory_content: str | None = ExtractRegexFormatter.extract_response(
            memory_response.text, 
            r'<memory>(.*?)</memory>'
        )

        if not memory_content:
            raise Exception("No memory content found in LLM response")

        embedding_request: EmbedRequest = EmbedRequest(
            text=memory_content,
            model_id=EMBEDDING_MODEL
        )

        # No need to set auth token in local environment as the BedrockGatewayClient
        # will now use IAM credentials directly
            
        embedding_response: EmbedResponse = LLMGatewayClient.embed_invoke(embedding_request)

        # Convert messages to JSON string for content field
        messages_dict = [message.model_dump() for message in request.session_context.get_messages()]
        messages_json = json.dumps(messages_dict)
        
        # Convert agent_id to UUID if it's not already a UUID
        agent_id = request.agent_id
        if agent_id and not isinstance(agent_id, uuid.UUID):
            try:
                agent_id = uuid.UUID(agent_id)
            except ValueError:
                # If agent_id is not a valid UUID string, generate a new UUID based on the string
                agent_id = uuid.uuid5(uuid.NAMESPACE_DNS, agent_id)
        
        memory: Memory = Memory(
            session_id=request.session_id,
            user_id=request.user_id,
            agent_id=str(agent_id),  # Convert UUID back to string for the model
            content=messages_json,  # Use JSON string instead of Message objects
            embedding_model=EMBEDDING_MODEL,  # Add the embedding model
            embedding=embedding_response.embedding
        )

        # Prepare the data for insertion, ensuring agent_id is a UUID object
        memory_data = memory.model_dump()
        # Remove the similarity field as it's not a column in the database table
        if 'similarity' in memory_data:
            del memory_data['similarity']
            
        if 'agent_id' in memory_data and memory_data['agent_id']:
            # Convert string agent_id back to UUID for database insertion
            memory_data['agent_id'] = agent_id
            
        with write_db.connect() as conn:
            conn.execute(
                insert(MEMORY_TABLE).values(memory_data)
            )
            conn.commit()

        return CreateMemoryResponse(memory=memory)
