"""
Integration tests for Memory Gateway.

This module contains integration tests for the Memory Gateway service,
testing the controller functionality with mocked external dependencies.
"""

import pytest
import sys
import os
from typing import Dict, Any
import uuid
import time
from unittest.mock import patch, MagicMock

# Add the source directory to the path so we can import the modules
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../../../', 'src'))

from agentic_platform.core.models.memory_models import (
    CreateMemoryRequest, 
    CreateMemoryResponse,
    GetMemoriesRequest,
    GetMemoriesResponse,
    GetSessionContextRequest,
    GetSessionContextResponse,
    UpsertSessionContextRequest,
    UpsertSessionContextResponse,
    SessionContext,
    Memory,
    Message
)
from agentic_platform.core.context.request_context import auth_context_var
from agentic_platform.core.models.auth_models import AgenticPlatformAuth, UserAuth

# Must match the user_id in the sample_create_memory_request fixture. Controllers
# scope every request to the authenticated caller, so tests run as that user.
CALLER_USER_ID = "550e8400-e29b-41d4-a716-446655440001"


@pytest.fixture(autouse=True)
def caller_auth_context():
    """Authenticate every test in this module as CALLER_USER_ID."""
    token = auth_context_var.set(AgenticPlatformAuth.from_user(UserAuth(user_id=CALLER_USER_ID)))
    yield
    auth_context_var.reset(token)


