import pytest
from unittest.mock import patch
from fastapi import HTTPException

from agentic_platform.core.models.memory_models import (
    GetSessionContextRequest, GetSessionContextResponse, SessionContext
)
from agentic_platform.service.memory_gateway.api.get_session_controller import GetSessionContextController

PATCH_TARGET = 'agentic_platform.service.memory_gateway.api.get_session_controller.MemoryClient.get_session_context'


class TestGetSessionContextController:
    """Test GetSessionContextController - scopes to the caller and delegates to MemoryClient"""

    @patch(PATCH_TARGET)
    def test_get_session_context_delegates_to_memory_client(self, mock_get_session_context, caller_auth):
        """Controller delegates with the caller's user_id and keeps other fields"""
        mock_response = GetSessionContextResponse(results=[
            SessionContext(session_id="test-session", user_id=caller_auth, messages=[])
        ])
        mock_get_session_context.return_value = mock_response

        request = GetSessionContextRequest(user_id=caller_auth, session_id="test-session")
        result = GetSessionContextController.get_session_context(request)

        mock_get_session_context.assert_called_once()
        passed = mock_get_session_context.call_args.args[0]
        assert passed.user_id == caller_auth
        assert passed.session_id == "test-session"
        assert result is mock_response

    @patch(PATCH_TARGET)
    def test_body_user_id_is_replaced_with_caller(self, mock_get_session_context, caller_auth, other_user_id):
        """A user_id in the body is ignored in favour of the authenticated caller"""
        mock_get_session_context.return_value = GetSessionContextResponse(results=[])

        request = GetSessionContextRequest(user_id=other_user_id, session_id="victim-session")
        GetSessionContextController.get_session_context(request)

        passed = mock_get_session_context.call_args.args[0]
        assert passed.user_id == caller_auth
        assert passed.session_id == "victim-session"
        # The original request object is not mutated
        assert request.user_id == other_user_id

    @patch(PATCH_TARGET)
    def test_missing_user_id_is_filled_from_caller(self, mock_get_session_context, caller_auth):
        """Omitting user_id still scopes to the caller (no unscoped session_id lookup)"""
        mock_get_session_context.return_value = GetSessionContextResponse(results=[])

        GetSessionContextController.get_session_context(GetSessionContextRequest(session_id="any-session"))

        assert mock_get_session_context.call_args.args[0].user_id == caller_auth

    @patch(PATCH_TARGET)
    def test_unauthenticated_is_forbidden(self, mock_get_session_context):
        """No auth context -> 403 and no database call"""
        with pytest.raises(HTTPException) as exc:
            GetSessionContextController.get_session_context(GetSessionContextRequest(user_id="x"))
        assert exc.value.status_code == 403
        mock_get_session_context.assert_not_called()

    @patch(PATCH_TARGET)
    def test_service_auth_is_forbidden(self, mock_get_session_context, service_auth):
        """Service (M2M) callers have no user identity -> 403"""
        with pytest.raises(HTTPException) as exc:
            GetSessionContextController.get_session_context(GetSessionContextRequest(user_id="x"))
        assert exc.value.status_code == 403
        mock_get_session_context.assert_not_called()

    @patch(PATCH_TARGET)
    def test_get_session_context_passes_through_exceptions(self, mock_get_session_context, caller_auth):
        """Controller passes through exceptions from MemoryClient"""
        mock_get_session_context.side_effect = ValueError("Database connection failed")

        with pytest.raises(ValueError, match="Database connection failed"):
            GetSessionContextController.get_session_context(GetSessionContextRequest(user_id=caller_auth))

        mock_get_session_context.assert_called_once()

    def test_controller_is_static_method(self):
        """Test that get_session_context is a static method"""
        # Should be able to call without instantiating
        assert hasattr(GetSessionContextController, 'get_session_context')
        assert callable(GetSessionContextController.get_session_context)
        
        # Method should not require self parameter
        import inspect
        sig = inspect.signature(GetSessionContextController.get_session_context)
        params = list(sig.parameters.keys())
        assert 'self' not in params
        assert 'request' in params
        assert len(params) == 1  # Only request parameter
    
    def test_controller_class_structure(self):
        """Test the controller class structure"""
        # Should be a simple class with only the static method
        methods = [method for method in dir(GetSessionContextController) 
                  if not method.startswith('_')]
        assert methods == ['get_session_context']
        
        # Should not be instantiable (no __init__ needed)
        controller = GetSessionContextController()
        assert controller is not None 