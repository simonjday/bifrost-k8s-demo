# Bifrost MCP Gateway — Demo Guide

> **Cluster:** k3d-demo
> **Date:** April 2026
> **Bifrost version:** v1.5.0-prerelease4

---

## Pre-Requisites

### 1 — Infrastructure running

| Component | Check | Expected |
|---|---|---|
| Bifrost StatefulSet | `kubectl -n ai-gateway get pods` | `bifrost-0` Running |
| Port-forward | `curl -s http://localhost:8080/health` | `{"status":"ok"}` |
| MCP SSE server | `curl -s --max-time 2 http://localhost:8811/sse` | `event: endpoint` |
| MCP Service | `kubectl -n ai-gateway get svc mcp-kubernetes-sse` | ClusterIP present |
| MCP Endpoints | `kubectl -n ai-gateway get endpoints mcp-kubernetes-sse` | `192.168.1.21:8811` |

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

**Virtual key:** Set with read-only tool allow-list and exported.

```bash
echo $BIFROST_VIRTUAL_KEY
# Must not be empty
```

If empty, get the key value from Bifrost UI → Keys and export:

```bash
export BIFROST_VIRTUAL_KEY="vk_your_key_here"
```

### 3 — Demo namespace and dodgy pods

The `goose-test` namespace already exists with `bad-app` (unhealthy) and `good-app`
(healthy) deployments. Verify they are in the expected state:

```bash
kubectl -n goose-test get pods
```

Expected — `bad-app` pods should be crashlooping or in a bad state. If not, force it:

```bash
# Confirm bad-app is actually bad (exits immediately)
kubectl -n goose-test describe deployment bad-app | grep -A5 "Containers:"
```

If `bad-app` pods are Running and healthy, patch the image to a broken one to
trigger CrashLoopBackOff for the demo:

```bash
kubectl -n goose-test set image deployment/bad-app bad-app=busybox \
  -- sh -c "exit 1"
```

Create additional broken pods for Demo 3 if needed:

```bash
# Standalone crashlooping pod for demo purposes
kubectl -n default run crash-demo \
  --image=busybox \
  --restart=Always \
  -- sh -c "echo 'starting'; sleep 2; exit 1"

# Wait for it to start crashlooping
kubectl -n default get pod crash-demo -w
```

Also create a pending pod (simulates resource pressure / unschedulable):

```bash
kubectl -n default run pending-demo \
  --image=nginx \
  --restart=Never \
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
# Expected: 12

# Kargo Stages
kubectl -n platform-demo get stages.kargo.akuity.io
# Expected: dev, staging, prod
```

### 5 — Cleanup commands (run after demo)

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
| Auth header (MCP) | `X-Api-Key: $BIFROST_VIRTUAL_KEY` |
| Auth header (completions) | `X-Api-Key: $BIFROST_VIRTUAL_KEY` |
| MCP client filter header | `x-bf-mcp-include-clients: kubernetes_local` |
| Tool name format | `kubernetes_local-<toolname>` |
| `mcp_servers` body field | ❌ Does not exist — use `x-bf-mcp-include-clients` header |
| Agent mode | ❌ `x-bf-agent-mode` header does NOT exist — configure `tools_to_auto_execute: ["*"]` on the MCP client via PUT /api/mcp/client/{id} |
| Confirmed model string | `anthropic/claude-sonnet-4-5-20250929` |
| Ollama model prefix | `openai/<modelname>` e.g. `openai/qwen2.5:7b` |
| Ollama provider type | `openai` (NOT `ollama`) — uses `/v1/chat/completions` path |
| Ollama base URL | `http://192.168.1.21:11434` — no `/v1` suffix |
| `x-bifrost-key` header | ❌ Wrong for MCP endpoint — use `X-Api-Key` |

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
      "content": "Triage the k3d-demo cluster. Check for any warning events, pods not in Running state, and node resource pressure. Give me a structured summary with severity ratings."
    }]
  }' | jq -r '.choices[0].message.content'
```

**Demo talking point:** The LLM autonomously called `events_list`, `pods_list`,
and `nodes_top` — Bifrost enforced the allow-list throughout. `pods_delete` was
never available even if the model had tried.

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
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
      "name": "kubernetes_local-namespaces_list",
      "arguments": {}
    }
  }' | jq -r '.result.content[0].text'
```

