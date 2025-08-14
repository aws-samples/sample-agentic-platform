# Module 4: Advanced Agent Features

## Overview
This module explores advanced agent capabilities through Model Context Protocol (MCP), multi-agent systems, and secure code execution. You'll learn how to combine different agent frameworks, create specialized tool servers, build interoperable AI systems that can collaborate effectively, and leverage AWS Bedrock AgentCore for secure code interpretation.

## Learning Objectives

* Create and deploy MCP-compatible tool servers
* Connect agents to multiple MCP servers simultaneously
* Mix and match different agent frameworks (PydanticAI, LangChain, etc.)
* Build collaborative multi-agent systems
* Integrate third-party MCP servers into your applications
* Use AWS Bedrock AgentCore Code Interpreter for secure code execution
* Perform data processing and file operations in sandboxed environments

## Prerequisites

- Completed Module 1 (Agentic Basics)
- Completed Module 2 (Workflow Agents)
- Completed Module 3 (Autonomous Agents)
- Python 3.10+
- AWS Bedrock access
- Basic understanding of async programming

## Notebooks

### 4_agentcore_tool_code_interpreter.ipynb
Learn how to use AWS Bedrock AgentCore Code Interpreter for secure code execution:
- Set up and configure AgentCore Code Interpreter with boto3
- Execute Python and JavaScript code in secure sandboxes
- Perform statistical calculations and data analysis
- Handle file operations (read, write, process)
- Process large files up to 100MB inline or 5GB via S3

## Installation

```bash
# Install dependencies from parent directory. 
uv sync 

# Navigate to module 4
cd labs/module4
```
