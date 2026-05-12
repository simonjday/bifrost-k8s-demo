# Bifrost + MCP + Observability Stack — Deployment Status

**Last Updated:** 2026-05-12 11:54 UTC  
**Cluster:** kind-devops-lab (kind v0.20+)  
**Status:** ✅ FULLY OPERATIONAL

---

## Component Status Summary

| Component | Status | Version | Namespace | Verified |
|-----------|--------|---------|-----------|----------|
| **Bifrost** | ✅ Running | v1.5.0 | ai-gateway | bifrost-0 pod healthy |
| **Kubernetes MCP** | ✅ Running | LaunchAgent | Mac local | Port 8811 responding |
| **Prometheus MCP** | ✅ Running | v0.18.0 | monitoring | 28 tools available |
| **kube-prometheus-stack** | ✅ Running | Latest | monitoring | Prometheus + Grafana + Alertmanager |
| **Prometheus ServiceMonitor** | ✅ Fixed | N/A | ai-gateway | Selector corrected, target UP |
| **Bifrost Metrics Scraping** | ✅ Working | N/A | N/A | 6 metric series in Prometheus |

---

## Bifrost (ai-gateway namespace)

### Deployment

```bash
kubectl -n ai-gateway get statefulset bifrost -o wide
# NAME      READY   AGE     IMAGE
# bifrost   1/1     3h16m   docker.io/maximhq/bifrost:v1.5.0
```

### Pod Status

```bash
kubectl -n ai-gateway get pods -l app=bifrost
# NAME        READY   STATUS    RESTARTS   AGE
# bifrost-0   1/1     Running   1          3h15m
```

**Pod metrics:**
- Resources: 500m CPU request, 512Mi mem request (limits: 2 CPU, 2Gi mem)
- Readiness: ✓ Healthy (HTTP GET /health)
- Liveness: ✓ Healthy (HTTP GET /health)

### Endpoints

```bash
kubectl -n ai-gateway get svc bifrost -o wide
# NAME      TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    
# bifrost   ClusterIP   10.97.64.147   <none>        8080/TCP
```

**Service selector:** `app.kubernetes.io/instance=bifrost` (Helm labels)

### Metrics Endpoint

```
GET http://bifrost-0:8080/metrics (in-cluster)
     ↓ (returns Prometheus format)
# HELP bifrost_success_requests_total Total successful requests...
# TYPE bifrost_success_requests_total counter
bifrost_success_requests_total{...model="qwen2.5:7b",...} 16
```

---

## MCP Servers

### Kubernetes MCP (Mac LaunchAgent)

```bash
# Service: mcp-kubernetes-sse in ai-gateway (socat proxy)
# LaunchAgent: com.local.mcp-kubernetes-sse
# Port: 8811

curl -s http://localhost:8811/sse | head
# event: endpoint
# data: {"version":"0.4","capabilities":{"...
```

**Tools available:** 20 (k8s operations, pods/nodes/events/logs)

**Bifrost registration:**
- Type: Server-Sent Events (SSE)
- URL: `http://192.168.1.21:8811/sse` (Mac LAN IP)
- Status: ✓ Connected

### Prometheus MCP Server (in-cluster)

```bash
kubectl -n monitoring get deploy prometheus-mcp -o wide
# NAME             READY   IMAGE
# prometheus-mcp   1/1     ghcr.io/supercorp-ai/supergateway:latest
```

**Deployment:**
- Image: supergateway (node entry point)
- Init container: copies Prometheus MCP binary to shared emptyDir
- Transport: streamableHttp (stateless, no session initialization)
- Port: 8080 (HTTP /mcp endpoint)

**Tools available:** 28 (Prometheus query operations)

**Bifrost registration:**
- Type: HTTP (Streamable)
- URL: `http://prometheus-mcp.monitoring.svc.cluster.local:8080/mcp`
- Status: ✓ Connected

### MCP Client Status in Bifrost

```bash
curl -s http://localhost:8080/api/mcp/clients | jq '.clients[] | {state, tool_count: (.tools | length)}'
# {
#   "state": "connected",
#   "tool_count": 20
# }
# {
#   "state": "connected",
#   "tool_count": 28
# }
# Total: 48 tools available
```

---

## Prometheus & Observability (monitoring namespace)

### Prometheus Instance

```bash
kubectl -n monitoring get statefulset prometheus-kube-prometheus-stack-prometheus
# NAME                                      READY   AGE
# prometheus-kube-prometheus-stack-prometheus   1/1     3h38m
```

**Configuration:**
- `serviceMonitorSelector.matchLabels.release: kube-prometheus-stack` ← required for Bifrost discovery

### Active Scrape Targets

```bash
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length'
# 11 (kubernetes, node-exporter, prometheus, bifrost, etc.)
```

**Bifrost target status:**
```
{
  "labels": {
    "instance": "10.244.1.21:8080",
    "job": "bifrost",
    "namespace": "ai-gateway",
    "pod": "bifrost-0",
    "service": "bifrost"
  },
  "scrapeUrl": "http://10.244.1.21:8080/metrics",
  "health": "up",
  "lastScrape": "2026-05-12T11:54:16.350023041Z",
  "scrapeInterval": "15s"
}
```

### Bifrost Metrics Available

All metrics scraped every 15 seconds:

```promql
# Success requests by model
bifrost_success_requests_total{model="qwen2.5:7b",...}
# ↓ 6 total series

# Error requests by status code
bifrost_error_requests_total{status_code="401",...}
# ↓ X series

# Token usage
bifrost_input_tokens_total{model="llama3.2:3b",...} = 72709
bifrost_output_tokens_total{model="qwen2.5-coder:7b",...} = 1082
```

