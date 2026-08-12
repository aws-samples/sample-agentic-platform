import pytest
from unittest.mock import MagicMock, patch

from agentic_platform.core.models.api_models import AgenticRequest, AgenticResponse
from agentic_platform.core.models.memory_models import Message
from agentic_platform.core.models.streaming_models import TextDeltaEvent
from agentic_platform.agent.agentic_chat.controller import agentic_chat_controller

CONTROLLER_MODULE = 'agentic_platform.agent.agentic_chat.controller.agentic_chat_controller'


class TestAgenticChatControllerInvoke:
    """Test the controller's non-streaming entry point"""

    @pytest.mark.asyncio
    @patch(f'{CONTROLLER_MODULE}.agent')
    async def test_invoke_delegates_to_agent(self, mock_agent):
        """Test that the controller passes the request straight through to the agent"""
        expected = AgenticResponse(
            message=Message.from_text('assistant', 'hello back'),
            session_id='session-abc'
        )
        mock_agent.invoke.return_value = expected
        request = AgenticRequest.from_text('hello', session_id='session-abc')

        result = await agentic_chat_controller.invoke(request)

        mock_agent.invoke.assert_called_once_with(request)
        assert result is expected

    @pytest.mark.asyncio
    @patch(f'{CONTROLLER_MODULE}.agent')
    async def test_invoke_rejects_streaming_request(self, mock_agent):
        """Test that a streaming request is rejected rather than silently answered non-streamed"""
        request = AgenticRequest.from_text('hello', stream=True)

        with pytest.raises(ValueError, match='/stream endpoint'):
            await agentic_chat_controller.invoke(request)

        mock_agent.invoke.assert_not_called()

    @pytest.mark.asyncio
    @patch(f'{CONTROLLER_MODULE}.agent')
    async def test_invoke_passes_through_agent_exceptions(self, mock_agent):
        """Test that agent failures are not swallowed by the controller"""
        mock_agent.invoke.side_effect = RuntimeError('model unavailable')

        with pytest.raises(RuntimeError, match='model unavailable'):
            await agentic_chat_controller.invoke(AgenticRequest.from_text('hello'))


class TestAgenticChatControllerCreateStream:
    """Test the controller's streaming entry point"""

    @pytest.mark.asyncio
    @patch(f'{CONTROLLER_MODULE}.agent')
    async def test_create_stream_yields_agent_events(self, mock_agent):
        """Test that events from the agent are forwarded in order"""
        first = TextDeltaEvent(session_id='session-abc', text='Hel')
        second = TextDeltaEvent(session_id='session-abc', text='lo')

        async def fake_invoke_stream(_request):
            yield first
            yield second

        mock_agent.invoke_stream = fake_invoke_stream
        request = AgenticRequest.from_text('hello', session_id='session-abc')

        events = [event async for event in agentic_chat_controller.create_stream(request)]

        assert events == [first, second]

    @pytest.mark.asyncio
    @patch(f'{CONTROLLER_MODULE}.agent')
    async def test_create_stream_handles_empty_stream(self, mock_agent):
        """Test that an agent yielding nothing produces no events rather than hanging or raising"""
        async def empty_stream(_request):
            return
            yield  # pragma: no cover - makes this an async generator

        mock_agent.invoke_stream = empty_stream

        events = [
            event async for event in
            agentic_chat_controller.create_stream(AgenticRequest.from_text('hello'))
        ]

        assert events == []


class TestAgenticChatControllerModule:
    """Test module-level wiring"""

    def test_module_exposes_a_single_agent_instance(self):
        """Test that the controller holds one shared agent rather than building one per request"""
        from agentic_platform.agent.agentic_chat.agent.agentic_chat_agent import (
            StrandsAgenticChatAgent
        )

        assert isinstance(agentic_chat_controller.agent, StrandsAgenticChatAgent)
