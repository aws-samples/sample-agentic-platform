# Data Platform Agent

This simple agent helps a user discover and query data. The agent can find tables in the Glue catalog and query them using Athena.

## Deployment

Run:

```
./deploy/deploy-application.sh strands-glue-athena --build
```

Then give the role `agent-ptfm-agent-role` permission to access the Glue catalog and Athena.

## Prerequisites

You should have some tables already created in the Glue catalog.

## Usage

Here's an example query:

```
Please tell me about any tables related to call centers
```