```bash
# Step 2 — resource consumption across all namespaces
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {
      "name": "kubernetes_local-pods_top",
      "arguments": {"all_namespaces": true}
    }
  }' | jq -r '.result.content[0].text'
```

**Demo talking point:** Both calls appear in the Bifrost dashboard (http://localhost:8080
→ Logs) with tool name, virtual key, and latency — full audit trail for every
resource query with zero kubectl on the operator's terminal.

**Top consumers on this cluster (known):** `gitea` (postgresql HA, pgpool),
`confluent` (Kafka, Schema Registry), `kyverno` (admission controller).

---

## Demo 3: CrashLoopBackOff Diagnosis

**Narrative:** A pod is crashing. Walk through diagnosis — pod state, current
and previous container logs, namespace events — all through Bifrost.

**Pre-req state:** `crash-demo` pod created in `default` namespace, or use
existing `bad-app` pods in `goose-test`.

```bash
# Step 1 — list pods to get the actual generated pod name (pods_get requires pod name not deployment name)
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
      "name": "kubernetes_local-pods_list_in_namespace",
      "arguments": {"namespace": "goose-test"}
    }
  }' | jq -r '.result.content[0].text'
```

Note the generated pod name from the output (e.g. `bad-app-799c448d6b-7xlqq`) — pod names include
the replicaset hash suffix and change on redeploy. Use the actual name from step 1 in steps 2 and 3.

```bash
# Step 2 — get pod detail (use actual pod name from step 1)
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {
      "name": "kubernetes_local-pods_get",
      "arguments": {"name": "bad-app-799c448d6b-7xlqq", "namespace": "goose-test"}
    }
  }' | jq -r '.result.content[0].text'
```

```bash
# Step 3 — pod logs (current and previous if restarted)
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -d '{
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": {
      "name": "kubernetes_local-pods_log",
      "arguments": {"name": "bad-app-799c448d6b-7xlqq", "namespace": "goose-test", "tail": 50}
    }
  }' | jq -r '.result.content[0].text'
```

```bash
# Step 4 — namespace events (shows restart history, probe failures, OOMKill etc.)
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -d '{
    "jsonrpc": "2.0",
    "id": 4,
    "method": "tools/call",
    "params": {
      "name": "kubernetes_local-events_list",
      "arguments": {"namespace": "goose-test"}
    }
  }' | jq -r '.result.content[0].text'
```

> **Note:** Pod names include a replicaset hash suffix (`bad-app-799c448d6b-7xlqq`) — always use
> `pods_list_in_namespace` first to get the current name. The hash changes on every new deployment.

---

## Demo 4: Argo CD Application Status via CRDs

**Narrative:** Query Argo CD Application resources — no argocd CLI, no direct
cluster access. Uses `resources_list` with custom CRDs.

**Pre-req state:** None — 12 Argo CD Applications are live and healthy.

```bash
# List all Argo CD Applications with sync/health status
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
      "name": "kubernetes_local-resources_list",
      "arguments": {
        "apiVersion": "argoproj.io/v1alpha1",
        "kind": "Application",
        "namespace": "argocd"
      }
    }
  }' | jq -r '.result.content[0].text'
```

```bash
# Get the platform-api-gateway-prod Application detail
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {
      "name": "kubernetes_local-resources_get",
      "arguments": {
        "apiVersion": "argoproj.io/v1alpha1",
        "kind": "Application",
        "name": "platform-api-gateway-prod",
        "namespace": "argocd"
      }
    }
  }' | jq -r '.result.content[0].text'
```

**Demo talking point:** Consumer never needed argocd CLI or cluster credentials.
Bifrost proxied the CRD query with full audit logging. The same pattern works for
any CRD: KafkaTopic, SchemaRegistry, KraftController, Kargo Stage.

---

## Demo 5: Governance Boundary (Destructive Tools Blocked)

**Narrative:** Developer has a read-only key. They attempt three destructive
operations. All blocked at Bifrost — the MCP server is never contacted.

**Pre-req state:** Virtual key configured with read-only allow-list (12 tools).

```bash
# Attempt 1 — delete a pod
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
      "name": "kubernetes_local-pods_delete",
      "arguments": {"name": "bifrost-0", "namespace": "ai-gateway"}
    }
  }' | jq '{attempt: "pods_delete", result: .error.message}'
```

```bash
# Attempt 2 — scale a StatefulSet to zero
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {
      "name": "kubernetes_local-resources_scale",
      "arguments": {
        "apiVersion": "apps/v1",
        "kind": "StatefulSet",
        "name": "bifrost",
        "namespace": "ai-gateway",
        "scale": 0
      }
    }
  }' | jq '{attempt: "resources_scale", result: .error.message}'
```

