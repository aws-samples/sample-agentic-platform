# Kubernetes Guide for AI Agents

This document provides context for AI agents modifying Kubernetes configurations.

## Critical Rules

**After ANY Helm chart change:**

```bash
# Validate chart
helm lint k8s/helm/charts/<chart-name>/

# Dry-run deployment
helm upgrade --install <release-name> ./k8s/helm/charts/<chart-name> \
  -f k8s/helm/values/applications/<values-file>.yaml \
  --dry-run
```

**After EVERY commit:**

```bash
gitleaks detect .
```

## Directory Structure

```
k8s/
└── helm/
    ├── charts/                    # Helm chart definitions
    │   ├── agentic-service/       # Generic chart for agents/services
    │   ├── litellm/               # LiteLLM gateway chart
    │   ├── mcp-server/            # MCP server chart
    │   └── otel/                  # OpenTelemetry collectors (deployed via Terraform)
    │
    └── values/
        ├── applications/          # Per-application value overrides
        │   ├── agentic-chat-values.yaml
        │   ├── jira-agent-values.yaml
        │   ├── memory-gateway-values.yaml
        │   ├── retrieval-gateway-values.yaml
        │   └── ...
        └── optional/              # Optional components
            └── langfuse-values.yaml
```

## Deployment Methods

### Method 1: Deploy Scripts (Agents & Services)

Most charts are deployed via `deploy/` scripts:

```bash
# Deploy single application
./deploy/deploy-application.sh <name> <type> [--build]

# Examples
./deploy/deploy-application.sh agentic-chat agent --build
./deploy/deploy-application.sh memory-gateway service

# Deploy all gateways
./deploy/deploy-gateways.sh --build
```

The script runs:
```bash
helm upgrade --install $SERVICE_NAME ./k8s/helm/charts/agentic-service \
  -f k8s/helm/values/applications/${SERVICE_NAME}-values.yaml
```

### Method 2: Terraform (OTEL Only)

The `otel` chart is deployed via the Kubernetes Terraform module:

```hcl
# infrastructure/modules/kubernetes/otel-collectors.tf
resource "helm_release" "otel_collectors" {
  name      = "otel-collectors"
  namespace = kubernetes_namespace.observability.metadata[0].name
  chart     = var.otel_chart_path  # Points to k8s/helm/charts/otel
  
  values = [...]
}
```

**Why Terraform for OTEL?**
- Deployed as infrastructure, not application
- Needs IRSA role from Terraform
- Must exist before applications deploy
- Lifecycle tied to cluster, not CI/CD

### Method 3: CI/CD Pipeline

GitHub Actions can deploy via the same scripts:

```yaml
# .github/workflows/deploy.yml
- run: ./deploy/deploy-application.sh agentic-chat agent
```

## Helm Charts

### agentic-service (Generic)

Used for all agents and gateway services. One chart, many value files.

**Key values:**
```yaml
namespace: "default"
replicaCount: 1

image:
  repository: "<account>.dkr.ecr.<region>.amazonaws.com/<name>"
  tag: latest

service:
  type: ClusterIP
  port: 80
  targetPort: 8080  # AgentCore interface

serviceAccount:
  name: ""
  create: true
  irsaConfigKey: "AGENT_ROLE_ARN"

resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    memory: 512Mi
```

### litellm

LLM Gateway (LiteLLM proxy).

**Deployed via:**
```bash
./deploy/deploy-litellm.sh
```

### mcp-server

MCP server deployments.

**Deployed via:**
```bash
./deploy/deploy-mcp-server.sh <name> [--build]
```

### otel

OpenTelemetry collectors for observability.

**Deployed via:** Terraform only (not scripts)

Located at `k8s/helm/charts/otel/`, referenced by:
```
infrastructure/modules/kubernetes/otel-collectors.tf
```

## Adding a New Application

### 1. Create Values File

Create `k8s/helm/values/applications/<name>-values.yaml`:

```yaml
namespace: "default"
replicaCount: 1

aws:
  region: "us-west-2"
  account: "123456789012"

image:
  repository: "123456789012.dkr.ecr.us-west-2.amazonaws.com/my-agent"
  tag: latest
  pullPolicy: Always

service:
  type: ClusterIP
  port: 80
  targetPort: 8080

serviceAccount:
  name: "my-agent-sa"
  create: true
  irsaConfigKey: "AGENT_ROLE_ARN"

resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    memory: 512Mi

env:
  - name: ENVIRONMENT
    value: "production"
  - name: LITELLM_API_ENDPOINT
    value: "http://litellm-gateway:4000"
```

### 2. Deploy

```bash
./deploy/deploy-application.sh my-agent agent --build
```

## Modifying Charts

### Adding a Template

Create in `k8s/helm/charts/<chart>/templates/`:

```yaml
# my-resource.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "chart.fullname" . }}-config
  namespace: {{ .Values.namespace | default .Release.Namespace }}
data:
  key: {{ .Values.configValue | quote }}
```

### Adding a Value

Add to `values.yaml`:
```yaml
configValue: "default"
```

Override in application values:
```yaml
configValue: "custom"
```

### Chart Helpers

Common helpers in `templates/_helpers.tpl`:

```yaml
{{- define "chart.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
```

## Deployment Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    Platform Bootstrap                        │
│         (Terraform deploys OTEL via helm_release)           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Gateway Services                          │
│    ./deploy/deploy-gateways.sh (memory, retrieval)          │
│    ./deploy/deploy-litellm.sh                               │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Agent Applications                        │
│    ./deploy/deploy-application.sh <agent> agent             │
│    (or via CI/CD pipeline)                                  │
└─────────────────────────────────────────────────────────────┘
```

## Common Operations

### Check Deployment Status

```bash
# List releases
helm list

# Check specific release
helm status <release-name>

# Get deployed values
helm get values <release-name>
```

### Rollback

```bash
# List history
helm history <release-name>

# Rollback to previous
helm rollback <release-name>

# Rollback to specific revision
helm rollback <release-name> <revision>
```

### Uninstall

```bash
helm uninstall <release-name>
```

### Debug

```bash
# Dry-run with debug
helm upgrade --install <name> ./k8s/helm/charts/<chart> \
  -f k8s/helm/values/applications/<values>.yaml \
  --dry-run --debug

# Template output only
helm template <name> ./k8s/helm/charts/<chart> \
  -f k8s/helm/values/applications/<values>.yaml
```

## IRSA (IAM Roles for Service Accounts)

Service accounts get IAM roles via IRSA:

```yaml
# In values file
serviceAccount:
  name: "my-service-sa"
  create: true
  irsaConfigKey: "AGENT_ROLE_ARN"  # Key in central config
```

The role ARN comes from Terraform outputs stored in a ConfigMap.

## Troubleshooting

### Pod Not Starting

```bash
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

### Service Not Accessible

```bash
kubectl get svc
kubectl get endpoints <service-name>
```

### Helm Release Failed

```bash
helm history <release-name>
helm get manifest <release-name>
kubectl get events --sort-by='.lastTimestamp'
```
