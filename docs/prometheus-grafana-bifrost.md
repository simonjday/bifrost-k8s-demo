# Prometheus & Grafana — Bifrost Metrics Setup

How Bifrost metrics are scraped by Prometheus and visualised in Grafana in the `kind-devops-lab` cluster. Covers the ServiceMonitor, verifying scraping is working, and importing the two provided Grafana dashboards.

---

## Architecture

```
Bifrost StatefulSet (ai-gateway)
  └── /metrics endpoint on port 8080 (http)
        └── ServiceMonitor (monitoring/bifrost)
              └── Prometheus (kube-prometheus-stack)
                    ├── PrometheusRule (monitoring/bifrost-alerts) → Alertmanager
                    └── Grafana datasource → Grafana dashboards
```

Prometheus is deployed via the `kube-prometheus-stack` Helm chart in the `monitoring` namespace. Bifrost exposes a Prometheus-compatible `/metrics` endpoint on its existing `http` port (8080). A `ServiceMonitor` resource tells Prometheus where to scrape.

---

## Prerequisites

- `kube-prometheus-stack` installed in the `monitoring` namespace (already present in this cluster, Helm release `kube-prometheus-stack`)
- Bifrost StatefulSet running in `ai-gateway` namespace — see [README.md](../README.md) for setup
- `kubectl` context set to `kind-devops-lab`

---

## Step 1 — Apply the ServiceMonitor

The ServiceMonitor lives in the `monitoring` namespace (where Prometheus can discover it via its `release: kube-prometheus-stack` label selector) and targets the `ai-gateway` namespace.

```yaml
# manifests/bifrost-servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: bifrost
  namespace: monitoring
  labels:
    release: kube-prometheus-stack      # must match Prometheus operator label selector
spec:
  namespaceSelector:
    matchNames:
      - ai-gateway
  selector:
    matchLabels:
      app.kubernetes.io/instance: bifrost
      app.kubernetes.io/name: bifrost
  endpoints:
    - port: http
      path: /metrics
      interval: 15s
```

Apply it:

```bash
kubectl apply -f manifests/bifrost-servicemonitor.yaml
```

> **Note:** This ServiceMonitor is already applied in the cluster (created 2026-05-07). If you're rebuilding the cluster from scratch, run the apply command above.

---

## Step 2 — Verify Prometheus is scraping Bifrost

Port-forward Prometheus:

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
```

Then check the targets page at `http://localhost:9090/targets` — look for a `bifrost` job with state `UP`.

Or check via the API:

```bash
curl -s http://localhost:9090/api/v1/targets | python3 -c "
import json, sys
d = json.load(sys.stdin)
targets = [t for t in d['data']['activeTargets'] if 'bifrost' in str(t.get('labels', {}))]
for t in targets:
    print('job:', t['labels'].get('job'), '| health:', t['health'], '| endpoint:', t['scrapeUrl'])
"
```

Expected output:
```
job: bifrost | health: up | endpoint: http://10.x.x.x:8080/metrics
```

Spot-check a metric is present:

```bash
curl -s http://localhost:9090/api/v1/query?query=bifrost_upstream_requests_total \
  | python3 -m json.tool | head -30
```

---

## Step 3 — Port-forward Grafana

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

Open `http://localhost:3000`. Default credentials are `admin` / `prom-operator` (set during kube-prometheus-stack install).

---

## Step 4 — Verify the Prometheus datasource

In Grafana → **Connections → Data sources** → confirm a datasource named `prometheus` exists and its UID is `prometheus`. Both dashboard JSONs reference `uid: "prometheus"` — if your datasource UID differs, update the `datasource.uid` fields in the JSON files before importing.

---

## Step 5 — Import the Grafana dashboards

Two dashboard JSON files are provided in `grafana-dashboards/`:

| File | Title | Best for |
|---|---|---|
| `bifrost-grafana-dashboard.json` | Bifrost AI Gateway | Quick overview — request rate, p95 latency, provider split, virtual key usage |
| `advanced-bifrost-grafana-dashboard.json` | Enhanced Bifrost AI Gateway Dashboard | Deep-dive — p95/p99/avg latency, success rate %, token throughput, retry activity, namespace + provider filter vars |

### Import steps

1. In Grafana → **Dashboards → Import**
2. Click **Upload dashboard JSON file**
3. Select `grafana-dashboards/bifrost-grafana-dashboard.json`
4. Set the Prometheus datasource to `prometheus` if prompted
5. Click **Import**
6. Repeat for `advanced-bifrost-grafana-dashboard.json`

Or import via the Grafana API:

```bash
# Set your Grafana API key or use basic auth
GRAFANA_URL="http://localhost:3000"
GRAFANA_AUTH="admin:prom-operator"

for f in grafana-dashboards/*.json; do
  echo "Importing $f..."
  curl -s -X POST \
    -H "Content-Type: application/json" \
    -u "$GRAFANA_AUTH" \
    -d "{\"dashboard\": $(cat $f), \"overwrite\": true, \"folderId\": 0}" \
    "$GRAFANA_URL/api/dashboards/import" | python3 -m json.tool
done
```

