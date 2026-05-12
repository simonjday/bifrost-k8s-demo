# Observability: Prometheus + Grafana + Bifrost Metrics

Complete setup for monitoring Bifrost metrics in Prometheus and visualizing in Grafana.

## Architecture

```
Bifrost Pod (10.244.1.21:8080)
  ↓ /metrics endpoint
Prometheus ServiceMonitor (ai-gateway/bifrost)
  ↓ Scrape every 15s
Prometheus (monitoring/prometheus)
  ↓ Query & store
Grafana (monitoring/grafana)
  ↓ Dashboards & alerts
```

## Prerequisites

- kube-prometheus-stack deployed in `monitoring` namespace
- Bifrost deployed in `ai-gateway` namespace with running metrics endpoint

## Step 1: Verify Bifrost Metrics Endpoint

```bash
kubectl -n ai-gateway exec bifrost-0 -- wget -qO- http://localhost:8080/metrics | head -20
```

Expected: Metrics like `bifrost_success_requests_total`, `bifrost_error_requests_total`, etc.

## Step 2: Create ServiceMonitor

**CRITICAL:** The selector must match **service labels**, not pod labels.

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

Apply:

```bash
kubectl apply -f manifests/bifrost-servicemonitor.yaml
```

## Step 3: Verify Prometheus Discovers Target

ServiceMonitor is discovered automatically by the Prometheus operator.

### Check operator logs for ServiceMonitor reconciliation

```bash
kubectl -n monitoring logs -l app.kubernetes.io/name=kube-prometheus-stack-operator --tail=20 | grep bifrost
```

Expected: `config=serviceMonitor/ai-gateway/bifrost/0`

### Check Prometheus active targets

```bash
curl -s 'http://localhost:9090/api/v1/targets' | \
  jq '.data.activeTargets[] | select(.labels.job=="bifrost")'
```

Expected:
```json
{
  "discoveredLabels": {
    "__address__": "10.244.1.21:8080",
    "__meta_kubernetes_service_name": "bifrost",
    "__metrics_path__": "/metrics",
    ...
  },
  "labels": {
    "instance": "10.244.1.21:8080",
    "job": "bifrost",
    "namespace": "ai-gateway",
    "pod": "bifrost-0",
    "service": "bifrost"
  },
  "scrapeUrl": "http://10.244.1.21:8080/metrics",
  "health": "up",
  ...
}
```

**Key fields:**
- `"health": "up"` — Prometheus is successfully scraping
- `"instance": "10.244.1.21:8080"` — Pod IP + metrics port
- `"job": "bifrost"` — ServiceMonitor name

### If target not appearing, restart Prometheus

```bash
kubectl -n monitoring delete pod prometheus-kube-prometheus-stack-prometheus-0
kubectl -n monitoring rollout status statefulset prometheus-kube-prometheus-stack-prometheus --timeout=60s
```

Wait 30s, then recheck targets.

## Step 4: Query Bifrost Metrics in Prometheus

Port-forward Prometheus:

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090 &
```

Open http://localhost:9090 → **Graph** tab.

### Query examples

**Success rate (%):**
```promql
(rate(bifrost_success_requests_total[5m]) / 
  (rate(bifrost_success_requests_total[5m]) + 
   rate(bifrost_error_requests_total[5m]))) * 100
```

**Error rate by status code:**
```promql
rate(bifrost_error_requests_total[5m]) by (status_code)
```

**Tokens per second:**
```promql
rate(bifrost_input_tokens_total[1m]) + rate(bifrost_output_tokens_total[1m])
```

**Top models by request count:**
```promql
topk(5, rate(bifrost_success_requests_total[5m])) by (model)
```

## Step 5: Build Grafana Dashboard

Port-forward Grafana:

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80 &
# Default: admin / prom-operator
```

### Add Prometheus Data Source

1. **Configuration** → **Data Sources** → **Add data source**
2. **Prometheus**
3. **URL:** `http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090`
4. **Save & Test**

### Create Dashboard

1. **+ Create** → **Dashboard**
2. Add panels for success rate, error rates, tokens/sec, model usage

## Step 6: Create PrometheusRule (Alerts)

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: bifrost-alerts
  namespace: ai-gateway
  labels:
    release: kube-prometheus-stack
spec:
  groups:
  - name: bifrost.rules
    interval: 30s
    rules:
    - alert: BifrostHighErrorRate
      expr: |
        (rate(bifrost_error_requests_total[5m]) / 
         (rate(bifrost_success_requests_total[5m]) + rate(bifrost_error_requests_total[5m]))) > 0.05
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Bifrost error rate >5%"

    - alert: BifrostMCPClientDisconnected
      expr: bifrost_mcp_clients_connected == 0
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "No MCP clients connected to Bifrost"
```

Apply:

```bash
kubectl apply -f manifests/bifrost-alerts.yaml
```

## Troubleshooting

### ServiceMonitor discovered but no active targets

**Cause:** ServiceMonitor selector doesn't match Bifrost service labels.

Bifrost service has Helm-standard labels like `app.kubernetes.io/name: bifrost`, not `app: bifrost`.

**Fix:** Verify and update ServiceMonitor selector:
```bash
# Check service labels
kubectl -n ai-gateway get svc bifrost --show-labels

# Update selector to match (use provided manifests/bifrost-servicemonitor.yaml)
kubectl apply -f manifests/bifrost-servicemonitor.yaml

# Restart Prometheus to force reload
kubectl -n monitoring delete pod prometheus-kube-prometheus-stack-prometheus-0
sleep 30

# Verify target is up
curl -s 'http://localhost:9090/api/v1/targets' | jq '.data.activeTargets[] | select(.labels.job=="bifrost") | .health'
# Expected: "up"
```

### Prometheus operator not discovering ServiceMonitor

**Check:** ServiceMonitor must have label `release: kube-prometheus-stack` to match Prometheus operator's ServiceMonitorSelector.

```bash
# Verify label
kubectl -n ai-gateway get servicemonitor bifrost -o yaml | grep -A 2 "labels:"
# Should show: release: kube-prometheus-stack
```

### Bifrost metrics returning zero results

**Cause:** Prometheus hasn't scraped new metrics yet, or Bifrost isn't receiving traffic.

**Fix:** 
1. Generate traffic: `bash scripts/bifrost-sim.sh 50`
2. Wait 30 seconds for Prometheus to scrape
3. Query again: `curl -s 'http://localhost:9090/api/v1/query?query=bifrost_success_requests_total'`