class TestMemoryGateway:
    """Integration tests for Memory Gateway controller with mocked external dependencies"""
    
    def test_create_memory_happy_path(self, sample_create_memory_request):
        """Test the create_memory controller happy path"""
        
        # Create a mock memory response
        mock_memory = Memory(
            memory_id=str(uuid.uuid4()),
            session_id=sample_create_memory_request["session_id"],
            user_id=sample_create_memory_request["user_id"],
            agent_id=sample_create_memory_request["agent_id"],
            content="Test memory content",
            embedding_model="amazon.titan-embed-text-v2:0",
            created_at=time.time(),
            updated_at=time.time(),
            embedding=[0.1] * 10  # Sample embedding vector
        )
        
        # Create a mock response
        mock_response = CreateMemoryResponse(memory=mock_memory)
        
        try:
            from agentic_platform.service.memory_gateway.api.create_memory_controller import CreateMemoryController
            from agentic_platform.service.memory_gateway.client.memory.memory_client import MemoryClient
            
            # Convert the request dict to a proper CreateMemoryRequest object
            request = CreateMemoryRequest(**sample_create_memory_request)
            
            # Mock the memory client
            with patch.object(MemoryClient, 'create_memory', return_value=mock_response) as mock_create_memory:
                
                # Call the controller
                response = CreateMemoryController.create_memory(request)
                
                # Verify the response
                assert isinstance(response, CreateMemoryResponse), "Response should be CreateMemoryResponse"
                assert response.memory is not None, "Response should have a memory"
                
                # Verify the memory contains the correct data
                assert response.memory.session_id == sample_create_memory_request["session_id"], "Memory session_id should match request"
                assert response.memory.user_id == sample_create_memory_request["user_id"], "Memory user_id should match request"
                assert response.memory.agent_id == sample_create_memory_request["agent_id"], "Memory agent_id should match request"
                
                # Verify that the memory client was called with the correct request
                mock_create_memory.assert_called_once_with(request)
                
                print(f"✅ Memory Gateway create_memory test passed!")
                print(f"   Created memory with ID: {response.memory.memory_id}")
                
        except ImportError as e:
            pytest.skip(f"Memory Gateway controller not available: {e}")
        except Exception as e:
            pytest.fail(f"Error testing Memory Gateway controller: {e}")
    
    def test_get_memories_by_session_id(self, sample_create_memory_request):
        """Test the get_memories controller by session_id"""
        
        # Create a mock memory
        mock_memory = Memory(
            memory_id=str(uuid.uuid4()),
            session_id=sample_create_memory_request["session_id"],
            user_id=sample_create_memory_request["user_id"],
            agent_id=sample_create_memory_request["agent_id"],
            content="Test memory content",
            embedding_model="amazon.titan-embed-text-v2:0",
            created_at=time.time(),
            updated_at=time.time()
        )
        
        # Create a mock response with the memory
        mock_response = GetMemoriesResponse(memories=[mock_memory])
        
        try:
            from agentic_platform.service.memory_gateway.api.get_memory_controller import GetMemoriesController
            from agentic_platform.service.memory_gateway.client.memory.memory_client import MemoryClient
            
            # Create a request to get memories by session_id
            session_id = sample_create_memory_request["session_id"]
            request = GetMemoriesRequest(
                session_id=session_id,
                limit=10
            )
            
            # Mock the memory client
            with patch.object(MemoryClient, 'get_memories', return_value=mock_response) as mock_get_memories:
                
                # Call the controller
                response = GetMemoriesController.get_memories(request)
                
                # Verify the response
                assert isinstance(response, GetMemoriesResponse), "Response should be GetMemoriesResponse"
                assert response.memories is not None, "Response should have memories"
                assert len(response.memories) > 0, "Should have at least one memory"
                
                # Verify the retrieved memory has the correct session_id
                for memory in response.memories:
                    assert memory.session_id == session_id, f"Memory session_id should be {session_id}"
                
                # Verify that the memory client was called with the correct request
                # Controller scopes the lookup to the authenticated caller
                mock_get_memories.assert_called_once_with(request.model_copy(update={"user_id": CALLER_USER_ID}))
                
                print(f"✅ Memory Gateway get_memories by session_id test passed!")
                print(f"   Retrieved {len(response.memories)} memories for session {session_id}")
                
        except ImportError as e:
            pytest.skip(f"Memory Gateway controller not available: {e}")
        except Exception as e:
            pytest.fail(f"Error testing Memory Gateway controller: {e}")
    
    def test_get_memories_by_user_id(self, sample_create_memory_request):
        """Test the get_memories controller by user_id"""
        
        # Create a mock memory
        mock_memory = Memory(
            memory_id=str(uuid.uuid4()),
            session_id=sample_create_memory_request["session_id"],
            user_id=sample_create_memory_request["user_id"],
            agent_id=sample_create_memory_request["agent_id"],
            content="Test memory content",
            embedding_model="amazon.titan-embed-text-v2:0",
            created_at=time.time(),
            updated_at=time.time()
        )
        
        # Create a mock response with the memory
        mock_response = GetMemoriesResponse(memories=[mock_memory])
        
        try:
            from agentic_platform.service.memory_gateway.api.get_memory_controller import GetMemoriesController
            from agentic_platform.service.memory_gateway.client.memory.memory_client import MemoryClient
            
            # Create a request to get memories by user_id
            user_id = sample_create_memory_request["user_id"]
            request = GetMemoriesRequest(
                user_id=user_id,
                limit=10
            )
            
            # Mock the memory client
            with patch.object(MemoryClient, 'get_memories', return_value=mock_response) as mock_get_memories:
                
                # Call the controller
                response = GetMemoriesController.get_memories(request)
                
                # Verify the response
                assert isinstance(response, GetMemoriesResponse), "Response should be GetMemoriesResponse"
                assert response.memories is not None, "Response should have memories"
                assert len(response.memories) > 0, "Should have at least one memory"
                
                # Verify the retrieved memory has the correct user_id
                for memory in response.memories:
                    assert memory.user_id == user_id, f"Memory user_id should be {user_id}"
                
                # Verify that the memory client was called with the correct request
                mock_get_memories.assert_called_once_with(request)
                
                print(f"✅ Memory Gateway get_memories by user_id test passed!")
                print(f"   Retrieved {len(response.memories)} memories for user {user_id}")
                
        except ImportError as e:
            pytest.skip(f"Memory Gateway controller not available: {e}")
        except Exception as e:
            pytest.fail(f"Error testing Memory Gateway controller: {e}")
    
    def test_get_session_context(self, sample_create_memory_request):
        """Test the get_session controller"""
        
        # Create a mock session context
        mock_session_context = SessionContext(
            session_id=sample_create_memory_request["session_id"],
            user_id=sample_create_memory_request["user_id"],
            agent_id=sample_create_memory_request["agent_id"],
            messages=[
                Message.from_text("user", "This is a test message")
            ],
            system_prompt="You are a helpful assistant for testing",
            session_metadata={"test": True}
        )
        
        # Create a mock response with the session context
        mock_response = GetSessionContextResponse(results=[mock_session_context])
        
        try:
            from agentic_platform.service.memory_gateway.api.get_session_controller import GetSessionContextController
            from agentic_platform.service.memory_gateway.client.memory.memory_client import MemoryClient
            
            # Create a request to get session context
            session_id = sample_create_memory_request["session_id"]
            request = GetSessionContextRequest(
                session_id=session_id
            )
            
            # Mock the memory client
            with patch.object(MemoryClient, 'get_session_context', return_value=mock_response) as mock_get_session:
                
                # Call the controller
                response = GetSessionContextController.get_session_context(request)
                
                # Verify the response
                assert isinstance(response, GetSessionContextResponse), "Response should be GetSessionContextResponse"
                assert response.results is not None, "Response should have results"
                
                # If we have results, verify they have the correct session_id
                if len(response.results) > 0:
                    session_context = response.results[0]
                    assert session_context.session_id == session_id, f"Session context session_id should be {session_id}"
                    
                    # Verify messages are present
                    assert session_context.messages is not None, "Session context should contain messages"
                    assert len(session_context.messages) > 0, "Messages should not be empty"
                
                # Verify that the memory client was called with the correct request
                # Controller scopes the lookup to the authenticated caller
                mock_get_session.assert_called_once_with(request.model_copy(update={"user_id": CALLER_USER_ID}))
                
                print(f"✅ Memory Gateway get_session test passed!")
                print(f"   Retrieved {len(response.results)} session contexts")
                
        except ImportError as e:
            pytest.skip(f"Memory Gateway controller not available: {e}")
        except Exception as e:
            pytest.fail(f"Error testing Memory Gateway controller: {e}")
    
    def test_upsert_session_context(self):
        """Test the upsert_session controller"""
        
        # Create a new session context
        session_id = str(uuid.uuid4())
        user_id = CALLER_USER_ID
        agent_id = str(uuid.uuid4())
        
        session_context = SessionContext(
            session_id=session_id,
            user_id=user_id,
            agent_id=agent_id,
            messages=[
                Message.from_text("user", "Hello, this is a test message for upsert")
            ],
            system_prompt="You are a helpful assistant for testing",
            session_metadata={"test": True, "purpose": "upsert_test"}
        )
        
        # Create a request with the session context
        request = UpsertSessionContextRequest(
            session_context=session_context
        )
        
        # Create a mock response with the same session context
        mock_response = UpsertSessionContextResponse(
            session_context=session_context
        )
        
        try:
            from agentic_platform.service.memory_gateway.api.upsert_session_controller import UpsertSessionContextController
            from agentic_platform.service.memory_gateway.client.memory.memory_client import MemoryClient
            
            # Mock the memory client
            with patch.object(MemoryClient, 'upsert_session_context', return_value=mock_response) as mock_upsert:
                
                # Call the controller
                response = UpsertSessionContextController.upsert_session_context(request)
                
                # Verify the response
                assert isinstance(response, UpsertSessionContextResponse), "Response should be UpsertSessionContextResponse"
                assert response.session_context is not None, "Response should have session_context"
                
                # Verify the session context contains the correct data
                assert response.session_context.session_id == session_id, "Session context session_id should match request"
                assert response.session_context.user_id == user_id, "Session context user_id should match request"
                assert response.session_context.agent_id == agent_id, "Session context agent_id should match request"
                assert response.session_context.system_prompt == "You are a helpful assistant for testing", "System prompt should match"
                
                # Verify messages are present
                assert response.session_context.messages is not None, "Session context should contain messages"
                assert len(response.session_context.messages) == 1, "Should have one message"
                
                # Verify that the memory client was called with the correct request
                mock_upsert.assert_called_once_with(request)
                
                print(f"✅ Memory Gateway upsert_session test passed!")
                print(f"   Upserted session context with ID: {session_id}")
                
        except ImportError as e:
            pytest.skip(f"Memory Gateway controller not available: {e}")
        except Exception as e:
            pytest.fail(f"Error testing Memory Gateway controller: {e}")
