"""
FastAPI server for the Strands Glue/Athena agent.
"""
from fastapi import FastAPI
import uvicorn
from typing import Dict, Any

from agentic_platform.core.middleware.configure_middleware import configuration_server_middleware
from agentic_platform.core.models.api_models import AgenticRequest, AgenticResponse
from agentic_platform.core.decorator.api_error_decorator import handle_exceptions
from agentic_platform.agent.strands_glue_athena.agent_controller import AgentController
import logging

# Get logger for this module
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

app = FastAPI(title="Strands Glue/Athena Agent API")

# Essential middleware
configuration_server_middleware(app, path_prefix="/api/strands-glue-athena")

# Essential endpoints
@app.post("/chat", response_model=AgenticResponse)
@handle_exceptions(status_code=500, error_prefix="Strands Glue/Athena Agent API Error")
async def chat(request: AgenticRequest) -> AgenticResponse:
    """
    Chat with the Strands Glue/Athena agent.
    Keep this app server very thin and push all logic to the controller.
    """
    return AgentController.chat(request)

@app.post("/chat/stream")
@handle_exceptions(status_code=500, error_prefix="Strands Glue/Athena Agent API Error")
async def stream_chat(request: AgenticRequest):
    """
    Stream chat with the Strands Glue/Athena agent.
    """
    return AgentController.stream_chat(request)

@app.get("/health")
async def health():
    """
    Health check endpoint for Kubernetes probes.
    """
    return {"status": "healthy"}

# Run the server with uvicorn
if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)  # nosec B104 - Binding to all interfaces within container is intended
