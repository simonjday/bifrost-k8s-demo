# Bifrost Demo Guide
**Open WebUI + curl — Local Ollama via Bifrost Gateway**
`devops-lab` · `bifrost-k8s-demo` · May 2026

---

## Overview

This guide covers two ways to demo Bifrost as an AI gateway for local Ollama models:

1. **curl** — direct API calls to demonstrate routing, auth, and access control
2. **Open WebUI** — a full chat UI that real users would recognise, backed by local Ollama models routed through Bifrost

Both approaches use the same Bifrost completions endpoint at `http://localhost:8080/v1/chat/completions`.

---

## Prerequisites

Before running any demo, confirm these are running:

```bash
# Bifrost port-forward
lsof -i :8080 | grep kubectl

# Ollama listening on all interfaces
lsof -i :11434 | grep -E '\*|0\.0\.0\.0'

# Quick end-to-end check
curl -s http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: sk-bf-0b7391e8-12b3-45f7-xxxxx" \
  -d '{"model":"openai/qwen2.5:7b","messages":[{"role":"user","content":"ping"}],"max_tokens":5}' \
  | jq '.choices[0].message.content'
```

---

## Part 1 — curl Demo

These curl commands tell a complete story about Bifrost's capabilities in sequence. Run them in order for maximum impact.

### Setup — Virtual Key Variables

```bash
export KEY_ALL="sk-bf-0b7391e8-12b3-45f7-bf83-xxxx"   # unrestricted key
export KEY_RESTRICTED="<your-restricted-key>"                   # llama3.2:3b only
export BIFROST="http://localhost:8080"
```

---

### 1. Basic Routing — Bifrost forwards to Ollama

```bash
curl -s $BIFROST/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY_ALL" \
  -d '{
    "model": "openai/qwen2.5:7b",
    "messages": [{"role":"user","content":"In one sentence, what is an AI gateway?"}],
    "max_tokens": 60
  }' | jq '{model, response: .choices[0].message.content, latency_ms: .extra_fields.latency}'
```

**What it shows:** Single endpoint, local model, sub-second latency.

---

### 2. Model Switching — Same endpoint, different model

```bash
curl -s $BIFROST/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY_ALL" \
  -d '{
    "model": "openai/llama3.2:3b",
    "messages": [{"role":"user","content":"In one sentence, what is an AI gateway?"}],
    "max_tokens": 60
  }' | jq '{model, response: .choices[0].message.content, latency_ms: .extra_fields.latency}'
```

**What it shows:** Switch from `qwen2.5:7b` to `llama3.2:3b` with no config change — same endpoint, same key.

---

### 3. Specialist Model Routing — Code model

```bash
curl -s $BIFROST/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY_ALL" \
  -d '{
    "model": "openai/qwen2.5-coder:7b",
    "messages": [{"role":"user","content":"Write a one-line Python function that checks if a number is prime."}],
    "max_tokens": 80
  }' | jq '{model, response: .choices[0].message.content}'
```

**What it shows:** Route to a specialist code model transparently — no code changes needed in the calling application.

---

### 4. Streaming Response

```bash
curl -s $BIFROST/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY_ALL" \
  -d '{
    "model": "openai/qwen2.5:7b",
    "messages": [{"role":"user","content":"List 3 benefits of running LLMs locally."}],
    "max_tokens": 150,
    "stream": true
  }'
```

**What it shows:** SSE streaming works end-to-end through Bifrost to Ollama.

---

### 5. Model Discovery — List available models

```bash
curl -s $BIFROST/v1/models \
  -H "X-Api-Key: $KEY_ALL" | jq '.data[].id'
```

**What it shows:** Bifrost exposes all registered models via the standard OpenAI models endpoint.

---

### 6. Access Control — Allowed model (restricted key)

```bash
curl -s $BIFROST/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY_RESTRICTED" \
  -d '{
    "model": "openai/llama3.2:3b",
    "messages": [{"role":"user","content":"ping"}],
    "max_tokens": 10
  }' | jq '{model, response: .choices[0].message.content}'
```

**What it shows:** Restricted key successfully calls its permitted model.

---

### 7. Access Control — Blocked model (restricted key)

```bash
curl -s $BIFROST/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY_RESTRICTED" \
  -d '{
    "model": "openai/qwen2.5:7b",
    "messages": [{"role":"user","content":"ping"}],
    "max_tokens": 10
  }' | jq .
```

