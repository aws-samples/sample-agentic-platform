"""Agentic Chat Agent implementation using Strands."""

import json
import logging
from typing import AsyncGenerator

from strands import Agent
from strands_tools import calculator
from strands.models.litellm import OpenAIModel

from agentic_platform.core.models.api_models import AgenticRequest, AgenticResponse
from agentic_platform.core.models.memory_models import Message, TextContent
from agentic_platform.core.models.streaming_models import StreamEvent
from agentic_platform.agent.agentic_chat.streaming.strands_converter import StrandsStreamingConverter
from agentic_platform.core.client.llm_gateway.llm_gateway_client import LLMGatewayClient, LiteLLMClientInfo

logger = logging.getLogger(__name__)


class StrandsAgenticChatAgent:
    """Agent implementation using Strands framework."""

    def __init__(self):
        """Initialize the agent with the Strands framework."""

        # Grab the proxy URL from our gateway client. 
        litellm_info: LiteLLMClientInfo = LLMGatewayClient.get_client_info()

        # To use the LiteLLM proxy, you need to use teh OpenAIModel. The default
        # litellm object uses the LiteLLM SDK which has name conflicts when trying
        # to use the proxy so it's preferred to use the OpenAIModel type when calling
        # the actual proxy vs. just using the SDK. 
        self.model = OpenAIModel(
            model_id="anthropic.claude-sonnet-4-20250514-v1:0",
            client_args={
                "api_key": litellm_info.api_key,
                "base_url": litellm_info.api_endpoint,
                "timeout": 30
            }
        )

        self.agent = Agent(
            model=self.model,
            tools=[calculator]
        )

    def invoke(self, request: AgenticRequest) -> AgenticResponse:
        """Invoke the Strands agent synchronously."""
        
        text_content = request.message.get_text_content()
        result = self.agent(text_content.text)
        
        response_message = Message(
            role="assistant",
            content=[TextContent(text=str(result))]
        )
        
        return AgenticResponse(
            message=response_message,
            session_id=request.session_id,
            metadata={"agent_type": "strands_agentic_chat"}
        )

    async def invoke_stream(self, request: AgenticRequest) -> AsyncGenerator[StreamEvent, None]:
        """Invoke the Strands agent with streaming support using async iterator."""        
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
               