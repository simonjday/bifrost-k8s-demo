# Bifrost AI Gateway — k3d Demo

A complete demo environment for [Bifrost AI Gateway](https://github.com/maximhq/bifrost) on a local k3d cluster, including Kubernetes MCP tool integration, Ollama local model support, and governed agentic workflows.

## What This Repo Contains

```
bifrost-k8s-demo/
├── README.md                                  # This file
├── docs/
│   ├── bifrost-analysis.md                    # In-depth Bifrost architecture and feature analysis
│   ├── demo-guide.md                          # Complete demo playbook (10 demos, pre-reqs, curl commands)
│   └── gateway-comparison.md                  # Bifrost vs LiteLLM vs Portkey vs Kong vs Helicone
├── manifests/
│   ├── namespace.yaml                         # ai-gateway namespace
│   ├── bifrost-values-dev.yaml                # Helm values for local k3d dev install
│   ├── bifrost-values-prod.yaml               # Helm values for production HA install
│   └── mcp-kubernetes-host-svc.yaml           # Service + Endpoints for Mac host MCP SSE server
├── scripts/
│   ├── install.sh                             # Full install: Bifrost + MCP + providers
│   ├── teardown.sh                            # Clean teardown (dry-run by default)
│   ├── start-mcp-server.sh                    # One-shot: apply k8s svc + start SSE server
│   ├── com.local.mcp-kubernetes-sse.plist     # macOS Launch Agent for kubernetes-mcp-server
│   └── warmup-ollama.sh                       # Pre-warm Ollama models before demo
└── demos/
    ├── 01-governance-block.sh                 # Demo 5: Destructive tool blocking
    ├── 02-cost-attribution.sh                 # Demo 2: Namespace resource consumption
    ├── 03-crashloop-diagnosis.sh              # Demo 3: Pod diagnosis workflow
    ├── 04-argocd-status.sh                    # Demo 4: Argo CD CRD queries
    ├── 05-kargo-pipeline.sh                   # Demo 6: Kargo stage and freight status
    ├── 06-lm-triage.sh                        # Demo 7: LLM-driven cluster triage (agent mode)
    ├── 07-multi-tool-correlation.sh           # Demo 8: Pods + Argo CD + Kargo correlation
    ├── 08-local-vs-cloud.sh                   # Demo 9: Ollama vs Anthropic comparison
    └── 09-ollama-fast-query.sh                # Demo 10: Sub-2s local model query
```

## Prerequisites

- k3d cluster running (`k3d cluster list`)
- Helm 3.x
- kubectl configured for the cluster
- Anthropic API key
- Ollama installed on Mac (`brew install ollama`)
- Node.js 18+ / npx (for `kubernetes-mcp-server`)
- Docker Desktop for Mac

## Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/simonjday/bifrost-k8s-demo.git
cd bifrost-k8s-demo

# 2. Run the install script
./scripts/install.sh --apply

# 3. Install the MCP server Launch Agent (runs automatically on login)
cp scripts/com.local.mcp-kubernetes-sse.plist ~/Library/LaunchAgents/
launchctl load -w ~/Library/LaunchAgents/com.local.mcp-kubernetes-sse.plist

# 4. Apply the in-cluster Service + Endpoints so Bifrost can reach the MCP server
kubectl apply -f manifests/mcp-kubernetes-host-svc.yaml

# Verify the MCP SSE endpoint is up
curl -s http://localhost:8811/healthz && echo "MCP server: OK"

# 5. Port-forward Bifrost UI
kubectl --context k3d-demo port-forward -n ai-gateway svc/bifrost 8080:8080 &

# 6. Register the MCP server in Bifrost UI → MCP → New MCP Server:
#   Name:            kubernetes_local
#   Connection Type: Server-Sent Events (SSE)
#   URL:             http://mcp-kubernetes-sse.ai-gateway.svc.cluster.local:8811/sse
#   Auth:            None

# 7. Verify Bifrost is connected (should show state: connected, tool_count: 20)
curl -s http://localhost:8080/api/mcp/clients | \
  jq '{state: .clients[0].state, tool_count: (.clients[0].tools | length)}'

# 8. Pre-warm Ollama (optional but recommended before demos)
./scripts/warmup-ollama.sh

# 9. Export your Bifrost virtual key (get from http://localhost:8080 → Keys)
export BIFROST_VIRTUAL_KEY="vk_your_key_here"

# 10. Run any demo
./demos/01-governance-block.sh
```

## Architecture

```
Mac Host
├── Ollama (0.0.0.0:11434) ──────────────────────────────────┐
├── kubernetes-mcp-server SSE (0.0.0.0:8811) ────────────────┐│
│   └── macOS Launch Agent (auto-start/restart on login)      ││
│                                                              ││
└── k3d-demo cluster (Docker)                                  ││
    └── ai-gateway namespace                                   ││
        ├── bifrost-0 (StatefulSet)                            ││
        │   └── port-forwarded → localhost:8080                ││
        ├── mcp-kubernetes-sse Service                         ││
        │   └── Endpoints: 192.168.1.21:8811 ────────────────►┘│
        │       (Mac LAN IP — reachable from k3d pods)          │
        └── openai provider → 192.168.1.21:11434 ─────────────►┘
```

## MCP Server — Launch Agent Setup

The `kubernetes-mcp-server` runs as a macOS Launch Agent so it starts automatically
at login and restarts on crash. It exposes `/sse`, `/mcp`, `/healthz`, and `/metrics`
on port 8811. Bifrost pods reach it via the `mcp-kubernetes-sse` in-cluster Service,
which uses a manual Endpoints object pointing at the Mac's LAN IP.

### Install (one-time)

```bash
# 1. Install the Launch Agent
cp scripts/com.local.mcp-kubernetes-sse.plist ~/Library/LaunchAgents/
launchctl load -w ~/Library/LaunchAgents/com.local.mcp-kubernetes-sse.plist

# 2. Verify it's running and listening
lsof -i :8811 | grep LISTEN       # should show kubernete ... *:8811 (LISTEN)
curl -s http://localhost:8811/healthz && echo OK

# 3. Apply the k8s Service + Endpoints
kubectl apply -f manifests/mcp-kubernetes-host-svc.yaml

# 4. Verify end-to-end from inside the cluster
kubectl --context k3d-demo exec -n ai-gateway bifrost-0 -- \
  wget -qO- http://mcp-kubernetes-sse.ai-gateway.svc.cluster.local:8811/healthz \
  && echo "In-cluster: OK"

# 5. Verify Bifrost picked it up
curl -s http://localhost:8080/api/mcp/clients | \
  jq '{state: .clients[0].state, tool_count: (.clients[0].tools | length)}'
# Expected: { "state": "connected", "tool_count": 20 }
```

### Logs

```bash
tail -f /tmp/mcp-kubernetes-sse.log   # stdout
tail -f /tmp/mcp-kubernetes-sse.err   # stderr / errors
```

### Manage

```bash
# Stop (stays installed, restarts on next login)
launchctl stop com.local.mcp-kubernetes-sse

# Reload after editing the plist
launchctl unload ~/Library/LaunchAgents/com.local.mcp-kubernetes-sse.plist
launchctl load -w ~/Library/LaunchAgents/com.local.mcp-kubernetes-sse.plist

# Uninstall completely
launchctl unload ~/Library/LaunchAgents/com.local.mcp-kubernetes-sse.plist
rm ~/Library/LaunchAgents/com.local.mcp-kubernetes-sse.plist
```

### Note on Claude Desktop

The Claude desktop app runs its own `kubernetes-mcp-server` instance in **stdio mode**
configured in `~/Library/Application Support/Claude/claude_desktop_config.json`.
This is completely separate from the SSE instance above — they run as two independent
processes and do not conflict. Do not change your Claude desktop config.

## Key Configuration Facts

| Item | Value |
|---|---|
| Bifrost UI | http://localhost:8080 (via port-forward) |
| MCP endpoint | `POST http://localhost:8080/mcp` (JSON-RPC 2.0) |
| Completions endpoint | `POST http://localhost:8080/v1/chat/completions` |
| Auth header | `X-Api-Key: $BIFROST_VIRTUAL_KEY` |
| MCP client filter | `x-bf-mcp-include-clients: kubernetes_local` |
| Anthropic model | `anthropic/claude-sonnet-4-5-20250929` |
| Ollama model prefix | `openai/<modelname>` e.g. `openai/qwen2.5:7b` |
| Ollama provider type | `openai` (NOT `ollama`) |
| Ollama base URL | `http://192.168.1.21:11434` (no `/v1` suffix) |
| MCP SSE URL (in-cluster) | `http://mcp-kubernetes-sse.ai-gateway.svc.cluster.local:8811/sse` |
| MCP SSE URL (local) | `http://localhost:8811/sse` |
| Mac LAN IP (k3d endpoint) | `192.168.1.21` |

## Known Gotchas

See [docs/demo-guide.md](docs/demo-guide.md) for full gotchas tables. Key issues:

- **Use k3d, not kind** — kind clusters cannot route to the Mac's LAN IP from pods.
  k3d routes through the Docker bridge directly to the Mac's LAN interface.
- **Mac LAN IP in Endpoints, not Docker gateway** — `192.168.1.21` works for k3d.
  If your IP changes update `manifests/mcp-kubernetes-host-svc.yaml` and re-apply.
- **`--port` flag only, no `--transport`** — `kubernetes-mcp-server` does not have a
  `--transport` flag. `--port 8811` is sufficient; `ENABLE_UNSAFE_SSE_TRANSPORT=1`
  env var is also required in the Launch Agent plist.
- **Wrong kubectl context** — always use `--context k3d-demo`. The default context
  may point at a different cluster (e.g. `kind-devops-lab`).
- **Port-forward required for localhost:8080** — Bifrost has no NodePort/Ingress in
  dev mode. Run: `kubectl --context k3d-demo port-forward -n ai-gateway svc/bifrost 8080:8080 &`
- **`state: null` from curl** — means port-forward isn't running or points at wrong cluster.
- Helm install issues (Kyverno label enforcement, encryption key secret, stale releases)
- Ollama provider registration (use `openai` type, no `/v1` in base URL)
- Agent mode configuration (`tools_to_auto_execute` on MCP client, not a request header)

## Validated Environment

| Component | Version |
|---|---|
| Bifrost | v1.5.0-prerelease7 (chart 2.1.13) |
| kubernetes-mcp-server | latest (Red Hat/containers) |
| k3d cluster | k3d-demo, k3s v1.33.x |
| Docker Desktop | Mac |
| Ollama models | qwen2.5:7b, qwen3-coder:30b, llama3.2:3b, qwen2.5-coder:7b, gemma4:latest |
| Anthropic | claude-sonnet-4-5-20250929 |

## Docs

- [Bifrost In-Depth Analysis](docs/bifrost-analysis.md)
- [Demo Guide](docs/demo-guide.md)
- [AI Gateway Comparison](docs/gateway-comparison.md)

## kind Cluster Support

kind clusters cannot route directly to the Mac's LAN IP from pods (unlike k3d).
A lightweight `socat` proxy Deployment is required inside the kind cluster to
bridge traffic from the Service to `192.168.65.254` (`host.docker.internal`).

### Install for kind

```bash
# 1. Apply the proxy Deployment + Service (replaces the k3d Endpoints approach)
kubectl --context kind-devops-lab apply -f manifests/mcp-kubernetes-proxy-kind.yaml

# 2. Verify proxy pod is running
kubectl --context kind-devops-lab get pods -n ai-gateway

# 3. Verify end-to-end
kubectl --context kind-devops-lab exec -n ai-gateway bifrost-0 -- \
  wget -qO- http://mcp-kubernetes-sse.ai-gateway.svc.cluster.local:8811/healthz \
  && echo "kind: OK"

# 4. Port-forward Bifrost (use port 8081 if k3d is already on 8080)
kubectl --context kind-devops-lab port-forward -n ai-gateway svc/bifrost 8081:8080 &

# 5. Check MCP client state
curl -s http://localhost:8081/api/mcp/clients | \
  jq '{state: .clients[0].state, tool_count: (.clients[0].tools | length)}'
```

### Architecture difference: k3d vs kind

| | k3d | kind |
|---|---|---|
| Mac reachable via | LAN IP `192.168.1.21` | Docker host `192.168.65.254` |
| Service backend | Manual Endpoints (direct) | socat proxy Deployment |
| Manifest | `mcp-kubernetes-host-svc.yaml` | `mcp-kubernetes-proxy-kind.yaml` |
| kube-proxy DNAT | Works with Endpoints | Requires pod selector |
