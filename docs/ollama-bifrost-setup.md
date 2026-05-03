# Ollama Local Models in Bifrost
**Configuration & Usage Guide for Claude Chat**
`devops-lab` · `bifrost-k8s-demo` · May 2026

---

## Overview

Bifrost acts as a unified AI gateway running inside your local k3d cluster. By registering Ollama as an OpenAI-compatible provider in Bifrost, any client — including Claude chat via the MCP connector — can route requests to locally-running Ollama models without leaving your machine.

---

## Architecture

The request flow from Claude chat to an Ollama model is:

```
Claude Chat  →  Bifrost (k3d or kind pod, ai-gateway ns)  →  Ollama (Mac host :11434)
```

Key points:

- Bifrost runs in the `ai-gateway` namespace on your local cluster (k3d or kind).
- Ollama runs natively on the Mac host, exposed on port `11434`.
- Bifrost reaches Ollama via a **host-reachable IP** — the exact IP differs between k3d and kind (see Cluster Networking below).
- Ollama is registered as an **`openai` provider type** — NOT an `ollama` type.
- Models are addressed as `openai/<modelname>` in requests.

---

## Prerequisites

### Software

- Ollama installed on Mac — `brew install ollama`
- k3d or kind cluster running
- Bifrost deployed in `ai-gateway` namespace via Helm
- `kubectl port-forward` running on `localhost:8080 → bifrost:8080`

### Cluster Networking — k3d vs kind

The IP used to reach Ollama from inside Bifrost pods **differs between cluster types**. Use the correct one when registering the Ollama provider.

| Cluster | Ollama Base URL | Notes |
|---|---|---|
| **kind** | `http://192.168.65.254:11434` | Docker Desktop internal gateway — always stable |
| **k3d** | `http://<MAC_LAN_IP>:11434` | Mac LAN IP e.g. `192.168.1.21` — can change on DHCP |

```bash
# Find your Mac LAN IP (needed for k3d only)
ipconfig getifaddr en0
```

> ⚠️ **kind** — use `192.168.65.254` (Docker Desktop gateway). The Mac LAN IP is not routable from kind pods.

> ⚠️ **k3d** — use the Mac LAN IP. `host.k3d.internal` does not resolve reliably from inside pods.

> ⚠️ **k3d + DHCP** — if your Mac LAN IP changes, update the Ollama provider Base URL in Bifrost and re-save. Consider setting a DHCP reservation.

---

## Ollama Setup

### Ensure Ollama Listens on All Interfaces

By default Ollama binds to `localhost` only, which means Bifrost pods cannot reach it. You must set `OLLAMA_HOST=0.0.0.0` before starting Ollama.

Check what Ollama is currently bound to:

```bash
lsof -i :11434
# Look for: TCP localhost:11434 (LISTEN)  ← bad, pods can't reach this
# Look for: TCP *:11434 (LISTEN)          ← good
```

#### Option A — launchctl setenv + brew services restart (validated fix)

`brew services restart` alone may not pick up plist changes due to macOS launchd caching. The reliable approach is to set the env var at the session level and then restart:

```bash
launchctl setenv OLLAMA_HOST 0.0.0.0
brew services restart ollama

# Verify — should show TCP *:11434 not TCP localhost:11434
lsof -i :11434
```

> ⚠️ `launchctl setenv` persists for the current login session only — it does not survive a full reboot. Combine with Option B for a fully permanent fix.

#### Option B — Edit the Homebrew Ollama plist (permanent, survives reboots)

The plist is at `~/Library/LaunchAgents/homebrew.mxcl.ollama.plist`. Add `OLLAMA_HOST` to the existing `EnvironmentVariables` dict. Full updated plist:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>EnvironmentVariables</key>
	<dict>
		<key>OLLAMA_FLASH_ATTENTION</key>
		<string>1</string>
		<key>OLLAMA_HOST</key>
		<string>0.0.0.0</string>
		<key>OLLAMA_KV_CACHE_TYPE</key>
		<string>q8_0</string>
	</dict>
	<key>KeepAlive</key>
	<true/>
	<key>Label</key>
	<string>homebrew.mxcl.ollama</string>
	<key>LimitLoadToSessionType</key>
	<array>
		<string>Aqua</string>
		<string>Background</string>
		<string>LoginWindow</string>
		<string>StandardIO</string>
		<string>System</string>
	</array>
	<key>ProgramArguments</key>
	<array>
		<string>/opt/homebrew/opt/ollama/bin/ollama</string>
		<string>serve</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>StandardErrorPath</key>
	<string>/opt/homebrew/var/log/ollama.log</string>
	<key>StandardOutPath</key>
	<string>/opt/homebrew/var/log/ollama.log</string>
	<key>WorkingDirectory</key>
	<string>/opt/homebrew/var</string>
