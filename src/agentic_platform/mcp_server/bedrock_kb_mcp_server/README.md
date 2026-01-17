# Bedrock Knowledge Base MCP Server

An MCP (Model Context Protocol) server that provides access to AWS Bedrock Knowledge Base for querying and retrieving relevant information.

## Overview

This MCP server exposes a single tool `query_knowledge_base` that allows AI agents and applications to search and retrieve information from an AWS Bedrock Knowledge Base.

## Features

- Simple query interface for knowledge base searches
- Returns top 5 most relevant results
- Includes relevance scores for each result
- Error handling and logging
- Runs via streamable-HTTP transport for Amazon Bedrock AgentCore Runtime compatibility
- Stateless HTTP server with health check endpoints

## Prerequisites

- Python 3.12+
- AWS credentials configured (via AWS CLI, IAM role, or environment variables)
- Access to an AWS Bedrock Knowledge Base
- uv package manager

## Installation

### Local Development

1. Install dependencies:
```bash
cd src/agentic_platform/mcp_server/bedrock_kb_mcp_server
uv pip install -r requirements.txt
```

2. Configure environment variables:
```bash
cp .env.example .env
# Edit .env and set your KNOWLEDGE_BASE_ID
```

3. Run the server:
```bash
export KNOWLEDGE_BASE_ID=your-kb-id
uv run python server.py
```

### Docker Deployment

1. Build the Docker image:
```bash
docker build -t bedrock-kb-mcp-server -f src/agentic_platform/mcp_server/bedrock_kb_mcp_server/Dockerfile .
```

2. Run the container:
```bash
docker run -e KNOWLEDGE_BASE_ID=your-kb-id -e AWS_REGION=us-west-2 bedrock-kb-mcp-server
```

## Configuration

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `KNOWLEDGE_BASE_ID` | Yes | - | AWS Bedrock Knowledge Base ID |
| `AWS_REGION` | No | us-west-2 | AWS region where the KB is located |
| `AWS_ACCESS_KEY_ID` | No | - | AWS access key (if not using IAM role) |
| `AWS_SECRET_ACCESS_KEY` | No | - | AWS secret key (if not using IAM role) |

## Usage

### Available Tools

#### query_knowledge_base

Query the AWS Bedrock Knowledge Base for relevant information.

**Parameters:**
- `query` (string, required): The search query text

**Returns:**
- String containing the most relevant results, or an error message

**Example:**
```
query: "What are the main features of AWS Bedrock?"
```

### Testing with HTTP/AgentCore

The server runs an HTTP endpoint compatible with Amazon Bedrock AgentCore:

```bash
# Start the server
python src/agentic_platform/mcp_server/bedrock_kb_mcp_server/server.py

# Test health check (in another terminal)
curl http://localhost:8080/health
# Expected: {"status":"healthy","service":"bedrock-kb-mcp-server"}

# Test MCP endpoint
curl -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":1}'
```

### Testing with MCP Inspector

The MCP Inspector is a tool for testing MCP servers interactively:

```bash
npx @modelcontextprotocol/inspector uv run python src/agentic_platform/mcp_server/bedrock_kb_mcp_server/server.py
```

This will open a web interface where you can:
1. View available tools
2. Test the `query_knowledge_base` tool
3. See responses and debug output

### Integration with Claude Desktop

Add this server to your Claude Desktop configuration:

```json
{
  "mcpServers": {
    "bedrock-kb": {
      "command": "uv",
      "args": [
        "run",
        "python",
        "/path/to/src/agentic_platform/mcp_server/bedrock_kb_mcp_server/server.py"
      ],
      "env": {
        "KNOWLEDGE_BASE_ID": "your-kb-id-here",
        "AWS_REGION": "us-west-2"
      }
    }
  }
}
```

## Architecture

The server uses:
- **FastMCP**: Simplified MCP server framework
- **boto3**: AWS SDK for Python to interact with Bedrock
- **streamable-HTTP transport**: HTTP-based stateless MCP communication for AgentCore compatibility
- **Uvicorn/Starlette**: ASGI server for HTTP handling

Server endpoints:
- `http://0.0.0.0:8080/mcp` - MCP protocol endpoint (streamable-HTTP)
- `http://0.0.0.0:8080/health` - Kubernetes health check endpoint

Query flow:
1. Receive query via MCP protocol over HTTP POST to /mcp
2. Call `bedrock-agent-runtime.retrieve()` API
3. Extract text content from top 5 results
4. Return formatted results with relevance scores

## Error Handling

The server handles various error scenarios:
- Missing `KNOWLEDGE_BASE_ID`: Raises ValueError on startup
- AWS API errors: Returns error message in response
- Empty results: Returns "No relevant information found"

All errors are logged for debugging purposes.

## Development

### Project Structure

```
bedrock_kb_mcp_server/
├── server.py          # Main MCP server implementation
├── requirements.txt   # Python dependencies
├── Dockerfile        # Container image definition
├── .env.example      # Example environment configuration
└── README.md         # This file
```

### Logging

The server uses Python's standard logging module. Set the logging level via:

```python
logging.basicConfig(level=logging.DEBUG)  # For verbose output
```

## Troubleshooting

### Server won't start

- Verify `KNOWLEDGE_BASE_ID` is set in environment
- Check AWS credentials are configured correctly
- Ensure boto3 can access the Bedrock service

### No results returned

- Verify the Knowledge Base ID is correct
- Check that the KB has been indexed with data
- Ensure your AWS credentials have permission to query the KB

### Connection issues

- The server exposes HTTP endpoints at port 8080
- MCP protocol available at `/mcp` endpoint
- Health checks available at `/health` endpoint
- For AgentCore integration, use the `/mcp` endpoint
- Check logs for detailed error messages

## License

Part of the Agentic Platform project.
