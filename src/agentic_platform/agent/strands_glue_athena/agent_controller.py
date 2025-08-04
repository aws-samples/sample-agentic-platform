"""
Controller for the Strands Glue/Athena agent.
"""
import re
from typing import Dict, Any, Optional

from agentic_platform.core.models.api_models import AgenticRequest, AgenticResponse
from agentic_platform.core.models.memory_models import Message, TextContent
from agentic_platform.agent.strands_glue_athena.agent_service import StrandsGlueAthenaAgent

# Instantiate the agent service so we don't recreate it on each request
agent_service = StrandsGlueAthenaAgent()


class AgentController:
    """
    Controller for the Strands Glue/Athena agent.
    """
    
    @classmethod
    def chat(cls, request: AgenticRequest) -> AgenticResponse:
        """
        Chat with the Strands Glue/Athena agent.
        
        The goal of this function is to abstract away the Strands specifics from the rest of the system.
        This is important to provide "2-way" compatibility between different frameworks.
        
        Args:
            request: The request containing the user message
            
        Returns:
            An AgenticResponse containing the agent's response
        """
        # Get the latest user text from the request
        user_text = request.latest_user_text
        if not user_text:
            user_text = "Hello"  # Default fallback
        
        # Process the message with the agent service
        response = agent_service.process_message(user_text, session_id=request.session_id)
        
        # Extract the response text
        response_text = response.get("text", "")
        
        # Create response message
        response_message = Message(
            role="assistant",
            content=[TextContent(type="text", text=response_text)]
        )
        
        # Return the agent response object to the server
        return AgenticResponse(
            message=response_message,
            session_id=request.session_id
        )
    
    @classmethod
    def stream_chat(cls, request: AgenticRequest):
        """
        Stream chat with the Strands Glue/Athena agent.
        
        Args:
            request: The request containing the user message
            
        Yields:
            Streaming response chunks
        """
        # Get the latest user text from the request
        user_text = request.latest_user_text
        if not user_text:
            user_text = "Hello"  # Default fallback
        
        # Stream the message with the agent service
        for chunk in agent_service.stream_message(user_text, session_id=request.session_id):
            # Extract the chunk text
            chunk_text = chunk.get("text", "")
            
            if chunk_text:
                # Create a streaming response chunk
                yield {
                    "type": "text",
                    "data": chunk_text
                }
