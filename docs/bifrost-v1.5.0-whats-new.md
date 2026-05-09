# Bifrost v1.5.0 — What's New

> Compared to v1.4.x. Released 6 May 2026.
> Full migration guide: https://docs.getbifrost.ai/migration-guides/v1.5.0

---

## 1. MCP Gateway — Major Expansion

MCP is the biggest area of change in v1.5.0. The gateway now has granular, enforcement-time control over what tools agents can call.

### Per-Tool Access Control on Virtual Keys

In v1.4.x, virtual keys could restrict which MCP clients were accessible, but not individual tools within a client. In v1.5.0, `tools_to_execute` on a virtual key acts as an enforcement-time allow-list — tools not listed are blocked at the point of inference and MCP execution, not just hidden in the UI.

```json
{
  "mcp_configs": [
    {
      "mcp_client_name": "kubernetes_local",
      "tools_to_execute": ["pods_list", "pods_get", "namespaces_list"]
    }
  ]
}
```

Use `["*"]` to allow all tools, `[]` to deny all.

### MCP Tool Groups

Tools can now be grouped and scoped to governance boundaries — virtual key, team, customer, user, provider, or API key. This allows you to define reusable sets of permitted tools and assign them across multiple virtual keys without duplicating config.

### Tool Annotations Preserved

MCP tool annotations (`readOnly`, `destructive`, `idempotent`, `openWorld`) are now preserved through bidirectional conversion. Agents can reason about tool behaviour before calling — e.g. refusing to call a `destructive` tool without confirmation.

### Per-Request Tool Filtering Headers

Two new request headers allow callers to filter which MCP tools are injected for a specific request, without changing the virtual key config:

```
x-bf-mcp-include-clients: kubernetes_local
x-bf-mcp-include-tools: pods_list,pods_get
```

Useful for demos and testing where you want a focused tool set per request.

### MCP Reverse Proxy OAuth

Full OAuth support for MCP servers sitting behind a reverse proxy, with separate server URL and client URL fields for cleaner configuration. Per-user OAuth flows are also supported.

### Disable Auto Tool Injection Per Request

A new `DisableAutoToolInject` flag on `MCPToolManagerConfig` suppresses automatic MCP tool injection for requests that don't need it, reducing token usage and prompt size.

---

## 2. Governance — Deny-by-Default Semantics (Breaking)

The most significant behavioural change in v1.5.0. The meaning of empty arrays has been inverted across all allow-list fields.

| What you write | v1.4.x | v1.5.0 |
|---|---|---|
| `[]` | Allow **all** | Allow **none** |
| `["*"]` | N/A | Allow **all** |
| `["a","b"]` | Only a and b | Only a and b |

Affected fields: `models` (provider key), `allowed_models` (VK provider config), `key_ids` (VK provider config), `tools_to_execute` (VK MCP config).

**Automatic migration runs on first startup** — existing data is converted. Any new config created after upgrading must use the new semantics explicitly.

### Virtual Keys are Now Deny-by-Default

In v1.4.x, a virtual key with no `provider_configs` had access to all providers. In v1.5.0 it blocks all providers. New VKs must explicitly list providers:

```json
{
  "provider_configs": [
    { "provider": "anthropic", "allowed_models": ["*"], "key_ids": ["*"], "weight": 1.0 },
    { "provider": "ollama",    "allowed_models": ["*"], "key_ids": ["*"], "weight": 1.0 }
  ]
}
```

### Whitelist Validation

Two new validation rules enforced at the API level (returns HTTP 400 if violated):
- Wildcard `*` cannot be mixed with specific values — `["*", "gpt-4o"]` is invalid
- Duplicate values are not allowed — `["gpt-4o", "gpt-4o"]` is invalid

---

## 3. Provider Keys API Separated

Provider key management now has dedicated endpoints. The `keys` field has been removed from provider create/update payloads entirely.

