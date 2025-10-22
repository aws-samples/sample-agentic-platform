"""FastAPI server for the Agentic Chat Agent."""

import json
import logging
from fastapi import FastAPI
from fastapi.responses import StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

from agentic_platform.core.middleware.configure_middleware import configuration_server_middleware
from agentic_platform.core.models.api_models import AgenticRequest, AgenticResponse
from agentic_platform.core.decorator.api_error_decorator import handle_exceptions
from agentic_platform.agent.agentic_rag.controller import agentic_rag_controller

# Configure logging
logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)
logger.setLevel(logging.WARN)

# Initialize FastAPI app
app = FastAPI(title="Agentic Rag Agent")

# Configure middleware
configuration_server_middleware(app, path_prefix="/api/agentic-rag")

# Invocations is the endpoint AgentCore uses. If you'd rather this stream, you can move the annotation to the stream method.
@app.post("/invocations", response_model=AgenticResponse)
@app.post("/invoke", response_model=AgenticResponse)
# @handle_exceptions(status_code=500, error_prefix="Agentic Chat Agent API Error")
async def invoke(request: AgenticRequest) -> AgenticResponse:
    """
    Invoke the Agentic Chat agent with a standard response.
    """
    return await agentic_rag_controller.invoke(request)


@app.post("/stream")
@handle_exceptions(status_code=500, error_prefix="Agentic Chat Agent Streaming API Error")
async def stream(request: AgenticRequest) -> StreamingResponse:
    """
    Stream responses from the Agentic Chat agent using Server-Sent Events.
    """
    async def event_generator():
        """Convert StreamEvent objects to SSE format with event names."""
        try:
            async for stream_event in agentic_rag_controller.create_stream(request):
                # Convert StreamEvent to SSE format with event name
                event_data = stream_event.model_dump(mode='json')
                event_type = stream_event.type.value  # Get the enum value
                sse_line = f"event: {event_type}\ndata: {json.dumps(event_data)}\n\n"
                yield sse_line
        except Exception as e:
            logger.error(f"Error in streaming: {e}")
            error_data = {
                "type": "error",
                "session_id": request.session_id,
                "error": str(e)
            }
            yield f"event: error\ndata: {json.dumps(error_data)}\n\n"
    
    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "Content-Type": "text/event-stream",
        }
    )


@app.get("/health")
@app.get("/ping")
async def health() -> dict[str, str]:
    """
    Health check endpoint for Kubernetes probes.
    
    Returns:
        Health status
    """
    return {"status": "healthy"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8003)  # nosec B104 - Binding to all interfaces within container is intended
