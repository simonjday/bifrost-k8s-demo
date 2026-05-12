# Bifrost + MCP Setup — kind-devops-lab Rebuild

## Overview

This guide covers the complete installation and verification of Bifrost, MCP servers (Kubernetes + Prometheus), and observability for a fresh `kind-devops-lab` cluster rebuild.

## Prerequisites

- `kind` cluster running (`kind-devops-lab`)
- `kubectl` configured for the cluster
- Helm 3.x
- kube-prometheus-stack deployed (Prometheus + Grafana)
- MCP servers available:
  - Kubernetes MCP server running on Mac as LaunchAgent (port 8811)
  - Prometheus MCP server image: `ghcr.io/tjhop/prometheus-mcp-server:latest`

## Step 1: Deploy Bifrost

Use the fixed `install.sh` script. It handles:
- Helm repo setup
- Namespace creation
- Encryption key secret
- MCP networking (socat proxy for kind)
- Metrics Server
- Observability manifests (ServiceMonitor + PrometheusRule)

### Run the installer

```bash
./scripts/install.sh --apply --context kind-devops-lab
```

**Key fixes in this version:**
- `kubectl_cmd()` function replaces string variable to fix word-splitting in conditionals
- Proper context handling for all kubectl calls
- No more "cannot reuse a name" errors on retry

### Verify Bifrost is running

```bash
kubectl -n ai-gateway get pods -l app=bifrost
```

Expected: `bifrost-0` in `Running` state.

## Step 2: Create Observability Manifests

Bifrost install creates:
- `manifests/bifrost-servicemonitor.yaml` — Prometheus scrapes Bifrost metrics
- `manifests/bifrost-alerts.yaml` — PrometheusRule with alerting rules

### ServiceMonitor (CRITICAL FIX)

The ServiceMonitor selector **must match the Bifrost service labels**, not pod labels.

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: bifrost
  namespace: ai-gateway
  labels:
    app: bifrost
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: bifrost
  endpoints:
  - port: http
    interval: 15s
    path: /metrics
    scheme: http
```

**Key points:**
- Selector `app.kubernetes.io/name: bifrost` — matches the Bifrost **service** labels (not pod labels)
- Label `release: kube-prometheus-stack` — required by Prometheus operator's ServiceMonitorSelector
- Port `http` and path `/metrics` — must match actual service configuration

### Verify ServiceMonitor is discovered

```bash
kubectl -n monitoring logs kube-prometheus-stack-operator-7c5ddfb54f-9csvc --tail=20 | grep bifrost
# Should show: config=serviceMonitor/ai-gateway/bifrost/0

# Then check Prometheus targets
curl -s 'http://localhost:9090/api/v1/targets' | jq '.data.activeTargets[] | select(.labels.job=="bifrost") | .health'
# Should show: "up"
```

### PrometheusRule

Alerts configured:
- `BifrostHighErrorRate` — >5% 5xx for 5m
- `BifrostHighLatency` — p95 latency >1s for 5m
- `BifrostPodCrashing` — Pod restarts detected
- `BifrostMCPClientDisconnected` — No active MCP clients for 5m
- `BifrostMemoryUsageHigh` — >85% memory for 5m

## Step 3: Verify MCP Networking (In-Cluster)

The socat proxy allows Bifrost to reach the Mac MCP server via DNS.

### Test from Bifrost pod

```bash
kubectl -n ai-gateway exec bifrost-0 -- wget -v --timeout=5 \
  http://mcp-kubernetes-sse.ai-gateway.svc.cluster.local:8811/healthz
