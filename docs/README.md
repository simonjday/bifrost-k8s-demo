# bifrost-k8s-demo — Documentation Index

`devops-lab` · `bifrost-k8s-demo` · May 2026

---

## Guides

| File | Purpose |
|---|---|
| [demo-guide.md](demo-guide.md) | Primary demo reference — 11 demos covering Kubernetes MCP, Prometheus MCP, governance, agent mode, failover, and local vs cloud model comparison |
| [Prometheus MCP Server — Deployment & Demo Guide.md](Prometheus%20MCP%20Server%20—%20Deployment%20%26%20Demo%20Guide.md) | Full setup guide for the Prometheus MCP integration — deployment, ServiceMonitor, Postman collection, troubleshooting |
| [ollama-bifrost-setup.md](ollama-bifrost-setup.md) | Ollama configuration — binding to all interfaces, provider registration in Bifrost, model management, Claude Desktop integration |
| [Argo CD MCP Server — Deployment Guide.md](Additional-MCP-Server-Guides/Argo%20CD%20MCP%20Server%20—%20Deployment%20Guide.md) | ArgoCD MCP server setup and demo scenarios |
| [AWS MCP Server — Deployment & Demo Guide.md](Additional-MCP-Server-Guides/AWS%20MCP%20Server%20—%20Deployment%20%26%20Demo%20Guide.md) | AWS MCP server setup and demo scenarios |
| [Azure MCP Server — Deployment & Demo Guide.md](Additional-MCP-Server-Guides/Azure%20MCP%20Server%20—%20Deployment%20%26%20Demo%20Guide.md) | Azure MCP server setup and demo scenarios |
| [Datadog MCP Server — Deployment & Demo Guide.md](Additional-MCP-Server-Guides/Datadog%20MCP%20Server%20—%20Deployment%20%26%20Demo%20Guide.md) | Datadog MCP server setup and demo scenarios |
| [Dynatrace MCP Server — Deployment & Demo Guide.md](Additional-MCP-Server-Guides/Dynatrace%20MCP%20Server%20—%20Deployment%20%26%20Demo%20Guide.md) | Dynatrace MCP server setup and demo scenarios |
| [GitHub MCP Server — Deployment & Demo Guide.md](Additional-MCP-Server-Guides/GitHub%20MCP%20Server%20—%20Deployment%20%26%20Demo%20Guide.md) | GitHub MCP server setup and demo scenarios |
| [Grafana MCP Server — Deployment & Demo Guide.md](Additional-MCP-Server-Guides/Grafana%20MCP%20Server%20—%20Deployment%20%26%20Demo%20Guide.md) | Grafana MCP server setup and demo scenarios |
| [prometheus-grafana-bifrost.md](prometheus-grafana-bifrost.md) | Bifrost metrics in Prometheus & Grafana — ServiceMonitor setup, verifying scraping, importing the two provided Grafana dashboards |

## Reference

| File | Purpose |
|---|---|
| [bifrost-analysis.md](bifrost-analysis.md) | In-depth Bifrost vendor analysis — architecture, performance, pros/cons, k8s setup manifests, test scenarios |
| [gateway-comparison.md](gateway-comparison.md) | Feature comparison across Bifrost, LiteLLM, Portkey, Kong AI, and Helicone |

## Assets

| Path | Contents |
|---|---|
| [screenshots/](screenshots/) | Demo and UI screenshots referenced in the guides |

---

## Quick Reference

| Item | Value |
|---|---|
| Bifrost UI | `http://localhost:8080` |
| Bifrost completions | `http://localhost:8080/v1/chat/completions` |
| Bifrost MCP endpoint | `http://localhost:8080/mcp` |
| Prometheus | `http://localhost:9090` |
| Grafana | `http://localhost:3000` |
| ArgoCD | `http://localhost:9080` |
| Open WebUI | `http://localhost:3001` |
| Kubernetes MCP server | SSE on Mac `:8811` via `new_kubernetes_local` |
| Prometheus MCP server | HTTP (Streamable) in-cluster `:8080/mcp` via `prometheus` |
| Ollama | Mac host `:11434` — must bind `0.0.0.0` |
| Auth header | `X-Api-Key: <virtual-key>` |
| Start port-forwards | `kubectl -n ai-gateway port-forward svc/bifrost 8080:8080 &` |

## Files Removed

The following files were consolidated into `demo-guide.md` and removed:

- `basic-bifrost-demo-guide.md` — superseded by `demo-guide.md`
- `bifrost-curl-examples.md` — absorbed into `demo-guide.md` quick reference
- `bifrost-openwebui-demo-scenarios.md` — Open WebUI content merged into `demo-guide.md`
