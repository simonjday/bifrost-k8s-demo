# Session Recap: Bifrost Prometheus Scraping — FIXED

**Date:** 2026-05-12  
**Cluster:** kind-devops-lab  
**Component:** Bifrost (v1.5.0) → Prometheus (monitoring)  

---

## Problem Statement

Bifrost `/metrics` endpoint was working, but Prometheus ServiceMonitor showed **"No active targets in this scrape pool"** despite being discovered.

---

## Root Cause Analysis

The ServiceMonitor selector was trying to match **pod labels** when it should match **service labels**.

**Service actual labels** (from `kubectl -n ai-gateway get svc bifrost --show-labels`):
```
app.kubernetes.io/instance=bifrost
app.kubernetes.io/managed-by=Helm
app.kubernetes.io/name=bifrost        ← THE MATCHING LABEL
app.kubernetes.io/version=1.5.0
helm.sh/chart=bifrost-2.1.15
```

**Broken selector:** `app: bifrost` (didn't exist in service)  
**Fixed selector:** `app.kubernetes.io/name: bifrost` (matches service)

---

## Fix Applied

### 1. Updated ServiceMonitor (`manifests/bifrost-servicemonitor.yaml`)

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: bifrost
  namespace: ai-gateway
  labels:
    app: bifrost
    release: kube-prometheus-stack  ← CRITICAL: Prometheus operator requires this
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: bifrost  ← MATCHES SERVICE LABELS
  endpoints:
  - port: http
    interval: 15s
    path: /metrics
    scheme: http
```

**Key requirements:**
- `release: kube-prometheus-stack` — ServiceMonitor label for Prometheus operator discovery
- `selector.matchLabels.app.kubernetes.io/name: bifrost` — matches service, not pods

### 2. Restart Prometheus to Force Reload

```bash
kubectl -n monitoring delete pod prometheus-kube-prometheus-stack-prometheus-0
```

---

## Verification Steps

### Step 1: Confirm Service Endpoints

```bash
% kubectl -n ai-gateway get endpoints bifrost
NAME      ENDPOINTS          AGE
bifrost   10.244.1.21:8080   3h15m
```

✓ Service has endpoints (pod is selected)

### Step 2: Verify Bifrost `/metrics` Endpoint

```bash
% kubectl -n ai-gateway exec bifrost-0 -- wget -qO- http://localhost:8080/metrics | head -5
# HELP bifrost_error_requests_total Total number of error requests...
# TYPE bifrost_error_requests_total counter
bifrost_error_requests_total{alias="",customer_id="",...status_code="401",...} 2
```

✓ `/metrics` endpoint working with real data

### Step 3: Check Prometheus Targets

```bash
% curl -s 'http://localhost:9090/api/v1/targets' | \
    jq '.data.activeTargets[] | select(.labels.job=="bifrost") | .health'
"up"
```

✓ Target is **UP** and being scraped

### Step 4: Query Bifrost Metrics

```bash
% curl -s 'http://localhost:9090/api/v1/query?query=bifrost_success_requests_total' | \
    jq '.data.result | length'
6
```

✓ **6 metric series** returned (real data from Bifrost)

### Step 5: Test via Postman

Postman collection MCP calls using `prometheus-query` tool:
- Infrastructure queries: ✓ Working
- Bifrost gateway metrics: ✓ Working (now returns data)

---

## Files Updated

| File | Changes |
|---|---|
| `manifests/bifrost-servicemonitor.yaml` | Selector fixed: `app.kubernetes.io/name: bifrost` |
| `docs/prometheus-grafana-bifrost.md` | Enhanced troubleshooting section with complete fix steps |
| `bifrost-mcp-rebuild-guide.md` | Added ServiceMonitor requirements (selector + labels) |
| `README.md` | Added Known Gotchas entries for ServiceMonitor debugging |

---

## Available Bifrost Metrics in Prometheus

All confirmed working and scraping every 15 seconds:

- `bifrost_success_requests_total` — successful API calls
- `bifrost_error_requests_total` — failed API calls
- `bifrost_input_tokens_total` — input tokens forwarded to providers
- `bifrost_output_tokens_total` — output tokens from providers

**Query examples:**
```promql
# Error rate
rate(bifrost_error_requests_total[5m]) / (rate(bifrost_success_requests_total[5m]) + rate(bifrost_error_requests_total[5m]))

# Tokens per second
rate(bifrost_input_tokens_total[1m]) + rate(bifrost_output_tokens_total[1m])

# Top models
topk(5, rate(bifrost_success_requests_total[5m])) by (model)
```

---

## Key Learnings

1. **ServiceMonitor selector matches services, not pods**  
   - ServiceMonitor discovers services via `selector.matchLabels`
   - Those matched services must have endpoints (pods)
   - Selector must match **service labels**, not pod labels

2. **Prometheus operator ServiceMonitorSelector**  
   - Prometheus CRD has `serviceMonitorSelector: {matchLabels: {release: kube-prometheus-stack}}`
   - Every ServiceMonitor must have `label release: kube-prometheus-stack`
   - Without this label, Prometheus operator ignores the ServiceMonitor

3. **Debugging flow**  
   - Check Prometheus logs: `kubectl -n monitoring logs prometheus-... --tail=50 | grep bifrost`
   - Verify Prometheus targets: `curl http://localhost:9090/api/v1/targets`
   - If target exists but `health: down`, check `/metrics` endpoint directly from pod
   - If target missing, check ServiceMonitor labels and selector

---

## Status: ✓ COMPLETE

- Bifrost metrics scraping in Prometheus: **✓ Working**
- All 4 Bifrost metric types available: **✓ Verified**
- Postman collection queries functional: **✓ Ready to test**
- Documentation updated: **✓ Complete**

Ready for Grafana dashboard builds and alerting rule configuration.