```

Expected output: `200 OK`.

## Step 4: Deploy Kubernetes MCP Server (Mac LaunchAgent)

The Kubernetes MCP server runs on the Mac as a LaunchAgent, making the local kubeconfig accessible to Bifrost via SSE.

### Install LaunchAgent (one-time)

```bash
cp scripts/com.local.mcp-kubernetes-sse.plist ~/Library/LaunchAgents/
launchctl load -w ~/Library/LaunchAgents/com.local.mcp-kubernetes-sse.plist
```

### Verify it's running

```bash
curl -v --max-time 5 http://localhost:8811/sse
```

Expected: `event: endpoint` stream.

## Step 5: Deploy Prometheus MCP Server

**CRITICAL:** Use supergateway as the entry point with proper `command`/`args` syntax. Do NOT use shell loops.

### Deploy

```bash
kubectl apply -f manifests/prometheus-mcp.yaml
```

Wait for rollout:

```bash
kubectl -n monitoring rollout status deploy/prometheus-mcp --timeout=60s
```

### Verify it's running

```bash
kubectl -n monitoring logs -l app=prometheus-mcp --tail=30 | grep "tool_count"
# Should show: msg="MCP server created" tool_count=28
```

## Step 6: Configure MCP Servers in Bifrost

Port-forward Bifrost:

```bash
kubectl -n ai-gateway port-forward svc/bifrost 8080:8080 &
```

Open http://localhost:8080 → **MCP** tab → **+ New MCP Server**.

### Kubernetes MCP Server

- **Name:** `kubernetes-local`
- **Type:** Server-Sent Events (SSE)
- **URL:** `http://192.168.1.21:8811/sse`

### Prometheus MCP Server

- **Name:** `prometheus`
- **Type:** HTTP (Streamable)
- **URL:** `http://prometheus-mcp.monitoring.svc.cluster.local:8080/mcp`

### Grant Virtual Key Permissions

Go to **Virtual Keys** → select your key → **Edit** → **MCP Servers**:
- Enable both `kubernetes-local` and `prometheus`
- Set **Allowed Tools:** `Allow All Tools`
- **Save**

### Refresh Key Permissions After Restart

After restarting Bifrost or Prometheus MCP, refresh the key permission cache:

1. Bifrost UI → **Virtual Keys** → your key
2. Toggle **Is this key active?** OFF → wait 3 seconds → ON
3. Verify:

```bash
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $YOUR_KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | \
  grep -o '"name":"prometheus' | wc -l
# Should return: 28
```

## Step 7: Verify Both MCP Servers Connected

```bash
curl -s http://localhost:8080/api/mcp/clients | jq '.clients[] | {state, tool_count: (.tools | length)}'
```

Expected:
```
{
  "state": "connected",
  "tool_count": 20
}
{
  "state": "connected",
  "tool_count": 28
}
```

## Step 8: Test MCP Tool Calls

### Kubernetes query

```bash
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $YOUR_KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"new_kubernetes_local-namespaces_list","arguments":{}}}' | \
  jq '.result.content[0].text' | head -c 200
```

### Prometheus query

```bash
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $YOUR_KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"prometheus-query","arguments":{"query":"bifrost_success_requests_total"}}}' | \
  jq '.result.content[0].text' | head -c 200
```

## Step 9: Generate Traffic (Optional, for Bifrost Metrics)

```bash
bash scripts/bifrost-sim.sh 50
sleep 30  # Wait for Prometheus to scrape
```

Then Bifrost metric queries will return data.

## Files

| File | Purpose |
|---|---|
| `scripts/install.sh` | Bifrost + observability installer |
| `manifests/bifrost-servicemonitor.yaml` | Prometheus scrape config (corrected selector) |
| `manifests/bifrost-alerts.yaml` | PrometheusRule alerts |
| `manifests/prometheus-mcp.yaml` | Prometheus MCP server deployment |
| `scripts/com.local.mcp-kubernetes-sse.plist` | Kubernetes MCP server LaunchAgent |

## Troubleshooting

| Issue | Solution |
|---|---|
| `helm install bifrost ... Error: cannot reuse a name` | Run `helm uninstall bifrost -n ai-gateway` first |
| Prometheus MCP `listen tcp :8080: bind: address already in use` | Check manifest args syntax; use proper `command: ["node"]` entry point |
| Tools show 0 in tools/list after restart | Toggle virtual key active OFF/ON to refresh permission cache |
| Prometheus not scraping Bifrost | Check ServiceMonitor selector matches service labels (`app.kubernetes.io/name: bifrost`). Check label `release: kube-prometheus-stack` |
| Bifrost metrics not in Prometheus | Verify `/metrics` endpoint works: `kubectl -n ai-gateway exec bifrost-0 -- wget -qO- http://localhost:8080/metrics \| head` |

## Next Steps

1. Add LLM providers — Bifrost UI → Providers tab
2. Create scoped virtual keys — Bifrost UI → Keys tab
3. Build Grafana dashboards with Bifrost metrics
4. Test with agents (Goose, Claude Code)
