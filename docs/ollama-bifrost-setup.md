# Ollama Local Models in Bifrost
**Configuration & Usage Guide**
`devops-lab` · `bifrost-k8s-demo` · May 2026

---

## Overview

Bifrost acts as a unified AI gateway running inside your local kind cluster. By registering Ollama as an OpenAI-compatible provider, any client can route requests to locally-running Ollama models without leaving your machine.

---

## Architecture

```
curl / Open WebUI  →  Bifrost :8080 (kind pod)  →  Ollama (Mac host :11434)
```

Bifrost runs inside a kind cluster (Docker Desktop). Ollama runs natively on the Mac host. The Mac's LAN IP (`192.168.1.21`) is directly reachable from kind pods via Docker Desktop's network bridging.

```
kind pod (bifrost-0)
    │
    │  openai provider → http://192.168.1.21:11434
    ▼
Mac Host
    ├── Ollama (0.0.0.0:11434)
    └── kubernetes-mcp-server (0.0.0.0:8811)
```

> **kind + Docker Desktop:** Use `192.168.1.21` (Mac LAN IP) as the Ollama base URL. This is confirmed reachable from kind pods. Update if your DHCP address changes — consider setting a DHCP reservation.

> **k3d clusters:** The same Mac LAN IP approach works for k3d. For kind clusters using an older Docker Desktop version where the LAN IP is not routable, use `192.168.65.254` (Docker Desktop gateway) instead and deploy a socat proxy pod.

---

## Prerequisites

- Ollama installed: `brew install ollama`
- kind cluster running with Bifrost deployed in `ai-gateway` namespace
- `kubectl port-forward` running: `kubectl -n ai-gateway port-forward svc/bifrost 8080:8080 &`

---

## Step 1 — Ensure Ollama Listens on All Interfaces

By default Ollama binds to `localhost` only — kind pods cannot reach it. Set `OLLAMA_HOST=0.0.0.0`.

Check current binding:

```bash
lsof -i :11434
# TCP localhost:11434 (LISTEN)  ← bad — pods can't reach this
# TCP *:11434 (LISTEN)          ← good
```

### Option A — launchctl + brew services (session-level, validated)

```bash
launchctl setenv OLLAMA_HOST 0.0.0.0
brew services restart ollama
lsof -i :11434   # verify TCP *:11434
```

> `launchctl setenv` persists for the current login session only — it does not survive a full reboot. Use Option B for a permanent fix.

### Option B — Edit the Homebrew plist (permanent, survives reboots)

Edit `~/Library/LaunchAgents/homebrew.mxcl.ollama.plist` and add `OLLAMA_HOST` to the `EnvironmentVariables` dict:

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

Force a full reload:

```bash
launchctl unload ~/Library/LaunchAgents/homebrew.mxcl.ollama.plist
launchctl load -w ~/Library/LaunchAgents/homebrew.mxcl.ollama.plist
lsof -i :11434   # verify TCP *:11434
```

### Option C — One-shot (no persistence)

```bash
pkill ollama
OLLAMA_HOST=0.0.0.0 ollama serve &
```

---

## Step 2 — Pull Models

Pull models on your Mac before registering them. Bifrost does not pull models automatically.

```bash
ollama pull qwen2.5:7b
ollama pull qwen2.5-coder:7b
ollama pull qwen3-coder:30b
ollama pull llama3.2:3b
ollama pull gemma4:latest
```

### Validated models

| Model | Size | Use case |
|---|---|---|
| `qwen2.5:7b` | 4.7 GB | General queries, fast |
| `qwen2.5-coder:7b` | 4.7 GB | Code generation and review |
| `qwen3-coder:30b` | 18.6 GB | Complex code tasks, highest local quality |
| `llama3.2:3b` | 2.0 GB | Very fast, simple queries |
| `gemma4:latest` | 9.6 GB | General purpose |

> Note: `qwen2.5-coder:1.5b-base` is a base model — it does not support chat completions and returns a 400 error. Use `qwen2.5-coder:7b` instead.

### Warm-up before demos

First request to a model is slow (30–60s) due to model loading:

```bash
bash scripts/warmup-ollama.sh
# or manually:
ollama run qwen2.5:7b "ping" && exit
```

---

## Step 3 — Register Ollama as a Provider in Bifrost

In the Bifrost UI at **http://localhost:8080** → **Providers → Add Provider**:

| Field | Value |
|---|---|
| Provider Type | `openai` |
| Provider Name | `ollama` (or any label) |
| Base URL | `http://192.168.1.21:11434` |
| API Key | `ollama` (any non-empty string — Ollama ignores it) |

> Do **NOT** add `/v1` to the Base URL. Bifrost appends it automatically — adding it causes double-path errors (`/v1/v1/chat/completions`).

> Do **NOT** select the `ollama` provider type if it appears — always use `openai`. The `ollama` type hits `/api/chat` which is a different path.

---

## Step 4 — Create a Virtual Key

In the Bifrost UI → **Keys → Create Key**:

