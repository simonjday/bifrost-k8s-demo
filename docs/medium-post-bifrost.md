# Bifrost — An AI Gateway That Actually Belongs in Your Kubernetes Platform

*Why I added an AI gateway to my platform engineering lab, how it works with Open WebUI and VS Code, and what I learned about model routing in a multi-provider setup.*

---

## The AI API Sprawl Problem

If you're running AI tooling in a platform engineering context, you quickly end up with a mess:

- VS Code Copilot pointing at OpenAI
- Open WebUI pointing at Ollama directly
- Each tool managing its own API keys
- No visibility into who's calling what, how much it costs, or whether requests are succeeding

What you actually want is the same thing you'd want for any API in a platform context: a single control point, observability, governance, and the ability to swap backends without changing client config.

That's what [Bifrost](https://github.com/maximhq/bifrost) is.

---

## What is Bifrost?

Bifrost is a high-performance AI gateway written in Go. It sits between your applications and upstream LLM providers, exposing a single OpenAI-compatible API endpoint regardless of which provider is behind it.

Key capabilities:

- **20+ provider support** — OpenAI, Anthropic, AWS Bedrock, Google Vertex, Azure, Ollama, Groq, and more
- **Virtual keys** — scoped API keys per team or tool with budget limits and model restrictions, configured via the UI
- **Automatic failover** — if the primary provider is down or rate-limited, route to a fallback automatically
- **Semantic caching** — cache semantically similar queries to reduce costs and latency
- **MCP gateway** — expose MCP tools to any OpenAI-compatible client (enterprise feature)
- **OpenTelemetry + Prometheus** — full observability out of the box

The MCP gateway capability is what made me deploy it in my Kubernetes lab.

---

## Architecture

```
                    ┌─────────────────────────┐
                    │       Applications       │
                    │  Open WebUI · VS Code    │
                    │  curl · custom apps      │
                    └───────────┬─────────────┘
                                │ OpenAI-compatible API
                    ┌───────────▼─────────────┐
                    │       Bifrost Gateway    │
                    │  Virtual Keys (UI)       │
                    │  Provider Routing        │
                    │  Automatic Failover      │
                    │  Semantic Cache          │
                    │  MCP Gateway             │
                    │  Prometheus /metrics     │
                    └───────────┬─────────────┘
          ┌──────────────────────┼────────────────────┐
          │                      │                    │
    ┌─────▼──────┐  ┌────────────▼──────┐  ┌─────────▼──────┐
    │   Ollama   │  │    Anthropic       │  │   OpenAI       │
    │  (local)   │  │    Claude          │  │   GPT-4o       │
    └────────────┘  └───────────────────┘  └────────────────┘
```

Everything speaks OpenAI API format to Bifrost. Behind it, providers are configured independently.

---

## Deploying Bifrost on Kubernetes

