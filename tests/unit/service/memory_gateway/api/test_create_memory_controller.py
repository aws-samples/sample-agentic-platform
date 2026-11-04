import pytest
from unittest.mock import patch
from fastapi import HTTPException

from agentic_platform.core.models.memory_models import (
    CreateMemoryRequest, CreateMemoryResponse, Memory, SessionContext
)
from agentic_platform.service.memory_gateway.api.create_memory_controller import CreateMemoryController

PATCH_TARGET = 'agentic_platform.service.memory_gateway.api.create_memory_controller.MemoryClient.create_memory'


def _request(user_id):
    return CreateMemoryRequest(
        user_id=user_id,
        session_id="test-session",
        agent_id="test-agent",
        session_context=SessionContext(session_id="test-session", user_id=user_id, messages=[])
    )


class TestCreateMemoryController:
    """Test CreateMemoryController - scopes to the caller and delegates to MemoryClient"""

    @patch(PATCH_TARGET)
    def test_create_memory_delegates_to_memory_client(self, mock_create_memory, caller_auth):
        """Controller delegates with the caller's user_id and keeps other fields"""
        mock_response = CreateMemoryResponse(memory=Memory(
            session_id="test-session",
            user_id=caller_auth,
            agent_id="test-agent",
            content="Test memory content",
            embedding_model="test-model"
        ))
        mock_create_memory.return_value = mock_response

        result = CreateMemoryController.create_memory(_request(caller_auth))

        mock_create_memory.assert_called_once()
        passed = mock_create_memory.call_args.args[0]
        assert passed.user_id == caller_auth
        assert passed.session_context.user_id == caller_auth
        assert passed.session_id == "test-session"
        assert passed.agent_id == "test-agent"
        assert result is mock_response

    @patch(PATCH_TARGET)
    def test_body_user_id_is_replaced_with_caller(self, mock_create_memory, caller_auth, other_user_id):
        """user_id in the body and nested session_context are both replaced with the caller"""
        mock_create_memory.return_value = None
        request = _request(other_user_id)

        CreateMemoryController.create_memory(request)

        passed = mock_create_memory.call_args.args[0]
        assert passed.user_id == caller_auth
        assert passed.session_context.user_id == caller_auth
        assert request.user_id == other_user_id

    @patch(PATCH_TARGET)
    def test_unauthenticated_is_forbidden(self, mock_create_memory):
        """No auth context -> 403 and no downstream call"""
        with pytest.raises(HTTPException) as exc:
            CreateMemoryController.create_memory(_request("x"))
        assert exc.value.status_code == 403
        mock_create_memory.assert_not_called()

    @patch(PATCH_TARGET)
    def test_service_auth_is_forbidden(self, mock_create_memory, service_auth):
        """Service (M2M) callers have no user identity -> 403"""
        with pytest.raises(HTTPException) as exc:
            CreateMemoryController.create_memory(_request("x"))
        assert exc.value.status_code == 403
        mock_create_memory.assert_not_called()

    @patch(PATCH_TARGET)
    def test_create_memory_passes_through_exceptions(self, mock_create_memory, caller_auth):
        """Controller passes through exceptions from MemoryClient"""
        mock_create_memory.side_effect = ValueError("Database connection failed")

        with pytest.raises(ValueError, match="Database connection failed"):
            CreateMemoryController.create_memory(_request(caller_auth))

        mock_create_memory.assert_called_once()

    def test_controller_is_static_method(self):
        """Test that create_memory is a static method"""
        # Should be able to call without instantiating
        assert hasattr(CreateMemoryController, 'create_memory')
        assert callable(CreateMemoryController.create_memory)
        
        # Method should not require self parameter
        import inspect
        sig = inspect.signature(CreateMemoryController.create_memory)
        params = list(sig.parameters.keys())
        assert 'self' not in params
        assert 'request' in params
        assert len(params) == 1  # Only request parameter
    
    def test_controller_class_structure(self):
        """Test the controller class structure"""
        # Should be a simple class with only the static method
        methods = [method for method in dir(CreateMemoryController) 
                  if not method.startswith('_')]
        assert methods == ['create_memory']
        
        # Should not be instantiable (no __init__ needed)
        controller = CreateMemoryController()
        assert controller is not None 