```bash
# Attempt 3 — exec into a pod
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -d '{
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": {
      "name": "kubernetes_local-pods_exec",
      "arguments": {
        "name": "bifrost-0",
        "namespace": "ai-gateway",
        "command": ["cat", "/etc/passwd"]
      }
    }
  }' | jq '{attempt: "pods_exec", result: .error.message}'
```

All three return `tool not found` — then open the Bifrost dashboard Logs tab to
show the blocked attempts were recorded with the virtual key that made them.

---

## Demo 6: Kargo Pipeline Status

**Narrative:** Query the Kargo promotion pipeline for `platform-demo` — current
freight, stage health, and promotion status across dev/staging/prod.

**Pre-req state:** None — Kargo is live with dev/staging/prod stages.

```bash
# List Kargo Stages for platform-demo
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
      "name": "kubernetes_local-resources_list",
      "arguments": {
        "apiVersion": "kargo.akuity.io/v1alpha1",
        "kind": "Stage",
        "namespace": "platform-demo"
      }
    }
  }' | jq -r '.result.content[0].text'
```

```bash
# Get dev stage detail (current freight, health, last verified)
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {
      "name": "kubernetes_local-resources_get",
      "arguments": {
        "apiVersion": "kargo.akuity.io/v1alpha1",
        "kind": "Stage",
        "name": "prod",
        "namespace": "platform-demo"
      }
    }
  }' | jq -r '.result.content[0].text'
```

```bash
# List Freight in the pipeline
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -d '{
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": {
      "name": "kubernetes_local-resources_list",
      "arguments": {
        "apiVersion": "kargo.akuity.io/v1alpha1",
        "kind": "Freight",
        "namespace": "platform-demo"
      }
    }
  }' | jq -r '.result.content[0].text'
```

**Demo talking point:** GitOps pipeline state — Argo CD sync status, Kargo
promotion health, cross-environment freight tracking — all queryable through one
governed Bifrost endpoint. No argocd CLI, no kargo CLI, no cluster credentials
handed to the consumer.

---

## Demo 7: LLM-Driven Multi-Step Diagnosis (Agent Mode)

**Narrative:** Ask the LLM to investigate the `goose-test` namespace which has
a mix of healthy (`good-app`) and unhealthy (`bad-app`, `ugly-app`) workloads.
The LLM calls three tools autonomously and returns a full structured diagnosis.

**Pre-req state:**
- `goose-test` namespace with mixed-health deployments (already live — `bad-app`, `ugly-app`, `good-app`, `single-app`)
- `tools_to_auto_execute` must be set on the MCP client (one-time setup):

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
2. Bifrost executes all three tools against the MCP server automatically (no client roundtrip)
3. Feeds results back to the LLM for synthesis
4. Returns the final `stop` response with the full diagnosis

**Confirmed output from live cluster (validated April 2026):**
- ✅ `good-app` — 3 replicas, Running, pinned digest, liveness/readiness probes, non-root security context
- ⚠️ `bad-app` — 2 replicas, Running but `nginx:latest`, no probes, Kyverno policy violations
- ⚠️ `ugly-app` — 2 replicas, Running but `:latest` tag, no probes, policy violations
- ⚠️ `single-app` — 1 replica, Running but runs as root, `allowPrivilegeEscalation: true`
- ✅ CronJob `scheduled-job` — completing successfully hourly
- ✅ Job `completed-job` — completed 3d ago

**Demo talking point:** `finish_reason` is `stop` not `tool_calls` — the full agentic loop
ran inside Bifrost. Three tool calls, zero client roundtrips, full audit trail in the
Bifrost dashboard logs.

---

## Demo 8: Multi-Tool Context — Pods + Argo CD Correlation

**Narrative:** A pod in `platform-prod` is consuming more memory than expected.
Use Bifrost to correlate the pod resource state with the Argo CD Application
that manages it — all in one session, one endpoint, one virtual key.

**Pre-req state:** None — `platform-prod` is live.

```bash
# Step 1 — resource consumption for platform-prod
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
      "name": "kubernetes_local-pods_top",
      "arguments": {"namespace": "platform-prod", "all_namespaces": false}
    }
  }' | jq -r '.result.content[0].text'
```

