"""
Real-Postgres integration tests: memory gateway operations are scoped to the
authenticated caller, so one user cannot read or overwrite another user's
session context or memories.

Requires a local Postgres with the memory tables migrated:

    make test-integ-db

The repo's root tests/conftest.py replaces psycopg2/pgvector with mocks, so these
tests skip when collected under a normal `make test` run.
"""

import os
import sys
import uuid
from unittest.mock import MagicMock, patch

import pytest

if isinstance(sys.modules.get("psycopg2"), MagicMock):
    pytest.skip("Database drivers are mocked by tests/conftest.py; run `make test-integ-db`",
                allow_module_level=True)

from fastapi import HTTPException
from sqlalchemy import delete, select, text

from agentic_platform.core.context.request_context import auth_context_var
from agentic_platform.core.models.auth_models import AgenticPlatformAuth, UserAuth
from agentic_platform.core.models.embedding_models import EmbedResponse
from agentic_platform.core.models.llm_models import LLMResponse
from agentic_platform.core.models.memory_models import (
    CreateMemoryRequest,
    GetMemoriesRequest,
    GetSessionContextRequest,
    Message,
    SessionContext,
    UpsertSessionContextRequest,
)
from agentic_platform.service.memory_gateway.api.create_memory_controller import CreateMemoryController
from agentic_platform.service.memory_gateway.api.get_memory_controller import GetMemoriesController
from agentic_platform.service.memory_gateway.api.get_session_controller import GetSessionContextController
from agentic_platform.service.memory_gateway.api.upsert_session_controller import UpsertSessionContextController
from agentic_platform.service.memory_gateway.client.memory import pg_memory_client
from agentic_platform.service.memory_gateway.client.memory.pg_memory_client import (
    MEMORY_TABLE,
    SESSION_CONTEXT_TABLE,
    write_db,
)

try:
    with write_db.connect() as _conn:
        _conn.execute(text("SELECT 1 FROM session_context LIMIT 1"))
except Exception as e:  # pragma: no cover - environment dependent
    pytest.skip(f"Postgres with memory tables not reachable: {e}", allow_module_level=True)

pytestmark = pytest.mark.integration

AGENT_ID = str(uuid.uuid4())


@pytest.fixture(autouse=True)
def pg_provider(monkeypatch):
    monkeypatch.setenv("MEMORY_PROVIDER", "postgres")


@pytest.fixture
def victim_id():
    return f"victim-{uuid.uuid4()}"


@pytest.fixture
def attacker_id():
    return f"attacker-{uuid.uuid4()}"


@pytest.fixture(autouse=True)
def cleanup(victim_id, attacker_id):
    yield
    with write_db.connect() as conn:
        for table in (SESSION_CONTEXT_TABLE, MEMORY_TABLE):
            conn.execute(delete(table).where(table.c.user_id.in_([victim_id, attacker_id])))
        conn.commit()


@pytest.fixture
def act_as():
    """Set the authenticated caller for subsequent controller calls."""
    tokens = []

    def _act_as(user_id):
        tokens.append(auth_context_var.set(AgenticPlatformAuth.from_user(UserAuth(user_id=user_id))))

    yield _act_as
    for token in reversed(tokens):
        auth_context_var.reset(token)


@pytest.fixture
def fake_llm():
    """Stub the LLM and embedding calls made by create_memory."""
    with patch.object(pg_memory_client.LLMGatewayClient, "chat_invoke",
                      return_value=LLMResponse(text="<memory>remembered fact</memory>")), \
         patch.object(pg_memory_client.LLMGatewayClient, "embed_invoke",
                      return_value=EmbedResponse(embedding=[0.01] * 1024)):
        yield


def _session(session_id, user_id, prompt, text_):
    return SessionContext(
        session_id=session_id,
        user_id=user_id,
        agent_id=AGENT_ID,
        system_prompt=prompt,
        messages=[Message.from_text("user", text_)],
        session_metadata={"owner": user_id},
    )


def _raw_session_row(session_id):
    with write_db.connect() as conn:
        return conn.execute(
            select(SESSION_CONTEXT_TABLE).where(SESSION_CONTEXT_TABLE.c.session_id == session_id)
        ).mappings().one()