The repo at [github.com/simonjday/bifrost-k8s-demo](https://github.com/simonjday/bifrost-k8s-demo) includes an `install.sh` script that handles everything — Bifrost Helm install, MCP server setup, and provider configuration — in one shot. It auto-detects whether you're running k3d or kind.

```bash
git clone https://github.com/simonjday/bifrost-k8s-demo.git
cd bifrost-k8s-demo

./scripts/install.sh --apply --context kind-devops-lab
```

### Port-forward and verify

```bash
kubectl -n ai-gateway port-forward svc/bifrost 8080:8080 &
curl http://localhost:8080/health
open http://localhost:8080
```

### MCP server persistence (macOS)

The Kubernetes MCP server runs as a Launch Agent so it survives reboots:

```bash
cp scripts/com.local.mcp-kubernetes-sse.plist ~/Library/LaunchAgents/
launchctl load -w ~/Library/LaunchAgents/com.local.mcp-kubernetes-sse.plist
```

Then register it in the Bifrost UI: **MCP → New MCP Server → SSE → `http://mcp-kubernetes-svc:3000/sse`**

Full setup walkthrough is in `docs/ollama-bifrost-setup.md`.

---

## Configuring Providers and Virtual Keys

This is important: **virtual keys are configured via the Bifrost web UI, not YAML**.

After deployment, port-forward to the UI:

```bash
kubectl port-forward svc/bifrost 8080:8080
open http://localhost:8080
```

From the UI you:

1. **Add providers** — paste your API key for Anthropic, OpenAI, etc. For Ollama, point at the local endpoint (`http://host.docker.internal:11434`)
2. **Create virtual keys** — each key can be restricted to specific models, given a budget limit, and scoped to a team or tool
3. **Configure routing rules** — set fallback order between providers

The virtual key is what you give to your tools (`OPENAI_API_KEY` in Open WebUI, VS Code, etc.). Bifrost handles the routing and enforcement behind the scenes.


---

## Open WebUI + Bifrost

Connecting Open WebUI to Bifrost is a single environment variable:

```bash
docker run -d \
  --name open-webui \
  -p 3000:8080 \
  -e OPENAI_API_BASE_URL=http://host.docker.internal:8080/v1 \
  -e OPENAI_API_KEY="<your-webui-virtual-key>" \
  ghcr.io/open-webui/open-webui:main
```

Open WebUI now sees all models from all providers configured in Bifrost. Users can switch between a local Ollama model and Claude Sonnet in the same conversation without anyone managing API keys directly.

---

## The MCP Gateway

The MCP gateway capability is an enterprise feature. When enabled, Bifrost connects to MCP servers (like the Kubernetes MCP server) and makes their tools available to **any OpenAI-compatible client**.

This means Open WebUI, VS Code Copilot, or any HTTP client can call Kubernetes tools without knowing anything about MCP:

```bash
curl -X POST http://localhost:8080/mcp/tools/call \
  -H "Authorization: Bearer <virtual-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "kubernetes-local:pods_list_in_namespace",
    "arguments": {"namespace": "kube-system"}
  }'
```

The response comes back as structured JSON from the Kubernetes API.

---

## What I Discovered About Model Routing

Running multiple models through Bifrost revealed something important: **model compliance with tool definitions varies enormously**.

Testing tool-calling through Bifrost with the Kubernetes MCP server:

| Model | Tool calling | Notes |
|---|---|---|
| qwen3-coder:30b | Reliable | Best overall. Occasional missing tool_call tag after text responses |
| claude-sonnet-4 | Excellent | Most reliable. Best for complex multi-step reasoning |
| qwen2.5:32b | Ignores tools | Answers from training data instead of calling tools |
| gemma3:12b | No tool support | No tool-calling in the Ollama build |
| llama3.2:3b | Inconsistent | Works sometimes, fails silently on complex chains |

For operational tooling, model selection matters more than model size.

---

## Observability

Bifrost exposes Prometheus metrics at `/metrics` out of the box:

```promql
# Request rate by provider
rate(bifrost_requests_total[5m])

# Error rate
rate(bifrost_errors_total[5m]) / rate(bifrost_requests_total[5m])

# Cache hit rate
bifrost_cache_hits_total / bifrost_requests_total
```

I scrape these with the same Prometheus stack running in the cluster — same dashboards, same alerting, same GitOps config.

---

## What Bifrost Is Not

To set realistic expectations:

- **Not an inference engine** — it doesn't run models, that's Ollama's job
- **Not a replacement for direct Ollama access** — for single-user single-model setups, Bifrost adds complexity without much benefit
- **MCP gateway is enterprise** — the free OSS version doesn't include MCP server integration

Where it adds genuine value is in multi-tool, multi-team, multi-provider environments — exactly the context most platform engineering teams find themselves in.

---

## The Setup in Practice

My current stack:

```
Open WebUI         → Bifrost → Ollama (qwen2.5:14b) for general chat
VS Code Copilot    → Bifrost → Anthropic (claude-haiku) for code completion
Custom scripts     → Bifrost → OpenAI / Anthropic for automation
```

One endpoint, multiple tools, different use cases. Virtual keys control access. Prometheus tracks usage. ArgoCD keeps the Helm release in sync.

The repo includes 10 demo scripts covering governance blocking, cost attribution, pod diagnosis, ArgoCD status, Kargo pipeline queries, LLM-driven triage, multi-tool correlation, and local vs cloud model comparison. Full playbook in `docs/demo-guide.md`.

Everything is at [github.com/simonjday/bifrost-k8s-demo](https://github.com/simonjday/bifrost-k8s-demo).

---

*Simon Day is a Platform & DevOps Engineer specialising in Kubernetes, GitOps, and Confluent Platform.*

*[GitHub](https://github.com/simonjday) · [Platform Engineering Notes on Substack](https://sjd2504.substack.com)*
