from typing import Dict, Any
import uuid
import re

from agentic_platform.core.models.memory_models import Message
from agentic_platform.core.models.prompt_models import BasePrompt
from agentic_platform.core.models.api_models import AgenticRequest, AgenticResponse

from agentic_platform.agent.langgraph_chat.chat_workflow import LangGraphChat
from agentic_platform.agent.langgraph_chat.chat_prompt import ChatPrompt

# Instantiate the chat service so we don't recreate the graph on each request.
chat_service = LangGraphChat()

class ChatController:

    @classmethod
    def extract_response(cls, text: str) -> str:
        response_match = re.search(r'<response>(.*?)</response>', text, re.DOTALL)
        return response_match.group(1).strip() if response_match else "I'm sorry, something went wrong. Please try again."

    @classmethod
    def chat(cls, request: AgenticRequest) -> AgenticResponse:
        """
        Chat with the LangGraph chat agent. 
        
        The goal of this function is to abstract away the LangGraph specifics from the rest of the system.
        This is important to provide "2-way" compatibility between different frameworks.
        """
        # TODO: Implement memory retrieval.
        # message_history = MessageHistory(messages=[])

        # Get the latest user text from the request
        user_text = request.latest_user_text
        if not user_text:
            user_text = "Hello"  # Default fallback

        # Convert the variables to a dictionary for the prompt to insert.
        inputs: Dict[str, Any] = {
            "chat_history": '',
            "message": user_text
        }

        # Create a Chat prompt object from the inputs.
        prompt: BasePrompt = ChatPrompt(inputs=inputs)

        # Run the chat service and get back a message object.
        response: Message = chat_service.run(prompt)

        # Extract and clean the response text
        response_text = cls.extract_response(response.text)
        
        # Create response message
        response_message = Message.from_text("assistant", response_text)

        # TODO: Append to the message history.
        
        # Return the agent response object to the server.
        return AgenticResponse(
            message=response_message,
            session_id=request.session_id
        )