### Grafana

```bash
kubectl -n monitoring get deploy kube-prometheus-stack-grafana
# NAME                             READY
# kube-prometheus-stack-grafana    3/3
```

**Access:**
- Local: http://localhost:3000 (via port-forward)
- Credentials: admin / prom-operator
- Data source: Prometheus (monitoring/prometheus)

---

## Bifrost API Gateway — Virtual Keys & Access Control

### Admin Key

```
sk-bf-d6373a91-f86b-42fd-8ecc-4a61aac010c2
```

**Permissions:**
- All 48 MCP tools
- All LLM models
- Full Kubernetes + Prometheus access

**Usage:**
```bash
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "X-Api-Key: sk-bf-..." \
  -d '{"model":"qwen2.5:7b","messages":[...]}'
```

### Restricted Key

```
sk-bf-78daabea-6191-4b2c-afd9-7bef84b066ea
```

**Permissions:**
- 7 read-only Kubernetes tools
- Ollama model: llama3.2:3b only
- No Prometheus access

---

## Network Configuration

### From Mac (Local)

| Service | Address | Port | Protocol |
|---------|---------|------|----------|
| Bifrost | localhost | 8080 | HTTP |
| Prometheus | localhost | 9090 | HTTP |
| Grafana | localhost | 3000 | HTTP |
| Kubernetes MCP | 192.168.1.21 | 8811 | SSE |
| Ollama | 192.168.1.21 | 11434 | HTTP |
| Docker Desktop gateway | 192.168.65.254 | 11434 | HTTP (for kind containers) |

### From inside kind cluster

| Service | Address | Port | Protocol |
|---------|---------|------|----------|
| Bifrost | bifrost.ai-gateway | 8080 | HTTP |
| Prometheus | kube-prometheus-stack-prometheus.monitoring | 9090 | HTTP |
| Prometheus MCP | prometheus-mcp.monitoring | 8080 | HTTP (/mcp) |
| Kubernetes API | kubernetes.default | 443 | HTTPS |

---

## Postman Collection Status

**File:** `bifrost-k8s-mcp_postman_collection.json`

### Request Folders

| Folder | Status | Notes |
|--------|--------|-------|
| 🔌 Bifrost — MCP Server Management | ✓ Working | List/add/edit MCP servers |
| 🔑 Bifrost — Virtual Keys | ✓ Working | Create/list/delete keys |
| 📊 Kubernetes — Namespace & Nodes | ✓ Working | List namespaces, node metrics |
| 📦 Kubernetes — Pod Operations | ✓ Working | Get pods, tail logs, execute commands |
| 📈 Prometheus — Infrastructure | ✓ Working | Targets, targets health, build info |
| 🔮 Bifrost — Gateway Metrics | ✓ Working | Success/error rates, token counts, model usage |

**All visualization scripts:** ✓ Fixed and working (single-string format for exec arrays)

---

## Known Issues & Resolutions (This Session)

| Issue | Root Cause | Resolution | Status |
|-------|-----------|-----------|--------|
| Prometheus not scraping Bifrost | ServiceMonitor selector mismatch | Updated selector to `app.kubernetes.io/name: bifrost` | ✅ FIXED |
| ServiceMonitor target: "No active targets" | Selector looked for `app: bifrost` in service | Service has Helm labels like `app.kubernetes.io/name`, not `app` | ✅ FIXED |
| Bifrost metrics empty in Prometheus | Prometheus hadn't scraped yet or selector was wrong | Both fixed: selector + restart Prometheus pod | ✅ FIXED |

---

## Quick Verification Commands

```bash
# 1. All pods running?
kubectl get pods --all-namespaces | grep -E "bifrost|prometheus|grafana" | grep -v Completed

# 2. Bifrost metrics endpoint working?
kubectl -n ai-gateway exec bifrost-0 -- wget -qO- http://localhost:8080/metrics | head -3

# 3. Prometheus scraping Bifrost?
curl -s http://localhost:9090/api/v1/query?query=bifrost_success_requests_total | jq '.data.result | length'
# Returns: 6 (or higher with more traffic)

# 4. MCP servers connected?
curl -s http://localhost:8080/api/mcp/clients | jq '.clients | length'
# Returns: 2

# 5. Can execute MCP tools?
curl -s -X POST http://localhost:8080/mcp \
  -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | \
  jq '.result.tools | length'
# Returns: 48
```

---

## Next Steps

1. **Grafana Dashboards:** Build panels using Bifrost metrics
2. **PrometheusRules:** Configure alerting (high error rate, disconnected clients)
3. **Traffic Generation:** Run `bifrost-sim.sh` for realistic metrics
4. **Agent Integration:** Test with Goose/Claude Code MCP extensions
5. **Production Hardening:** Add resource limits, backup, disaster recovery

---

## Files & Documentation

| File | Purpose |
|------|---------|
| `manifests/bifrost-servicemonitor.yaml` | ✓ Corrected ServiceMonitor |
| `manifests/prometheus-mcp.yaml` | ✓ Prometheus MCP deployment |
| `docs/prometheus-grafana-bifrost.md` | ✓ Updated troubleshooting guide |
| `bifrost-mcp-rebuild-guide.md` | ✓ Complete setup walkthrough |
| `README.md` | ✓ Known Gotchas updated |
| `SESSION_RECAP_2026-05-12-...` | ✓ This session's fixes |

---

**Generated:** 2026-05-12  
**Validated By:** Simon Day (Accenture Platform Engineering)  
**Next Review:** After Postman collection testing
