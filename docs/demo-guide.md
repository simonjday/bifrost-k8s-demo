# Bifrost MCP Gateway — Demo Guide

> **Clusters:** k3d-demo / kind-devops-lab (auto-detected)
> **Date:** May 2026
> **Bifrost version:** v1.5.0-prerelease7

---

## Pre-Requisites

### 1 — Infrastructure running

| Component | Check | Expected |
|---|---|---|
| Bifrost StatefulSet | `kubectl -n ai-gateway get pods` | `bifrost-0` Running |
| Port-forward | `curl -s http://localhost:8080/health` | `{"status":"ok"}` |
| MCP SSE server | `curl -s --max-time 2 http://localhost:8811/sse` | `event: endpoint` |
| MCP Service | `kubectl -n ai-gateway get svc mcp-kubernetes-sse` | ClusterIP present |
| MCP Endpoints (k3d) | `kubectl -n ai-gateway get endpoints mcp-kubernetes-sse` | `192.168.1.21:8811` |
| MCP Endpoints (kind) | `kubectl -n ai-gateway get endpoints mcp-kubernetes-sse` | `192.168.65.254:8811` via socat proxy |

Start anything missing:

```bash
# Port-forward (if not running)
kubectl -n ai-gateway port-forward svc/bifrost 8080:8080 &

# SSE server (if not running)
ENABLE_UNSAFE_SSE_TRANSPORT=1 PORT=8811 HOST=0.0.0.0 \
  npx -y kubernetes-mcp-server@latest &
```

### 2 — Bifrost configured

**Provider:** At least one LLM provider key registered in Bifrost UI → Providers.

```bash
curl -s http://localhost:8080/api/providers | jq '[.providers[].name]'
# Expected: ["anthropic"] or ["openai"] etc.
```

**MCP server:** `kubernetes_local` registered and connected.

```bash
curl -s http://localhost:8080/api/mcp/clients \
  | jq '{name: .clients[0].config.name, state: .clients[0].state, tools: (.clients[0].tools | length)}'
# Expected: name=kubernetes_local, state=connected, tools=19
```

**Virtual key:** Set and exported.

```bash
echo $BIFROST_VIRTUAL_KEY
# Must not be empty — get from Bifrost UI → Keys
export BIFROST_VIRTUAL_KEY="vk_your_key_here"
```

### 3 — Demo namespace and workloads

The `goose-test` namespace is a purpose-built demo namespace containing a mix
of healthy and unhealthy workloads to drive the diagnosis demos:

| Workload | State | Why |
|---|---|---|
| `good-app` | ✅ Healthy | Pinned digest, probes, non-root security context |
| `bad-app` | ⚠️ Policy violations | `nginx:latest` tag, no probes, Kyverno violations |
| `ugly-app` | ⚠️ Policy violations | `:latest` tag, no probes, policy violations |
| `single-app` | ⚠️ Security risk | Runs as root, `allowPrivilegeEscalation: true` |
| `scheduled-job` | ✅ CronJob | Completing successfully hourly |
| `completed-job` | ✅ Job | Completed |

Verify the namespace is in the expected state:

```bash
kubectl -n goose-test get pods
```

If `bad-app` pods are Running and healthy rather than crashlooping, force it:

```bash
kubectl -n goose-test set image deployment/bad-app bad-app=busybox -- sh -c "exit 1"
```

Create additional broken pods for Demo 3 if needed:

```bash
# Standalone crashlooping pod
kubectl -n default run crash-demo \
  --image=busybox --restart=Always \
  -- sh -c "echo 'starting'; sleep 2; exit 1"

# Pending pod (simulates resource pressure / unschedulable)
kubectl -n default run pending-demo \
  --image=nginx --restart=Never \
  --overrides='{
    "spec": {
      "containers": [{"name":"pending-demo","image":"nginx","resources":{"requests":{"cpu":"99","memory":"99Gi"}}}],
      "nodeSelector": {"non-existent-label": "true"}
    }
  }'
```

### 4 — Confirm CRDs available for Demos 4 and 8

```bash
# Argo CD Applications
kubectl -n argocd get applications --no-headers | wc -l
# Expected: 5+

# Kargo Stages
kubectl -n platform-demo get stages.kargo.akuity.io
# Expected: dev, staging, prod
```

### 5 — Ollama running (for Demos 8 and 9)

Ollama must be bound to all interfaces and reachable from inside the cluster.
Full setup is covered in [docs/ollama-bifrost-setup.md](ollama-bifrost-setup.md).

Quick check:

