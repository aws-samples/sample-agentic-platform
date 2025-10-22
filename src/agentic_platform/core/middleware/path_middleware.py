from typing import Any, Callable, Pattern, Match, Optional, cast, TypeVar, Awaitable
import re
from starlette.middleware.base import BaseHTTPMiddleware
from fastapi import Request, Response
from starlette.types import ASGIApp, Scope, Receive, Send
import logging

T = TypeVar('T', bound=ASGIApp)

logger = logging.getLogger(__name__)

class PathTransformMiddleware(BaseHTTPMiddleware):
    """
    Middleware to transform incoming request paths to match FastAPI route definitions.
    This handles requests from load balancers that include additional path prefixes.
    
    Example:
        With path_prefix='/api/langgraph-chat/v1'
        A request to '/api/langgraph-chat/v1/chat' will be routed to '/chat'
    """
    
    pattern: Pattern[str]
    original_prefix: str
    
    def __init__(self, app: T, path_prefix: str):
        """
        Initialize the middleware.
        
        Args:
            app: The FastAPI application
            path_prefix: The complete path prefix to match and remove from incoming requests
        """
        super().__init__(app)
        # Escape the path prefix for use in regex
        escaped_path_prefix: str = re.escape(path_prefix)
        # Build the pattern - match the exact prefix and capture everything after it
        self.pattern = re.compile(f"^{escaped_path_prefix}(/.*)")
        self.original_prefix = path_prefix
    
    async def dispatch(
        self, 
        request: Request, 
        call_next: Callable[[Request], Awaitable[Response]]
    ) -> Response:
        # Extract the original path
        original_path: str = cast(str, request.scope["path"])
        
        # Check if the path matches our pattern
        match: Optional[Match[str]] = self.pattern.search(original_path)
        if match:
            # Extract just the endpoint part (the captured group)
            endpoint_path: str = match.group(1)
            
            # Update the path in the request scope
            request.scope["path"] = endpoint_path
            
            # Store the original path in request state for reference if needed
            request.state.original_path = original_path
            request.state.path_prefix = self.original_prefix
            
            # print(f"Transformed path from {original_path} to {endpoint_path}")
        # else:
        #     logger.info(f"Path {original_path} did not match pattern, no transformation applied")
        
        # Continue processing the request with the modified path
        response: Response = await call_next(request)
        return response