</dict>
</plist>
```

After saving, force a full reload to ensure the change takes effect:

```bash
launchctl unload ~/Library/LaunchAgents/homebrew.mxcl.ollama.plist
launchctl load -w ~/Library/LaunchAgents/homebrew.mxcl.ollama.plist

# Verify
lsof -i :11434
# Should show: TCP *:11434 (LISTEN)
```

#### Option C — One-shot (no persistence)

For a quick test without changing the service config:

```bash
pkill ollama
OLLAMA_HOST=0.0.0.0 ollama serve &
```

---

## Step 1 — Register Ollama as a Provider in Bifrost

Open the Bifrost UI at **http://localhost:8080** and navigate to **Providers → Add Provider**.

| Field | Value |
|---|---|
| Provider Type | `openai` |
| Provider Name | `ollama` (or any label you prefer) |
| Base URL (kind) | `http://192.168.65.254:11434` |
| Base URL (k3d) | `http://<YOUR_LAN_IP>:11434` |
| API Key | `ollama` (any non-empty string — Ollama ignores it) |
| Models | Add each model you have pulled — see Step 2 |

> ⚠️ Do **NOT** add `/v1` to the Base URL. Bifrost appends the path automatically. Using `/v1` will cause double-path errors.

> ⚠️ Do **NOT** select the `ollama` provider type if it appears — use `openai`. The OpenAI-compatible endpoint is what Bifrost uses.

---

## Step 2 — Pull Ollama Models

Pull models on your Mac before registering them. Bifrost does not pull models automatically.

### Validated Models (currently pulled)

| Model | Size | Use Case |
|---|---|---|
| `qwen2.5:7b` | 4.7 GB | General queries, fast responses |
| `qwen2.5-coder:7b` | 4.7 GB | Code generation and review |
| `qwen2.5-coder:1.5b-base` | 986 MB | Lightweight code tasks, very fast |
| `qwen3-coder:30b` | 18.6 GB | Large code tasks (slower, higher quality) |
| `llama3.2:3b` | 2.0 GB | Lightweight / low-latency queries |
| `gemma4:latest` | 9.6 GB | General purpose (Google) |

### Pull Commands

```bash
ollama pull qwen2.5:7b
ollama pull qwen2.5-coder:7b
ollama pull qwen2.5-coder:1.5b-base
ollama pull qwen3-coder:30b
ollama pull llama3.2:3b
ollama pull gemma4:latest
```

### Warm-up (Recommended Before Demos)

The first request to a model is slow due to model loading. Pre-warm using:

```bash
# From the bifrost-k8s-demo repo
./scripts/warmup-ollama.sh

# Or manually
curl http://localhost:11434/api/generate \
  -d '{"model":"qwen2.5:7b","prompt":"ping","stream":false}'
```

---

## Step 3 — Create a Virtual Key

Virtual keys control which providers and models are accessible. Create one scoped to your Ollama provider.

In the Bifrost UI: **Keys → Create Key**

| Field | Value |
|---|---|
| Key Name | `ollama-local` (or any label) |
| Provider Configurations | Select `OpenAI` (the Ollama provider) |
| Allowed Models | Leave empty to allow all models on the provider |
| Allowed Keys | Select the provider key (e.g. `ollama-local`) — **required** |
| Weight | `1` |

> ⚠️ **Allowed Keys must not be left empty.** Even though the hint says "keep empty to use all available keys", leaving it empty results in a 403 `Model is not allowed for this virtual key` error. You must explicitly select the provider key from the dropdown.

> ⚠️ **Allowed Models** — leave this empty to allow all models registered on the provider. If you add model names here, they must match exactly what is registered on the provider (bare name, no `openai/` prefix).

Copy the generated virtual key — you will use it as the `X-Api-Key` header in requests.

---

