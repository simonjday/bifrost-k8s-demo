# Query Your Kubernetes Cluster and LLM Metrics from a Single MCP Interface

This guide documents a reference architecture for connecting [Bifrost](https://github.com/maximhq/bifrost) — an open-source AI gateway — to both a Kubernetes cluster and a Prometheus observability stack through the Model Context Protocol (MCP).

## What We Are Building

The integration connects three systems:

- **Bifrost** running inside a [kind](https://kind.sigs.k8s.io/) cluster, acting as an AI gateway
- **Two MCP servers** registered with Bifrost — Kubernetes (20 tools) + Prometheus (28 tools)
- **kube-prometheus-stack** scraping Bifrost's own `/metrics` endpoint for LLM usage metrics

The result is a single interface (Postman collection) with 48 tools for cluster management and metrics queries.

## Prerequisites

- [kind](https://kind.sigs.k8s.io/) installed locally
- [Helm](https://helm.sh/) for installing kube-prometheus-stack
- [Bifrost](https://github.com/maximhq/bifrost) deployed into the cluster
- kubectl configured for the kind cluster
- Postman desktop app (for the collection and visualizations)

---

## Architecture Overview

### MCP Server Registration

| Server Name | Connection Type | URL |
|---|---|---|
| `new_kubernetes_local` | Server-Sent Events (SSE) | `http://192.168.1.21:8811/sse` |
| `prometheus` | HTTP (Streamable) | `http://prometheus-mcp.monitoring.svc.cluster.local:8080/mcp` |

---

## Part 1 — Kubernetes MCP Server Setup

The kubernetes MCP server runs on the host Mac as a LaunchAgent. See the rebuild guide for setup details.

---

## Part 2 — Prometheus MCP Server Setup

The prometheus MCP server runs inside the cluster. The `prometheus-mcp-server` binary only supports stdio transport, so [supergateway](https://github.com/supercorp-ai/supergateway) wraps it as a streamable HTTP endpoint.

### Why Streamable HTTP

The streamable HTTP transport is stateless — no MCP session initialization handshake. This is critical because Bifrost does not send `notifications/initialized` before making tool calls.

### Deployment (Corrected Approach)

**CRITICAL:** Use supergateway as the entry point with proper `command`/`args` syntax. Do NOT use shell loops.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus-mcp
  namespace: monitoring
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
      initContainers:
      - name: copy-binary
        image: ghcr.io/tjhop/prometheus-mcp-server:latest
        command: ["cp", "/bin/prometheus-mcp-server", "/shared/prometheus-mcp-server"]
        volumeMounts:
        - name: shared
          mountPath: /shared
      containers:
      - name: supergateway
        image: ghcr.io/supercorp-ai/supergateway:latest
        command: ["node"]
        args:
          - --
          - /usr/local/lib/node_modules/supergateway/dist/index.js
          - --stdio
          - /shared/prometheus-mcp-server --prometheus.url=http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090 --web.listen-address=:0
          - --outputTransport
          - streamableHttp
          - --port
          - "8080"
        ports:
        - containerPort: 8080
          name: http
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        volumeMounts:
        - name: shared
          mountPath: /shared
      volumes:
      - name: shared
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus-mcp
  namespace: monitoring
spec:
  type: ClusterIP
  ports:
  - name: http
    port: 8080
    targetPort: 8080
  selector:
    app: prometheus-mcp
```

### Key Design Decisions

**Proper entry point:** Use `command: ["node"]` to invoke supergateway as the container entry point. This ensures args are passed as an array, not a shell string.

**Correct args structure:** The args array must be proper YAML array format. This is NOT a shell string.

**`--web.listen-address=:0`:** Assigns a random available port on startup, eliminating conflicts.

**No shell loops:** Stateless streamableHttp avoids connection state loss. There is no persistent session to lose.

### Verify

```bash
# Check pod is running (no port conflicts)
kubectl -n monitoring logs -l app=prometheus-mcp --tail=20 | grep "tool_count"
# Should show: msg="MCP server created" tool_count=28

# Verify endpoint is reachable
kubectl -n ai-gateway exec bifrost-0 -- \
  wget -qO- http://prometheus-mcp.monitoring.svc.cluster.local:8080/mcp --timeout=3 2>&1 | head -3
```

### Add to Bifrost

In the Bifrost UI, go to **MCP → New MCP Server**:

| Field | Value |
|---|---|
| Name | `prometheus` |
| Connection Type | HTTP (Streamable) |
| URL | `http://prometheus-mcp.monitoring.svc.cluster.local:8080/mcp` |

### Grant Virtual Key Permissions

Go to **Virtual Keys** → select your key → **Edit** → **MCP Servers**:
- Enable `prometheus`
- Set **Allowed Tools:** `Allow All Tools`
- **Save**

### Refresh Key Permissions After Restart

After restarting Bifrost or Prometheus MCP:

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

---

## Part 3 — Prometheus Observability Setup

### ServiceMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: bifrost
  namespace: ai-gateway
  labels:
    app: bifrost
    release: prometheus
spec:
  selector:
    matchLabels:
      app: bifrost
  endpoints:
  - port: http
    interval: 15s
    path: /metrics
    scheme: http
```

Key points:
- Label `release: prometheus` ensures kube-prometheus-stack discovers it
- Port `http` (8080)
- 15s scrape interval

---

## Part 4 — Testing with Postman

A complete Postman collection is included with 48+ requests and visualizations.

### Import

1. Open Postman
2. **Import** → `bifrost-k8s-mcp_postman_collection.json`
3. Set collection variables:
   - `BF`: `http://localhost:8080/mcp`
   - `ADMIN_KEY`: Your admin key from Bifrost UI
   - `RESTRICTED_KEY`: Your restricted key

### Generate Traffic

```bash
bash scripts/bifrost-sim.sh 50
sleep 30
```

Then run the `🔮 Bifrost — Gateway Metrics` folder in Postman.

---

## Troubleshooting

| Issue | Fix |
|---|---|
| `listen tcp :8080: bind: address already in use` | Verify `command: ["node"]` and proper args array (not shell string) |
| prometheus tools show 0 in tools/list | Toggle key active OFF/ON to refresh cache |
| Prometheus query returns empty | Verify metric exists: `curl http://localhost:9090/api/v1/query?query=up` |
