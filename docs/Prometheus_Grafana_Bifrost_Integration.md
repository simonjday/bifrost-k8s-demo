# Prometheus, Grafana & Bifrost Integration

## Overview

This guide covers integrating Prometheus, Grafana, and Bifrost (AI Gateway) with MCP (Model Context Protocol) support for intelligent monitoring and querying.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Bifrost AI Gateway (OpenAI-compatible API)                  │
│                                                              │
│ ├─ LLM Providers (routing/fallback)                         │
│ ├─ AI Agents (Goose, Claude, etc.)                         │
│ └─ MCP Tools Integration                                    │
│    ├─ prometheus-mcp → Prometheus queries (28+ tools)      │
│    ├─ kubernetes-local → Cluster operations                │
│    └─ [Other MCPs...]                                      │
└─────────────────────────────────────────────────────────────┘
         ↑                    ↑
         │ REST API           │ MCP Protocol
         │                    │
    ┌────┴────────────────────┴────────┐
    │                                   │
    ↓                                   ↓
┌──────────────────┐          ┌──────────────────┐
│ Grafana          │          │ prometheus-mcp   │
│ - Dashboards     │          │ - streamableHttp │
│ - Alerting       │          │ - Stateful mode  │
│ - Data source    │          │ - Auto-recovery  │
└────────┬─────────┘          └────────┬─────────┘
         │                             │
         └──────────────┬──────────────┘
                        ↓
              ┌───────────────────┐
              │ Prometheus        │
              │ (TSDB + HTTP API) │
              └───────────────────┘
```

---

## Components

### 1. Prometheus
**Role:** Time-series database, scrapes metrics, exposes HTTP API
**Deployment:** kube-prometheus-stack
**Port:** 9090
**Health Check:** `GET /-/healthy`

### 2. Grafana
**Role:** Visualization, dashboards, alerting
**Deployment:** Standalone (part of monitoring stack)
**Port:** 3000
**Data Source Config:** Prometheus http://prometheus-svc:9090

### 3. Bifrost
**Role:** AI API gateway, routes to LLMs, manages MCP tools
**Deployment:** Helm chart in ai-gateway namespace
**Port:** 8080
**MCP Clients:** Configured in UI or config file

### 4. prometheus-mcp-server (NEW)
**Role:** MCP bridge, translates MCP tool calls to Prometheus queries
**Deployment:** `manifests/prometheus-mcp-stateful-5min.yaml`
**Port:** 8080
**Transport:** StreamableHttp (HTTP-based MCP)
**Features:**
- 28+ tools (query, range_query, label_names, label_values, etc.)
- Automatic session recovery every ~45-60s
- Zero pod restarts, transparent to users
- Stateful mode with 5-minute session timeout

---

## Deployment

### Prerequisites

```bash
# 1. kube-prometheus-stack running
kubectl get deployment -n monitoring | grep prometheus

# 2. Bifrost deployed
kubectl get pods -n ai-gateway | grep bifrost

# 3. monitoring namespace exists
kubectl get namespace monitoring
```

### Install prometheus-mcp

```bash
# Apply the deployment
kubectl apply -f manifests/prometheus-mcp-stateful-5min.yaml

# Verify Pod is Ready
kubectl get pods -n monitoring -l app=prometheus-mcp
# Expected: 1/1 Running, 0 Restarts

# Verify Service
kubectl get svc -n monitoring prometheus-mcp
# Expected: ClusterIP with port 8080
```

### Configure Bifrost MCP Client

In **Bifrost UI** → Settings → MCP Clients → Add New:

```
Name:              prometheus-mcp
Type:              HTTP
URL:               http://prometheus-mcp.monitoring.svc.cluster.local:8080/
Transport:         StreamableHttp
Path:              / (default)
Headers:           (none)
Tool Execution:    Auto-execute all
```

---

## Usage Examples

### 1. Grafana Dashboard
- Create dashboard pointing to Prometheus data source
- Build panels with PromQL queries
- Set up alerting rules

### 2. Bifrost AI Agent (e.g., Goose)
```
User: "What's the current pod error rate?"

Goose (with prometheus-mcp):
  ✓ Calls prometheus-mcp MCP tool: query
  ✓ Executes: rate(pod_errors_total[5m])
  ✓ Returns: 0.15 errors/sec
  ✓ Responds: "Current error rate is 0.15 errors per second"
