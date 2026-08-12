import pytest
from unittest.mock import MagicMock, patch

from agentic_platform.core.models.api_models import AgenticRequest, AgenticResponse
from agentic_platform.core.models.streaming_models import (
    ErrorEvent, StreamEventType, TextDeltaEvent
)

AGENT_MODULE = 'agentic_platform.agent.agentic_chat.agent.agentic_chat_agent'


@pytest.fixture
def mock_gateway_client():
    """Mock the LLM gateway client so no endpoint or key is resolved from the environment"""
    with patch(f'{AGENT_MODULE}.LLMGatewayClient') as mock_client:
        mock_client.get_client_info.return_value = MagicMock(
            api_key='test-key',
            api_endpoint='http://localhost:4000/v1'
        )
        yield mock_client


@pytest.fixture
def mock_strands_agent():
    """Mock the Strands Agent so the framework's own loop is never exercised"""
    with patch(f'{AGENT_MODULE}.Agent') as mock_agent_cls:
        yield mock_agent_cls.return_value


@pytest.fixture
def chat_agent(mock_gateway_client, mock_strands_agent):
    """Create the agent with the Strands framework and model stubbed out"""
    with patch(f'{AGENT_MODULE}.OpenAIModel'):
        from agentic_platform.agent.agentic_chat.agent.agentic_chat_agent import (
            StrandsAgenticChatAgent
        )
        return StrandsAgenticChatAgent()


class TestStrandsAgenticChatAgentInit:
    """Test agent construction wires the LiteLLM proxy details from the gateway client"""

    def test_model_configured_from_gateway_client(self, mock_gateway_client, mock_strands_agent):
        """Test that the model receives credentials from LLMGatewayClient rather than hardcoded values"""
        with patch(f'{AGENT_MODULE}.OpenAIModel') as mock_model_cls:
            from agentic_platform.agent.agentic_chat.agent.agentic_chat_agent import (
                StrandsAgenticChatAgent
            )
            StrandsAgenticChatAgent()

        mock_gateway_client.get_client_info.assert_called_once()
        client_args = mock_model_cls.call_args.kwargs['client_args']
        assert client_args['api_key'] == 'test-key'
        assert client_args['base_url'] == 'http://localhost:4000/v1'


class TestStrandsAgenticChatAgentInvoke:
    """Test the synchronous invoke path"""

    def test_invoke_returns_agentic_response(self, chat_agent, mock_strands_agent):
        """Test that invoke returns an AgenticResponse carrying the agent's text"""
        mock_strands_agent.return_value = 'Paris is the capital of France.'
        request = AgenticRequest.from_text('What is the capital of France?')

        response = chat_agent.invoke(request)

        assert isinstance(response, AgenticResponse)
        assert response.message.role == 'assistant'
        assert response.text == 'Paris is the capital of France.'

    def test_invoke_forwards_user_text_to_strands(self, chat_agent, mock_strands_agent):
        """Test that the user's text is what gets handed to the Strands agent"""
        mock_strands_agent.return_value = 'ok'
        request = AgenticRequest.from_text('summarize this')

        chat_agent.invoke(request)

        mock_strands_agent.assert_called_once_with('summarize this')

    def test_invoke_preserves_session_id(self, chat_agent, mock_strands_agent):
        """Test that the caller's session id is echoed back on the response"""
        mock_strands_agent.return_value = 'ok'
        request = AgenticRequest.from_text('hello', session_id='session-abc')

        response = chat_agent.invoke(request)

        assert response.session_id == 'session-abc'

    def test_invoke_tags_response_with_agent_type(self, chat_agent, mock_strands_agent):
        """Test that metadata identifies which agent produced the response"""
        mock_strands_agent.return_value = 'ok'

        response = chat_agent.invoke(AgenticRequest.from_text('hello'))

        assert response.metadata['agent_type'] == 'strands_agentic_chat'

    def test_invoke_coerces_non_string_result(self, chat_agent, mock_strands_agent):
        """Test that a non-string result from Strands is stringified rather than raising"""
        mock_strands_agent.return_value = 42

        response = chat_agent.invoke(AgenticRequest.from_text('hello'))

        assert response.text == '42'


class TestStrandsAgenticChatAgentInvokeStream:
    """Test the streaming invoke path"""

    @pytest.mark.asyncio
    async def test_invoke_stream_yields_converted_events(self, chat_agent, mock_strands_agent):
        """Test that Strands chunks are converted to platform StreamEvents"""
        async def fake_stream(_text):
            yield {'event': 'chunk-1'}
            yield {'event': 'chunk-2'}

        mock_strands_agent.stream_async = fake_stream
        expected = TextDeltaEvent(session_id='session-abc', text='hi')

        with patch(f'{AGENT_MODULE}.StrandsStreamingConverter') as mock_converter_cls:
            mock_converter_cls.return_value.convert_chunks_to_events.return_value = [expected]
            request = AgenticRequest.from_text('hello', session_id='session-abc')

            events = [event async for event in chat_agent.invoke_stream(request)]

        # One event per chunk, both passed through the converter
        assert events == [expected, expected]
        assert mock_converter_cls.return_value.convert_chunks_to_events.call_count == 2

    @pytest.mark.asyncio
    async def test_invoke_stream_yields_error_event_on_failure(self, chat_agent, mock_strands_agent):
        """Test that a failure mid-stream surfaces as an ErrorEvent instead of propagating"""
        async def failing_stream(_text):
            yield {'event': 'chunk-1'}
            raise RuntimeError('upstream exploded')

        mock_strands_agent.stream_async = failing_stream

        with patch(f'{AGENT_MODULE}.StrandsStreamingConverter') as mock_converter_cls:
            mock_converter_cls.return_value.convert_chunks_to_events.return_value = []
            request = AgenticRequest.from_text('hello', session_id='session-abc')

            events = [event async for event in chat_agent.invoke_stream(request)]

        assert len(events) == 1
        assert isinstance(events[0], ErrorEvent)
        assert events[0].type == StreamEventType.ERROR
        assert events[0].session_id == 'session-abc'
        assert 'upstream exploded' in events[0].error
