# Agentic RAG Agent

This agent answers questions by searching your Amazon Bedrock Knowledge Base and providing responses based on the retrieved information.

## Prerequisites

You need an Amazon Bedrock Knowledge Base already created and populated with your documents.

## Local Development

### Environment Setup

Create a `.env` file in this directory:

```bash
LITELLM_API_ENDPOINT=http://localhost:4000
LITELLM_KEY=sk-your-litellm-key
ENVIRONMENT=local
KNOWLEDGE_BASE_ID=your-knowledge-base-id
```

If you deployed the platform, you can find the LiteLLM API URL and key in the stack outputs.

### Running Locally

Use the Makefile to start the agent:

```bash
make agentic-rag
```

The agent will run on port 8004.

### Testing

```bash
curl -X POST "http://localhost:8004/invocations" \
  -H "Content-Type: application/json" \
  -d '{
    "message": {
      "role": "user", 
      "content": [{"type": "text", "text": "Can you tell me a joke?"}]
    },
    "session_id": "test-session"
  }'
```

## Deployment

### Building the Container

Use the build script to create and push the Docker image to ECR:

```bash
./deploy/build-container.sh agentic_rag
```

### Deploying to AgentCore

Deploy using the AgentCore infrastructure stack. See the [AgentCore Runtime Stack](../../../../infrastructure/stacks/agentcore-runtime/README.md) for instructions.

## Usage

Ask questions about topics covered in your knowledge base:

The agent will search your knowledge base and provide informed responses based on the retrieved content.
