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

### ServiceMonitor

Targets `bifrost` service in `ai-gateway`, scrapes port `http` (8080) every 15s, auto-discovered by kube-prometheus-stack via `release: prometheus` label.

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

**CRITICAL:** Use supergateway as the entry point with proper `command`/`args` syntax. Do NOT use shell loops or direct binary invocation.

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
kubectl -n monitoring logs -l app=prometheus-mcp --tail=30
```

Expected output (no port bind errors):
```
msg="MCP server created" prometheus_url=http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090 tool_count=28
msg="server session connected"
msg="session initialized"
```

**Troubleshooting port conflict:**
- If you see `listen tcp :8080: bind: address already in use`, verify the manifest:
  1. Uses `command: ["node"]` entry point (not shell script)
  2. Has proper args array formatting
  3. Includes `--web.listen-address=:0` (tells Prometheus to use random port)

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

Go to **Virtual Keys** → select your key → **Edit** → **MCP Servers** section:
- Enable both `kubernetes-local` and `prometheus`
- Set **Allowed Tools:** `Allow All Tools`
- **Save**

### Refresh Key Permissions (Important!)

After restarting Bifrost or Prometheus MCP, the key permission cache becomes stale:

1. Bifrost UI → **Virtual Keys** → your key
2. Toggle **Is this key active?** OFF → wait 3 seconds → ON
3. Verify tools:

```bash
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $YOUR_KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | \
  grep -o '"name":"prometheus' | wc -l
```

Expected: `28` (Prometheus tools).

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
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"prometheus-query","arguments":{"query":"up"}}}' | \
  jq '.result.content[0].text' | head -c 200
```

## Step 9: Generate Traffic (Optional, for Bifrost Metrics)

```bash
bash scripts/bifrost-sim.sh 50
sleep 30  # Wait for Prometheus to scrape
```

Then test Bifrost metrics:

```bash
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $YOUR_KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"prometheus-query","arguments":{"query":"bifrost_gateway_requests_total"}}}' | \
  jq '.result.content[0].text' | head -c 200
```

## Files

| File | Purpose |
|---|---|
| `scripts/install.sh` | Bifrost + observability installer |
| `manifests/bifrost-servicemonitor.yaml` | Prometheus scrape config |
| `manifests/bifrost-alerts.yaml` | PrometheusRule alerts |
| `manifests/prometheus-mcp.yaml` | Prometheus MCP server (supergateway-wrapped) |

## Known Issues & Fixes

| Issue | Fix |
|---|---|
| `helm install bifrost ... Error: cannot reuse a name` | `helm uninstall bifrost -n ai-gateway` first |
| Prometheus MCP `bind: address already in use` | Use proper `command: ["node"]` with correct args array (no shell loop) |
| prometheus tools return 0 after Bifrost restart | Toggle virtual key active OFF/ON to refresh cache |
| Kubernetes tools timeout | Verify LaunchAgent: `curl http://localhost:8811/sse` |
| Prometheus query empty result | Verify metric exists in Prometheus UI: `http://localhost:9090` |

## Next Steps

1. Add LLM providers — Bifrost UI → Providers tab
2. Create scoped virtual keys — Bifrost UI → Keys tab
3. Build Grafana dashboards with Bifrost metrics
4. Test with agents (Goose, Claude Code)
