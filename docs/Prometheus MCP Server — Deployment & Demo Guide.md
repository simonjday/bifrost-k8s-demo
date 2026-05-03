# Prometheus MCP Server — Deployment & Demo Guide

## Overview

Two strong Prometheus MCP server options exist. Use `pab1it0/prometheus-mcp-server`
for simplicity — it runs via Docker, needs only a Prometheus URL, and has no
extra dependencies.

|Server                           |Language|Notes                                           |
|---------------------------------|--------|------------------------------------------------|
|**pab1it0/prometheus-mcp-server**|Python  |✅ Simple, Docker-based, no auth needed for local|
|tjhop/prometheus-mcp-server      |Go      |More tools, configurable toolsets, Helm chart   |

Your Prometheus is already running in the cluster at:
`http://prometheus-kube-prometheus-stack-prometheus.monitoring:9090`

-----

## Architecture

```
Claude Desktop (stdio)
    │
    ▼
Docker: ghcr.io/pab1it0/prometheus-mcp-server
    │ PROMETHEUS_URL=http://localhost:9090
    ▼
kubectl port-forward → prometheus pod :9090
    │
    ▼
prometheus-kube-prometheus-stack-prometheus-0 (monitoring namespace)
```

The Prometheus pod must be port-forwarded to localhost:9090 for the
Mac-side MCP server to reach it. Add this to your startup runbook.

-----

## Setup

### 1. Port-forward Prometheus

```bash
kubectl --context kind-devops-lab port-forward \
  -n monitoring \
  svc/kube-prometheus-stack-prometheus 9090:9090 &

# Verify
curl -s http://localhost:9090/-/healthy && echo "Prometheus: OK"
```

### 2. Update claude_desktop_config.json

```json
{
  "mcpServers": {
    "kubernetes-local": {
      "command": "npx",
      "args": ["-y", "kubernetes-mcp-server@latest"]
    },
    "github": {
      "command": "docker",
      "args": ["run", "-i", "--rm", "-e", "GITHUB_PERSONAL_ACCESS_TOKEN",
               "ghcr.io/github/github-mcp-server"],
      "env": { "GITHUB_PERSONAL_ACCESS_TOKEN": "<your-pat>" }
    },
    "prometheus": {
      "command": "docker",
      "args": [
        "run", "-i", "--rm",
        "-e", "PROMETHEUS_URL",
        "--network", "host",
        "ghcr.io/pab1it0/prometheus-mcp-server:latest"
      ],
      "env": {
        "PROMETHEUS_URL": "http://localhost:9090"
      }
    }
  }
}
```

Note: `--network host` is required so the Docker container can reach
`localhost:9090` on your Mac where the port-forward is running.

### 3. Restart Claude Desktop

```bash
osascript -e 'quit app "Claude"'
sleep 3
open -a Claude
```

### 4. Verify

Ask Claude: “Query Prometheus for the list of all available metric names” —
you should get a list of metrics like `kube_pod_status_phase`,
`container_cpu_usage_seconds_total`, etc.

-----

## Part 2 — Bifrost SSE Setup (in-cluster access)

For Bifrost, the Prometheus MCP server can run inside the cluster directly,
with no port-forward needed — Prometheus is already accessible at its
in-cluster DNS name.

### In-cluster Deployment

```yaml
# manifests/prometheus-mcp-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus-mcp
  namespace: monitoring
  labels:
    app: prometheus-mcp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prometheus-mcp
  template:
    metadata:
      labels:
        app: prometheus-mcp
    spec:
      containers:
      - name: prometheus-mcp
        image: ghcr.io/pab1it0/prometheus-mcp-server:latest
        env:
        - name: PROMETHEUS_URL
          value: "http://kube-prometheus-stack-prometheus.monitoring:9090"
        ports:
        - containerPort: 8000
          name: sse
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus-mcp
  namespace: monitoring
spec:
  selector:
    app: prometheus-mcp
  ports:
  - name: sse
    port: 8000
    targetPort: 8000
```

Then expose via socat proxy in ai-gateway namespace (same pattern as
mcp-kubernetes-proxy) and register in Bifrost UI.

-----

## Tools Available

|Tool                 |Description                     |
|---------------------|--------------------------------|
|`execute_query`      |Run instant PromQL query        |
|`execute_range_query`|Run range query over time window|
|`list_metrics`       |Discover all metric names       |
|`get_metric_metadata`|Get type/help for a metric      |
|`list_labels`        |List all label names            |
|`get_label_values`   |Get values for a specific label |
|`query_exemplars`    |Fetch exemplars for a metric    |

-----

## Demo Prompts

### Infrastructure Health

```
What is the current CPU usage across all pods in the kind-devops-lab cluster?
Show me the top 5 by CPU consumption
```

```
Show me memory usage trends for the ai-gateway namespace over the last hour
```

```
Are there any pods that have been restarting frequently in the last 30 minutes?
Query the restart count metrics
```

### Application Metrics

```
Query Prometheus for guestbook HTTP request rates and error rates over the
last 15 minutes — is the app healthy?
```

```
Show me the apache_workers metrics for the guestbook app — how many workers
are busy vs idle?
```

```
What is the p99 latency for all HTTP requests in the apps namespace?
```

### Alerting & SLOs

```
Are there any Prometheus alerts currently firing? Show me the alert name,
severity, and how long they've been active
```

```
Which metrics have the highest cardinality in this cluster? This could indicate
label explosion issues
```

```
Create a PromQL query that would tell me if the guestbook app has had more
than 1% error rate in the last 5 minutes — then run it
```

### Capacity Planning

```
Show me node CPU and memory utilisation trends over the last hour — are
we close to any resource limits?
```

```
Which namespace is consuming the most memory right now?
```

```
Query etcd metrics — what's the current database size and are there any
performance concerns?
```

### Multi-tool (Prometheus + Kubernetes)

```
Cross-reference: find any pods that are showing high CPU in Prometheus
but have no CPU limits set in Kubernetes
```

```
The load-generator pod is using 14m CPU — query Prometheus for its actual
request rate and error rate to understand if that usage is justified
```

```
Correlate: check if the guestbook pod restart events in Kubernetes line up
with any spikes in the Prometheus metrics around the same time
```

-----

## Gotchas

- **Port-forward required for stdio mode** — Prometheus must be accessible at
  `localhost:9090`. Add to your startup runbook alongside the Bifrost port-forward.
- **`--network host` in Docker config** — required so the container can reach
  the Mac’s localhost port-forward. Without it, connection refused.
- **Prometheus scrape interval** — metrics are only as fresh as the last scrape
  (default 30s in kube-prometheus-stack). Very recent events may not appear.
- **PromQL knowledge not required** — the MCP server will generate and execute
  PromQL from natural language. You don’t need to know PromQL syntax.
- **Restart Claude Desktop after kind cluster restart** — like all MCP servers,
  the Docker container caches the connection at startup.