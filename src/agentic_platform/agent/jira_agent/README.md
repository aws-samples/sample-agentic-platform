# Jira Agent with Knowledge Base Integration

A Strands-based agent that integrates with AWS Bedrock Knowledge Base via MCP (Model Context Protocol) to provide intelligent responses based on your organization's support ticket history.

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Jira Agent    │────▶│   MCP Server    │────▶│  Bedrock KB     │
│   (Strands)     │     │   (stdio)       │     │  (S3 Vectors)   │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │                       │                       │
        │                       │                       │
        ▼                       ▼                       ▼
   FastAPI Server         Subprocess            Vector Search
   /invoke endpoint       spawned by agent      over documents
```

### How It Works

1. **Agent Initialization**: When the Jira agent starts, it creates an MCP client configured to spawn the Bedrock KB MCP server as a subprocess using stdio transport.

2. **Tool Discovery**: The MCP client connects to the server and discovers available tools (e.g., `query_knowledge_base`).

3. **Query Processing**: When a user sends a request, the agent:
   - Analyzes the query using Claude (via Bedrock)
   - Decides whether to use the knowledge base tool
   - Calls the MCP server's `query_knowledge_base` tool if needed
   - Synthesizes the results into a helpful response

4. **Knowledge Base Search**: The MCP server queries AWS Bedrock Knowledge Base, which:
   - Converts the query to embeddings using Nova 2 multimodal
   - Performs vector similarity search in S3 Vectors
   - Returns the most relevant document chunks

## Local Development Setup

### Prerequisites

- AWS credentials configured (via `aws configure` or environment variables)
- Access to AWS Bedrock and a configured Knowledge Base
- Python 3.12+
- uv package manager

### 1. Configure Environment Variables

Copy the example `.env` file and update with your values:

```bash
cd src/agentic_platform/agent/jira_agent
cp .env.example .env  # or edit .env directly
```

Edit `.env` with your configuration:

```bash
# Bedrock Knowledge Base Configuration
KNOWLEDGE_BASE_ID=<your-knowledge-base-id>
AWS_REGION=us-east-1

# LiteLLM Gateway (optional - for production use)
# LITELLM_API_ENDPOINT=http://localhost:4000
# LITELLM_KEY=<your-litellm-key>
```

### 2. Populate the Knowledge Base

The agent queries a Bedrock Knowledge Base that needs to be populated with your documents. Example support tickets are provided in the `examples/` directory.

#### Option A: Using AWS Console

1. Navigate to **Amazon Bedrock** → **Knowledge bases**
2. Select your knowledge base
3. Click on the data source
4. Upload files to the linked S3 bucket
5. Click **Sync** to ingest the documents

#### Option B: Using AWS CLI

```bash
# Upload documents to the KB's S3 bucket
aws s3 cp examples/ s3://<your-kb-documents-bucket>/ --recursive --region us-east-1

# Trigger a sync/ingestion job
aws bedrock-agent start-ingestion-job \
  --knowledge-base-id <your-knowledge-base-id> \
  --data-source-id <your-data-source-id> \
  --region us-east-1

# Check sync status
aws bedrock-agent get-ingestion-job \
  --knowledge-base-id <your-knowledge-base-id> \
  --data-source-id <your-data-source-id> \
  --ingestion-job-id <job-id-from-previous-command> \
  --region us-east-1
```

### 3. Run the Agent

```bash
# From the repository root
make dev jira_agent

# Or manually
cd src
uv run --env-file agentic_platform/agent/jira_agent/.env -- \
  uvicorn agentic_platform.agent.jira_agent.server:app --reload --port 8080
```

### 4. Test the Agent

```bash
curl -X POST http://localhost:8080/invoke \
  -H "Content-Type: application/json" \
  -d '{
    "message": {
      "role": "user",
      "content": [{"type": "text", "text": "What issues are related to email notifications?"}]
    },
    "session_id": "test-123"
  }'
```

## Example Documents

The `examples/` directory contains sample support tickets that demonstrate the expected document format:

- `ticket_001.md` - Email notification delivery issues
- `ticket_002.md` - Browser performance problems
- `ticket_003.md` - API rate limiting errors

These markdown files follow a structured format with:
- Ticket metadata (status, priority, assignee)
- Problem description and reproduction steps
- Environment details
- Root cause analysis
- Resolution information

## MCP Server Details

The Bedrock KB MCP server (`bedrock_kb_mcp_server`) provides:

### Tools

| Tool | Description |
|------|-------------|
| `query_knowledge_base` | Searches the knowledge base and returns relevant document chunks |

### Transport Modes

- **stdio** (default for local): Agent spawns server as subprocess
- **streamable-http**: For remote/deployed scenarios

### Configuration

The MCP server reads these environment variables:
- `KNOWLEDGE_BASE_ID` (required): Bedrock Knowledge Base ID
- `AWS_REGION` (optional): AWS region, defaults to `us-east-1`

## Troubleshooting

### No results from knowledge base

1. Verify the knowledge base ID is correct
2. Check that documents have been synced (ingestion job completed)
3. Ensure the IAM role has `s3vectors:PutVectors` permission
4. Try broader search terms

### MCP connection errors

1. Ensure AWS credentials are valid (`aws sts get-caller-identity`)
2. Check that the MCP server module path is correct
3. Review logs for subprocess startup errors

### Authentication errors

1. Run `aws configure` or set `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`
2. For SSO/credential process users, ensure credentials are refreshed

## File Structure

```
jira_agent/
├── server.py              # FastAPI server with /invoke endpoint
├── jira_controller.py     # Request handling and agent orchestration
├── jira_agent.py          # Strands agent with MCP integration
├── jira_prompt.py         # System prompt configuration
├── .env                   # Environment configuration
├── Dockerfile             # Container definition
├── requirements.txt       # Python dependencies
├── README.md              # This file
└── examples/              # Sample knowledge base documents
    ├── ticket_001.md
    ├── ticket_002.md
    └── ticket_003.md
```

## Related Components

- **MCP Server**: `src/agentic_platform/mcp_server/bedrock_kb_mcp_server/`
- **Infrastructure**: `infrastructure/stacks/knowledge-layer/` (Terraform)
- **Core Models**: `src/agentic_platform/core/models/`
