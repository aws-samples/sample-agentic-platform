from typing import List, Callable
from agentic_platform.core.models.api_models import AgenticRequest, AgenticResponse
from agentic_platform.core.models.memory_models import Message, TextContent
from agentic_platform.core.models.prompt_models import BasePrompt
from agentic_platform.core.client.memory_gateway.memory_gateway_client import MemoryGatewayClient
from agentic_platform.core.models.memory_models import SessionContext, Message
from agentic_platform.core.client.llm_gateway.llm_gateway_client import LLMGatewayClient
from agentic_platform.core.models.llm_models import LiteLLMClientInfo

from strands import Agent as StrandsAgent
from strands.models.litellm import LiteLLMModel as StrandsLiteLLMModel

from agentic_platform.core.models.memory_models import (
    UpsertSessionContextRequest, 
    GetSessionContextRequest
)

memory_client = MemoryGatewayClient()

class StrandsAgentWrapper:
    """
    Wrapper for Strands agent that integrates with our platform abstractions.
    Strands provides a simple, clean API for building agents with native LiteLLM integration.
    """
    
    def __init__(self, tools: List[Callable], base_prompt: BasePrompt = None):
        self.conversation: SessionContext = SessionContext()
        
        # Use default prompt if none provided
        if base_prompt is None:
            base_prompt = BasePrompt(
                system_prompt="You are a helpful assistant.",
                model_id="us.anthropic.claude-3-5-haiku-20241022-v1:0"
            )
        
        # Get LiteLLM client info for routing through our gateway
        litellm_info: LiteLLMClientInfo = LLMGatewayClient.get_client_info()
        
        # Extract hyperparameters
        temp: float = base_prompt.hyperparams.get("temperature", 0.5)
        max_tokens: int = base_prompt.hyperparams.get("max_tokens", 1000)
        
        # Create LiteLLM model for Strands
        # Route through our LiteLLM gateway by using the gateway endpoint
        model_params = {
            "max_tokens": max_tokens,
            "temperature": temp,
        }
        
        # Add gateway routing if available
        try:
            model_params["api_base"] = litellm_info.api_endpoint
            model_params["api_key"] = litellm_info.api_key
        except Exception:
            # Fall back to direct model access if gateway not available
            pass
            
        self.model = StrandsLiteLLMModel(
            model_id=f"bedrock/{base_prompt.model_id}",
            params=model_params
        )
        
        # Create the Strands agent
        self.agent = StrandsAgent(
            model=self.model,
            tools=tools,
            system_prompt=base_prompt.system_prompt
        )
    
    def invoke(self, request: AgenticRequest) -> AgenticResponse:
        """
        Invoke the Strands agent with our standard request/response format.
        """
        # Get or create conversation
        if request.session_id:
            sess_request = GetSessionContextRequest(session_id=request.session_id)
            session_results = memory_client.get_session_context(sess_request).results
            if session_results:
                self.conversation = session_results[0]
            else:
                self.conversation = SessionContext(session_id=request.session_id)
        else:
            self.conversation = SessionContext(session_id=request.session_id)

        # Add the message from request to conversation
        self.conversation.add_message(request.message)
        
        # Extract user text for Strands
        user_text = ""
        if request.message.content:
            for content in request.message.content:
                if hasattr(content, 'text') and content.text:
                    user_text = content.text
                    break
        
        if not user_text:
            raise ValueError("No user message text found in request")

        # Call Strands agent - this handles the full conversation flow internally
        response_text = self.agent(user_text)
        
        # Convert response to our format
        response_message = Message(
            role="assistant",
            content=[TextContent(type="text", text=response_text)]
        )
        
        # Add response to conversation
        self.conversation.add_message(response_message)
        
        # Save updated conversation
        memory_client.upsert_session_context(UpsertSessionContextRequest(
            session_context=self.conversation
        ))

        # Return the response using our standard format
        return AgenticResponse(
            session_id=self.conversation.session_id,
            message=response_message,
            metadata={
                "framework": "strands",
                "model": self.model.model_id
            }
        )