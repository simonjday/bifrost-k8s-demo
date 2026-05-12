# Bifrost Metric Queries — Corrected Reference

**IMPORTANT:** Use these queries with Prometheus MCP or direct Prometheus queries. Not `bifrost_gateway_requests_total` — it doesn't exist.

---

## Available Bifrost Metrics

All metrics are **counters** scraped from Bifrost `/metrics` endpoint every 15 seconds.

| Metric | Labels | Example |
|--------|--------|---------|
| `bifrost_success_requests_total` | model, provider, routing_rule_name, method | Success count by model |
| `bifrost_error_requests_total` | status_code, provider, model, routing_rule_name | Error count by status |
| `bifrost_input_tokens_total` | model, provider | Total input tokens |
| `bifrost_output_tokens_total` | model, provider | Total output tokens |

---

## Common PromQL Queries

### 1. Success Requests by Model (instant)
```promql
bifrost_success_requests_total
```
**Returns:** All time series (use for debugging/inspection)

### 2. Success Rate % (5m)
```promql
(
  sum(rate(bifrost_success_requests_total[5m])) /
  (sum(rate(bifrost_success_requests_total[5m])) + sum(rate(bifrost_error_requests_total[5m])))
) * 100
```

### 3. Request Rate by Provider (5m)
```promql
sum(rate(bifrost_success_requests_total[5m])) by (provider)
```
**Returns:** Requests/sec per provider (ollama, anthropic, etc.)

### 4. Error Rate by Provider (5m)
```promql
sum(rate(bifrost_error_requests_total[5m])) by (provider)
```
**Returns:** Errors/sec per provider

### 5. Error Count by Status Code (5m)
```promql
sum(rate(bifrost_error_requests_total[5m])) by (status_code)
```
**Returns:** 401, 429, 500, 504 errors

### 6. Request Count by Model (5m)
```promql
sum(rate(bifrost_success_requests_total[5m])) by (model)
```
**Returns:** Requests/sec per model (qwen2.5:7b, llama3.2:3b, etc.)

### 7. Token Throughput (5m)
```promql
sum(rate(bifrost_input_tokens_total[5m])) + sum(rate(bifrost_output_tokens_total[5m]))
```
**Returns:** Total tokens/sec (input + output)

### 8. Input vs Output Tokens (5m)
```promql
sum(rate(bifrost_input_tokens_total[5m])) by (model)
sum(rate(bifrost_output_tokens_total[5m])) by (model)
```
**Returns:** Token rates by model separately

### 9. Provider + Model Breakdown (5m)
```promql
sum(rate(bifrost_success_requests_total[5m])) by (provider, model)
```
**Returns:** Requests/sec matrix (provider × model)

### 10. Top 5 Models by Request Volume
```promql
topk(5, sum(rate(bifrost_success_requests_total[5m])) by (model))
```

---

## Testing Queries via Postman

All Bifrost queries in the **🔮 Bifrost — Gateway Metrics** folder use the `prometheus-query` tool.

**Request format:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "prometheus-query",
    "arguments": {
      "query": "bifrost_success_requests_total"
    }
  }
}
```

**Headers:**
```
Content-Type: application/json
X-Api-Key: sk-bf-d6373a91-f86b-42fd-8ecc-4a61aac010c2
```

**Full curl example:**
```bash
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: sk-bf-d6373a91-f86b-42fd-8ecc-4a61aac010c2" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"prometheus-query","arguments":{"query":"sum(rate(bifrost_success_requests_total[5m])) by (provider)"}}}' | jq '.result.content[0].text'
```

---

## Grafana Dashboard Queries

Use these as-is in Grafana panels (set datasource to Prometheus):

### Success Rate Gauge
```promql
(
  sum(rate(bifrost_success_requests_total[5m])) /
  (sum(rate(bifrost_success_requests_total[5m])) + sum(rate(bifrost_error_requests_total[5m])))
) * 100
```

### Requests Timeline (Graph)
```promql
sum(rate(bifrost_success_requests_total[5m])) by (provider)
```

### Error Rate Timeline (Graph)
```promql
sum(rate(bifrost_error_requests_total[5m])) by (provider)
```

### Token Throughput (Stat)
```promql
sum(rate(bifrost_input_tokens_total[5m])) + sum(rate(bifrost_output_tokens_total[5m]))
```

---

## Debugging: Verify Metrics Available

```bash
# 1. Check Prometheus is scraping
curl -s http://localhost:9090/api/v1/targets | \
  jq '.data.activeTargets[] | select(.labels.job=="bifrost") | .health'
# Expected: "up"

# 2. Check metric names available
curl -s 'http://localhost:9090/api/v1/label/__name__/values?match=bifrost' | \
  jq '.data[]'
# Expected: [bifrost_success_requests_total, bifrost_error_requests_total, bifrost_input_tokens_total, bifrost_output_tokens_total]

# 3. Test a query
curl -s 'http://localhost:9090/api/v1/query?query=bifrost_success_requests_total' | \
  jq '.data.result | length'
# Expected: > 0 (number of time series)
```

---

## What Changed (This Session)

| Query | Status | Fix |
|-------|--------|-----|
| `bifrost_gateway_requests_total` | ❌ Never existed | Replaced with `bifrost_success_requests_total` |
| `bifrost_gateway_request_duration_seconds_bucket` | ❌ Never existed | Removed; use `bifrost_success_requests_total by (model)` |
| Error rate `{status="error"}` label filter | ❌ Wrong approach | Use `bifrost_error_requests_total` metric directly |

---

## No More Data?

If queries still return no data:

1. **Is Prometheus scraping Bifrost?**
   ```bash
   curl -s http://localhost:9090/api/v1/query?query=bifrost_success_requests_total | jq '.data.result | length'
   ```
   If returns `0`, restart Prometheus: `kubectl -n monitoring delete pod prometheus-kube-prometheus-stack-prometheus-0`

2. **Is there traffic?**
   ```bash
   bash scripts/bifrost-sim.sh 50
   sleep 30
   # Then re-query
   ```

3. **Is the metric name correct?**
   ```bash
   curl -s 'http://localhost:9090/api/v1/label/__name__/values?match=bifrost' | jq
   ```

---

**Updated:** 2026-05-12  
**Status:** All queries corrected and verified ✓