---

## Dashboard Reference

### Bifrost AI Gateway (basic)

| Panel | Type | What it shows |
|---|---|---|
| Total Requests | Stat | Cumulative `bifrost_upstream_requests_total` |
| Successful Requests | Stat | Cumulative `bifrost_success_requests_total` |
| Input Tokens | Stat | Cumulative `bifrost_input_tokens_total` |
| Output Tokens | Stat | Cumulative `bifrost_output_tokens_total` |
| Request Rate | Time series | `rate(bifrost_upstream_requests_total[1m])` in req/s |
| P95 Latency | Time series | `histogram_quantile(0.95, ...)` in seconds |
| Requests by Provider | Pie chart | Split by `provider` label |
| Requests by Virtual Key | Bar gauge | Split by `virtual_key_name` label |
| Raw Metrics | Table | Instant snapshot of all label combinations |

Default time range: last 1 hour. Refresh: 10s.

### Enhanced Bifrost AI Gateway Dashboard (advanced)

Adds on top of the basic dashboard:

| Panel | Type | What it shows |
|---|---|---|
| Success Rate % | Time series | `(success / total) * 100` — spot provider errors immediately |
| P95 vs P99 Latency | Time series | p95, p99, and average on one chart |
| Requests by Pod | Bar gauge | Per-pod breakdown — useful when scaled to >1 replica |
| Token Throughput | Time series | Input and output tokens/sec over time |
| Requests by Provider Over Time | Time series | Provider traffic share over the selected window |
| Retry Activity | Table | Requests with `number_of_retries != 0` grouped by provider |

Template variables: `namespace` and `provider` — both multi-select with All option. Default time range: last 6 hours.

---

## Key Metrics Reference

| Metric | Type | Labels | Description |
|---|---|---|---|
| `bifrost_upstream_requests_total` | Counter | `provider`, `virtual_key_name`, `pod`, `namespace`, `number_of_retries` | Every upstream request |
| `bifrost_success_requests_total` | Counter | `provider`, `virtual_key_name`, `pod`, `namespace` | Successful requests only |
| `bifrost_input_tokens_total` | Counter | `provider`, `virtual_key_name`, `pod`, `namespace` | Input tokens consumed |
| `bifrost_output_tokens_total` | Counter | `provider`, `virtual_key_name`, `pod`, `namespace` | Output tokens generated |
| `bifrost_upstream_latency_seconds` | Histogram | `provider`, `virtual_key_name`, `pod`, `namespace`, `le` | End-to-end upstream latency |

---

## Useful PromQL Queries

```promql
# Overall error rate
1 - (sum(rate(bifrost_success_requests_total[5m])) / sum(rate(bifrost_upstream_requests_total[5m])))

# P99 latency per provider
histogram_quantile(0.99,
  sum(rate(bifrost_upstream_latency_seconds_bucket[5m])) by (provider, le)
)

# Token throughput (total tokens/sec)
sum(rate(bifrost_input_tokens_total[1m])) + sum(rate(bifrost_output_tokens_total[1m]))

# Requests per virtual key (rate)
sum(rate(bifrost_upstream_requests_total[5m])) by (virtual_key_name)

# Retry rate
sum(rate(bifrost_upstream_requests_total{number_of_retries!="0"}[5m]))
  / sum(rate(bifrost_upstream_requests_total[5m]))
```

---

## Alert Rules

A `PrometheusRule` resource is deployed in the `monitoring` namespace with 6 alerts covering errors, latency, token burn, and cost. The manifest is at `manifests/bifrost-alerts.yaml`.

> **Note:** This PrometheusRule is already applied in the cluster. If rebuilding from scratch, run `kubectl apply -f manifests/bifrost-alerts.yaml`.

### Deployed Alerts

| Alert | Severity | Condition | For |
|---|---|---|---|
| `BifrostHighErrorRate` | critical | > 5 errors/sec | 5m |
| `BifrostLowSuccessRate` | critical | success rate < 90% | 5m |
| `BifrostHighLatencyP99` | warning | p99 upstream latency > 10s | 5m |
| `BifrostHighStreamFirstTokenLatency` | warning | p99 TTFT > 5s | 5m |
| `BifrostHighTokenBurnRate` | warning | > 1000 tokens/sec combined | 5m |
| `BifrostHighCostRate` | warning | projected spend > $1/hr | 10m |

### Manifest

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: bifrost-alerts
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
    app: kube-prometheus-stack
