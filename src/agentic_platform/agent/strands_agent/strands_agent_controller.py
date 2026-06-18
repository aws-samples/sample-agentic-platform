from agentic_platform.core.models.api_models import AgenticRequest, AgenticResponse
from typing import List, Callable, Optional
from agentic_platform.agent.strands_agent.strands_agent import StrandsAgentWrapper
from agentic_platform.tool.retrieval.retrieval_tool import retrieve_and_answer
from agentic_platform.tool.weather.weather_tool import weather_report
from agentic_platform.tool.calculator.calculator_tool import handle_calculation

# Pull the tools from our tool directory into the agent. Description is pulled from the docstring.
tools: List[Callable] = [retrieve_and_answer, weather_report, handle_calculation]

class StrandsAgentController:
    _agent: Optional[StrandsAgentWrapper] = None
    
    @classmethod
    def _get_agent(cls) -> StrandsAgentWrapper:
        """Lazy-load the agent to avoid initialization issues during imports"""
        if cls._agent is None:
            cls._agent = StrandsAgentWrapper(tools=tools)
        return cls._agent

    @classmethod
    def invoke(cls, request: AgenticRequest) -> AgenticResponse:
        """
        Invoke the Strands agent. 
        """
        agent = cls._get_agent()
        return agent.invoke(request)