```bash
# Confirm Ollama is listening on all interfaces
lsof -i :11434 | grep '\*'

# Confirm reachable from Mac
curl -s http://localhost:11434/api/tags | jq '[.models[].name]'

# Confirm reachable from cluster (use correct IP for your cluster type)
# k3d:
kubectl -n ai-gateway exec -it bifrost-0 -- wget -qO- http://192.168.1.21:11434/api/tags
# kind:
kubectl -n ai-gateway exec -it bifrost-0 -- wget -qO- http://192.168.65.254:11434/api/tags
```

### 6 — Cleanup (run after demo)

```bash
kubectl -n default delete pod crash-demo --ignore-not-found=true
kubectl -n default delete pod pending-demo --ignore-not-found=true
```

---

## Key API Facts (applies to all demos)

| Item | Value |
|---|---|
| MCP JSON-RPC endpoint | `POST http://localhost:8080/mcp` |
| LLM completions endpoint | `POST http://localhost:8080/v1/chat/completions` |
| Auth header | `X-Api-Key: $BIFROST_VIRTUAL_KEY` |
| MCP client filter header | `x-bf-mcp-include-clients: kubernetes_local` |
| Tool name format | `kubernetes_local-<toolname>` |
| `mcp_servers` body field | ❌ Does not exist — use `x-bf-mcp-include-clients` header |
| Agent mode | Configure `tools_to_auto_execute: ["*"]` on the MCP client via PUT /api/mcp/client/{id} — there is no `x-bf-agent-mode` request header |
| Anthropic model string | `anthropic/claude-sonnet-4-5-20250929` |
| Ollama model prefix | `openai/<modelname>` e.g. `openai/qwen2.5:7b` |
| Ollama provider type | `openai` (NOT `ollama`) |
| Ollama base URL (k3d) | `http://192.168.1.21:11434` — no `/v1` suffix |
| Ollama base URL (kind) | `http://192.168.65.254:11434` — no `/v1` suffix |

---

## Demo 1: Cluster Health Triage (LLM-driven)

**Narrative:** On-call engineer asks the AI to triage the cluster. Bifrost injects
all registered read-only k8s tools into the completion — the LLM decides which
tools to call, results are synthesised into a structured incident report.

**Pre-req state:** `crash-demo` and `pending-demo` pods created (see pre-reqs).

```bash
curl -s -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -H "x-bf-mcp-include-clients: kubernetes_local" \
  -d '{
    "model": "anthropic/claude-sonnet-4-5-20250929",
    "messages": [{
      "role": "user",
      "content": "Triage the cluster. Check for any warning events, pods not in Running state, and node resource pressure. Give me a structured summary with severity ratings."
    }]
  }' | jq -r '.choices[0].message.content'
```

**Talking point:** The LLM autonomously called `events_list`, `pods_list`, and
`nodes_top` — Bifrost enforced the allow-list throughout. `pods_delete` was never
available even if the model had tried.

---

## Demo 2: Namespace Cost Attribution

**Narrative:** Platform team querying resource consumption across all namespaces
for internal chargeback. No kubectl, no direct cluster access.

**Pre-req state:** None — cluster is live.

```bash
# Step 1 — list namespaces
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"kubernetes_local-namespaces_list","arguments":{}}}' \
  | jq -r '.result.content[0].text'
```

```bash
# Step 2 — resource consumption across all namespaces
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"kubernetes_local-pods_top","arguments":{"all_namespaces":true}}}' \
  | jq -r '.result.content[0].text'
```

**Talking point:** Both calls appear in the Bifrost dashboard (`http://localhost:8080`
→ Logs) with tool name, virtual key, and latency — full audit trail for every
resource query with zero kubectl on the operator's terminal.

---

## Demo 3: CrashLoopBackOff Diagnosis

**Narrative:** A pod is crashing. Walk through diagnosis — pod state, current
and previous container logs, namespace events — all through Bifrost.

**Pre-req state:** `crash-demo` pod created in `default` namespace, or use
existing `bad-app` pods in `goose-test`.

```bash
# Step 1 — list pods to get the actual generated pod name
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"kubernetes_local-pods_list_in_namespace","arguments":{"namespace":"goose-test"}}}' \
  | jq -r '.result.content[0].text'
```

> **Note:** Pod names include a replicaset hash suffix (e.g. `bad-app-799c448d6b-7xlqq`)
> and change on every redeploy. Always run `pods_list_in_namespace` first to get
> the current name before calling `pods_get` or `pods_log`.

```bash
# Step 2 — get pod detail (substitute actual pod name from step 1)
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"kubernetes_local-pods_get","arguments":{"name":"bad-app-799c448d6b-7xlqq","namespace":"goose-test"}}}' \
  | jq -r '.result.content[0].text'
```