spec:
  groups:
    - name: bifrost.rules
      interval: 30s
      rules:
        - alert: BifrostHighErrorRate
          expr: sum(rate(bifrost_error_requests_total[5m])) > 5
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: High Bifrost error rate
            description: "Bifrost error rate is {{ $value | humanize }} errors/sec over the last 5 minutes"

        - alert: BifrostLowSuccessRate
          expr: |
            sum(rate(bifrost_success_requests_total[5m])) /
            sum(rate(bifrost_upstream_requests_total[5m])) < 0.9
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: Bifrost success rate below 90%
            description: "Success rate is {{ $value | humanizePercentage }} over the last 5 minutes"

        - alert: BifrostHighLatencyP99
          expr: histogram_quantile(0.99, sum(rate(bifrost_upstream_latency_seconds_bucket[5m])) by (le, provider, model)) > 10
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: Bifrost upstream p99 latency is high
            description: "p99 latency for {{ $labels.provider }}/{{ $labels.model }} is {{ $value | humanizeDuration }}"

        - alert: BifrostHighStreamFirstTokenLatency
          expr: histogram_quantile(0.99, sum(rate(bifrost_stream_first_token_latency_seconds_bucket[5m])) by (le, provider, model)) > 5
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: Bifrost time-to-first-token p99 is high
            description: "TTFT p99 for {{ $labels.provider }}/{{ $labels.model }} is {{ $value | humanizeDuration }}"

        - alert: BifrostHighTokenBurnRate
          expr: sum(rate(bifrost_input_tokens_total[5m]) + rate(bifrost_output_tokens_total[5m])) > 1000
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: Bifrost token consumption rate is high
            description: "Token burn rate is {{ $value | humanize }} tokens/sec — check for runaway requests"

        - alert: BifrostHighCostRate
          expr: sum(rate(bifrost_cost_total[1h])) * 3600 > 1
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: Bifrost cost accruing rapidly
            description: "Projected hourly cost is ${{ $value | humanize }}"
```

### Verify alerts loaded

```bash
curl -s http://localhost:9090/api/v1/rules \
  | jq '.data.groups[].rules[] | select(.name | startswith("Bifrost")) | {name, state, health}'
```

### Test an alert (lower threshold to trigger)

```bash
# Lower BifrostHighErrorRate threshold to 0 to force firing
kubectl patch prometheusrule bifrost-alerts -n monitoring --type='json' \
  -p='[{"op":"replace","path":"/spec/groups/0/rules/0/expr","value":"sum(rate(bifrost_error_requests_total[5m])) > 0"}]'

# Watch state: inactive → pending → firing (takes up to 5m due to 'for' duration)
curl -s http://localhost:9090/api/v1/rules \
  | jq '.data.groups[].rules[] | select(.name | startswith("Bifrost")) | {name, state}'

# Restore
kubectl apply -f manifests/bifrost-alerts.yaml
```

### Threshold tuning

| Alert | Default | Notes |
|---|---|---|
| `BifrostHighErrorRate` | > 5/sec | Lower for production |
| `BifrostLowSuccessRate` | < 90% | Consider 95–99% for production |
| `BifrostHighLatencyP99` | > 10s | Raise for Ollama on CPU |
| `BifrostHighStreamFirstTokenLatency` | > 5s | Ollama on CPU will routinely exceed this |
| `BifrostHighTokenBurnRate` | > 1000 tok/sec | Tune to expected throughput |
| `BifrostHighCostRate` | > $1/hr | Adjust to your budget |

---

## Troubleshooting

**Prometheus target shows DOWN**
- Check Bifrost pod is running: `kubectl get pods -n ai-gateway`
- Confirm the service has the expected labels: `kubectl get svc bifrost -n ai-gateway --show-labels`
- Check the ServiceMonitor selector matches: `kubectl get servicemonitor bifrost -n monitoring -o yaml`

**No data in Grafana panels**
- Confirm the Prometheus datasource UID is `prometheus` — both dashboards hardcode this UID
- Try running `bifrost_upstream_requests_total` directly in Grafana's Explore view to test connectivity
- Make sure Bifrost has received at least one request (run a demo script or hit the API manually)

**ServiceMonitor not picked up by Prometheus**
- The `release: kube-prometheus-stack` label on the ServiceMonitor must match the Prometheus operator's `serviceMonitorSelector` — verify with:
  ```bash
  kubectl get prometheus -n monitoring -o jsonpath='{.items[0].spec.serviceMonitorSelector}'
  ```

---

## Port-forward convenience script

Both services need to be forwarded for full observability:

```bash
#!/bin/bash
# port-forward-observability.sh
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 &
kubectl port-forward -n ai-gateway svc/bifrost 8080:8080 &
echo "Prometheus: http://localhost:9090"
echo "Grafana:    http://localhost:3000  (admin / prom-operator)"
echo "Bifrost UI: http://localhost:8080"
wait
```

---

*Related docs: [docs/README.md](README.md) · [Prometheus MCP Server — Deployment & Demo Guide.md](Prometheus%20MCP%20Server%20—%20Deployment%20%26%20Demo%20Guide.md) · [Grafana MCP Server — Deployment & Demo Guide.md](Additional-MCP-Server-Guides/Grafana%20MCP%20Server%20—%20Deployment%20%26%20Demo%20Guide.md)*
