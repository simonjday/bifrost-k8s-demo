# Grafana MCP Server — Deployment & Demo Guide

## Overview

The official Grafana MCP server (`grafana/mcp-grafana`) is maintained by Grafana Labs and is the best choice. It provides access to dashboards, datasources, alerts, panels, and can execute PromQL/LogQL queries directly through Grafana.

**Key advantage over Prometheus MCP**: Grafana MCP understands your *dashboards* — it can query specific panels, find existing visualizations, and generate deep links. It's the higher-level observability interface while Prometheus MCP is the raw query engine.

Your Grafana is already running in the cluster: `kube-prometheus-stack-grafana.monitoring`

------

## Architecture

```
Claude Desktop (stdio)
    │
    ▼
npx mcp-grafana (or Docker)
    │ GRAFANA_URL=http://localhost:3000
    │ GRAFANA_API_KEY=<service-account-token>
    ▼
kubectl port-forward → grafana pod :3000
    │
    ▼
kube-prometheus-stack-grafana (monitoring namespace)
    └── Datasource: Prometheus → prometheus pod :9090
```

------

## Setup

### 1. Port-forward Grafana

```bash
kubectl --context kind-devops-lab port-forward \
  -n monitoring \
  svc/kube-prometheus-stack-grafana 3000:80 &

# Verify — default credentials are admin/prom-operator
curl -s http://localhost:3000/api/health | jq .
```

### 2. Create a Grafana Service Account

```bash
# Get the Grafana admin password
kubectl --context kind-devops-lab get secret \
  kube-prometheus-stack-grafana \
  -n monitoring \
  -o jsonpath='{.data.admin-password}' | base64 -d && echo

# Create a service account via API
curl -s -X POST http://localhost:3000/api/serviceaccounts \
  -H "Content-Type: application/json" \
  -u admin:<password> \
  -d '{"name":"mcp-server","role":"Viewer"}' | jq .

# Note the service account ID from the response, then create a token
SA_ID=<id-from-above>
curl -s -X POST http://localhost:3000/api/serviceaccounts/$SA_ID/tokens \
  -H "Content-Type: application/json" \
  -u admin:<password> \
  -d '{"name":"mcp-token"}' | jq .key

# Save the token — starts with glsa_
export GRAFANA_API_KEY=glsa_xxxxxxxxxxxx
```

### 3. Update claude_desktop_config.json

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
      "args": ["run", "-i", "--rm", "-e", "PROMETHEUS_URL",
               "--network", "host",
               "ghcr.io/pab1it0/prometheus-mcp-server:latest"],
      "env": { "PROMETHEUS_URL": "http://localhost:9090" }
    },
    "grafana": {
      "command": "npx",
      "args": ["-y", "@grafana/mcp-grafana@latest"],
      "env": {
        "GRAFANA_URL": "http://localhost:3000",
        "GRAFANA_API_KEY": "<your-glsa-token>"
      }
    }
  }
}
```

### 4. Restart Claude Desktop

```bash
osascript -e 'quit app "Claude"'
sleep 3
open -a Claude
```

### 5. Verify

Ask Claude: "List all dashboards in my Grafana instance" — you should see the kube-prometheus-stack dashboards like "Kubernetes / Compute Resources / Cluster".

------

## Part 2 — Bifrost SSE Setup (in-cluster)

For in-cluster access from Bifrost, run the Grafana MCP server as a Deployment in the monitoring namespace — it can reach Grafana directly without port-forwarding.

```yaml
# manifests/grafana-mcp-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana-mcp
  namespace: monitoring
  labels:
    app: grafana-mcp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: grafana-mcp
  template:
    metadata:
      labels:
        app: grafana-mcp
    spec:
      containers:
      - name: grafana-mcp
        image: ghcr.io/grafana/mcp-grafana:latest
        args:
        - --transport=sse
        - --disable-oncall         # not installed in this demo
        - --disable-incident       # not installed in this demo
        env:
        - name: GRAFANA_URL
          value: "http://kube-prometheus-stack-grafana.monitoring"
        - name: GRAFANA_API_KEY
          valueFrom:
            secretKeyRef:
              name: grafana-mcp-token
              key: token
        ports:
        - containerPort: 3000
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
  name: grafana-mcp
  namespace: monitoring
spec:
  selector:
    app: grafana-mcp
  ports:
  - name: sse
    port: 3000
    targetPort: 3000
```

Create the secret first:

```bash
kubectl --context kind-devops-lab create secret generic grafana-mcp-token \
  -n monitoring \
  --from-literal=token=$GRAFANA_API_KEY
