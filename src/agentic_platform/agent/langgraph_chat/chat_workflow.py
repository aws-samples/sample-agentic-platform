from typing import Dict
import re

from langgraph.graph import END, Graph, START


from agentic_platform.core.models.prompt_models import BasePrompt
from agentic_platform.core.models.llm_models import LLMResponse, LLMRequest
from agentic_platform.core.models.memory_models import Message
from agentic_platform.core.client.llm_gateway.llm_gateway_client import LLMGatewayClient


class LangGraphChat:

    def __init__(self):
        self.agent: Graph = self.create_agent()

    @staticmethod
    def call_llm(prompt: BasePrompt) -> LLMResponse:
        """Call Bedrock through the LLM Gateway"""
        request: LLMRequest = LLMRequest(
            system_prompt=prompt.system_prompt,
            messages=[Message(role='user', text=prompt.user_prompt)],
            model_id=prompt.model_id,
            hyperparams=prompt.hyperparams
        )

        return LLMGatewayClient.chat_invoke(request=request)


    def create_agent(self) -> Graph:
        """Create and return the LangGraph agent workflow"""
        # Create our graph
        workflow: Graph = Graph()

        # Add our LLM node
        workflow.add_node("llm", self.call_llm)

        # Set up the flow: START -> LLM -> END
        workflow.add_edge(START, "llm")
        workflow.add_edge("llm", END)

        # Compile the graph
        return workflow.compile()

    def run(self, prompt: BasePrompt) -> Message:
        """Run the agent with the given messages"""
        
        # Run the agent
        response: LLMResponse = self.agent.invoke(prompt)
        print(response)
        return Message(
            role='assistant',
            text=response.text
        )
