# Bifrost AI Gateway — k3d Demo

A complete demo environment for [Bifrost AI Gateway](https://github.com/maximhq/bifrost) on a local k3d cluster, including Kubernetes MCP tool integration, Ollama local model support, and governed agentic workflows.

## What This Repo Contains

```
bifrost-k8s-demo/
├── README.md                        # This file
├── docs/
│   ├── bifrost-analysis.md          # In-depth Bifrost architecture and feature analysis
│   ├── demo-guide.md                # Complete demo playbook (10 demos, pre-reqs, curl commands)
│   └── gateway-comparison.md        # Bifrost vs LiteLLM vs Portkey vs Kong vs Helicone
├── manifests/
│   ├── namespace.yaml               # ai-gateway namespace
│   ├── bifrost-values-dev.yaml      # Helm values for local k3d dev install
│   ├── bifrost-values-prod.yaml     # Helm values for production HA install
│   └── mcp-kubernetes-host-svc.yaml # Service + Endpoints for Mac host MCP SSE server
├── scripts/
│   ├── install.sh                   # Full install: Bifrost + MCP + providers
│   ├── teardown.sh                  # Clean teardown (dry-run by default)
│   ├── start-mcp-server.sh          # Start kubernetes-mcp-server in SSE mode
│   └── warmup-ollama.sh             # Pre-warm Ollama models before demo
└── demos/
    ├── 01-governance-block.sh       # Demo 5: Destructive tool blocking
    ├── 02-cost-attribution.sh       # Demo 2: Namespace resource consumption
    ├── 03-crashloop-diagnosis.sh    # Demo 3: Pod diagnosis workflow
    ├── 04-argocd-status.sh          # Demo 4: Argo CD CRD queries
    ├── 05-kargo-pipeline.sh         # Demo 6: Kargo stage and freight status
    ├── 06-lm-triage.sh              # Demo 7: LLM-driven cluster triage (agent mode)
    ├── 07-multi-tool-correlation.sh # Demo 8: Pods + Argo CD + Kargo correlation
    ├── 08-local-vs-cloud.sh         # Demo 9: Ollama vs Anthropic comparison
    └── 09-ollama-fast-query.sh      # Demo 10: Sub-2s local model query
```

## Prerequisites

- k3d cluster running (`k3d cluster list`)
- Helm 3.x
- kubectl configured for the cluster
- Anthropic API key
- Ollama installed on Mac (`brew install ollama`)
- Node.js 18+ (for `kubernetes-mcp-server`)

## Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/simonjday/bifrost-k8s-demo.git
cd bifrost-k8s-demo

# 2. Run the install script
./scripts/install.sh

# 3. Start the MCP server
./scripts/start-mcp-server.sh

# 4. Pre-warm Ollama (optional but recommended before demos)
./scripts/warmup-ollama.sh

# 5. Export your Bifrost virtual key (get from http://localhost:8080 → Keys)
export BIFROST_VIRTUAL_KEY="vk_your_key_here"

# 6. Run any demo
./demos/01-governance-block.sh
```

## Architecture

```
Mac Host
├── Ollama (0.0.0.0:11434) ─────────────────────────────┐
├── kubernetes-mcp-server SSE (0.0.0.0:8811) ───────────┐│
│                                                         ││
└── k3d-demo cluster                                      ││
    └── ai-gateway namespace                              ││
        ├── bifrost-0 (StatefulSet)                       ││
        ├── mcp-kubernetes-sse Service ──────────────────►┘│
        │   └── Endpoints: 192.168.1.21:8811               │
        └── [openai provider → 192.168.1.21:11434] ───────►┘
```

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
| Ollama base URL | `http://192.168.1.21:11434` (no `/v1` suffix) |

## Known Gotchas

See [docs/demo-guide.md](docs/demo-guide.md) for full gotchas tables covering:
- Helm install issues (Kyverno label enforcement, encryption key secret, stale releases)
- MCP server networking (`host.k3d.internal` doesn't resolve from pods — use LAN IP)
- Ollama provider registration (use `openai` type, no `/v1` in base URL)
- Agent mode configuration (`tools_to_auto_execute` on MCP client, not a request header)

## Validated Environment

| Component | Version |
|---|---|
| Bifrost | v1.5.0-prerelease4 (chart 2.1.8) |
| kubernetes-mcp-server | latest (Red Hat/containers) |
| k3d | k3d-demo, k3s v1.33.6+k3s1 |
| Ollama models | qwen2.5:7b, qwen3-coder:30b, llama3.2:3b, qwen2.5-coder:7b, gemma4:latest |
| Anthropic | claude-sonnet-4-5-20250929 |

## Docs

- [Bifrost In-Depth Analysis](docs/bifrost-analysis.md)
- [Demo Guide](docs/demo-guide.md)
- [AI Gateway Comparison](docs/gateway-comparison.md)
