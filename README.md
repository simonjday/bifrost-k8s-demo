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
curl -s http://localhost:8811/sse

# 5. Register the MCP server in Bifrost UI → MCP → New MCP Server:
#   Name:            kubernetes_local
#   Connection Type: Server-Sent Events (SSE)
#   URL:             http://mcp-kubernetes-sse.ai-gateway.svc.cluster.local:8811/sse
#   Auth:            None

# 6. Pre-warm Ollama (optional but recommended before demos)
./scripts/warmup-ollama.sh

# 7. Export your Bifrost virtual key (get from http://localhost:8080 → Keys)
export BIFROST_VIRTUAL_KEY="vk_your_key_here"

# 8. Run any demo
./demos/01-governance-block.sh
```

## Architecture

```
Mac Host
├── Ollama (0.0.0.0:11434) ─────────────────────────────┐
├── kubernetes-mcp-server SSE (0.0.0.0:8811) ───────────┐│
│   └── runs as macOS Launch Agent (auto-start/restart)  ││
│                                                         ││
└── k3d-demo cluster                                      ││
    └── ai-gateway namespace                              ││
        ├── bifrost-0 (StatefulSet)                       ││
        ├── mcp-kubernetes-sse Service ──────────────────►┘│
        │   └── Endpoints: <Mac LAN IP>:8811               │
        └── [openai provider → <Mac LAN IP>:11434] ───────►┘
```

## MCP Server — Launch Agent Setup

The `kubernetes-mcp-server` runs as a macOS Launch Agent so it starts automatically
at login and restarts on crash. It exposes an SSE endpoint that Bifrost pods reach
via the `mcp-kubernetes-sse` in-cluster Service.

### Install (one-time)

```bash
# 1. Install the Launch Agent
cp scripts/com.local.mcp-kubernetes-sse.plist ~/Library/LaunchAgents/
launchctl load -w ~/Library/LaunchAgents/com.local.mcp-kubernetes-sse.plist

# 2. Apply the k8s Service + Endpoints
kubectl apply -f manifests/mcp-kubernetes-host-svc.yaml

# 3. Verify
curl -s http://localhost:8811/sse          # should stream SSE events
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

### If your Mac IP changes (DHCP)

The `mcp-kubernetes-host-svc.yaml` Endpoints object is hardcoded to your Mac's LAN IP.
If it changes, update the IP and re-apply:

```bash
# Edit the ip field in manifests/mcp-kubernetes-host-svc.yaml, then:
kubectl apply -f manifests/mcp-kubernetes-host-svc.yaml

# Or use start-mcp-server.sh which auto-detects your current IP and re-applies:
./scripts/start-mcp-server.sh
```

### Note on Claude Desktop

The Claude desktop app runs its own `kubernetes-mcp-server` instance in **stdio mode**
for its own tool use — this is separate from the SSE instance above. The two do not
conflict. Do not change your `claude_desktop_config.json`.

## Key Configuration Facts

| Item | Value |
|---|---|
| Bifrost UI | http://localhost:8080 |
| MCP endpoint | `POST http://localhost:8080/mcp` (JSON-RPC 2.0) |
| Completions endpoint | `POST http://localhost:8080/v1/chat/completions` |
| Auth header | `X-Api-Key: $BIFROST_VIRTUAL_KEY` |
| MCP client filter | `x-bf-mcp-include-clients: kubernetes_local` |
| Anthropic model | `anthropic/claude-sonnet-4-5-20250929` |
| Ollama model prefix | `openai/<modelname>` e.g. `openai/qwen2.5:7b` |
| Ollama provider type | `openai` (NOT `ollama`) |
| Ollama base URL | `http://<Mac LAN IP>:11434` (no `/v1` suffix) |
| MCP SSE URL (in-cluster) | `http://mcp-kubernetes-sse.ai-gateway.svc.cluster.local:8811/sse` |
| MCP SSE URL (local) | `http://localhost:8811/sse` |

## Known Gotchas

See [docs/demo-guide.md](docs/demo-guide.md) for full gotchas tables covering:
- Helm install issues (Kyverno label enforcement, encryption key secret, stale releases)
- MCP server networking (`host.k3d.internal` doesn't resolve from pods — use LAN IP)
- MCP server must use `--port` flag only; `--transport` flag does not exist in this package
- `ENABLE_UNSAFE_SSE_TRANSPORT=1` env var required for SSE mode
- Ollama provider registration (use `openai` type, no `/v1` in base URL)
- Agent mode configuration (`tools_to_auto_execute` on MCP client, not a request header)

## Validated Environment

| Component | Version |
|---|---|
| Bifrost | v1.5.0-prerelease7 (chart 2.1.13) |
| kubernetes-mcp-server | latest (Red Hat/containers) |
| k3d | devops-lab, k3s v1.33.x |
| Ollama models | qwen2.5:7b, qwen3-coder:30b, llama3.2:3b, qwen2.5-coder:7b, gemma4:latest |
| Anthropic | claude-sonnet-4-5-20250929 |

## Docs

- [Bifrost In-Depth Analysis](docs/bifrost-analysis.md)
- [Demo Guide](docs/demo-guide.md)
- [AI Gateway Comparison](docs/gateway-comparison.md)
