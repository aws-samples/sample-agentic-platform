import pytest
from unittest.mock import patch
from fastapi import HTTPException

from agentic_platform.core.models.memory_models import (
    UpsertSessionContextRequest, UpsertSessionContextResponse, SessionContext
)
from agentic_platform.service.memory_gateway.api.upsert_session_controller import UpsertSessionContextController

PATCH_TARGET = 'agentic_platform.service.memory_gateway.api.upsert_session_controller.MemoryClient.upsert_session_context'


def _request(user_id):
    return UpsertSessionContextRequest(session_context=SessionContext(
        session_id="test-session",
        user_id=user_id,
        agent_id="test-agent",
        system_prompt="Test system prompt",
        messages=[],
        session_metadata={"k": "v"}
    ))


class TestUpsertSessionContextController:
    """Test UpsertSessionContextController - scopes to the caller and delegates to MemoryClient"""

    @patch(PATCH_TARGET)
    def test_upsert_session_context_delegates_to_memory_client(self, mock_upsert, caller_auth):
        """Controller delegates with the caller's user_id and keeps other fields"""
        request = _request(caller_auth)
        mock_response = UpsertSessionContextResponse(session_context=request.session_context)
        mock_upsert.return_value = mock_response

        result = UpsertSessionContextController.upsert_session_context(request)

        mock_upsert.assert_called_once()
        passed = mock_upsert.call_args.args[0].session_context
        assert passed.user_id == caller_auth
        assert passed.session_id == "test-session"
        assert passed.agent_id == "test-agent"
        assert passed.system_prompt == "Test system prompt"
        assert passed.session_metadata == {"k": "v"}
        assert result is mock_response

    @patch(PATCH_TARGET)
    def test_body_user_id_is_replaced_with_caller(self, mock_upsert, caller_auth, other_user_id):
        """A user_id in the body's session_context is ignored in favour of the caller"""
        request = _request(other_user_id)
        mock_upsert.return_value = UpsertSessionContextResponse(session_context=request.session_context)

        UpsertSessionContextController.upsert_session_context(request)

        assert mock_upsert.call_args.args[0].session_context.user_id == caller_auth
        assert request.session_context.user_id == other_user_id

    @patch(PATCH_TARGET)
    def test_missing_user_id_is_filled_from_caller(self, mock_upsert, caller_auth):
        """A session_context without user_id is stored under the caller"""
        request = _request(None)
        mock_upsert.return_value = UpsertSessionContextResponse(session_context=request.session_context)

        UpsertSessionContextController.upsert_session_context(request)

        assert mock_upsert.call_args.args[0].session_context.user_id == caller_auth

    @patch(PATCH_TARGET)
    def test_session_owned_by_another_user_is_forbidden(self, mock_upsert, caller_auth):
        """PermissionError from the client (session owned by someone else) -> 403"""
        mock_upsert.side_effect = PermissionError("Session context belongs to a different user")

        with pytest.raises(HTTPException) as exc:
            UpsertSessionContextController.upsert_session_context(_request(caller_auth))

        assert exc.value.status_code == 403
        # Don't leak that the session exists for someone else
        assert "different user" not in str(exc.value.detail)

    @patch(PATCH_TARGET)
    def test_unauthenticated_is_forbidden(self, mock_upsert):
        """No auth context -> 403 and no database call"""
        with pytest.raises(HTTPException) as exc:
            UpsertSessionContextController.upsert_session_context(_request("x"))
        assert exc.value.status_code == 403
        mock_upsert.assert_not_called()

    @patch(PATCH_TARGET)
    def test_service_auth_is_forbidden(self, mock_upsert, service_auth):
        """Service (M2M) callers have no user identity -> 403"""
        with pytest.raises(HTTPException) as exc:
            UpsertSessionContextController.upsert_session_context(_request("x"))
        assert exc.value.status_code == 403
        mock_upsert.assert_not_called()

    @patch(PATCH_TARGET)
    def test_upsert_session_context_passes_through_exceptions(self, mock_upsert, caller_auth):
        """Controller passes through other exceptions from MemoryClient"""
        mock_upsert.side_effect = ValueError("Database connection failed")

        with pytest.raises(ValueError, match="Database connection failed"):
            UpsertSessionContextController.upsert_session_context(_request(caller_auth))

        mock_upsert.assert_called_once()

    def test_controller_is_static_method(self):
        """Test that upsert_session_context is a static method"""
        # Should be able to call without instantiating
        assert hasattr(UpsertSessionContextController, 'upsert_session_context')
        assert callable(UpsertSessionContextController.upsert_session_context)
        
        # Method should not require self parameter
        import inspect
        sig = inspect.signature(UpsertSessionContextController.upsert_session_context)
        params = list(sig.parameters.keys())
        assert 'self' not in params
        assert 'request' in params
        assert len(params) == 1  # Only request parameter
    
    def test_controller_class_structure(self):
        """Test the controller class structure"""
        # Should be a simple class with only the static method
        methods = [method for method in dir(UpsertSessionContextController) 
                  if not method.startswith('_')]
        assert methods == ['upsert_session_context']
        
        # Should not be instantiable (no __init__ needed)
        controller = UpsertSessionContextController()
        assert controller is not None 