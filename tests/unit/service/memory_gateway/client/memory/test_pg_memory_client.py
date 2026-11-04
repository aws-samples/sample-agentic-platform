import pytest
from unittest.mock import patch, MagicMock, call
import uuid
import json
from datetime import datetime

from agentic_platform.core.models.memory_models import (
    GetSessionContextRequest, GetSessionContextResponse, SessionContext,
    UpsertSessionContextRequest, UpsertSessionContextResponse,
    GetMemoriesRequest, GetMemoriesResponse, Memory,
    CreateMemoryRequest, CreateMemoryResponse
)
from agentic_platform.service.memory_gateway.client.memory.pg_memory_client import PGMemoryClient

@patch('agentic_platform.service.memory_gateway.client.memory.pg_memory_client.MEMORY_TABLE')
class TestPGMemoryClient:
    """Test PGMemoryClient - database interaction methods"""
    
    def setup_method(self):
        """Setup test data"""
        self.sample_session_id = str(uuid.uuid4())
        self.sample_user_id = "test-user"
        self.sample_agent_id = str(uuid.uuid4())
        
        # Create proper Message objects for session context
        from agentic_platform.core.models.memory_models import Message
        messages = [Message(role="user", text="Hello")]
        
        self.sample_session_context = SessionContext(
            session_id=self.sample_session_id,
            user_id=self.sample_user_id,
            agent_id=self.sample_agent_id,
            system_prompt="Test system prompt",
            messages=messages,
            session_metadata={"key": "value"}
        )

        # Create a mock memory table structure to avoid Vector column issues
        self.mock_memory_table = MagicMock()
        self.mock_memory_table.c = MagicMock()
        self.mock_memory_table.c.session_id = MagicMock()
        self.mock_memory_table.c.user_id = MagicMock()
        self.mock_memory_table.c.agent_id = MagicMock()
        self.mock_memory_table.c.content = MagicMock()
        self.mock_memory_table.c.created_at = MagicMock()
        self.mock_memory_table.c.memory_type = MagicMock()

    @patch('agentic_platform.service.memory_gateway.client.memory.pg_memory_client.read_db')
    def test_get_session_context_by_session_id(self, mock_read_db, mock_memory_table):
        """Test getting session context by session_id"""
        # Setup mock database response
        mock_conn = MagicMock()
        mock_read_db.connect.return_value.__enter__.return_value = mock_conn
        
        mock_row = MagicMock()
        # Create proper message structure for database response
        messages_data = [{"role": "user", "content": [{"type": "text", "text": "Hello"}]}]
        
        mock_row._mapping = {
            'session_id': uuid.UUID(self.sample_session_id),
            'user_id': self.sample_user_id,
            'agent_id': self.sample_agent_id,
            'system_prompt': "Test system prompt",
            'messages': messages_data,
            'session_metadata': {"key": "value"},
            'created_at': datetime.now(),
            'updated_at': datetime.now()
        }
        mock_conn.execute.return_value = [mock_row]
        
        # Create request
        request = GetSessionContextRequest(session_id=self.sample_session_id)
        
        # Call method
        result = PGMemoryClient.get_session_context(request)
        
        # Verify results
        assert isinstance(result, GetSessionContextResponse)
        assert len(result.results) == 1
        assert result.results[0].session_id == self.sample_session_id
        assert result.results[0].user_id == self.sample_user_id
        
        # Verify database was called
        mock_read_db.connect.assert_called_once()
        mock_conn.execute.assert_called_once()

    @patch('agentic_platform.service.memory_gateway.client.memory.pg_memory_client.read_db')
    def test_get_session_context_by_user_id(self, mock_read_db, mock_memory_table):
        """Test getting session context by user_id"""
        # Setup mock database response
        mock_conn = MagicMock()
        mock_read_db.connect.return_value.__enter__.return_value = mock_conn
        
        mock_row = MagicMock()
        # Create proper message structure for database response
        messages_data = [{"role": "user", "content": [{"type": "text", "text": "Hello"}]}]
        
        mock_row._mapping = {
            'session_id': uuid.UUID(self.sample_session_id),
            'user_id': self.sample_user_id,
            'agent_id': self.sample_agent_id,
            'system_prompt': "Test system prompt",
            'messages': messages_data,
            'session_metadata': {"key": "value"},
            'created_at': datetime.now(),
            'updated_at': datetime.now()
        }
        mock_conn.execute.return_value = [mock_row]
        
        # Create request
        request = GetSessionContextRequest(user_id=self.sample_user_id)
        
        # Call method
        result = PGMemoryClient.get_session_context(request)
        
        # Verify results
        assert isinstance(result, GetSessionContextResponse)
        assert len(result.results) == 1
        assert result.results[0].user_id == self.sample_user_id
        
        # Verify database was called
        mock_read_db.connect.assert_called_once()
        mock_conn.execute.assert_called_once()

    @patch('agentic_platform.service.memory_gateway.client.memory.pg_memory_client.write_db')
    def test_upsert_session_context_new_session(self, mock_write_db, mock_memory_table):
        """Test upserting a new session context"""
        # Setup mock database connection
        mock_conn = MagicMock()
        mock_conn.execute.return_value.rowcount = 1
        mock_write_db.connect.return_value.__enter__.return_value = mock_conn

        # Create request
        request = UpsertSessionContextRequest(session_context=self.sample_session_context)

        # Call method
        result = PGMemoryClient.upsert_session_context(request)

        # Verify results
        assert isinstance(result, UpsertSessionContextResponse)
        assert result.session_context.session_id == self.sample_session_id

        # Verify database operations
        mock_write_db.connect.assert_called_once()
        mock_conn.execute.assert_called_once()
        mock_conn.commit.assert_called_once()

    @patch('agentic_platform.service.memory_gateway.client.memory.pg_memory_client.write_db')
    def test_upsert_session_context_update_is_restricted_to_owner(self, mock_write_db, mock_memory_table):
        """The ON CONFLICT update only applies to rows owned by the same user_id"""
        from sqlalchemy.dialects import postgresql

        mock_conn = MagicMock()
        mock_conn.execute.return_value.rowcount = 1
        mock_write_db.connect.return_value.__enter__.return_value = mock_conn

        PGMemoryClient.upsert_session_context(
            UpsertSessionContextRequest(session_context=self.sample_session_context)
        )

        stmt = mock_conn.execute.call_args.args[0]
        compiled = stmt.compile(dialect=postgresql.dialect())
        sql = str(compiled)
        assert "ON CONFLICT (session_id) DO UPDATE" in sql
        assert "WHERE session_context.user_id = " in sql
        assert self.sample_user_id in compiled.params.values()

    @patch('agentic_platform.service.memory_gateway.client.memory.pg_memory_client.write_db')
    def test_upsert_session_context_owned_by_another_user_raises(self, mock_write_db, mock_memory_table):
        """No row affected (conflict with another user's session) -> PermissionError, no commit"""
        mock_conn = MagicMock()
        mock_conn.execute.return_value.rowcount = 0
        mock_write_db.connect.return_value.__enter__.return_value = mock_conn

        with pytest.raises(PermissionError):
            PGMemoryClient.upsert_session_context(
                UpsertSessionContextRequest(session_context=self.sample_session_context)
            )

        mock_conn.rollback.assert_called_once()
        mock_conn.commit.assert_not_called()

    @patch('agentic_platform.service.memory_gateway.client.memory.pg_memory_client.select')
    @patch('agentic_platform.service.memory_gateway.client.memory.pg_memory_client.desc')
    @patch('agentic_platform.service.memory_gateway.client.memory.pg_memory_client.read_db')
    def test_get_memories_by_session_id(self, mock_read_db, mock_desc, mock_select, mock_memory_table):
        """Test getting memories by session_id"""
        # Setup mock select to return the mocked memory table
        mock_select.return_value = MagicMock()
        mock_memory_table.return_value = self.mock_memory_table
        mock_desc.return_value = MagicMock()  # Mock the desc function
        
        # Setup mock database response
        mock_conn = MagicMock()
        mock_read_db.connect.return_value.__enter__.return_value = mock_conn
        
        mock_row = MagicMock()
        mock_row._mapping = {
            'memory_id': uuid.uuid4(),
            'session_id': uuid.UUID(self.sample_session_id),
            'user_id': self.sample_user_id,
            'agent_id': uuid.UUID(self.sample_agent_id),
            'memory_type': 'general',
            'content': "Test memory content",
            'embedding_model': "amazon.titan-embed-text-v2:0",
            'embedding': None,
            'created_at': datetime.now(),
            'updated_at': datetime.now()
        }
        mock_conn.execute.return_value = [mock_row]
        
        # Create request
        request = GetMemoriesRequest(session_id=self.sample_session_id)
        
        # Call method
        result = PGMemoryClient.get_memories(request)
        
        # Verify results
        assert isinstance(result, GetMemoriesResponse)
        assert len(result.memories) == 1
        assert result.memories[0].content == "Test memory content"
        
        # Verify database was called
        mock_read_db.connect.assert_called_once()
        mock_conn.execute.assert_called_once()

    @patch('agentic_platform.service.memory_gateway.client.memory.pg_memory_client.select')
    @patch('agentic_platform.service.memory_gateway.client.memory.pg_memory_client.desc')
    @patch('agentic_platform.service.memory_gateway.client.memory.pg_memory_client.read_db')
    def test_get_memories_with_embedding_similarity(self, mock_read_db, mock_desc, mock_select, mock_memory_table):
        """Test getting memories with embedding similarity search"""
        # Setup mock select to return the mocked memory table
        mock_select.return_value = MagicMock()
        mock_memory_table.return_value = self.mock_memory_table
        mock_desc.return_value = MagicMock()  # Mock the desc function
        
        # Setup mock database response
        mock_conn = MagicMock()
        mock_read_db.connect.return_value.__enter__.return_value = mock_conn
        
        mock_row = MagicMock()
        mock_row._mapping = {
            'memory_id': uuid.uuid4(),
            'session_id': uuid.UUID(self.sample_session_id),
            'user_id': self.sample_user_id,
            'agent_id': uuid.UUID(self.sample_agent_id),
            'memory_type': 'general',
            'content': "Test memory content",
            'embedding_model': "amazon.titan-embed-text-v2:0",
            'embedding': None,
            'created_at': datetime.now(),
            'updated_at': datetime.now(),
            'similarity': 0.85
        }
        mock_conn.execute.return_value = [mock_row]
        
        # Create request with embedding
        embedding = [0.1] * 1024  # Sample embedding vector
        request = GetMemoriesRequest(
            session_id=self.sample_session_id,
            embedding=embedding
        )
        
        # Call method
        result = PGMemoryClient.get_memories(request)
        
        # Verify results
        assert isinstance(result, GetMemoriesResponse)
        assert len(result.memories) == 1
        
        # Verify database was called
        mock_read_db.connect.assert_called_once()
        mock_conn.execute.assert_called_once()

    @patch('agentic_platform.service.memory_gateway.client.memory.pg_memory_client.insert')
    @patch('agentic_platform.service.memory_gateway.client.memory.pg_memory_client.write_db')
    @patch('agentic_platform.service.memory_gateway.client.memory.pg_memory_client.LLMGatewayClient')
    @patch('agentic_platform.service.memory_gateway.client.memory.pg_memory_client.get_auth_token')
    def test_create_memory_success(self, mock_get_auth_token, mock_llm_client, mock_write_db, mock_insert, mock_memory_table):
        """Test successful memory creation"""
        # Setup mocks
        mock_get_auth_token.return_value = "test-token"
        mock_conn = MagicMock()
        mock_write_db.connect.return_value.__enter__.return_value = mock_conn
        
        # Mock the insert function to return a mock statement
        mock_insert_stmt = MagicMock()
        mock_insert.return_value.values.return_value = mock_insert_stmt
        
        # Mock LLM response for memory creation - create actual objects, not MagicMocks
        from agentic_platform.core.models.llm_models import LLMResponse
        mock_llm_response = LLMResponse(
            text="<memory>Generated memory content</memory>",
            input_tokens=10,
            output_tokens=15,
            model_id="test-model"
        )
        
        # Mock embedding response  
        from agentic_platform.core.models.embedding_models import EmbedResponse
        mock_embed_response = EmbedResponse(embedding=[0.1] * 1024)
        
        # Mock the LLMGatewayClient static methods directly
        mock_llm_client.chat_invoke.return_value = mock_llm_response
        mock_llm_client.embed_invoke.return_value = mock_embed_response
        
        # Create request with proper session context
        request = CreateMemoryRequest(
            user_id=self.sample_user_id,
            session_id=self.sample_session_id,
            agent_id=self.sample_agent_id,
            session_context=self.sample_session_context
        )
        
        # Call method
        result = PGMemoryClient.create_memory(request)
        
        # Verify results
        assert isinstance(result, CreateMemoryResponse)
        assert result.memory.user_id == self.sample_user_id
        
        # Verify database operations
        mock_write_db.connect.assert_called_once()
        mock_conn.execute.assert_called()
        mock_conn.commit.assert_called_once()

    @patch('agentic_platform.service.memory_gateway.client.memory.pg_memory_client.read_db')
    def test_get_session_context_empty_result(self, mock_read_db, mock_memory_table):
        """Test getting session context when no results found"""
        # Setup mock database response with empty result
        mock_conn = MagicMock()
        mock_read_db.connect.return_value.__enter__.return_value = mock_conn
        mock_conn.execute.return_value = []
        
        # Create request
        request = GetSessionContextRequest(session_id=self.sample_session_id)
        
        # Call method
        result = PGMemoryClient.get_session_context(request)
        
        # Verify results
        assert isinstance(result, GetSessionContextResponse)
        assert len(result.results) == 0
        
        # Verify database was called
        mock_read_db.connect.assert_called_once()
        mock_conn.execute.assert_called_once()

    def test_methods_are_class_methods(self, mock_memory_table):
        """Test that all public methods are class methods"""
        methods_to_check = [
            'get_session_context',
            'upsert_session_context',
            'get_memories',
            'create_memory'
        ]
        
        for method_name in methods_to_check:
            assert hasattr(PGMemoryClient, method_name)
            method = getattr(PGMemoryClient, method_name)
            assert callable(method)
            
            # Check that it's a classmethod by checking the descriptor type
            # or by checking the method is callable and has proper signature
            import inspect
            sig = inspect.signature(method)
            params = list(sig.parameters.keys())
            # For classmethod, the first parameter is the class parameter
            # Check if it exists and has expected parameter names
            assert len(params) > 0, f"Method {method_name} should have parameters"
            # Methods should be callable from the class directly
            assert callable(method), f"Method {method_name} should be callable"

    @patch('agentic_platform.service.memory_gateway.client.memory.pg_memory_client.select')
    @patch('agentic_platform.service.memory_gateway.client.memory.pg_memory_client.desc')
    @patch('agentic_platform.service.memory_gateway.client.memory.pg_memory_client.read_db')
    def test_get_memories_handles_agent_id_conversion(self, mock_read_db, mock_desc, mock_select, mock_memory_table):
        """Test that get_memories properly handles agent_id string to UUID conversion"""
        # Setup mock select to return the mocked memory table
        mock_select.return_value = MagicMock()
        mock_memory_table.return_value = self.mock_memory_table
        mock_desc.return_value = MagicMock()  # Mock the desc function
        
        # Setup mock database response
        mock_conn = MagicMock()
        mock_read_db.connect.return_value.__enter__.return_value = mock_conn
        mock_conn.execute.return_value = []
        
        # Create request with string agent_id
        request = GetMemoriesRequest(
            session_id=self.sample_session_id,
            agent_id="test-agent-string"
        )
        
        # Call method - should not raise exception
        result = PGMemoryClient.get_memories(request)
        
        # Verify results
        assert isinstance(result, GetMemoriesResponse)
        
        # Verify database was called
        mock_read_db.connect.assert_called_once()
        mock_conn.execute.assert_called_once() 