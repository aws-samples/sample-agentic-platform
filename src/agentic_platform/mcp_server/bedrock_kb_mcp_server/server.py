"""MCP Server for AWS Bedrock Knowledge Base queries."""

import os
import logging
from typing import Any, Dict, Optional
import boto3
from mcp.server.fastmcp import FastMCP
from starlette.requests import Request
from starlette.responses import Response

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class BedrockKnowledgeBaseMCPServer:
    """MCP server for querying AWS Bedrock Knowledge Base."""

    def __init__(self, name: str = "bedrock-kb"):
        """Initialize the MCP server.

        Args:
            name: Name of the MCP server
        """
        self.mcp = FastMCP(name)

        # Read configuration from environment
        self.knowledge_base_id = os.getenv('KNOWLEDGE_BASE_ID')
        if not self.knowledge_base_id:
            raise ValueError("KNOWLEDGE_BASE_ID environment variable must be set")

        # Initialize boto3 client
        region = os.getenv('AWS_REGION', 'us-east-1')
        self.bedrock_client = boto3.client('bedrock-agent-runtime', region_name=region)

        logger.info(f"Initialized Bedrock KB MCP Server with Knowledge Base ID: {self.knowledge_base_id}")

        # Register tools
        self._register_tools()

    def _register_tools(self):
        """Register all tools with the MCP server."""

        @self.mcp.tool()
        def query_knowledge_base(query: str) -> str:
            """Query the AWS Bedrock Knowledge Base for relevant information.

            This tool searches the knowledge base using the provided query text
            and returns the most relevant results.

            Args:
                query: The search query text to find relevant information

            Returns:
                Relevant information from the knowledge base, or an error message
            """
            try:
                logger.info(f"Querying knowledge base with: {query}")
                logger.info(f"Knowledge Base ID: {self.knowledge_base_id}")

                # Call Bedrock Knowledge Base retrieve API
                response = self.bedrock_client.retrieve(
                    knowledgeBaseId=self.knowledge_base_id,
                    retrievalQuery={'text': query},
                    retrievalConfiguration={
                        'vectorSearchConfiguration': {
                            'numberOfResults': 5
                        }
                    }
                )

                logger.info(f"Raw response keys: {response.keys()}")
                logger.info(f"Number of results: {len(response.get('retrievalResults', []))}")

                # Extract text content from results
                results = []
                for i, result in enumerate(response.get('retrievalResults', [])):
                    content = result.get('content', {}).get('text', '')
                    score = result.get('score', 0)
                    source = result.get('location', {}).get('s3Location', {}).get('uri', 'unknown')
                    logger.info(f"Result {i}: score={score:.4f}, source={source}, content_len={len(content)}")
                    if content:
                        results.append(f"[Score: {score:.4f}]\n{content}")

                if results:
                    logger.info(f"Returning {len(results)} results")
                    return "\n\n---\n\n".join(results)
                else:
                    logger.warning("No results found for query")
                    return "No relevant information found in the knowledge base."

            except Exception as e:
                logger.error(f"Error querying knowledge base: {str(e)}", exc_info=True)
                return f"Error accessing knowledge base: {str(e)}"

    def get_server(self) -> FastMCP:
        """Return the configured MCP server.

        Returns:
            Configured FastMCP server instance
        """
        return self.mcp


# Create and export the server
mcp_server = BedrockKnowledgeBaseMCPServer()
mcp = mcp_server.get_server()


if __name__ == "__main__":
    import sys
    transport = sys.argv[1] if len(sys.argv) > 1 else "stdio"
    logger.info(f"Starting Bedrock Knowledge Base MCP Server with {transport} transport")
    mcp.run(transport=transport)
