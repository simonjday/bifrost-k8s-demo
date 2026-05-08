# Bifrost AI Gateway — In-Depth Analysis

> **Audience:** Kubernetes / Platform Architect
> **Date:** April 2026 (updated May 2026)
> **Vendor:** Maxim AI (H3 Labs Inc.)
> **Repo:** [github.com/maximhq/bifrost](https://github.com/maximhq/bifrost) — Apache 2.0
> **Stack:** Go binary, single static executable, OpenAI-compatible API surface

-----

## Table of Contents

1. [What It Is](#what-it-is)
2. [Architecture](#architecture)
3. [Performance](#performance)
4. [Feature Breakdown](#feature-breakdown)
5. [Pros](#pros)
6. [Cons](#cons)
7. [Costs](#costs)
8. [kind Test Environment Setup](#kind-test-environment-setup)
9. [Test Scenarios](#test-scenarios)
10. [Verdict](#verdict)

-----

## What It Is

Bifrost is a high-performance AI gateway that unifies access to 20+ LLM providers (OpenAI, Anthropic, AWS Bedrock, Google Vertex, Azure, and more) through a single OpenAI-compatible API, with automatic failover, load balancing, semantic caching, and enterprise-grade governance.

Its infrastructure role is a **unified control plane** sitting between your applications and upstream LLM providers — routing, cost governance, observability, and MCP tooling all in one Go process. It is explicitly not a self-hosted inference engine (no quantisation, no PagedAttention, no GPU scheduling).

-----

## Architecture

```
                        ┌─────────────────────────────┐
                        │        Applications          │
                        │  (OpenAI SDK / Anthropic SDK │
                        │   / LangChain / raw HTTP)    │
                        └────────────┬────────────────┘
                                     │ base_url = bifrost
                        ┌────────────▼────────────────┐
                        │        Bifrost Gateway        │
                        │  ┌──────────────────────┐   │
                        │  │  Virtual Keys / RBAC  │   │
                        │  │  Budget Enforcement   │   │
                        │  │  Routing Rules        │   │
                        │  │  Semantic Cache       │   │
                        │  │  MCP Client/Server    │   │
                        │  │  OTel / Prometheus    │   │
                        │  └──────────────────────┘   │
                        │  SQLite │ PostgreSQL (store)  │
                        └────────────┬────────────────┘
               ┌─────────────────────┼────────────────────┐
               │                     │                    │
    ┌──────────▼──────┐  ┌──────────▼──────┐  ┌─────────▼──────┐
    │     OpenAI       │  │    Anthropic     │  │  AWS Bedrock   │
    │   AWS Bedrock    │  │  Google Vertex   │  │    Groq etc.   │
    └──────────────────┘  └──────────────────┘  └────────────────┘
```

### Modular layout (from source)

```
bifrost/
├── core/
│   ├── providers/      # Per-provider implementations (OpenAI, Anthropic, etc.)
│   ├── schemas/        # Shared interfaces and structs
│   └── bifrost.go      # Core implementation
├── framework/
│   ├── configstore/    # SQLite / PostgreSQL config backends
│   ├── logstore/       # Request log backends
│   └── vectorstore/    # Weaviate / Qdrant / Pinecone backends
├── transports/
│   └── bifrost-http/   # HTTP gateway layer
├── ui/                 # Built-in web UI
└── plugins/
    ├── governance/     # Budget management and access control
    ├── logging/        # Request logging
    ├── mocker/         # Mock provider responses (key for testing)
    ├── maxim/          # Maxim AI observability integration
    └── jsonparser/     # JSON manipulation utilities
```

Key operational characteristics:

- **Single Go binary** — no JVM, no Python interpreter, no sidecar required
- Config and log persistence: **SQLite** (default, zero-config) or **PostgreSQL** (production)
- Native **Prometheus** metrics scrape endpoint + **OTLP** for Grafana / New Relic / Honeycomb
- **Helm chart** published for Kubernetes deployment
- Acts as both **MCP client** (connects to external MCP servers via STDIO, HTTP, SSE) and **MCP server** (exposes a unified `/mcp` endpoint to clients like Claude Code / Cursor)

-----

## Performance

Headline benchmark: **11 µs mean overhead at 5,000 RPS** (sustained load, logging and retries enabled).

|Metric                |Bifrost  |LiteLLM       |Delta          |
|----------------------|---------|--------------|---------------|
|P99 latency at 500 RPS|~1.68s   |~90.72s       |**54x faster** |
|Throughput            |424 req/s|44.84 req/s   |**9.4x higher**|
|Memory under load     |~120 MB  |~372 MB       |**3x lighter** |
|Gateway overhead      |11 µs    |hundreds of µs|~40–50x        |


> **Note:** Benchmarks are vendor-published. Independent validation recommended before using as a procurement argument.

For AI workloads specifically — low RPS but high latency due to streaming tokens — Kong and NGINX-based gateways carry unnecessary overhead. Bifrost's architecture is optimised for streaming, semantic caching, and agentic tool chaining where latency compounds across multiple LLM calls.

-----

## Feature Breakdown

### OSS (free, self-hosted, Apache 2.0)

|Feature                |Detail                                                                              |
|-----------------------|------------------------------------------------------------------------------------|
|**Drop-in replacement**|Change only `base_url` in existing SDK usage                                        |
|**Provider routing**   |20+ providers, weighted routing, model aliasing                                     |
|**Automatic failover** |Configurable fallback chains per virtual key                                        |
|**Virtual keys**       |Primary governance entity — budgets, rate limits, routing, allowed MCP tools per key|
|**Budget hierarchy**   |4-tier: customer → team → user → virtual key                                        |
|**Semantic caching**   |Dual-layer: exact hash + vector similarity (Weaviate / Qdrant / Redis / Pinecone)   |
|**MCP gateway**        |Client + server, OAuth 2.0, per-key tool allow-lists, agent mode, code mode         |
|**Observability**      |Built-in dashboard, Prometheus metrics, OTLP tracing                                |
|**Mocker plugin**      |Mock provider responses — zero-egress local dev/test                                |
|**Custom plugins**     |Go or WASM plugins for bespoke middleware                                           |
|**Async inference**    |Fire-and-forget request pattern                                                     |
|**LiteLLM compat**     |Drop-in LiteLLM API compatibility mode                                              |

### Enterprise (custom pricing, contact sales)

Everything in OSS, plus:

|Feature                       |Detail                                                                                  |
|------------------------------|----------------------------------------------------------------------------------------|
|**Guardrails**                |AWS Bedrock Guardrails, Azure Content Safety, Patronus AI — real-time output filtering  |
|**Cluster mode**              |Peer-to-peer HA, gossip-based sync, zero-downtime rolling deploys                       |
|**Adaptive load balancing**   |Real-time performance-driven traffic shifting across providers                          |
|**Enterprise SSO**            |SAML + OIDC (Okta, Microsoft Entra)                                                     |
|**RBAC**                      |Fine-grained custom roles across all Bifrost resources                                  |
|**Vault support**             |HashiCorp Vault, AWS Secrets Manager, GCP Secret Manager, Azure Key Vault               |
|**MCP federated auth**        |Transform existing enterprise APIs into MCP tools with federated auth — no code required|
|**Audit logs**                |Immutable trails for SOC 2, GDPR, HIPAA, ISO 27001                                      |
|**Log exports**               |Automated export of request logs + telemetry to storage/data lakes                      |
|**Datadog connector**         |Native APM traces, LLM Observability, metrics                                           |
|**VPC / on-prem / air-gapped**|In-VPC isolation, private networking, enterprise security controls                      |
|**SLA-backed support**        |Dedicated Slack/Teams channel, custom SLA, direct engineering access                    |

**Compliance certifications (enterprise):** SOC 2 Type II, GDPR, ISO 27001, HIPAA.

> ⚠️ Formal ZDR (Zero Data Retention) policy and encryption-at-rest details are not published in public documentation. For regulated deployments, obtain written confirmation from vendor before procurement.

-----

## Pros

**1. Latency is genuinely negligible.**
11 µs mean overhead makes the gateway effectively free from a performance budget perspective. For agentic workflows where LLM → tool → LLM calls chain, this compounds favourably vs Python-based alternatives.

**2. Purpose-built for AI traffic patterns.**
Streaming, semantic caching, MCP execution, provider-specific retry semantics — all first-class. Not bolted onto a general-purpose API gateway.

**3. OSS core is feature-rich.**
Governance primitives, semantic caching, OTel/Prometheus, virtual keys, fallbacks, and the Mocker plugin are all in the free tier. Full PoC possible with zero licensing.

**4. Helm chart + official Kubernetes deployment.**
HA via gossip-protocol, automatic service discovery, and zero-downtime rolling deployments are documented and Helm-native.

**5. Single binary, minimal footprint.**
No dependency graph. Fits naturally into a constrained kind environment without fighting resource limits. 120 MB RAM under load.

**6. Drop-in SDK compatibility.**
`base_url` swap only — no application code changes, no SDK replacement.

**7. Unified MCP + LLM control plane.**
Rather than a separate MCP proxy, Bifrost handles both LLM routing and MCP tool governance in one process. Single point of auth, access control, and audit for both.

**8. Mocker plugin.**
Critical for local test environments — mock provider responses without live API credentials or egress. Full round-trip testing at zero cost.

-----

## Cons

**1. Enterprise pricing is opaque.**
No published tiers. Custom pricing requires a vendor conversation. Problematic for procurement cycles that need pre-engagement budget estimates.

**2. Cluster mode is enterprise-gated.**
HA clustering is not in OSS. For production multi-replica deployments with state synchronisation, you're on enterprise or self-managing PostgreSQL-backed consistency.

**3. Guardrails are enterprise-only.**
Content safety / output filtering is enterprise-gated. For regulated environments this is a hard requirement, not optional.

**4. Semantic caching requires an external vector store.**
No embedded vector DB. Weaviate or Qdrant (or similar) must be deployed and maintained separately. Adds operational surface area.

**5. Relatively young project.**
Breaking changes documented (v1.5.0 migration guide). Community is Discord-based. Production reference list is limited compared to LiteLLM or Kong.

**6. Vendor entanglement risk.**
Bifrost is built by Maxim AI; the Maxim AI observability platform is the native deep-integration target. Commercial incentive is toward their paid observability product for anything beyond basic Prometheus metrics.

**7. SAML/SSO is enterprise-gated.**
Organisations with SSO mandates are forced to enterprise tier regardless of other feature requirements.

**8. No public ZDR documentation.**
Encryption-at-rest and data retention semantics are implementation-dependent. Infosec review will require formal vendor answers.

-----

## Costs

|Tier                    |Price                    |Notes                                                                                     |
|------------------------|-------------------------|------------------------------------------------------------------------------------------|
|**OSS**                 |Free                     |Self-hosted (Docker / k8s / binary). No cluster mode, guardrails, SAML, vault, audit logs.|
|**Enterprise**          |Custom (contact sales)   |14-day free trial available. All OSS features + full enterprise stack.                    |
|**Infrastructure (OSS)**|Your cluster costs       |~120 MB RAM, 250m–500m CPU per replica at load.                                           |
|**Vector store**        |Separate infra           |Weaviate / Qdrant / Pinecone for semantic caching.                                        |
|**Provider APIs**       |Pass-through, zero markup|You pay upstream (OpenAI, Anthropic, Bedrock etc.) directly.                              |

No per-request fees, no token markups at any tier. The gateway adds zero cost to API spend itself.

-----

## kind Test Environment Setup

> **Note:** This repo uses a kind cluster (`devops-lab`) rather than k3d. The manifests below apply to both — adjust `k3d cluster list` to `kind get clusters` and `k3d kubeconfig write` to `kind export kubeconfig` as needed.

### Prerequisites

```bash
# Verify cluster
kind get clusters
kubectl config use-context kind-devops-lab
kubectl get nodes
```

### 1. Namespace

```yaml
# 00-namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ai-gateway
```

```bash
kubectl apply -f 00-namespace.yaml
```

### 2. Config Secret (SQLite / zero-config for local dev)

```yaml
# 01-bifrost-config-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: bifrost-config
  namespace: ai-gateway
type: Opaque
stringData:
  config.json: |
    {
      "config_store": {
        "enabled": false
      },
      "logs_store": {
        "enabled": false
      }
    }
```

> **Production variant:** Replace with PostgreSQL config — deploy `bitnami/postgresql` in the same namespace and update `config.json` accordingly:

```yaml
stringData:
  config.json: |
    {
      "config_store": {
        "enabled": true,
        "type": "postgres",
        "config": {
          "host": "postgresql.ai-gateway.svc.cluster.local",
          "port": "5432",
          "user": "bifrost",
          "password": "changeme",
          "db_name": "bifrost",
          "ssl_mode": "disable"
        }
      },
      "logs_store": {
        "enabled": true,
        "type": "postgres",
        "config": {
          "host": "postgresql.ai-gateway.svc.cluster.local",
          "port": "5432",
          "user": "bifrost",
          "password": "changeme",
          "db_name": "bifrost",
          "ssl_mode": "disable"
        }
      }
    }
```

### 3. Deployment + Service

```yaml
# 02-bifrost-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: bifrost
  namespace: ai-gateway
  labels:
    app: bifrost
spec:
  replicas: 1
  selector:
    matchLabels:
      app: bifrost
  template:
    metadata:
      labels:
        app: bifrost
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
        prometheus.io/path: "/metrics"
    spec:
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        fsGroupChangePolicy: OnRootMismatch
      initContainers:
      - name: fix-permissions
        image: busybox:latest
        command: ["sh", "-c", "chown -R 1000:1000 /app/data && chmod -R 755 /app/data"]
        securityContext:
          runAsUser: 0
        volumeMounts:
        - name: data
          mountPath: /app/data
      containers:
      - name: bifrost
        image: maximhq/bifrost:latest
        ports:
        - containerPort: 8080
          name: http
        securityContext:
          runAsNonRoot: true
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: false
        resources:
          requests:
            cpu: 250m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
        volumeMounts:
        - name: data
          mountPath: /app/data
        - name: config
          mountPath: /app/data/config.json
          subPath: config.json
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
      volumes:
      - name: data
        emptyDir: {}
      - name: config
        secret:
          secretName: bifrost-config
---
apiVersion: v1
kind: Service
metadata:
  name: bifrost
  namespace: ai-gateway
  labels:
    app: bifrost
spec:
  selector:
    app: bifrost
  ports:
  - port: 8080
    targetPort: 8080
    name: http
  type: ClusterIP
```

```bash
kubectl apply -f 01-bifrost-config-secret.yaml
kubectl apply -f 02-bifrost-deployment.yaml

# Verify
kubectl -n ai-gateway get pods -w
kubectl -n ai-gateway logs -f deploy/bifrost
```

### 4. Local port-forward

```bash
kubectl -n ai-gateway port-forward svc/bifrost 8080:8080 &
# Web UI: http://localhost:8080
# API:    http://localhost:8080/v1/chat/completions
```

### 5. Helm alternative

```bash
helm repo add bifrost https://maximhq.github.io/bifrost/helm-charts
helm repo update

helm install bifrost bifrost/bifrost \
  --namespace ai-gateway \
  --create-namespace \
  --set persistence.enabled=false
```

### 6. ServiceMonitor (kube-prometheus-stack)

```yaml
# 03-bifrost-servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: bifrost
  namespace: monitoring
  labels:
    app: bifrost
    release: kube-prometheus-stack   # must match Prometheus operator serviceMonitorSelector
spec:
  namespaceSelector:
    matchNames:
    - ai-gateway
  selector:
    matchLabels:
      app.kubernetes.io/name: bifrost
      app.kubernetes.io/instance: bifrost
  endpoints:
  - port: http
    path: /metrics
    interval: 15s
    scrapeTimeout: 10s
```

```bash
kubectl apply -f 03-bifrost-servicemonitor.yaml
```

Confirmed metrics in Bifrost v1.5:

- `bifrost_upstream_requests_total` — requests routed to upstream providers
- `bifrost_success_requests_total` — successful upstream responses
- `bifrost_input_tokens_total` — input tokens consumed
- `bifrost_output_tokens_total` — output tokens generated
- `bifrost_upstream_latency_seconds_bucket/count/sum` — upstream latency histogram

All metrics include `provider`, `model`, and `key_name` labels.

-----

## Test Scenarios

### Scenario 1: Mocker Plugin — Zero-Egress Smoke Test

Configure a Mock provider via the web UI (http://localhost:8080). Validates the full request/response path, virtual key enforcement, and log capture with no live API keys or egress.

```bash
# Create a virtual key via UI first, then:
curl -s -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: <your-virtual-key>" \
  -d '{
    "model": "mock/mock-model",
    "messages": [{"role": "user", "content": "test request"}]
  }' | jq .
```

Expected: structured response from the mock provider, request visible in the built-in dashboard.

-----

### Scenario 2: Provider Failover

Configure two providers (e.g., OpenAI primary with an intentionally invalid key, Anthropic as fallback with a valid key). Proves the failover chain before any production dependency.

```bash
curl -s -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: <your-virtual-key>" \
  -d '{
    "model": "openai/llama3.2:3b",
    "messages": [{"role": "user", "content": "failover test"}]
  }' | jq '{provider: .extra_fields.provider, response: .choices[0].message.content}'

# Check upstream request counters
curl -s http://localhost:8080/metrics | grep bifrost_upstream_requests_total
```

-----

### Scenario 3: Budget Enforcement

Create two virtual keys with different token budgets via the UI. Exhaust one key with rapid requests, confirm it is blocked while the other key continues operating.

```bash
#!/usr/bin/env zsh
GATEWAY="http://localhost:8080"
PAYLOAD='{"model":"mock/mock-model","messages":[{"role":"user","content":"budget test"}]}'

echo "==> Exhausting low-budget key..."
for i in {1..20}; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$GATEWAY/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "X-Api-Key: $BIFROST_KEY_LOW_BUDGET" \
    -d "$PAYLOAD")
  echo "Request $i: HTTP $STATUS"
done

echo ""
echo "==> Testing high-budget key (should still work)..."
curl -s -X POST "$GATEWAY/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_KEY_HIGH_BUDGET" \
  -d "$PAYLOAD" | jq '.choices[0].message.content // .error'
```

-----

### Scenario 4: Semantic Caching with Qdrant

Deploy Qdrant in-cluster, configure Bifrost to use it as the vector store, then validate cache hits with semantically similar prompts.

```bash
helm repo add qdrant https://qdrant.github.io/qdrant-helm
helm repo update
helm install qdrant qdrant/qdrant \
  --namespace ai-gateway \
  --set replicaCount=1 \
  --set resources.requests.memory=256Mi \
  --set resources.requests.cpu=100m
```

Configure in Bifrost UI:

```json
{
  "vector_store": {
    "type": "qdrant",
    "config": {
      "host": "qdrant.ai-gateway.svc.cluster.local",
      "port": 6333,
      "collection": "bifrost-cache",
      "similarity_threshold": 0.92
    }
  }
}
```

```bash
#!/usr/bin/env zsh
GATEWAY="http://localhost:8080"
KEY="$BIFROST_VIRTUAL_KEY"

send() {
  curl -s -X POST "$GATEWAY/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "X-Api-Key: $KEY" \
    -d "{\"model\":\"openai/qwen2.5:7b\",\"messages\":[{\"role\":\"user\",\"content\":\"$1\"}]}" \
    -w "\nHTTP: %{http_code}, Time: %{time_total}s\n"
}

echo "==> First request (cache miss expected):"
send "What is the capital of France?"

echo ""
echo "==> Semantically similar request (cache hit expected):"
send "Can you tell me France's capital city?"
```

-----

### Scenario 5: Prometheus Metrics Validation

```bash
#!/usr/bin/env zsh
GATEWAY="http://localhost:8080"

echo "==> Bifrost metrics:"
curl -s "$GATEWAY/metrics" | grep "^bifrost_" | sort

echo ""
echo "==> Key metrics (v1.5 confirmed):"
curl -s "$GATEWAY/metrics" | grep -E \
  "bifrost_upstream_requests_total|bifrost_success_requests_total|bifrost_input_tokens_total|bifrost_output_tokens_total|bifrost_upstream_latency"
```

Validate via Prometheus (port-forward to `localhost:9090`):

```promql
# Request rate by model
rate(bifrost_upstream_requests_total[5m])

# Success rate
rate(bifrost_success_requests_total[5m]) /
  rate(bifrost_upstream_requests_total[5m])

# p99 upstream latency by model
histogram_quantile(0.99,
  sum(rate(bifrost_upstream_latency_seconds_bucket[5m])) by (le, provider, model)
)

# Token throughput
sum(rate(bifrost_input_tokens_total[5m]) + rate(bifrost_output_tokens_total[5m]))
  by (provider, model)
```

See [Prometheus MCP Server — Deployment & Demo Guide](Prometheus%20MCP%20Server%20—%20Deployment%20%26%20Demo%20Guide.md) for the full Prometheus integration setup including the ServiceMonitor, prometheus-mcp-server deployment, and Postman collection.

-----

### Scenario 6: MCP Gateway Integration — Kubernetes MCP Server

Registers the kubernetes MCP server running as a LaunchAgent on the Mac host as a
Bifrost MCP server, routing all tool calls through Bifrost with virtual key governance.

#### Architecture

```
Bifrost Pod (ai-gateway namespace, kind cluster)
    │ JSON-RPC 2.0
    ▼
kubernetes-mcp-server (SSE, Mac host :8811)
    │ kubectl API calls
    ▼
kind cluster API server
```

The Mac's LAN IP (`192.168.1.21`) is directly reachable from kind pods via Docker Desktop
network bridging — no proxy pod or Service+Endpoints manifest required.

#### Step 1 — Start the MCP server as a LaunchAgent

The server runs as a macOS LaunchAgent and starts automatically on login.
The plist is at `scripts/com.local.mcp-kubernetes-sse.plist` in this repo.

```bash
# Load the LaunchAgent
launchctl load ~/Library/LaunchAgents/com.local.mcp-kubernetes-sse.plist

# Verify it started
launchctl list | grep mcp-kubernetes
tail -20 /tmp/mcp-kubernetes-sse.log
```

The server listens on `0.0.0.0:8811`. Verify from the Mac:

```bash
curl -v --max-time 5 http://localhost:8811/sse
# Expected: event: endpoint
#           data: /sse?sessionId=<uuid>
```

#### Step 2 — Verify reachability from inside the Bifrost pod

```bash
kubectl exec -n ai-gateway bifrost-0 -- \
  wget -qO- http://192.168.1.21:8811/sse --timeout=3 2>&1 | head -3
# Expected: event: endpoint
```

#### Step 3 — Register in Bifrost UI

Navigate to **http://localhost:8080 → MCP Gateway → MCP Catalog → New MCP Server**:

| Field | Value |
|---|---|
| Name | `new_kubernetes_local` |
| Connection Type | Server-Sent Events (SSE) |
| Connection URL | `http://192.168.1.21:8811/sse` |
| Authentication Type | None |

> The previous entry `kubernetes_local` was disconnected due to an incorrect SSE URL
> and could not be edited in the Bifrost UI — a new entry `new_kubernetes_local` was
> created. All tool names carry the `new_kubernetes_local-` prefix accordingly.

After saving, verify 20 tools are registered:

```bash
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: <your-admin-key>" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' \
  | jq '[.result.tools[].name | select(startswith("new_kubernetes_local"))] | length'
# Expected: 20
```

#### Step 4 — Scope the virtual key allow-list

In Bifrost UI → **Keys → your key → Edit → MCP Tools**.

Restricted key (read-only, 7 tools):

```
new_kubernetes_local-events_list
new_kubernetes_local-namespaces_list
new_kubernetes_local-pods_get
new_kubernetes_local-pods_list
new_kubernetes_local-pods_list_in_namespace
new_kubernetes_local-resources_get
new_kubernetes_local-resources_list
```

Admin key has access to all 20 tools including destructive operations
(`pods_delete`, `pods_exec`, `resources_scale`, `resources_create_or_update`, `resources_delete`).

#### Step 5 — Validate allowed tool call

```bash
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: <your-admin-key>" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
      "name": "new_kubernetes_local-pods_list_in_namespace",
      "arguments": {"namespace": "ai-gateway"}
    }
  }' | jq -r '.result.content[0].text'
# Expected: live pod list including bifrost-0
```

#### Step 6 — Validate governance block (restricted key)

```bash
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: <your-restricted-key>" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {
      "name": "new_kubernetes_local-pods_delete",
      "arguments": {"name": "bifrost-0", "namespace": "ai-gateway"}
    }
  }' | jq '.error'
# Expected: {"code": -32602, "message": "tool 'new_kubernetes_local-pods_delete' not found: tool not found"}
```

The call is rejected at Bifrost — the MCP server is never contacted.

#### Troubleshooting

| Issue | Root cause | Fix |
|---|---|---|
| SSE disconnected in Bifrost UI | LaunchAgent restarted | Check `launchctl list \| grep mcp` and `tail /tmp/mcp-kubernetes-sse.log` |
| Tool not found | Wrong prefix used | All tools use `new_kubernetes_local-` prefix |
| `192.168.1.21` unreachable from pod | Mac LAN IP changed (DHCP) | Run `ipconfig getifaddr en0` and update Bifrost server URL |
| `x-bf-mcp-include-clients` not routing | Wrong client name | Use `new_kubernetes_local` (the Bifrost server name) |

-----

### Scenario 7: Full Teardown (Dry-run Default)

```bash
#!/usr/bin/env zsh
# teardown-bifrost.sh
# Dry-run by default. Pass --apply to actually delete.

DRY_RUN=true
[[ "$1" == "--apply" ]] && DRY_RUN=false

NS="ai-gateway"

if $DRY_RUN; then
  echo "[DRY-RUN] helm uninstall bifrost --namespace $NS"
  echo "[DRY-RUN] kubectl -n $NS delete secret bifrost-encryption-key"
  echo "[DRY-RUN] kubectl -n monitoring delete servicemonitor bifrost"
  echo "[DRY-RUN] kubectl delete namespace $NS"
  echo "[DRY-RUN] launchctl unload ~/Library/LaunchAgents/com.local.mcp-kubernetes-sse.plist"
  echo ""
  echo "Re-run with --apply to execute."
else
  helm uninstall bifrost --namespace $NS
  kubectl -n $NS delete secret bifrost-encryption-key --ignore-not-found=true
  kubectl -n monitoring delete servicemonitor bifrost --ignore-not-found=true
  kubectl delete namespace $NS --ignore-not-found=true
  launchctl unload ~/Library/LaunchAgents/com.local.mcp-kubernetes-sse.plist 2>/dev/null
fi
```

-----

## Verdict

### OSS

Legitimate production-grade gateway for non-regulated or internal workloads. Performance, governance primitives, and observability in the free tier are genuinely strong. Good fit for developer tooling, internal AI APIs, and PoC/evaluation work.

### Enterprise (regulated / financial context)

Enterprise tier is effectively required — SAML, audit logs, guardrails, and vault integration are table-stakes for infosec sign-off. Opaque pricing and absent public ZDR/encryption documentation require formal vendor engagement before any procurement conversation. Request SOC 2 Type II report and written data handling confirmation upfront.

### vs LiteLLM

Materially faster, better Go-native k8s fit, lower memory footprint. Younger project with smaller community. Python shop familiarity advantage goes to LiteLLM.

### vs Kong AI Gateway

Far simpler to operate — no Lua expertise, no NGINX-level resource overhead, no separate database required for basic operation. Bifrost wins on simplicity and AI-specific feature depth. Kong wins if you already have Kong in the stack and need general API management + AI in one platform.

### kind/k3d Development Loop

The Mocker plugin + kind combination is a clean, zero-cost dev loop. The full routing/governance/observability stack can be exercised without live API spend or external egress — the right approach for evaluating before any enterprise commercial conversation.

-----

*Review compiled April 2026, updated May 2026. Benchmark figures are vendor-published — independent validation recommended before use in procurement decisions.*