```

------

## Tools Available

| Category        | Tools                                                        |
| --------------- | ------------------------------------------------------------ |
| **Dashboards**  | `search_dashboards`, `get_dashboard_by_uid`, `get_dashboard_summary` |
| **Panels**      | `get_dashboard_panels`, `run_panel_query`, `get_panel_image` |
| **Datasources** | `list_datasources`, `query_prometheus`, `query_loki`         |
| **Alerts**      | `list_alert_rules`, `get_alert_rule`, `list_alert_instances` |
| **Navigation**  | `generate_deeplink` (opens specific views in Grafana UI)     |

------

## Demo Prompts

### Dashboard Discovery

```
List all dashboards in Grafana and tell me which ones are related to Kubernetes
Find the Kubernetes cluster overview dashboard and summarise what panels it contains
Which Grafana datasources are configured and are they all healthy?
```

### Panel Queries

```
Run the CPU usage query from the Kubernetes compute resources dashboard
and tell me which namespace is using the most CPU right now
Find the guestbook-related panels in any dashboard and show me the current
request rate and error rate
Execute the memory usage panel query for the monitoring namespace and tell
me if anything looks abnormal
```

### Alerting

```
Are there any Grafana alert rules currently firing? Show me the name,
severity, labels, and how long they have been active
List all alert rules configured in Grafana — which ones are in error state
vs normal vs pending?
Show me the notification policies in Grafana — where do alerts get routed?
```

### Cross-tool Observability (Grafana + Prometheus + Kubernetes)

```
Full observability check on the guestbook app:
1. Check pod status and restart count in Kubernetes
2. Query the apache_up and apache_accesses_total metrics in Prometheus
3. Find and run the relevant Grafana dashboard panel queries
Give me a health summary
An alert fired 10 minutes ago for high memory usage. Use Grafana to find
the relevant dashboard, query Prometheus for the memory trend, and check
Kubernetes for any OOMKilled events in that timeframe
Generate a Grafana deeplink to the Kubernetes pods dashboard filtered to
the ai-gateway namespace so I can share it with my team
```

### Demo Scenarios

```
I'm about to do a live demo. Give me a full cluster health check:
Prometheus alerts, Grafana dashboard status, pod health, and resource usage —
all in a single summary
Walk me through what observability data is available for this cluster —
what dashboards exist, what metrics are collected, and what alerts are configured
```

------

## Gotchas

- **Both port-forwards needed for stdio** — Grafana (`3000`) AND Prometheus (`9090`) must be forwarded. Grafana queries Prometheus via its datasource, so both need to be reachable.
- **Service account role** — `Viewer` is sufficient for all read operations. Only needed for creating/updating dashboards or alert rules.
- **Disable unused tool categories** — `--disable-oncall` and `--disable-incident` reduce context window usage since those tools won't be available in your kube-prometheus-stack install.
- **`get_panel_image` requires Grafana Image Renderer** — not installed in the default kube-prometheus-stack. Skip this tool or the call will fail.
- **Token in config file** — never commit `claude_desktop_config.json` to git since it contains the Grafana API key. Add it to `.gitignore`.
- **Restart after kind cluster restart** — same as all other MCP servers, re-apply port-forwards and restart Claude Desktop.

------

## Full Startup Runbook (all 4 MCP servers)

Add to your startup script or run manually after cluster start:

```bash
#!/usr/bin/env bash
# startup.sh — port-forward all services needed for MCP servers

CTX="--context kind-devops-lab"
NS_MONITORING="-n monitoring"
NS_ARGOCD="-n argocd"
NS_AIGATEWAY="-n ai-gateway"

# Bifrost
kubectl $CTX port-forward $NS_AIGATEWAY svc/bifrost 8080:8080 &

# Prometheus (for Prometheus MCP)
kubectl $CTX port-forward $NS_MONITORING svc/kube-prometheus-stack-prometheus 9090:9090 &

# Grafana (for Grafana MCP)
kubectl $CTX port-forward $NS_MONITORING svc/kube-prometheus-stack-grafana 3000:80 &

# Argo CD (for Argo CD MCP) — HTTP port 80 → localhost:9080
kubectl $CTX port-forward $NS_ARGOCD svc/argocd-server 9080:80 &

sleep 3
echo "Port-forwards active:"
echo "  Bifrost:    http://localhost:8080"
echo "  Prometheus: http://localhost:9090"
echo "  Grafana:    http://localhost:3000"
echo "  Argo CD:    http://localhost:9080"
chmod +x scripts/startup.sh
./scripts/startup.sh
```