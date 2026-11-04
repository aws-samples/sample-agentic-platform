import pytest

from agentic_platform.core.context.request_context import auth_context_var
from agentic_platform.core.models.auth_models import AgenticPlatformAuth, UserAuth, ServiceAuth

CALLER_USER_ID = "caller-user"
OTHER_USER_ID = "other-user"


@pytest.fixture
def set_auth():
    """Set the request auth context for a test and restore it afterwards."""
    tokens = []

    def _set(auth):
        tokens.append(auth_context_var.set(auth))

    yield _set

    for token in reversed(tokens):
        auth_context_var.reset(token)


@pytest.fixture
def caller_auth(set_auth):
    """Authenticate the test as CALLER_USER_ID."""
    set_auth(AgenticPlatformAuth.from_user(UserAuth(user_id=CALLER_USER_ID)))
    return CALLER_USER_ID


@pytest.fixture
def other_user_id():
    """A user_id belonging to someone other than the caller."""
    return OTHER_USER_ID


@pytest.fixture
def service_auth(set_auth):
    """Authenticate the test as an M2M service (no user identity)."""
    set_auth(AgenticPlatformAuth.from_service(ServiceAuth(service_id="svc", name="svc")))