## Step 4 — Calling Ollama Models from Claude Chat

Claude chat routes requests through the Bifrost MCP connector. Once the provider and virtual key are configured, you can target Ollama models directly.

### Model Name Format

Always prefix the model name with `openai/`:

| Model | Request string |
|---|---|
| `qwen2.5:7b` | `openai/qwen2.5:7b` |
| `qwen2.5-coder:7b` | `openai/qwen2.5-coder:7b` |
| `qwen2.5-coder:1.5b-base` | `openai/qwen2.5-coder:1.5b-base` |
| `qwen3-coder:30b` | `openai/qwen3-coder:30b` |
| `llama3.2:3b` | `openai/llama3.2:3b` |
| `gemma4:latest` | `openai/gemma4:latest` |

> ⚠️ The prefix is always `openai/` regardless of the model family, because Bifrost registered Ollama as an OpenAI-compatible provider.

### Direct curl Test

Verify the end-to-end path before using from Claude chat:

```bash
curl -s http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $BIFROST_VIRTUAL_KEY" \
  -d '{
    "model": "openai/qwen2.5:7b",
    "messages": [{"role":"user","content":"Hello, respond in one sentence."}],
    "max_tokens": 100
  }' | jq '.choices[0].message.content'
```

---

## Step 5 — Understanding Bifrost's Two Roles

Bifrost serves two distinct purposes — it is important to understand both before connecting it to Claude Desktop.

### Role 1 — MCP Server (Tool Gateway)

Bifrost acts as an MCP server, exposing whatever external MCP tools it is connected to (e.g. `kubernetes-mcp-server`) through a single `/mcp` endpoint. When Claude Desktop connects to Bifrost via MCP, it discovers and can use those **tools** — not Ollama models.

```
Claude Desktop ──MCP──▶ Bifrost /mcp ──▶ kubernetes tools, filesystem tools, etc.
```

### Role 2 — AI Gateway (Completions API)

Bifrost also acts as an OpenAI-compatible HTTP gateway, routing chat completion requests to configured providers including Ollama. This is how you call Ollama models — via `POST /v1/chat/completions`, not via MCP.

```
curl / application ──POST /v1/chat/completions──▶ Bifrost ──▶ Ollama (openai/qwen2.5:7b)
```

> ⚠️ Connecting Bifrost as an MCP tool in Claude Desktop gives Claude access to **Kubernetes and other connected tools**, not Ollama inference. Calling Ollama models is done via the completions API separately.

---

## Step 6 — Connecting Bifrost to Claude Desktop (MCP Tools)

This gives Claude Desktop access to all tools Bifrost is connected to (e.g. kubernetes-mcp-server). Add the `bifrost` entry to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "kubernetes-local": {
      "command": "npx",
      "args": ["-y", "kubernetes-mcp-server@latest"]
    },
    "argocd": {
      "command": "npx",
      "args": ["-y", "argocd-mcp@latest", "stdio"],
      "env": {
        "ARGOCD_BASE_URL": "http://localhost:9080",
        "ARGOCD_API_TOKEN": "<your-token>"
      }
    },
    "bifrost": {
      "command": "npx",
      "args": [
        "-y",
        "mcp-remote@latest",
        "http://localhost:8080/mcp",
        "--header",
        "X-Api-Key: ${BIFROST_VIRTUAL_KEY}"
      ],
      "env": {
        "BIFROST_VIRTUAL_KEY": "sk-bf-xxxx-your-key"
      }
    }
  }
}
```

> ⚠️ The Bifrost port-forward must be running **before** Claude Desktop starts: `kubectl -n ai-gateway port-forward svc/bifrost 8080:8080 &`

Restart Claude Desktop after saving:

```bash
osascript -e 'quit app "Claude"'
sleep 5
open -a Claude
```

Check the MCP log to verify connection:

```bash
tail -f ~/Library/Logs/Claude/mcp-server-bifrost.log
```

You should see `Proxy established successfully` and `tools/list` completing without errors.

---

## Step 7 — Calling Ollama Models via the Completions API

Ollama models are called directly via the Bifrost completions API — not through the MCP connection. With the port-forward running, use the following pattern:

### curl

```bash
curl -s http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: sk-bf-xxxx-your-key" \
  -d '{
    "model": "openai/qwen2.5:7b",
    "messages": [{"role":"user","content":"What is a Kubernetes deployment?"}],
    "max_tokens": 500
  }' | jq '.choices[0].message.content'