```bash
# Step 3 — pod logs (last 50 lines)
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"kubernetes_local-pods_log","arguments":{"name":"bad-app-799c448d6b-7xlqq","namespace":"goose-test","tail":50}}}' \
  | jq -r '.result.content[0].text'
```

```bash
# Step 4 — namespace events (shows restart history, probe failures, OOMKill)
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -d '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"kubernetes_local-events_list","arguments":{"namespace":"goose-test"}}}' \
  | jq -r '.result.content[0].text'
```

---

## Demo 4: Argo CD Application Status via CRDs

**Narrative:** Query Argo CD Application resources — no argocd CLI, no direct
cluster access. Uses `resources_list` with custom CRDs.

**Pre-req state:** None — Argo CD Applications are live and healthy.

```bash
# List all Argo CD Applications with sync/health status
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"kubernetes_local-resources_list","arguments":{"apiVersion":"argoproj.io/v1alpha1","kind":"Application","namespace":"argocd"}}}' \
  | jq -r '.result.content[0].text'
```

```bash
# Get a specific Application in detail
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"kubernetes_local-resources_get","arguments":{"apiVersion":"argoproj.io/v1alpha1","kind":"Application","name":"podinfo","namespace":"argocd"}}}' \
  | jq -r '.result.content[0].text'
```

**Talking point:** The consumer never needed argocd CLI or cluster credentials.
Bifrost proxied the CRD query with full audit logging. The same pattern works for
any CRD — KafkaTopic, SchemaRegistry, Kargo Stage — without any gateway reconfiguration.

---

## Demo 5: Governance Boundary (Destructive Tools Blocked)

**Narrative:** Developer has a read-only key. They attempt three destructive
operations. All are blocked at Bifrost — the MCP server is never contacted.

**Pre-req state:** Virtual key configured with read-only tool allow-list.

```bash
# Attempt 1 — delete a pod
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"kubernetes_local-pods_delete","arguments":{"name":"bifrost-0","namespace":"ai-gateway"}}}' \
  | jq '{attempt: "pods_delete", result: .error.message}'
```

```bash
# Attempt 2 — scale a StatefulSet to zero
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"kubernetes_local-resources_scale","arguments":{"apiVersion":"apps/v1","kind":"StatefulSet","name":"bifrost","namespace":"ai-gateway","scale":0}}}' \
  | jq '{attempt: "resources_scale", result: .error.message}'
```

```bash
# Attempt 3 — exec into a pod
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"kubernetes_local-pods_exec","arguments":{"name":"bifrost-0","namespace":"ai-gateway","command":["cat","/etc/passwd"]}}}' \
  | jq '{attempt: "pods_exec", result: .error.message}'
```

All three return `tool not found`. Open the Bifrost Logs tab to show the blocked
attempts were recorded with the virtual key that made them.

**Talking point:** The MCP server never received these requests. Bifrost enforced
the allow-list before any downstream call was made — every blocked attempt is
logged with the key identity, timestamp, and tool name.

---

## Demo 6: Kargo Pipeline Status

**Narrative:** Query the Kargo promotion pipeline — current freight, stage health,
and promotion status across dev/staging/prod.

**Pre-req state:** Kargo installed with dev/staging/prod stages in `platform-demo`.

```bash
# List Kargo Stages
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"kubernetes_local-resources_list","arguments":{"apiVersion":"kargo.akuity.io/v1alpha1","kind":"Stage","namespace":"platform-demo"}}}' \
  | jq -r '.result.content[0].text'
```

```bash
# Get prod stage detail — current freight, health, last verified
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"kubernetes_local-resources_get","arguments":{"apiVersion":"kargo.akuity.io/v1alpha1","kind":"Stage","name":"prod","namespace":"platform-demo"}}}' \
  | jq -r '.result.content[0].text'
```

```bash
# List Freight in the pipeline
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"kubernetes_local-resources_list","arguments":{"apiVersion":"kargo.akuity.io/v1alpha1","kind":"Freight","namespace":"platform-demo"}}}' \
  | jq -r '.result.content[0].text'
```

**Talking point:** GitOps pipeline state — Argo CD sync status, Kargo promotion
health, cross-environment freight tracking — all queryable through one governed
endpoint. No argocd CLI, no kargo CLI, no cluster credentials given to the consumer.

---

## Demo 7: LLM-Driven Multi-Step Diagnosis (Agent Mode)

**Narrative:** Ask the LLM to investigate the `goose-test` namespace — a mix of
healthy and unhealthy workloads. The LLM calls multiple tools autonomously and
returns a full structured diagnosis.