```bash
# Step 2 — check the Argo CD Application managing it
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {
      "name": "kubernetes_local-resources_get",
      "arguments": {
        "apiVersion": "argoproj.io/v1alpha1",
        "kind": "Application",
        "name": "platform-demo-prod",
        "namespace": "argocd"
      }
    }
  }' | jq -r '.result.content[0].text'
```

```bash
# Step 3 — check the Kargo Stage that promoted the current freight
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -d '{
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": {
      "name": "kubernetes_local-resources_get",
      "arguments": {
        "apiVersion": "kargo.akuity.io/v1alpha1",
        "kind": "Stage",
        "name": "prod",
        "namespace": "platform-demo"
      }
    }
  }' | jq -r '.result.content[0].text'
```

**Demo talking point:** Three different resource types — pods, Argo CD Application
CRD, Kargo Stage CRD — all through one governed endpoint. The consumer gets
a joined-up view of runtime state + GitOps state + promotion history without
needing credentials for any of the underlying systems.

---

## Suggested Demo Order

| Order | Demo | Duration | Impact |
|---|---|---|---|
| 1 | **Demo 5** — Governance block | 2 min | Opens with security — sets the tone |
| 2 | **Demo 10** — Ollama fast query | 2 min | Sub-2s local inference, zero cost |
| 3 | **Demo 2** — Cost attribution | 3 min | Shows observability and audit trail |
| 4 | **Demo 4** — Argo CD CRDs | 3 min | Proves it's not just core k8s |
| 5 | **Demo 3** — CrashLoopBackOff diagnosis | 4 min | Real operational workflow |
| 6 | **Demo 7** — LLM multi-step diagnosis | 5 min | Shows agentic value prop |
| 7 | **Demo 9** — Local vs Cloud comparison | 5 min | Quality/cost tradeoff, same endpoint |
| 8 | **Demo 8** — Multi-tool correlation | 4 min | Closes with the full picture |

---

## Quick Reference — All Tool Names

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

---

## Ollama Local Models via Bifrost

### Overview

Ollama exposes an OpenAI-compatible API at `http://localhost:11434/v1`. Bifrost
routes to it from inside k3d using the Mac's LAN IP (`192.168.1.21`) — the same
host bridge pattern used for the MCP SSE server.

**Available local models (validated April 2026):**

| Model string | Size | Best for |
|---|---|---|
| `openai/qwen2.5:7b` | 7B | Fast general queries, namespace/pod listing |
| `openai/qwen3-coder:30b` | 30B | Best local tool call quality, complex diagnosis |
| `openai/qwen2.5-coder:7b` | 7B | Code and k8s tasks |
| `openai/llama3.2:3b` | 3B | Very fast, simple queries only |
| `openai/gemma4:latest` | 8B | General purpose |
| `openai/qwen2.5-coder:1.5b-base` | 1.5B | Minimal, basic tasks |

> All Ollama models use the `openai/` prefix in the model string — they are
> registered under the `openai` provider type in Bifrost (see setup steps below).

---

### Setup Steps (exact sequence that worked)

#### Step 1 — Bind Ollama to all interfaces

By default Ollama only listens on `localhost`. Bifrost pods can't reach `localhost`
on the Mac — they need the LAN IP. Restart Ollama bound to all interfaces:

```bash
pkill ollama 2>/dev/null
OLLAMA_HOST=0.0.0.0 ollama serve &
```

To make this permanent (survives reboots):

```bash
launchctl setenv OLLAMA_HOST "0.0.0.0"
# Then restart Ollama from the menu bar
```

Verify from inside the Bifrost pod:

```bash
kubectl -n ai-gateway exec -it bifrost-0 -- \
  sh -c 'wget -qO- http://192.168.1.21:11434/api/tags 2>&1 | head -3'
```

Expected: JSON list of models. Empty response = Ollama still bound to localhost only.

#### Step 2 — Register Ollama as an `openai` provider in Bifrost UI

> ⚠️ **Do NOT use `ollama` as the provider type.** Bifrost's native `ollama`
> provider type hits Ollama's native `/api/chat` endpoint which uses a different
> request format. Use `openai` as the provider type instead — Bifrost then sends
> OpenAI-format requests to `/v1/chat/completions` which Ollama's compatibility
> layer understands.

