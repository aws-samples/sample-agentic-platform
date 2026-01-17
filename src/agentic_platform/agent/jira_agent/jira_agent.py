"""Jira Agent implementation using Strands with MCP Knowledge Base integration."""

import logging
import os
from typing import AsyncGenerator

from mcp import stdio_client, StdioServerParameters
from strands import Agent
from strands.models import BedrockModel
from strands.tools.mcp import MCPClient

from agentic_platform.core.models.api_models import AgenticRequest, AgenticResponse
from agentic_platform.core.models.memory_models import Message, TextContent
from agentic_platform.core.models.streaming_models import StreamEvent
from agentic_platform.core.converter.strands_converters import StrandsStreamingConverter
from agentic_platform.agent.jira_agent.jira_prompt import JiraPrompt

logger = logging.getLogger(__name__)


class StrandsJiraAgent:
    """Jira Agent implementation using Strands framework with MCP KB integration."""

    def __init__(self):
        """Initialize the agent with Strands framework and MCP client."""

        # Use Bedrock directly for local testing
        self.model = BedrockModel(
            model_id="us.anthropic.claude-sonnet-4-20250514-v1:0",
            region_name=os.getenv("AWS_REGION", "us-east-1")
        )

        self.prompt = JiraPrompt()

        # Initialize MCP client for Bedrock KB using stdio
        self.mcp_client = MCPClient(lambda: stdio_client(
            StdioServerParameters(
                command="uv",
                args=["run", "python", "-m", "agentic_platform.mcp_server.bedrock_kb_mcp_server.server"],
                env={
                    "KNOWLEDGE_BASE_ID": os.getenv("KNOWLEDGE_BASE_ID", ""),
                    "AWS_REGION": os.getenv("AWS_REGION", "us-east-1"),
                    **os.environ
                }
            )
        ))

    def invoke(self, request: AgenticRequest) -> AgenticResponse:
        """Invoke the Strands Jira agent synchronously."""

        text_content = request.message.get_text_content()
        
        with self.mcp_client:
            tools = self.mcp_client.list_tools_sync()
            agent = Agent(
                model=self.model,
                system_prompt=self.prompt.system_prompt,
                tools=tools
            )
            result = agent(text_content.text)

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
        """Invoke the Strands Jira agent with streaming support."""
        converter = StrandsStreamingConverter(request.session_id)
        text_content = request.message.get_text_content()

        try:
            with self.mcp_client:
                tools = self.mcp_client.list_tools_sync()
                agent = Agent(
                    model=self.model,
                    system_prompt=self.prompt.system_prompt,
                    tools=tools
                )
                async for event in agent.stream_async(text_content.text):
                    platform_events = converter.convert_chunks_to_events(event)
                    for platform_event in platform_events:
                        yield platform_event

        except Exception as e:
            logger.error(f"Error in streaming: {e}")
            from agentic_platform.core.models.streaming_models import ErrorEvent
            yield ErrorEvent(session_id=request.session_id, error=str(e))