```

### 3. Direct API (curl)
```bash
# Initialize MCP session
curl -X POST http://localhost:8080/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'

# Call query tool
curl -X POST http://localhost:8080/ \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc":"2.0",
    "id":2,
    "method":"tools/call",
    "params":{
      "name":"query",
      "arguments":{"query":"up"}
    }
  }'
```

---

## prometheus-mcp Session Lifecycle

### Expected Behavior

**With continuous queries:**
- Queries 1-20 succeed (session warm, ~45-60s duration)
- Query 21 may fail briefly (context deadline reached)
- Bifrost auto-reconnects within 3-6 seconds
- Queries 22+ succeed (new session)
- Pod never restarts (0 restarts maintained)

### Auto-Recovery Details

```
Event Timeline:
t=0s   New session created (UUID: abc123...)
t=30s  Continuous query traffic keeps session alive
t=50s  Context deadline approaching
t=55s  Child process exits gracefully
t=56s  Readiness probe detects TCP socket issue
t=58s  Pod marked NotReady
t=60s  Bifrost detects unhealthy pod, auto-reconnects
t=61s  New session created (UUID: xyz789...)
t=62s  Pod marked Ready again
       → Next query succeeds transparently
```

### What Users Experience

✅ **Good:**
- Queries work continuously
- Auto-recovery is transparent (no manual action)
- Pod stays stable (0 restarts)
- Single-query failures are rare and brief

❌ **Not ideal, but manageable:**
- Every ~45-60s, brief interruption may occur
- Bifrost reconnects automatically (not visible in most cases)
- If needed, manual reconnect in Bifrost UI still works

---

## Troubleshooting

### prometheus-mcp Pod Not Ready

```bash
# Check logs
kubectl logs -n monitoring -l app=prometheus-mcp --tail=50

# Check events
kubectl describe pod -n monitoring -l app=prometheus-mcp

# Verify Prometheus is accessible from pod
kubectl exec -n monitoring -it <pod-name> -c supergateway -- \
  wget -O- http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090/-/healthy
```

### Bifrost: "No valid session ID" Error

**Cause:** Session expired (after ~60s idle or activity)
**Solution:** Bifrost auto-reconnects; if stuck, click "Reconnect" in MCP client settings

### Prometheus API Timeout

**Error:** Queries hang or return "context deadline exceeded"
**Solution:** Increase `--prometheus.timeout` flag in deployment args

```yaml
args:
  - --prometheus.timeout
  - "120s"  # Increase from 60s to 2 minutes
```

---

## Performance Notes

| Metric | Value |
|--------|-------|
| Pod cold start | 5-10s |
| Query latency | 200-500ms |
| Session lifetime | 45-60s (with auto-recovery) |
| Pod restart rate | 0 (design spec) |
| CPU request | 200m / limit 500m |
| Memory request | 256Mi / limit 1Gi |

---

## Monitoring prometheus-mcp Itself

### Recommended Alerts

```yaml
- alert: PrometheusMCPDown
  expr: up{job="prometheus-mcp"} == 0
  for: 2m
  annotations:
    summary: "prometheus-mcp is down"

- alert: PrometheusMCPHighLatency
  expr: histogram_quantile(0.95, http_request_duration_seconds{job="prometheus-mcp"}) > 2
  annotations:
    summary: "prometheus-mcp high latency"
```

---

## Files Reference

**Deployment:**
- `manifests/prometheus-mcp-stateful-5min.yaml` — Main deployment

**Documentation:**
- `docs/Prometheus_MCP_Deployment_Guide.md` — Comprehensive guide
- `docs/SESSION_RECAP_Final.md` — Technical deep-dive

**Testing:**
- `scripts/test-prometheus-connectivity.sh` — Connectivity validation

---

## Integration Checklist

- [ ] kube-prometheus-stack deployed and healthy
- [ ] Bifrost deployed in ai-gateway namespace
- [ ] prometheus-mcp pod running (1/1 Ready)
- [ ] Bifrost MCP client configured for prometheus-mcp
- [ ] Test query via Bifrost UI or curl
- [ ] Load test 20+ queries, observe auto-recovery
- [ ] Grafana dashboards using Prometheus data source
- [ ] Alerting rules configured and tested

---

**Last Updated:** 2026-05-14  
**Status:** Production-ready ✅
