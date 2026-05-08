# Bifrost — curl Examples

Direct curl examples for all MCP tools available via Bifrost. Run the discovery command first to confirm exact tool names registered in your instance.

```bash
export KEY="<your-admin-key>"
export BF="http://localhost:8080/mcp"
```

---

## Discover Available Tools

Always run this first to confirm exact tool names and prefixes:

```bash
curl -s -X POST $BF \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' \
  | jq '[.result.tools[].name]'
```

---

## Kubernetes Tools (`new_kubernetes_local-`)

### Namespaces

```bash
curl -s -X POST $BF \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"new_kubernetes_local-namespaces_list","arguments":{}}}' \
  | jq -r '.result.content[0].text'
```

### Pods — list all namespaces

```bash
curl -s -X POST $BF \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"new_kubernetes_local-pods_list","arguments":{}}}' \
  | jq -r '.result.content[0].text'
```

### Pods — list in namespace

```bash
curl -s -X POST $BF \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"new_kubernetes_local-pods_list_in_namespace","arguments":{"namespace":"<namespace>"}}}' \
  | jq -r '.result.content[0].text'
```

### Pods — get single pod

```bash
curl -s -X POST $BF \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"new_kubernetes_local-pods_get","arguments":{"name":"<pod-name>","namespace":"<namespace>"}}}' \
  | jq -r '.result.content[0].text'
```

### Pods — logs

```bash
curl -s -X POST $BF \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"new_kubernetes_local-pods_log","arguments":{"name":"<pod-name>","namespace":"<namespace>","tail":50}}}' \
  | jq -r '.result.content[0].text'
```

### Pods — resource usage (top)

```bash
curl -s -X POST $BF \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"new_kubernetes_local-pods_top","arguments":{"namespace":"<namespace>"}}}' \
  | jq -r '.result.content[0].text'
```

### Pods — exec

```bash
curl -s -X POST $BF \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"new_kubernetes_local-pods_exec","arguments":{"name":"<pod-name>","namespace":"<namespace>","command":["sh","-c","echo hello"]}}}' \
  | jq -r '.result.content[0].text'
```

### Pods — delete

```bash
curl -s -X POST $BF \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"new_kubernetes_local-pods_delete","arguments":{"name":"<pod-name>","namespace":"<namespace>"}}}' \
  | jq -r '.result.content[0].text'
```

### Nodes — resource usage (top)

```bash
curl -s -X POST $BF \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"new_kubernetes_local-nodes_top","arguments":{}}}' \
  | jq -r '.result.content[0].text'
```

### Events — list in namespace

```bash
curl -s -X POST $BF \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"new_kubernetes_local-events_list","arguments":{"namespace":"<namespace>"}}}' \
  | jq -r '.result.content[0].text'
```

### Resources — list (any resource type)

```bash
curl -s -X POST $BF \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"new_kubernetes_local-resources_list","arguments":{"apiVersion":"argoproj.io/v1alpha1","kind":"Application","namespace":"argocd"}}}' \
  | jq -r '.result.content[0].text'
```

### Resources — list Deployments

```bash
curl -s -X POST $BF \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"new_kubernetes_local-resources_list","arguments":{"apiVersion":"apps/v1","kind":"Deployment","namespace":"<namespace>"}}}' \
  | jq -r '.result.content[0].text'
```

### Resources — get single resource

```bash
curl -s -X POST $BF \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"new_kubernetes_local-resources_get","arguments":{"apiVersion":"argoproj.io/v1alpha1","kind":"Application","name":"<app-name>","namespace":"argocd"}}}' \
  | jq -r '.result.content[0].text'
```

### Resources — scale deployment

```bash
curl -s -X POST $BF \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"new_kubernetes_local-resources_scale","arguments":{"apiVersion":"apps/v1","kind":"Deployment","name":"<deployment-name>","namespace":"<namespace>","scale":2}}}' \
  | jq -r '.result.content[0].text'
```