| Before (v1.4.x) | After (v1.5.0) |
|---|---|
| `POST /api/providers` with `keys` field | `keys` field ignored/removed |
| `GET /api/providers/{p}` returns `keys` | `keys` field absent |
| No dedicated keys endpoint | `GET/POST /api/providers/{p}/keys` |
| | `PUT/DELETE /api/providers/{p}/keys/{id}` |

`allowed_keys` has also been renamed to `key_ids` everywhere.

---

## 4. Model Aliases — Unified Field

Per-provider `deployments` maps (Azure, Bedrock, Vertex, Replicate) have been replaced with a single unified `aliases` field. This simplifies config and provides consistent aliasing across all providers.

```json
{
  "aliases": {
    "my-gpt4": "gpt-4o",
    "fast-model": "gpt-4o-mini"
  }
}
```

Existing `deployments` configs are automatically migrated on first startup.

---

## 5. Auto-Resolve Provider

When no provider prefix is given in the model name, Bifrost now auto-resolves the provider from configured providers. Previously this would return a 400 error — `model should be in provider/model format`. Now it will attempt to match the model name across registered providers.

---

## 6. Observability — New Metrics

v1.5.0 adds metrics that were absent in v1.4.x:

| Metric | What it tracks |
|---|---|
| `bifrost_error_requests_total` | Failed requests by provider/model/status code |
| `bifrost_cost_total` | Accumulated cost in USD by provider/model/virtual key |
| `bifrost_stream_first_token_latency_seconds` | Time-to-first-token histogram for streaming requests |
| `bifrost_stream_inter_token_latency_seconds` | Inter-token latency histogram for streaming requests |

These are the metrics that our `PrometheusRule` alerts are built on — none of them existed in v1.4.24.

### Per-Request Content Logging Overrides

Content logging and raw request/response visibility can now be toggled per-request via override flags, rather than being a global setting. Useful for debugging specific requests without turning on full content logging cluster-wide.

### Passthrough Streaming Accumulation

Raw provider streams (passthrough mode) are now accumulated properly, enabling cost tracking and logging on streams that previously bypassed the accounting layer.

---

## 7. Anthropic — New Model and Capability Support

- **Claude Opus 4.7** — compatibility including adaptive thinking, task-budget beta headers, display parameter handling, and `xhigh` effort mapping
- **Structured Outputs** — `response_format` and structured-output support across chat completions and Responses API
- **Anthropic Server Tools** — web search, code execution, and computer use containers surfaced end-to-end through the gateway
- **Computer Use** — cross-provider parity fixes across Bedrock, Vertex, and direct Anthropic

---

## 8. Weight is Now Nullable on Virtual Key Provider Configs

`weight` on a VK provider config was previously a required `float64`. It is now an optional `*float64`:

- `weight: 0.5` — provider participates in weighted load balancing
- `weight: null` / omitted — provider is accessible for direct routing but excluded from weighted selection

This allows you to configure providers that are only reachable via explicit routing rules, not load balancing.

---

## 9. Breaking Changes Summary

| # | Change | Impact |
|---|---|---|
| 1 | Empty array `[]` now means deny-all | All allow-list fields — auto-migrated for existing data |
| 2 | `allowed_keys` renamed to `key_ids` | Must update any direct API calls or config.json |
| 3 | VK `provider_configs: []` now blocks all providers | New VKs need explicit provider list |
| 4 | Whitelist validation — no mixed wildcards, no duplicates | API returns 400 on invalid config |
| 5 | `weight` is now nullable | Client code assuming non-null weight needs updating |
| 6 | Provider keys API separated | `keys` removed from provider payload — use `/keys` endpoints |
| 7 | Compat plugin restructured | If using LiteLLM compat plugin, check migration guide |
| 8 | Replicate image edits removed from generations endpoint | Use dedicated edits endpoint |
| 9 | Provider `deployments` replaced by `aliases` | Auto-migrated for existing data |

> **Database backup required before upgrading.** The automatic migration is not revertible. A database migrated to v1.5.0 cannot run v1.4.x.

---

*Source: https://docs.getbifrost.ai/migration-guides/v1.5.0 · https://docs.getbifrost.ai/changelogs/v1.5.0-prerelease7*