```

### From an application or script

Point any OpenAI-compatible SDK at `http://localhost:8080` with your virtual key and use `openai/<modelname>` as the model string.

### Model strings

| Model | Request string |
|---|---|
| `qwen2.5:7b` | `openai/qwen2.5:7b` |
| `qwen2.5-coder:7b` | `openai/qwen2.5-coder:7b` |
| `qwen2.5-coder:1.5b-base` | `openai/qwen2.5-coder:1.5b-base` |
| `qwen3-coder:30b` | `openai/qwen3-coder:30b` |
| `llama3.2:3b` | `openai/llama3.2:3b` |
| `gemma4:latest` | `openai/gemma4:latest` |

### Model selection guide

| If you need... | Use |
|---|---|
| Fast general answers | `openai/llama3.2:3b` or `openai/qwen2.5-coder:1.5b-base` |
| Good general answers | `openai/qwen2.5:7b` |
| Code generation / review | `openai/qwen2.5-coder:7b` |
| Complex code tasks | `openai/qwen3-coder:30b` |
| General purpose alternative | `openai/gemma4:latest` |

### Verify which model responded

The response always includes metadata confirming the model used:

```json
"extra_fields": {
  "provider": "openai",
  "model_requested": "qwen2.5:7b",
  "latency": 17081
}
```

Check the Bifrost UI under **Logs** for a full audit trail of every request.

---



### 403 — Model is not allowed for this virtual key

This means the virtual key's **Allowed Keys** field is empty — no provider key is linked to it. In the Bifrost UI:

1. **Keys → Edit** the virtual key
2. Under **Provider Configurations → OpenAI → Allowed Keys**, select the provider key (e.g. `ollama-local`)
3. Save

Do not leave Allowed Keys empty even though the UI hint implies it is optional.

### Connection Refused from Bifrost to Ollama

- Confirm Ollama is running: `curl http://localhost:11434/api/tags`
- Confirm `OLLAMA_HOST=0.0.0.0` is set — `lsof -i :11434` should show `TCP *:11434` not `TCP localhost:11434`
- **kind** — use `192.168.65.254` as the Base URL, not the Mac LAN IP
- **k3d** — use the Mac LAN IP (e.g. `192.168.1.21`), not `localhost` or `host.k3d.internal`
- Check macOS firewall is not blocking port `11434`

### Model Not Found

- Confirm the model is pulled: `ollama list`
- Confirm the model is registered in the Bifrost provider settings
- Model names are case-sensitive and must match exactly (e.g. `qwen2.5:7b` not `Qwen2.5:7b`)

### Slow First Response

This is normal. Ollama loads the model into memory on first request. Subsequent requests are fast. Run the warmup script before demos.

### `state: null` from Bifrost API

The port-forward to Bifrost is not running. Start it:

```bash
kubectl -n ai-gateway port-forward svc/bifrost 8080:8080 &
```

### Double `/v1/v1` Path Error

This happens when the Bifrost provider Base URL includes `/v1`. Remove the `/v1` suffix from the Ollama provider Base URL — Bifrost appends it automatically.

---

## Quick Reference

| Item | Value |
|---|---|
| Bifrost UI | `http://localhost:8080` |
| Completions endpoint | `POST http://localhost:8080/v1/chat/completions` |
| Auth header | `X-Api-Key: $BIFROST_VIRTUAL_KEY` |
| Ollama provider type | `openai` (NOT `ollama`) |
| Ollama base URL (kind) | `http://192.168.65.254:11434` (no `/v1` suffix) |
| Ollama base URL (k3d) | `http://<LAN_IP>:11434` (no `/v1` suffix) |
| OLLAMA_HOST binding | `OLLAMA_HOST=0.0.0.0 ollama serve` |
| Model prefix | `openai/<modelname>` e.g. `openai/qwen2.5:7b` |
| Check Ollama is up | `curl http://localhost:11434/api/tags` |
| List pulled models | `ollama list` |
| Warm up a model | `ollama run qwen2.5:7b "ping"` |
| Start port-forward | `kubectl -n ai-gateway port-forward svc/bifrost 8080:8080 &` |
