from fastapi import FastAPI
import uvicorn

from agentic_platform.core.middleware.configure_middleware import configuration_server_middleware
from agentic_platform.core.models.api_models import AgenticRequest, AgenticResponse
from agentic_platform.core.decorator.api_error_decorator import handle_exceptions
from agentic_platform.agent.strands_agent.strands_agent_controller import StrandsAgentController
import logging

# Get logger for this module
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

app = FastAPI(title="Strands Agent API")

# Essential middleware.
configuration_server_middleware(app, path_prefix="/api/strands-agent")

# Essential endpoints
@app.post("/invoke", response_model=AgenticResponse)
@handle_exceptions(status_code=500, error_prefix="Strands Agent API Error")
async def invoke(request: AgenticRequest) -> AgenticResponse:
    """
    Invoke the Strands agent.
    Keep this app server very thin and push all logic to the controller.
    """
    return StrandsAgentController.invoke(request)

@app.get("/health")
async def health():
    """
    Health check endpoint for Kubernetes probes.
    """
    return {"status": "healthy"}

# Run the server with uvicorn.
if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)  # nosec B104 - Binding to all interfaces within container is intended