**Pre-req state:** `goose-test` namespace live with mixed-health deployments.
`tools_to_auto_execute` must be set on the MCP client (one-time setup):

```bash
curl -s -X PUT "http://localhost:8080/api/mcp/client/6bb088d2-d4b4-42d2-8801-97f06c4579d1" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "kubernetes_local",
    "connection_type": "sse",
    "connection_string": "http://mcp-kubernetes-sse.ai-gateway.svc.cluster.local:8811/sse",
    "auth_type": "none",
    "tools_to_execute": ["*"],
    "tools_to_auto_execute": ["*"],
    "is_ping_available": true
  }' | jq .

# Verify
curl -s http://localhost:8080/api/mcp/clients \
  | jq '.clients[0].config | {tools_to_execute, tools_to_auto_execute}'
```

```bash
curl -s -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -H "x-bf-mcp-include-clients: kubernetes_local" \
  -d '{
    "model": "anthropic/claude-sonnet-4-5-20250929",
    "messages": [{
      "role": "user",
      "content": "Investigate the goose-test namespace. I have a mix of healthy and unhealthy workloads in there. List the pods, check their resource consumption, and look for any warning events. Tell me which apps are healthy, which are not, and what the likely cause is."
    }]
  }' | jq -r '.choices[0].message.content'
```

**What Bifrost does internally:**
1. Sends completion request to Anthropic — LLM returns `tool_calls` for `pods_list_in_namespace`, `pods_top`, `events_list`
2. Bifrost executes all three tools against the MCP server automatically (no client roundtrip needed)
3. Feeds results back to the LLM for synthesis
4. Returns the final `stop` response with the full diagnosis

**Validated output (May 2026, live cluster):**

| Workload | Status | Diagnosis |
|---|---|---|
| `good-app` | ✅ Healthy | 3 replicas, pinned digest, probes, non-root |
| `bad-app` | ⚠️ Violations | `nginx:latest`, no probes, Kyverno policy violations |
| `ugly-app` | ⚠️ Violations | `:latest` tag, no probes, policy violations |
| `single-app` | ⚠️ Security risk | Runs as root, `allowPrivilegeEscalation: true` |
| `scheduled-job` | ✅ CronJob | Completing successfully hourly |
| `completed-job` | ✅ Job | Completed |

**Talking point:** `finish_reason` is `stop` not `tool_calls` — the full agentic
loop ran inside Bifrost. Three tool calls, zero client roundtrips, full audit trail
in the Bifrost Logs tab.

---

## Demo 8: Local vs Cloud Model Comparison

**Narrative:** Run the same cluster investigation query against a local Ollama
model and Anthropic Claude side by side. Show the quality/cost/latency tradeoff
— both going through the same Bifrost endpoint, same governance, same MCP tools.

**Pre-req state:** Ollama running with `OLLAMA_HOST=0.0.0.0`, `qwen3-coder:30b`
pre-warmed, `openai` provider registered in Bifrost.

> See [docs/ollama-bifrost-setup.md](ollama-bifrost-setup.md) for full Ollama setup steps.

```bash
echo "=== LOCAL: qwen2.5:7b (fast, zero cost) ==="
time curl -s -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -H "x-bf-mcp-include-clients: kubernetes_local" \
  -d '{"model":"openai/qwen2.5:7b","messages":[{"role":"user","content":"Investigate the goose-test namespace and tell me which apps are unhealthy."}]}' \
  | jq -r '.choices[0].message.content'

echo ""
echo "=== LOCAL: qwen3-coder:30b (best local quality, zero cost) ==="
time curl -s -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -H "x-bf-mcp-include-clients: kubernetes_local" \
  -d '{"model":"openai/qwen3-coder:30b","messages":[{"role":"user","content":"Investigate the goose-test namespace and tell me which apps are unhealthy."}]}' \
  | jq -r '.choices[0].message.content'

echo ""
echo "=== CLOUD: claude-sonnet-4-5 (~$0.003/call) ==="
time curl -s -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -H "x-bf-mcp-include-clients: kubernetes_local" \
  -d '{"model":"anthropic/claude-sonnet-4-5-20250929","messages":[{"role":"user","content":"Investigate the goose-test namespace and tell me which apps are unhealthy."}]}' \
  | jq -r '.choices[0].message.content'
```

**Validated results (May 2026):**

| Model | Latency | Quality |
|---|---|---|
| `qwen2.5:7b` | ~2s | Basic pod listing, simple identification |
| `qwen3-coder:30b` | ~18s | Identifies bad-app and scheduled-job issues, misses policy detail |
| `claude-sonnet-4-5-20250929` | ~4.5s | Full diagnosis: Kyverno violations, missing probes, security context, root cause per app |

