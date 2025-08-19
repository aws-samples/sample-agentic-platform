# Agentic Platform
A modular repository demonstrating how to build an agentic platform including labs and a deployable sample "agentic platform" to demonstrate how to operationalize agents from multiple open source frameworks as well as Bedrock agents.

## Project status
This sample is active

# Architecture
## High Level Architecture
![High Level Architecture](media/highlevel-architecture.png)

The sample platform is built on EKS and uses a variety of AWS services to deploy 10+ agentic systems demonstrating how everything works together. It's instrumented with telemetry and demonstrates operational considerations when deploying agents. Code is written in an abstracted/modular way to make it easy to switch the underlying infrastructure components to suit your needs.

## Agent Process Architecture
![Agent Process Architecture](media/agent-design.png)
Each agent runs as a FastAPI server sharing a core package which contains types and client abstractions (like LLM API provider). APIs are authenticated using Cognito through a middleware layer that's simple to swap out for your own IDP. 

The agents themselves do not have IAM roles attached to them. Instead they connect to AWS resources through microservices like the LLM Gateway, Memory Gateway, and Retrieval Gateway (which do have IAM roles through IRSA). Those requests are authenticated by passing JWT tokens between each request. Each pod running in EKS is authenticated using oAuth regardless of whether the request was service <> service or user <> service by validating tokens against the IDP's public cert.

Lastly, telemetry information is collected using open telemetry collectors and pushed to X-Ray for traces, Cloudwatch for metrics, and OpenSearch for logs. An agent uses the observability facade (in the common package) which is pre-configured to send to our open telemetry endpoints. The OTEL collectors then push the telemetry data to any endpoint that supports open telemetry protocol (OTLP). This makes it easy to switch vendors or different services. Anything that supports OTLP will work.

# Getting Started

## Quick Start
1. Clone this repository
2. Follow the deployment guide in [DEPLOYMENT.md](DEPLOYMENT.md) to set up the infrastructure
3. Explore the hands-on labs in the `labs/` directory

## Labs
There are 5 progressive modules that increase in complexity, going from the basics to operational considerations when running an agent platform at scale:

1. **Module 1**: Prompt Engineering & Evaluation
2. **Module 2**: Common Agentic Patterns  
3. **Module 3**: Building Agentic Applications
4. **Module 4**: Advanced Agentic Concepts: Multi-Agent, MCP, AgentCore Tools
5. **Module 5**: Deployment and Infrastructure

Only module 5 requires the agent platform to be deployed. See [labs/README.md](labs/README.md) for detailed lab instructions.

To run labs locally:
```bash
# Install dependencies
uv sync 

# Start Jupyter Lab
uv run jupyter lab
```

# Deployment

**Important Notice:** This project deploys resources in your AWS environment using Terraform. You will incur costs for the AWS resources used.

For complete deployment instructions, see [DEPLOYMENT.md](DEPLOYMENT.md). We provide both:
- **Automated bootstrap** (recommended): Uses CloudFormation templates to set up everything automatically
- **Manual deployment**: Step-by-step instructions for custom deployments

## Security
Make sure to run security scans if making changes to the code:
* [Checkov](https://www.checkov.io/2.Basics/Installing%20Checkov.html)
* [Bandit](https://bandit.readthedocs.io/en/latest/)
* [Gitleaks](https://github.com/gitleaks/gitleaks)

**Suppressed Warnings**: There are warnings suppressed in the codebase. Review these prior to using any code in your environment.

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## Contributing
We are open to contributions and this project is actively being worked on. Items on our roadmap include:
1. Making deployment easier through a bootstrap terraform module
2. Cleaning up deployments with a more structured approach to GitOps
3. Adding additional labs on more advanced agent topics
4. Building a test harness & eval suite that runs against the code base
5. Adding more agent examples from the labs into the sample platform

## Authors and acknowledgment
* Tanner McRae
* Randy DeFauw
* James Levine

## License

This library is licensed under the MIT-0 License. See the LICENSE file.
