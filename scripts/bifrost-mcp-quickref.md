# Bifrost + MCP Quick Reference

## Common Commands

### Port Forwards

```bash
# Bifrost UI
kubectl -n ai-gateway port-forward svc/bifrost 8080:8080 &

# Prometheus
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090 &

# Grafana
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80 &

# Kill all port-forwards
pkill -f "port-forward"
```

### Health Checks

```bash
# Bifrost health
curl -s http://localhost:8080/health | jq '.'

# MCP clients connected
curl -s http://localhost:8080/api/mcp/clients | jq '.clients[] | {name, state, tool_count: (.tools | length)}'

# Prometheus scrape status
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job == "prometheus/bifrost/0")'
```

### Pod Logs

```bash
# Bifrost
kubectl -n ai-gateway logs -f bifrost-0

# Socat proxy
kubectl -n ai-gateway logs -f deploy/mcp-kubernetes-proxy

# Prometheus MCP
kubectl -n monitoring logs -f deploy/prometheus-mcp

# With context
kubectl -n ai-gateway logs bifrost-0 --tail=50 --context kind-devops-lab
```

### Exec into Pods

```bash
# Bifrost
kubectl -n ai-gateway exec -it bifrost-0 -- sh

# Prometheus MCP
kubectl -n monitoring exec -it deploy/prometheus-mcp -- sh
```

## Verification Checklist

### After Fresh Install

```bash
# 1. Bifrost running
kubectl -n ai-gateway get pods bifrost-0

# 2. Socat proxy running
kubectl -n ai-gateway get pods -l app=mcp-kubernetes-proxy

# 3. Prometheus MCP running
kubectl -n monitoring get pods -l app=prometheus-mcp

# 4. MCP networking (from Bifrost pod)
kubectl -n ai-gateway exec bifrost-0 -- \
  wget -q -O- http://mcp-kubernetes-sse.ai-gateway.svc.cluster.local:8811/healthz

# 5. Both clients connected
curl -s http://localhost:8080/api/mcp/clients | jq '.clients | length'
# Should return: 2

# 6. Prometheus scraping Bifrost
curl -s "http://localhost:9090/api/v1/query?query=up{job=\"prometheus/bifrost/0\"}" | \
  jq '.data.result[0].value[1]'
# Should return: "1" (or close to 1)
```

## Troubleshooting

### Issue: MCP server fails to connect

**Symptom:** Bifrost UI shows MCP server as `disconnected`

**Debug:**
```bash
# Check if service exists
kubectl -n monitoring get svc prometheus-mcp

# Check pod logs
kubectl -n monitoring logs deploy/prometheus-mcp | grep -i error

# Verify connectivity from Bifrost
kubectl -n ai-gateway exec bifrost-0 -- \
  wget -v http://prometheus-mcp.monitoring.svc.cluster.local:8080/mcp
```

**Fix:**
- Ensure Prometheus MCP pod is `Running` and ready
- Check `--prometheus.url` flag points to correct Prometheus instance
- Verify `--mcp.transport http` is set (not `stdio`)

### Issue: Bifrost pod won't start

**Symptom:** `CrashLoopBackOff` or `CreateContainerConfigError`

**Debug:**
```bash
# Check pod events
kubectl -n ai-gateway describe pod bifrost-0

# Check logs
kubectl -n ai-gateway logs bifrost-0 --previous

# Check persistent volume
kubectl -n ai-gateway get pvc
```

**Fix:**
- If encryption key missing: `kubectl -n ai-gateway create secret generic bifrost-encryption-key --from-literal=encryption-key="$(openssl rand -base64 32)"`
- If PVC not bound: `kubectl -n ai-gateway delete pvc data-bifrost-0` and re-deploy

### Issue: socat proxy not reachable in-cluster

**Symptom:** Bifrost can't reach `mcp-kubernetes-sse` service

**Debug:**
```bash
# From Bifrost pod
kubectl -n ai-gateway exec bifrost-0 -- nslookup mcp-kubernetes-sse.ai-gateway.svc.cluster.local
kubectl -n ai-gateway exec bifrost-0 -- wget -v http://mcp-kubernetes-sse.ai-gateway.svc.cluster.local:8811/healthz

# Check socat proxy logs
kubectl -n ai-gateway logs deploy/mcp-kubernetes-proxy
```