**Talking point:** Same endpoint, same virtual key, same MCP tool governance —
swap one field in the request body to choose between free local inference and
cloud-quality diagnosis. Bifrost abstracts the routing completely.

---

## Demo 9: Ollama Fast Query (Sub-2s Local Inference)

**Narrative:** Show a sub-2-second namespace list using the local 7B model.
Demonstrates that not every query needs a cloud model or incurs API cost.

```bash
curl -s -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -H "x-bf-mcp-include-clients: kubernetes_local" \
  -d '{
    "model": "openai/qwen2.5:7b",
    "messages": [{"role":"user","content":"List all namespaces in the cluster and categorise them as system, infrastructure, or application namespaces."}]
  }' | jq -r '.choices[0].message.content'
```

**Validated output:** All namespaces returned and correctly categorised from a
single `namespaces_list` tool call. Latency ~1.5–2s.

---

## Suggested Demo Order

| Order | Demo | Duration | Key message |
|---|---|---|---|
| 1 | **Demo 5** — Governance block | 2 min | Opens with security — sets the tone |
| 2 | **Demo 9** — Ollama fast query | 2 min | Sub-2s local inference, zero cost |
| 3 | **Demo 2** — Cost attribution | 3 min | Observability and audit trail |
| 4 | **Demo 4** — Argo CD CRDs | 3 min | Not just core k8s — any CRD |
| 5 | **Demo 3** — CrashLoopBackOff | 4 min | Real operational workflow |
| 6 | **Demo 7** — LLM multi-step diagnosis | 5 min | Agentic value prop |
| 7 | **Demo 8** — Local vs Cloud comparison | 5 min | Quality/cost tradeoff, same endpoint |
| 8 | **Demo 1** — Cluster triage | 4 min | Closes with the full picture |

---

## Quick Reference — Tool Names

```
kubernetes_local-configuration_view
kubernetes_local-namespaces_list
kubernetes_local-events_list
kubernetes_local-nodes_top
kubernetes_local-nodes_stats_summary
kubernetes_local-pods_get
kubernetes_local-pods_list
kubernetes_local-pods_list_in_namespace
kubernetes_local-pods_log
kubernetes_local-pods_top
kubernetes_local-resources_get
kubernetes_local-resources_list
```

> Run `tools/list` via the MCP endpoint to confirm the full current list including
> any newly added tools.

---

## Ollama Models Reference

Full setup is in [docs/ollama-bifrost-setup.md](ollama-bifrost-setup.md). Quick reference:

| Model string | Size | Best for |
|---|---|---|
| `openai/qwen2.5:7b` | 7B | Fast general queries |
| `openai/qwen2.5-coder:7b` | 7B | Code and k8s tasks |
| `openai/qwen2.5-coder:1.5b-base` | 1.5B | Minimal, very fast, basic tasks |
| `openai/qwen3-coder:30b` | 30B | Best local quality, complex diagnosis |
| `openai/llama3.2:3b` | 3B | Very fast, simple queries only |
| `openai/gemma4:latest` | 8B | General purpose |

**Pre-warm before demos (first call on large models takes 30–60s):**

```bash
ollama run qwen3-coder:30b "hello" && exit
```

---

## Ollama Gotchas

| Issue | Root cause | Fix |
|---|---|---|
| Empty response from in-cluster connectivity test | Ollama bound to `localhost` only | `OLLAMA_HOST=0.0.0.0 ollama serve` — see setup doc |
| `404 page not found` | Wrong provider type — native `ollama` type hits `/api/chat` | Register as `openai` provider type |
| `404 page not found` with `openai` type | Double `/v1` path — base URL had `/v1` suffix | Remove `/v1` from base URL — use `http://<IP>:11434` only |
| `model_blocked 403` | Virtual key `allowed_models` missing Ollama model names | Add `openai/*` to allowed_models on virtual key |
| `keys: []` on openai provider config | UI adds provider config but doesn't link the key | Use PUT API with explicit `key_id` to force linkage |
| `Method Not Allowed` on DELETE /api/provider | Bifrost API doesn't support provider DELETE | Use Bifrost UI → Providers → Delete |
| First call slow (30–60s) on large models | Ollama loading model into memory | Pre-warm: `ollama run qwen3-coder:30b "hello"` before demo |
| kind cluster: model unreachable | Using Mac LAN IP instead of Docker gateway | Use `192.168.65.254` not `192.168.1.21` for kind |

---

*Compiled May 2026 from live cluster state — kind-devops-lab and k3d-demo.*