| Field | Value |
|---|---|
| Key Name | `ollama-local` |
| Provider Configurations | Select `OpenAI` (the Ollama provider) |
| Allowed Models | Leave empty to allow all models |
| Allowed Keys | Select the provider key — **required** |
| Weight | `1` |

> **Allowed Keys must not be left empty.** Despite the UI hint, leaving it empty causes a `403 Model is not allowed` error. Explicitly select the provider key.

Copy the generated virtual key — use it as the `X-Api-Key` header.

---

## Step 5 — Verify End-to-End

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

## Model Name Format

Always prefix with `openai/` regardless of model family:

| Model | Request string |
|---|---|
| `qwen2.5:7b` | `openai/qwen2.5:7b` |
| `qwen2.5-coder:7b` | `openai/qwen2.5-coder:7b` |
| `qwen3-coder:30b` | `openai/qwen3-coder:30b` |
| `llama3.2:3b` | `openai/llama3.2:3b` |
| `gemma4:latest` | `openai/gemma4:latest` |

---

## Understanding Bifrost's Two Roles

### Role 1 — MCP Server (Tool Gateway)

Bifrost exposes connected MCP tools (Kubernetes, Prometheus, etc.) through `/mcp`. Connecting Claude Desktop to Bifrost via MCP gives access to **tools**, not Ollama inference.

```
Claude Desktop ──MCP──▶ Bifrost /mcp ──▶ Kubernetes tools, Prometheus tools
```

### Role 2 — AI Gateway (Completions API)

Bifrost routes chat completion requests to providers including Ollama via `POST /v1/chat/completions`.

```
curl / app ──POST /v1/chat/completions──▶ Bifrost ──▶ Ollama (openai/qwen2.5:7b)
```

---

## Claude Desktop Integration (MCP Tools)

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

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
        "BIFROST_VIRTUAL_KEY": "<your-admin-key>"
      }
    }
  }
}
```

> The Bifrost port-forward must be running before Claude Desktop starts.

Restart Claude Desktop after saving:

```bash
osascript -e 'quit app "Claude"'
sleep 5
open -a Claude
```

Verify connection:

```bash
tail -f ~/Library/Logs/Claude/mcp-server-bifrost.log
# Look for: Proxy established successfully
```

---

## Open WebUI Setup

Open WebUI provides a chat interface for non-technical users backed by Ollama models through Bifrost.

```bash
docker run -d \
  --name open-webui \
  -p 3001:8080 \
  -e OPENAI_API_BASE_URL=http://host.docker.internal:8080/v1 \
  -e OPENAI_API_KEY=<your-admin-key> \
  -v open-webui:/app/backend/data \
  --restart always \
  ghcr.io/open-webui/open-webui:main
```

> Port `3000` is used by Grafana — Open WebUI runs on `3001`.
> `host.docker.internal` routes from the Docker container to the Mac host (Bifrost port-forward).

Access at `http://localhost:3001`. Models appear in the dropdown with the `openai/` prefix.

**Verify Bifrost is in the path:** After sending a message, check `http://localhost:8080/logs` — the request should appear with provider `openai`, the model name, latency, and token counts.

---

## Troubleshooting

| Issue | Root cause | Fix |
|---|---|---|
| `403 Model is not allowed` | Allowed Keys empty in virtual key config | Bifrost UI → Keys → Edit → Provider Configurations → select provider key |
| Connection refused from Bifrost to Ollama | Ollama bound to `localhost` | `OLLAMA_HOST=0.0.0.0 ollama serve` — verify `TCP *:11434` |
| `404 page not found` | Wrong provider type (`ollama` instead of `openai`) | Register as `openai` provider type |
| Double `/v1/v1` path error | `/v1` included in Base URL | Remove `/v1` from Base URL — use `http://192.168.1.21:11434` |
| Model not found | Model not pulled or not registered in provider | `ollama list` then add to Bifrost provider config |
| Slow first response | Ollama loading model into memory | Pre-warm: `ollama run qwen2.5:7b "ping"` before demo |
| `state: null` from Bifrost API | Port-forward not running | `kubectl -n ai-gateway port-forward svc/bifrost 8080:8080 &` |
| No models in Open WebUI dropdown | Port-forward not running or wrong env var | Check `OPENAI_API_BASE_URL=http://host.docker.internal:8080/v1` |

---

## Quick Reference

| Item | Value |
|---|---|
| Bifrost UI | `http://localhost:8080` |
| Completions endpoint | `POST http://localhost:8080/v1/chat/completions` |
| Auth header | `X-Api-Key: $BIFROST_VIRTUAL_KEY` |
| Ollama provider type | `openai` (NOT `ollama`) |
| Ollama base URL (kind) | `http://192.168.1.21:11434` (no `/v1` suffix) |
| OLLAMA_HOST binding | `OLLAMA_HOST=0.0.0.0 ollama serve` |
| Model prefix | `openai/<modelname>` |
| Check Ollama binding | `lsof -i :11434` — must show `TCP *:11434` |
| List pulled models | `ollama list` |
| Warm up a model | `ollama run qwen2.5:7b "ping"` |
| Open WebUI | `http://localhost:3001` |
