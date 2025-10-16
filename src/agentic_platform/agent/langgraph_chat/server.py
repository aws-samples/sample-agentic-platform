from fastapi import FastAPI
import uvicorn

from agentic_platform.core.middleware.configure_middleware import configuration_server_middleware
from agentic_platform.core.models.api_models import AgenticRequest, AgenticResponse
from agentic_platform.core.decorator.api_error_decorator import handle_exceptions
from agentic_platform.agent.langgraph_chat.chat_controller import ChatController
import logging

# Get logger for this module
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

app = FastAPI(title="LangGraph Chat API",)

# Essential middleware.
configuration_server_middleware(app,path_prefix="/api/langgraph-chat")

# Essential endpoints
@app.post("/invocations", response_model=AgenticResponse)
@app.post("/chat", response_model=AgenticResponse)
@handle_exceptions(status_code=500, error_prefix="LangGraph Chat API Error")
async def chat(request: AgenticRequest) -> AgenticResponse:
    """
    Chat with the LangGraph chat agent.
    Keep this app server very thin and push all logic to the controller.
    """
    return ChatController.chat(request)

@app.get("/health")
@app.get("/ping")
async def health():
    """
    Health check endpoint for Kubernetes probes.
    """
    return {"status": "healthy"}

# Run the server with uvicorn.
if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000) # nosec B104 - Binding to all interfaces within container is intended