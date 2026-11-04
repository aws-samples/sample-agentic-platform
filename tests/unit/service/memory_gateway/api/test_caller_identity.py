import pytest
from fastapi import HTTPException

from agentic_platform.core.models.auth_models import AgenticPlatformAuth, UserAuth
from agentic_platform.service.memory_gateway.api.caller_identity import get_caller_user_id


class TestGetCallerUserId:
    def test_returns_user_id_from_auth_context(self, caller_auth):
        assert get_caller_user_id() == caller_auth

    def test_no_auth_context_is_forbidden(self):
        with pytest.raises(HTTPException) as exc:
            get_caller_user_id()
        assert exc.value.status_code == 403

    def test_service_auth_is_forbidden(self, service_auth):
        with pytest.raises(HTTPException) as exc:
            get_caller_user_id()
        assert exc.value.status_code == 403

    def test_user_type_without_user_is_forbidden(self, set_auth):
        set_auth(AgenticPlatformAuth(type="user", user=None))
        with pytest.raises(HTTPException) as exc:
            get_caller_user_id()
        assert exc.value.status_code == 403

    def test_empty_user_id_is_forbidden(self, set_auth):
        set_auth(AgenticPlatformAuth.from_user(UserAuth(user_id="")))
        with pytest.raises(HTTPException) as exc:
            get_caller_user_id()
        assert exc.value.status_code == 403