**Expected response:**
```json
{
  "type": "model_blocked",
  "status_code": 403,
  "error": {
    "message": "Model 'qwen2.5:7b' is not allowed for this virtual key"
  }
}
```

**What it shows:** Bifrost enforces model-level access control per virtual key — the backend never receives the request.

---

### 8. Auth Rejection — Invalid key

```bash
curl -s $BIFROST/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: sk-invalid-key" \
  -d '{
    "model": "openai/qwen2.5:7b",
    "messages": [{"role":"user","content":"ping"}],
    "max_tokens": 10
  }' | jq .
```

**What it shows:** Unknown keys are rejected at the gateway before reaching any model.

---

### 9. Full Metadata — Show audit trail fields

```bash
curl -s $BIFROST/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY_ALL" \
  -d '{
    "model": "openai/qwen2.5:7b",
    "messages": [{"role":"user","content":"ping"}],
    "max_tokens": 10
  }' | jq '{
    model,
    provider: .extra_fields.provider,
    model_requested: .extra_fields.model_requested,
    latency_ms: .extra_fields.latency,
    request_type: .extra_fields.request_type,
    tokens: .usage
  }'
```

**What it shows:** Every request carries full audit metadata — provider, model, latency, token usage — available in the Bifrost UI Logs tab.

---

## Part 2 — Open WebUI Setup

Open WebUI is a self-hosted ChatGPT-style interface. Pointed at Bifrost, it gives non-technical users a familiar chat experience backed entirely by local Ollama models.

### Architecture

```
Browser → Open WebUI :3001 → Bifrost :8080 → Ollama :11434 (local models)
```

> ⚠️ Port `3000` is used by Grafana in this environment. Open WebUI runs on `3001`.

### Install and Run

**Option A — Docker (recommended):**

```bash
docker run -d \
  --name open-webui \
  -p 3001:8080 \
  -e OPENAI_API_BASE_URL=http://host.docker.internal:8080/v1 \
  -e OPENAI_API_KEY=sk-bf-0b7391e8-12b3-45f7-bf83-xxxxx \
  -v open-webui:/app/backend/data \
  --restart always \
  ghcr.io/open-webui/open-webui:main
```

> ⚠️ `host.docker.internal` resolves to the Mac host from inside Docker — this routes Open WebUI → Bifrost on your Mac. Do not use `localhost` here.

**Option B — Docker Compose:**

```yaml
services:
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    ports:
      - "3001:8080"
    environment:
      OPENAI_API_BASE_URL: http://host.docker.internal:8080/v1
      OPENAI_API_KEY: sk-bf-0b7391e8-12b3-45f7-bf83-xxxxxxx
    volumes:
      - open-webui:/app/backend/data
    restart: always

volumes:
  open-webui:
```

```bash
docker compose up -d
```

### Access Open WebUI

Open `http://localhost:3001` in your browser. On first launch, create an admin account (local only, no external auth).

### Select a Model

In the model dropdown you will see all models registered in Bifrost (the same ones returned by `GET /v1/models`). Select any `openai/` prefixed model to route through Bifrost to Ollama.

### Verify Bifrost is in the path

After sending a message, check the Bifrost UI **Logs** tab at `http://localhost:8080` — you should see the request appear with provider `openai`, the model name, latency, and token counts.

---

## Demo Story — Talking Points

Run these in order for a complete demo narrative:

| Step | curl # | What you say |
|---|---|---|
| Single endpoint | 1 | "One URL for all models — local or cloud" |
| Model switch | 2 | "Change the model string, nothing else changes" |
| Specialist model | 3 | "Route to a code model transparently" |
| Streaming | 4 | "Streaming works end to end" |
| Model list | 5 | "Bifrost knows what's available" |
| Allowed access | 6 | "This key is scoped to one model" |
| Blocked access | 7 | "Other models are rejected at the gateway" |
| Auth rejection | 8 | "Unknown keys never reach the backend" |
| Audit trail | 9 | "Every request is logged with full metadata" |
| Open WebUI | — | "This is what a real user sees" |

---

## Quick Reference

| Item | Value |
|---|---|
| Bifrost endpoint | `http://localhost:8080/v1/chat/completions` |
| Models endpoint | `http://localhost:8080/v1/models` |
| Bifrost UI / Logs | `http://localhost:8080` |
| Open WebUI | `http://localhost:3001` |
| Auth header | `X-Api-Key: <virtual-key>` |
| Model prefix | `openai/<modelname>` |
| Start port-forward | `kubectl -n ai-gateway port-forward svc/bifrost 8080:8080 &` |