@pytest.fixture
def victim_session(act_as, victim_id):
    session_id = str(uuid.uuid4())
    act_as(victim_id)
    UpsertSessionContextController.upsert_session_context(UpsertSessionContextRequest(
        session_context=_session(session_id, victim_id, "victim prompt", "victim secret")
    ))
    return session_id


class TestSessionContextScoping:

    def test_owner_can_read_and_update_own_session(self, act_as, victim_id, victim_session):
        act_as(victim_id)
        results = GetSessionContextController.get_session_context(
            GetSessionContextRequest(session_id=victim_session)).results
        assert [r.system_prompt for r in results] == ["victim prompt"]

        UpsertSessionContextController.upsert_session_context(UpsertSessionContextRequest(
            session_context=_session(victim_session, victim_id, "updated prompt", "more")
        ))
        assert _raw_session_row(victim_session)["system_prompt"] == "updated prompt"

    def test_attacker_cannot_read_by_body_user_id(self, act_as, attacker_id, victim_id, victim_session):
        act_as(attacker_id)
        results = GetSessionContextController.get_session_context(
            GetSessionContextRequest(user_id=victim_id)).results
        assert results == []

    def test_attacker_cannot_read_by_session_id(self, act_as, attacker_id, victim_id, victim_session):
        act_as(attacker_id)
        results = GetSessionContextController.get_session_context(
            GetSessionContextRequest(user_id=victim_id, session_id=victim_session)).results
        assert results == []

    @pytest.mark.parametrize("body_user", ["victim", "attacker"])
    def test_attacker_cannot_overwrite_victim_session(self, act_as, attacker_id, victim_id,
                                                       victim_session, body_user):
        body_user_id = victim_id if body_user == "victim" else attacker_id
        act_as(attacker_id)
        with pytest.raises(HTTPException) as exc:
            UpsertSessionContextController.upsert_session_context(UpsertSessionContextRequest(
                session_context=_session(victim_session, body_user_id, "attacker prompt", "pwned")
            ))
        assert exc.value.status_code == 403

        row = _raw_session_row(victim_session)
        assert row["user_id"] == victim_id
        assert row["system_prompt"] == "victim prompt"
        assert row["messages"][0]["content"][0]["text"] == "victim secret"

        act_as(victim_id)
        results = GetSessionContextController.get_session_context(
            GetSessionContextRequest(session_id=victim_session)).results
        assert [r.system_prompt for r in results] == ["victim prompt"]

    def test_body_user_id_ignored_on_new_session(self, act_as, attacker_id, victim_id):
        """Creating a session with someone else's user_id stores it under the caller."""
        session_id = str(uuid.uuid4())
        act_as(attacker_id)
        UpsertSessionContextController.upsert_session_context(UpsertSessionContextRequest(
            session_context=_session(session_id, victim_id, "planted", "planted")
        ))
        assert _raw_session_row(session_id)["user_id"] == attacker_id

        act_as(victim_id)
        assert GetSessionContextController.get_session_context(GetSessionContextRequest()).results == []


class TestMemoryScoping:

    def _create(self, user_id, session_id):
        return CreateMemoryController.create_memory(CreateMemoryRequest(
            user_id=user_id,
            session_id=session_id,
            agent_id=AGENT_ID,
            session_context=_session(session_id, user_id, "p", f"memory of {user_id}"),
        )).memory

    def test_attacker_cannot_read_victim_memories(self, fake_llm, act_as, attacker_id, victim_id):
        session_id = str(uuid.uuid4())
        act_as(victim_id)
        self._create(victim_id, session_id)

        act_as(attacker_id)
        assert GetMemoriesController.get_memories(GetMemoriesRequest(user_id=victim_id)).memories == []
        assert GetMemoriesController.get_memories(GetMemoriesRequest(session_id=session_id)).memories == []

        act_as(victim_id)
        memories = GetMemoriesController.get_memories(GetMemoriesRequest(session_id=session_id)).memories
        assert [m.user_id for m in memories] == [victim_id]

    def test_attacker_cannot_plant_memory_for_victim(self, fake_llm, act_as, attacker_id, victim_id):
        session_id = str(uuid.uuid4())
        act_as(attacker_id)
        created = self._create(victim_id, session_id)
        assert created.user_id == attacker_id

        act_as(victim_id)
        assert GetMemoriesController.get_memories(GetMemoriesRequest(session_id=session_id)).memories == []