### Configuration — view kubeconfig

```bash
curl -s -X POST $BF \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"new_kubernetes_local-configuration_view","arguments":{}}}' \
  | jq -r '.result.content[0].text'
```

### Configuration — list contexts

```bash
curl -s -X POST $BF \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"new_kubernetes_local-configuration_contexts_list","arguments":{}}}' \
  | jq -r '.result.content[0].text'
```

---

## Prometheus Tools (`prometheus-`)

### Health check

```bash
curl -s -X POST $BF \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"prometheus-healthy","arguments":{}}}' \
  | jq -r '.result.content[0].text'
```

### Instant query

```bash
curl -s -X POST $BF \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"prometheus-query","arguments":{"query":"up"}}}' \
  | jq -r '.result.content[0].text'
```

### CPU usage by pod

```bash
curl -s -X POST $BF \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"prometheus-query","arguments":{"query":"sum(rate(container_cpu_usage_seconds_total{container!=\"\"}[5m])) by (namespace, pod)"}}}' \
  | jq -r '.result.content[0].text'
```

### Memory usage by pod

```bash
curl -s -X POST $BF \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"prometheus-query","arguments":{"query":"sum(container_memory_working_set_bytes{container!=\"\"}) by (namespace, pod)"}}}' \
  | jq -r '.result.content[0].text'
```

### Range query — CPU last hour

```bash
curl -s -X POST $BF \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"prometheus-range_query","arguments":{"query":"sum(rate(container_cpu_usage_seconds_total{container!=\"\"}[5m])) by (namespace, pod)","start_time":"1h","step":"5m"}}}' \
  | jq -r '.result.content[0].text'
```

### Active alerts

```bash
curl -s -X POST $BF \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"prometheus-list_alerts","arguments":{}}}' \
  | jq -r '.result.content[0].text'
```

### Scrape targets

```bash
curl -s -X POST $BF \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"prometheus-list_targets","arguments":{}}}' \
  | jq -r '.result.content[0].text'
```

### Bifrost gateway metrics — total requests by model

```bash
curl -s -X POST $BF \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"prometheus-query","arguments":{"query":"sum(bifrost_upstream_requests_total) by (provider, model, key_name)"}}}' \
  | jq -r '.result.content[0].text'
```

### Bifrost gateway metrics — p99 latency by model

```bash
curl -s -X POST $BF \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"prometheus-query","arguments":{"query":"histogram_quantile(0.99, sum(rate(bifrost_upstream_latency_seconds_bucket[5m])) by (le, provider, model))"}}}' \
  | jq -r '.result.content[0].text'
```

### TSDB stats

```bash
curl -s -X POST $BF \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"prometheus-tsdb_stats","arguments":{}}}' \
  | jq -r '.result.content[0].text'
```

### Build info

```bash
curl -s -X POST $BF \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"prometheus-build_info","arguments":{}}}' \
  | jq -r '.result.content[0].text'
```

---

## Access Control — Restricted Key Examples

The restricted key has access to 7 read-only Kubernetes tools only. Use these to demonstrate permission enforcement.

```bash
export KEY_RESTRICTED="<your-restricted-key>"
```

### Allowed — list pods (succeeds)

```bash
curl -s -X POST $BF \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY_RESTRICTED" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"new_kubernetes_local-pods_list","arguments":{}}}' \
  | jq -r '.result.content[0].text'
```

### Denied — delete pod (fails)

```bash
curl -s -X POST $BF \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY_RESTRICTED" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"new_kubernetes_local-pods_delete","arguments":{"name":"my-pod","namespace":"default"}}}' \
  | jq .
```

### Denied — scale deployment (fails)

```bash
curl -s -X POST $BF \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY_RESTRICTED" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"new_kubernetes_local-resources_scale","arguments":{"apiVersion":"apps/v1","kind":"Deployment","name":"my-deployment","namespace":"default","scale":0}}}' \
  | jq .
```
