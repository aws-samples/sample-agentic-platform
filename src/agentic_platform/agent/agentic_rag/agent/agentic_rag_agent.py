"""Agentic RAG Agent implementation using Strands."""

import os
import logging
from typing import AsyncGenerator

from strands import Agent
from strands.models.litellm import OpenAIModel

from agentic_platform.core.models.api_models import AgenticRequest, AgenticResponse
from agentic_platform.core.models.memory_models import Message, TextContent
from agentic_platform.core.models.streaming_models import StreamEvent
from agentic_platform.core.converter.strands_converters import StrandsStreamingConverter
from agentic_platform.core.client.llm_gateway.llm_gateway_client import LLMGatewayClient, LiteLLMClientInfo
from agentic_platform.agent.agentic_rag.prompt.agentic_rag_prompt import AgenticRagPrompt
from agentic_platform.agent.agentic_rag.tool.kb_tool import search_knowledge_base

logger = logging.getLogger(__name__)


class StrandsAgenticRagAgent:
    """RAG Agent implementation using Strands framework with Bedrock knowledge base."""

    def __init__(self):
        """Initialize the RAG agent with Bedrock KB access."""

        litellm_info: LiteLLMClientInfo = LLMGatewayClient.get_client_info()

        self.model = OpenAIModel(
            model_id="anthropic.claude-sonnet-4-20250514-v1:0",
            client_args={
                "api_key": litellm_info.api_key,
                "base_url": litellm_info.api_endpoint,
                "timeout": 30
            }
        )

        prompt: AgenticRagPrompt = AgenticRagPrompt()

        self.agent = Agent(
            model=self.model,
            system_prompt=prompt.system_prompt,
            tools=[search_knowledge_base]
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
            metadata={
                "agent_type": "strands_agentic_rag",
                "kb_search_performed": True
            }
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
               