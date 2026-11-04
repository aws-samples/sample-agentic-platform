import pytest
from unittest.mock import patch
from fastapi import HTTPException

from agentic_platform.core.models.memory_models import (
    GetMemoriesRequest, GetMemoriesResponse, Memory
)
from agentic_platform.service.memory_gateway.api.get_memory_controller import GetMemoriesController

PATCH_TARGET = 'agentic_platform.service.memory_gateway.api.get_memory_controller.MemoryClient.get_memories'


class TestGetMemoriesController:
    """Test GetMemoriesController - scopes to the caller and delegates to MemoryClient"""

    @patch(PATCH_TARGET)
    def test_get_memories_delegates_to_memory_client(self, mock_get_memories, caller_auth):
        """Controller delegates with the caller's user_id and keeps other fields"""
        mock_memory = Memory(
            session_id="test-session",
            user_id=caller_auth,
            agent_id="test-agent",
            content="Test memory content",
            embedding_model="test-model"
        )
        mock_response = GetMemoriesResponse(memories=[mock_memory])
        mock_get_memories.return_value = mock_response

        request = GetMemoriesRequest(user_id=caller_auth, session_id="test-session", agent_id="test-agent", limit=5)
        result = GetMemoriesController.get_memories(request)

        mock_get_memories.assert_called_once()
        passed = mock_get_memories.call_args.args[0]
        assert passed.user_id == caller_auth
        assert passed.session_id == "test-session"
        assert passed.agent_id == "test-agent"
        assert passed.limit == 5
        assert result is mock_response

    @patch(PATCH_TARGET)
    def test_body_user_id_is_replaced_with_caller(self, mock_get_memories, caller_auth, other_user_id):
        """A user_id in the body is ignored in favour of the authenticated caller"""
        mock_get_memories.return_value = GetMemoriesResponse(memories=[])

        request = GetMemoriesRequest(user_id=other_user_id)
        GetMemoriesController.get_memories(request)

        assert mock_get_memories.call_args.args[0].user_id == caller_auth
        assert request.user_id == other_user_id

    @patch(PATCH_TARGET)
    def test_missing_user_id_is_filled_from_caller(self, mock_get_memories, caller_auth):
        """Querying by session_id only still scopes to the caller"""
        mock_get_memories.return_value = GetMemoriesResponse(memories=[])

        GetMemoriesController.get_memories(GetMemoriesRequest(session_id="victim-session"))

        assert mock_get_memories.call_args.args[0].user_id == caller_auth

    @patch(PATCH_TARGET)
    def test_unauthenticated_is_forbidden(self, mock_get_memories):
        """No auth context -> 403 and no database call"""
        with pytest.raises(HTTPException) as exc:
            GetMemoriesController.get_memories(GetMemoriesRequest(user_id="x"))
        assert exc.value.status_code == 403
        mock_get_memories.assert_not_called()

    @patch(PATCH_TARGET)
    def test_service_auth_is_forbidden(self, mock_get_memories, service_auth):
        """Service (M2M) callers have no user identity -> 403"""
        with pytest.raises(HTTPException) as exc:
            GetMemoriesController.get_memories(GetMemoriesRequest(user_id="x"))
        assert exc.value.status_code == 403
        mock_get_memories.assert_not_called()

    @patch(PATCH_TARGET)
    def test_get_memories_passes_through_exceptions(self, mock_get_memories, caller_auth):
        """Controller passes through exceptions from MemoryClient"""
        mock_get_memories.side_effect = ValueError("Database connection failed")

        with pytest.raises(ValueError, match="Database connection failed"):
            GetMemoriesController.get_memories(GetMemoriesRequest(user_id=caller_auth))

        mock_get_memories.assert_called_once()

    def test_controller_is_static_method(self):
        """Test that get_memories is a static method"""
        # Should be able to call without instantiating
        assert hasattr(GetMemoriesController, 'get_memories')
        assert callable(GetMemoriesController.get_memories)
        
        # Method should not require self parameter
        import inspect
        sig = inspect.signature(GetMemoriesController.get_memories)
        params = list(sig.parameters.keys())
        assert 'self' not in params
        assert 'request' in params
        assert len(params) == 1  # Only request parameter
    
    def test_controller_class_structure(self):
        """Test the controller class structure"""
        # Should be a simple class with only the static method
        methods = [method for method in dir(GetMemoriesController) 
                  if not method.startswith('_')]
        assert methods == ['get_memories']
        
        # Should not be instantiable (no __init__ needed)
        controller = GetMemoriesController()
        assert controller is not None 