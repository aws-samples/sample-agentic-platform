# Strands Agent

This is a Strands-based agent implementation that integrates with the agentic platform. Strands is a modern agent framework that provides a clean, simple API for building agents with native LiteLLM integration.

## Features

- **Native LiteLLM Integration**: Routes through the platform's LiteLLM gateway
- **Simple API**: Clean, intuitive interface for agent interactions
- **Tool Integration**: Works with the platform's existing tool ecosystem
- **Memory Management**: Integrates with the platform's memory gateway
- **Kubernetes Ready**: Includes Docker and Helm configurations for EKS deployment

## Architecture

The Strands agent follows the same pattern as other platform agents:

- `strands_agent.py`: Core agent implementation with platform integration
- `strands_agent_controller.py`: Controller layer for request handling
- `server.py`: FastAPI server for HTTP endpoints
- `requirements.txt`: Python dependencies

## Testing

### Quick Test (No Setup Required)
```bash
# Run structural tests
python tests/strands_agent/test_strands_agent.py
```

### Comprehensive Testing
```bash
# Run all available tests
python tests/strands_agent/run_tests.py
```

### Notebook Examples
```bash
# Open the notebook with Strands examples
jupyter notebook labs/module3/notebooks/5_agent_frameworks.ipynb
# Navigate to the "Strands" section
```

See `tests/strands_agent/README.md` for complete testing and deployment documentation.

## Deployment

### Local Development

1. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

2. Run the server:
   ```bash
   python server.py
   ```

3. Test the API:
   ```bash
   python tests/strands_agent/test_strands_api.py
   ```

### EKS Deployment

1. Build and push the container:
   ```bash
   ./deploy/build-container.sh strands-agent
   ```

2. Deploy to Kubernetes:
   ```bash
   ./deploy/deploy-application.sh strands-agent
   ```

3. Test the deployed service:
   ```bash
   python tests/strands_agent/test_strands_api.py https://your-eks-cluster.com/strands-agent
   ```

## API Endpoints

- `POST /invoke`: Invoke the Strands agent with an AgenticRequest
- `GET /health`: Health check endpoint

## Configuration

The agent is configured through:
- Environment variables for gateway endpoints
- Helm values in `k8s/helm/values/applications/strands-agent-values.yaml`
- AWS IAM roles for service permissions

## Tools

The agent comes pre-configured with:
- Weather reporting tool
- Calculator tool  
- Retrieval tool

Additional tools can be added by modifying the `tools` list in `strands_agent_controller.py`.