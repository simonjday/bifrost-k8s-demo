# bifrost-k8s-demo — Documentation Index

`devops-lab` · `bifrost-k8s-demo` · May 2026

---

## Guides

| File | Purpose |
|---|---|
| [demo-guide.md](demo-guide.md) | Primary demo reference — 11 demos covering Kubernetes MCP, Prometheus MCP, governance, agent mode, failover, and local vs cloud model comparison |
| [Prometheus MCP Server — Deployment & Demo Guide.md](Prometheus%20MCP%20Server%20—%20Deployment%20%26%20Demo%20Guide.md) | Full setup guide for the Prometheus MCP integration — deployment, ServiceMonitor, Postman collection, troubleshooting |
| [prometheus-grafana-bifrost.md](prometheus-grafana-bifrost.md) | Bifrost metrics in Prometheus & Grafana — ServiceMonitor setup, verifying scraping, importing the two provided Grafana dashboards |
| [ollama-bifrost-setup.md](ollama-bifrost-setup.md) | Ollama configuration — binding to all interfaces, provider registration in Bifrost, model management, Claude Desktop integration |

## Troubleshooting & Reference

| File | Purpose |
|---|---|
| [SERVICEMONITOR_DEBUG_QUICK_REF.md](SERVICEMONITOR_DEBUG_QUICK_REF.md) | **[NEW]** ServiceMonitor troubleshooting and debug checklist — fix "No active targets" issues |
| [BIFROST_METRICS_QUERY_REFERENCE.md](BIFROST_METRICS_QUERY_REFERENCE.md) | **[NEW]** Complete reference of Bifrost metrics and example PromQL queries for Prometheus |
| [SESSION_RECAP_2026-05-12-prometheus-bifrost-fix.md](SESSION_RECAP_2026-05-12-prometheus-bifrost-fix.md) | **[NEW]** Session recap: Prometheus integration fixes, root cause analysis, and key learnings from May 12, 2026 work |

## Architecture & Analysis

| File | Purpose |
|---|---|
| [bifrost-analysis.md](bifrost-analysis.md) | In-depth Bifrost vendor analysis — architecture, performance, pros/cons, k8s setup manifests, test scenarios |
| [gateway-comparison.md](gateway-comparison.md) | Feature comparison across Bifrost, LiteLLM, Portkey, Kong AI, and Helicone |
| [bifrost-mcp-rebuild-guide.md](bifrost-mcp-rebuild-guide.md) | Step-by-step guide for full cluster rebuild, Bifrost install, observability, and MCP setup |
| [bifrost-mcp-quickref.md](bifrost-mcp-quickref.md) | Quick reference, health checks, troubleshooting, and common debugging commands |

## MCP Server Setup Guides

| File | Purpose |
|---|---|
| [Additional-MCP-Server-Guides/Argo CD MCP Server — Deployment Guide.md](Additional-MCP-Server-Guides/Argo%20CD%20MCP%20Server%20—%20Deployment%20Guide.md) | ArgoCD MCP server setup and demo scenarios |
| [Additional-MCP-Server-Guides/AWS MCP Server — Deployment & Demo Guide.md](Additional-MCP-Server-Guides/AWS%20MCP%20Server%20—%20Deployment%20%26%20Demo%20Guide.md) | AWS MCP server setup and demo scenarios |
| [Additional-MCP-Server-Guides/Azure MCP Server — Deployment & Demo Guide.md](Additional-MCP-Server-Guides/Azure%20MCP%20Server%20—%20Deployment%20%26%20Demo%20Guide.md) | Azure MCP server setup and demo scenarios |
| [Additional-MCP-Server-Guides/Datadog MCP Server — Deployment & Demo Guide.md](Additional-MCP-Server-Guides/Datadog%20MCP%20Server%20—%20Deployment%20%26%20Demo%20Guide.md) | Datadog MCP server setup and demo scenarios |
| [Additional-MCP-Server-Guides/Dynatrace MCP Server — Deployment & Demo Guide.md](Additional-MCP-Server-Guides/Dynatrace%20MCP%20Server%20—%20Deployment%20%26%20Demo%20Guide.md) | Dynatrace MCP server setup and demo scenarios |
| [Additional-MCP-Server-Guides/GitHub MCP Server — Deployment & Demo Guide.md](Additional-MCP-Server-Guides/GitHub%20MCP%20Server%20—%20Deployment%20%26%20Demo%20Guide.md) | GitHub MCP server setup and demo scenarios |
| [Additional-MCP-Server-Guides/Grafana MCP Server — Deployment & Demo Guide.md](Additional-MCP-Server-Guides/Grafana%20MCP%20Server%20—%20Deployment%20%26%20Demo%20Guide.md) | Grafana MCP server setup and demo scenarios |

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

---

## Prometheus MCP Server Stability Note

The Prometheus MCP server (`prometheus-mcp-server` v0.18.0) has a known limitation: **it exits after ~5 seconds with `context deadline exceeded`**. This affects Postman queries via the MCP interface.

**Workaround:** Use the **Direct Prometheus Queries** folder in the Postman collection (bypasses MCP entirely, always stable):

```bash
# Direct Prometheus API query (always works)
curl -s 'http://localhost:9090/api/v1/query?query=bifrost_success_requests_total' | jq '.data.result'
```

See [SERVICEMONITOR_DEBUG_QUICK_REF.md](SERVICEMONITOR_DEBUG_QUICK_REF.md) for more troubleshooting.

---

## Files Removed/Consolidated

The following files were consolidated into other guides and removed:

- `basic-bifrost-demo-guide.md` — superseded by `demo-guide.md`
- `bifrost-curl-examples.md` — absorbed into `demo-guide.md` quick reference
- `bifrost-openwebui-demo-scenarios.md` — Open WebUI content merged into `demo-guide.md`

---

**Last Updated:** May 12, 2026 — Prometheus Integration, MCP Stability Notes, and New Troubleshooting Guides
