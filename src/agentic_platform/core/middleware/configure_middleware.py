from typing import List
import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from agentic_platform.core.middleware.auth.auth_middleware import AuthMiddleware
from agentic_platform.core.middleware.path_middleware import PathTransformMiddleware
from agentic_platform.core.middleware.request_context_middleware import RequestContextMiddleware

ENVIRONMENT: str = os.getenv("ENVIRONMENT")

def configuration_server_middleware(app: FastAPI, path_prefix: str, excluded_paths: List[str] = None) -> FastAPI:
    '''
    Configure the middleware for the servers. This is common to all servers.
    FastAPI is like a stack (LIFO) of middleware and order matters.

    Args:
        app: The FastAPI app to configure.
        path_prefix: The path prefix for the server. ALB sends the full path to the pod so we rewrite it in middleware.
        excluded_paths: The paths to exclude from our oAuth middleware.
    '''
    # Adds the token and auth results to the context variable for access throughout the invocation.
    app.add_middleware(RequestContextMiddleware)
    # Auth results are stored in the request state.
    
    # Don't authenticate requests normally if running locally or inside of agentcore (which handles auth separately).
    if ENVIRONMENT not in ['local', 'agentcore']:
        app.add_middleware(AuthMiddleware, excluded_paths=excluded_paths)

    # Converts things like /llm-gateway/model/llama3-70b/converse to /model/llama3-70b/converse
    app.add_middleware(PathTransformMiddleware, path_prefix=path_prefix)

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"], # nosemgrep: wildcard-cors
        allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "X-Service-ID"],
    )

    return app