> ⚠️ **Do NOT include `/v1` in the base URL.** Bifrost's `openai` provider type
> appends `/v1/chat/completions` internally. Setting
> `base_url: http://192.168.1.21:11434/v1` produces a double path:
> `http://192.168.1.21:11434/v1/v1/chat/completions` → `404 page not found`.
> The correct base URL is `http://192.168.1.21:11434` with no suffix.

**In Bifrost UI → Providers → Add Provider:**

| Field | Value |
|---|---|
| **Provider type** | `OpenAI` |
| **Base URL** | `http://192.168.1.21:11434` ← no `/v1` suffix |
| **API Key name** | `ollama-local` |
| **API Key value** | `ollama` (any non-empty string — Ollama ignores it) |
| **Models** | `qwen2.5:7b`, `qwen3-coder:30b`, `llama3.2:3b`, `qwen2.5-coder:7b`, `gemma4:latest`, `qwen2.5-coder:1.5b-base` |
| **Timeout** | `120` |

**Or via API (note: provider type is `openai`, no `name` override field):**

```bash
curl -s -X POST http://localhost:8080/api/providers \
  -H "Content-Type: application/json" \
  -d '{
    "provider": "openai",
    "network_config": {
      "base_url": "http://192.168.1.21:11434",
      "default_request_timeout_in_seconds": 120,
      "stream_idle_timeout_in_seconds": 300,
      "max_retries": 0
    },
    "keys": [{
      "name": "ollama-local",
      "value": "ollama",
      "models": [
        "qwen2.5:7b",
        "qwen3-coder:30b",
        "llama3.2:3b",
        "qwen2.5-coder:7b",
        "gemma4:latest",
        "qwen2.5-coder:1.5b-base"
      ],
      "weight": 1.0
    }]
  }' | jq .
```

#### Step 3 — Link the Ollama key to your virtual key

After registering the provider, get the new key ID and the virtual key ID:

```bash
# Get Ollama key ID
OLLAMA_KEY_ID=$(curl -s http://localhost:8080/api/providers \
  | jq -r '.providers[] | select(.name=="openai") | .keys[] | select(.name=="ollama-local") | .id')
echo $OLLAMA_KEY_ID

# Virtual key ID (from your deployment)
VK_ID="dd36e54e-c0d8-4961-b8bc-fbdcd66cf1de"
```

Update the virtual key to include the Ollama key and allowed models:

```bash
curl -s -X PUT "http://localhost:8080/api/governance/virtual-keys/$VK_ID" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"kubernetes_local\",
    \"provider_configs\": [
      {
        \"provider\": \"anthropic\",
        \"weight\": 0.5,
        \"keys\": [{
          \"key_id\": \"9a7b81cb-929b-4d7e-a4c3-6a5d48743bb4\",
          \"name\": \"Claude key\",
          \"provider\": \"anthropic\",
          \"enabled\": true
        }],
        \"allowed_models\": [\"anthropic/*\"]
      },
      {
        \"provider\": \"openai\",
        \"weight\": 0.5,
        \"keys\": [{
          \"key_id\": \"$OLLAMA_KEY_ID\",
          \"name\": \"ollama-local\",
          \"provider\": \"openai\",
          \"enabled\": true
        }],
        \"allowed_models\": [
          \"openai/*\",
          \"qwen2.5:7b\",
          \"qwen3-coder:30b\",
          \"llama3.2:3b\",
          \"qwen2.5-coder:7b\",
          \"gemma4:latest\",
          \"qwen2.5-coder:1.5b-base\"
        ]
      }
    ]
  }" | jq '{message: .message, openai_keys: [.virtual_key.provider_configs[] | select(.provider=="openai") | .keys[].name]}'
```

> **Gotcha:** After adding the `openai` provider config to the virtual key via
> the UI's Allowed Models field, the key linkage (`"keys": []`) may still be
> empty. Always verify with the API response — if `keys` is empty, use the PUT
> above with the explicit `key_id` to force the linkage.

#### Step 4 — Warm up the model before demo

First call on large models (~30B) takes 30–60s while Ollama loads into memory.
Pre-warm before the demo:

```bash
ollama run qwen3-coder:30b "hello" && exit
# or
curl -s http://localhost:11434/api/generate \
  -d '{"model":"qwen3-coder:30b","prompt":"hello","stream":false}' | jq .response
```

#### Step 5 — Verify end to end

```bash
# Basic completion
curl -s -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -d '{
    "model": "openai/qwen2.5:7b",
    "messages": [{"role": "user", "content": "In one sentence: what is Kubernetes?"}]
  }' | jq -r '.choices[0].message.content'
```