**Fix:**
- Verify socat proxy deployment exists: `kubectl -n ai-gateway get deploy mcp-kubernetes-proxy`
- Verify service selector matches: `kubectl -n ai-gateway get svc mcp-kubernetes-sse -o yaml | grep selector`
- Restart proxy: `kubectl -n ai-gateway rollout restart deploy/mcp-kubernetes-proxy`

### Issue: Mac MCP server unreachable from kind

**Symptom:** In-cluster DNS resolves to socat proxy IP, but proxy can't reach `192.168.1.21:8811`

**Debug:**
```bash
# Check Mac MCP server is running
launchctl list com.local.mcp-kubernetes-sse

# From kind worker node (via docker)
docker exec <kind-container-id> \
  curl -v http://192.168.1.21:8811/healthz
```

**Fix:**
- Start Mac MCP server: `launchctl load -w ~/Library/LaunchAgents/com.local.mcp-kubernetes-sse.plist`
- Verify it's listening: `lsof -i :8811`
- Check firewall allows kind → Mac communication

### Issue: Prometheus not scraping Bifrost

**Symptom:** No `bifrost_*` metrics in Prometheus

**Debug:**
```bash
# Check ServiceMonitor exists
kubectl -n ai-gateway get servicemonitor bifrost

# Check Prometheus targets
curl -s http://localhost:9090/api/v1/targets | \
  jq '.data.activeTargets[] | select(.labels.job == "prometheus/bifrost/0")'

# Manual metric test
kubectl -n ai-gateway exec bifrost-0 -- \
  wget -q -O- http://localhost:8080/metrics | head -20
```

**Fix:**
- Ensure ServiceMonitor has correct labels and is in the right namespace
- Verify Prometheus instance can reach Bifrost service on port 8080
- Check Prometheus scrape interval (default 30s)

### Issue: Bifrost 500 errors on MCP tool calls

**Symptom:** Bifrost API returns 500 when invoking MCP tools

**Debug:**
```bash
# Check Bifrost logs around error time
kubectl -n ai-gateway logs bifrost-0 --tail=100 | grep -i error

# Check MCP client logs
kubectl -n monitoring logs deploy/prometheus-mcp | grep -i error

# Test tool directly via Bifrost API
curl -s -X POST http://localhost:8080/mcp \
  -H "X-Api-Key: <your-key>" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":1}' | jq '.'
```

**Fix:**
- Ensure MCP client is in `connected` state
- Verify tool is available: `curl -s http://localhost:8080/api/mcp/clients | jq '.clients[].tools[].name'`
- Check MCP server logs for tool execution errors

## Common MCP Queries

### Kubernetes MCP

```bash
# List available tools
curl -s http://localhost:8080/api/mcp/clients | \
  jq '.clients[] | select(.state == "connected") | .tools[] | .name'

# Call a tool via Bifrost API
curl -s -X POST http://localhost:8080/mcp \
  -H "X-Api-Key: <your-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "tools/call",
    "params": {
      "name": "new_kubernetes_local-pods_list_in_namespace",
      "arguments": {"namespace": "default"}
    },
    "id": 1
  }' | jq '.'
```

### Prometheus MCP

```bash
# Query Bifrost request rate
curl -s -X POST http://localhost:8080/mcp \
  -H "X-Api-Key: <your-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "tools/call",
    "params": {
      "name": "prometheus-query",
      "arguments": {
        "query": "rate(bifrost_gateway_requests_total[5m])"
      }
    },
    "id": 1
  }' | jq '.'
```

## Key Metrics

| Metric | Purpose |
|--------|---------|
| `bifrost_gateway_requests_total` | Total requests through Bifrost |
| `bifrost_gateway_request_duration_seconds` | Request latency histogram |
| `bifrost_mcp_client_connected` | MCP client connection status |
| `bifrost_container_last_seen` | Pod restart tracking |

## Files & Locations

| Item | Location |
|------|----------|
| Bifrost Helm values | `manifests/bifrost-values-dev.yaml` |
| ServiceMonitor | `manifests/bifrost-servicemonitor.yaml` |
| PrometheusRule | `manifests/bifrost-alerts.yaml` |
| Prometheus MCP manifest | `manifests/prometheus-mcp.yaml` |
| Install script | `scripts/install.sh` |
