"""Jira Agent implementation using Strands."""

import logging
from typing import AsyncGenerator

from strands import Agent
from strands.models.litellm import OpenAIModel

from agentic_platform.core.models.api_models import AgenticRequest, AgenticResponse
from agentic_platform.core.models.memory_models import Message, TextContent
from agentic_platform.core.models.streaming_models import StreamEvent
from agentic_platform.core.converter.strands_converters import StrandsStreamingConverter
from agentic_platform.core.client.llm_gateway.llm_gateway_client import LLMGatewayClient, LiteLLMClientInfo
from agentic_platform.agent.jira_agent.jira_prompt import JiraPrompt

logger = logging.getLogger(__name__)


class StrandsJiraAgent:
    """Jira Agent implementation using Strands framework."""

    def __init__(self):
        """Initialize the agent with Strands framework."""

        # Grab the proxy URL from our gateway client
        litellm_info: LiteLLMClientInfo = LLMGatewayClient.get_client_info()

        # To use the LiteLLM proxy, use the OpenAIModel to avoid name conflicts
        self.model = OpenAIModel(
            model_id="us.anthropic.claude-haiku-4-5-20251001-v1:0",
            client_args={
                "api_key": litellm_info.api_key,
                "base_url": litellm_info.api_endpoint,
                "timeout": 30
            }
        )

        prompt = JiraPrompt()

        # Initialize simple agent (MCP integration to be added later)
        self.agent = Agent(
            model=self.model,
            system_prompt=prompt.system_prompt
        )

    def invoke(self, request: AgenticRequest) -> AgenticResponse:
        """Invoke the Strands Jira agent synchronously."""

        text_content = request.message.get_text_content()
        result = self.agent(text_content.text)

        response_message = Message(
            role="assistant",
            content=[TextContent(text=str(result))]
        )

        return AgenticResponse(
            message=response_message,
            session_id=request.session_id,
            metadata={"agent_type": "strands_jira_agent"}
        )

    async def invoke_stream(self, request: AgenticRequest) -> AsyncGenerator[StreamEvent, None]:
        """Invoke the Strands Jira agent with streaming support using async iterator."""
        converter = StrandsStreamingConverter(request.session_id)
        text_content = request.message.get_text_content()

        try:
            async for event in self.agent.stream_async(text_content.text):
                # Convert Strands event to platform StreamEvents (can be multiple)
                platform_events = converter.convert_chunks_to_events(event)

                # Yield each event
                for platform_event in platform_events:
                    yield platform_event

        except Exception as e:
            logger.error(f"Error in streaming: {e}")
            from agentic_platform.core.models.streaming_models import ErrorEvent
            error_event = ErrorEvent(
                session_id=request.session_id,
                error=str(e)
            )
            yield error_event