Expected: single sentence response. Latency ~2s for 7B.

---

### Demo 9: Local vs Cloud Model Comparison

**Narrative:** Run the same cluster investigation query against a local Ollama
model and Anthropic Claude side by side. Show the quality/cost/latency tradeoff
in real time — both going through the same Bifrost endpoint, same governance,
same MCP tools.

**Pre-req state:** Ollama running with `OLLAMA_HOST=0.0.0.0`, `qwen3-coder:30b`
pre-warmed, `openai` provider registered in Bifrost.

```bash
echo "=== LOCAL: qwen2.5:7b (fast, zero cost) ==="
time curl -s -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -H "x-bf-mcp-include-clients: kubernetes_local" \
  -d '{
    "model": "openai/qwen2.5:7b",
    "messages": [{"role": "user", "content": "Investigate the goose-test namespace and tell me which apps are unhealthy."}]
  }' | jq -r '.choices[0].message.content'

echo ""
echo "=== LOCAL: qwen3-coder:30b (best local quality, zero cost) ==="
time curl -s -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -H "x-bf-mcp-include-clients: kubernetes_local" \
  -d '{
    "model": "openai/qwen3-coder:30b",
    "messages": [{"role": "user", "content": "Investigate the goose-test namespace and tell me which apps are unhealthy."}]
  }' | jq -r '.choices[0].message.content'

echo ""
echo "=== CLOUD: claude-sonnet-4-5 (~$0.003/call) ==="
time curl -s -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -H "x-bf-mcp-include-clients: kubernetes_local" \
  -d '{
    "model": "anthropic/claude-sonnet-4-5-20250929",
    "messages": [{"role": "user", "content": "Investigate the goose-test namespace and tell me which apps are unhealthy."}]
  }' | jq -r '.choices[0].message.content'
```

**Validated results from live cluster (April 2026):**

| Model | Latency | Quality highlights |
|---|---|---|
| `qwen2.5:7b` | ~2s | Basic pod listing, simple identification |
| `qwen3-coder:30b` | ~18s | Identifies bad-app and scheduled-job issues, misses policy detail |
| `claude-sonnet-4-5-20250929` | ~4.5s | Full diagnosis: Kyverno violations, missing probes, security context, root cause per app |

**Demo talking point:** Same endpoint, same virtual key, same MCP tool governance
— swap one field in the request body to choose between free local inference and
cloud-quality diagnosis. Bifrost abstracts the routing completely.

---

### Demo 10: Ollama Namespace List (Fast Read-Only Query)

**Narrative:** Show a sub-2-second MCP tool call using the local 7B model.
Good for demonstrating that not every query needs a cloud model.

```bash
curl -s -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -H "x-bf-mcp-include-clients: kubernetes_local" \
  -d '{
    "model": "openai/qwen2.5:7b",
    "messages": [{"role": "user", "content": "List all namespaces in the cluster and categorise them as system, infrastructure, or application namespaces."}]
  }' | jq -r '.choices[0].message.content'
```

**Confirmed working output:** All 26 namespaces returned and correctly categorised
by the model from a single `namespaces_list` tool call.

---

### Ollama Gotchas Summary

| Issue | Root cause | Fix |
|---|---|---|
| Empty response from pod connectivity test | Ollama bound to `localhost` only | `OLLAMA_HOST=0.0.0.0 ollama serve` |
| `404 page not found` from Bifrost | Wrong provider type — native `ollama` type hits `/api/chat` not `/v1/chat/completions` | Register as `openai` provider type |
| `404 page not found` with `openai` provider | Double `/v1` path — `base_url` had `/v1` suffix, Bifrost appends another | Remove `/v1` from base URL — use `http://192.168.1.21:11434` only |
| `model_blocked 403` | Virtual key `allowed_models` doesn't include `openai/*` or Ollama model names | Add `openai/*` to allowed_models on virtual key |
| `keys: []` on openai provider config | UI adds the provider config but doesn't link the key — silent failure | Use PUT API with explicit `key_id` to force linkage |
| `Method Not Allowed` on DELETE /api/provider | Bifrost API doesn't support DELETE on providers — use UI | Delete via Bifrost UI → Providers → Delete |
| First call slow (30–60s) on large models | Ollama loading model into memory | Pre-warm: `ollama run qwen3-coder:30b "hello"` before demo |

---

*Compiled April 2026 from live k3d-demo cluster state.*
