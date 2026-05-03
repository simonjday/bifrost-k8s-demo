# Bifrost Demo — Open WebUI Scenarios
**Step-by-step walkthrough for demonstrating local Ollama models via Bifrost**
`devops-lab` · May 2026

---

## Pre-flight Checklist

Before starting the demo, confirm everything is running:

```bash
# 1. Bifrost port-forward
lsof -i :8080 | grep kubectl

# 2. Ollama listening on all interfaces
lsof -i :11434 | grep '\*'

# 3. Open WebUI container running
docker ps | grep open-webui

# 4. Quick end-to-end sanity check
curl -s http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: sk-bf-0b7391e8-12b3-45f7-bf83-69f6f8910115" \
  -d '{"model":"openai/qwen2.5:7b","messages":[{"role":"user","content":"ping"}],"max_tokens":5}' \
  | jq '.choices[0].message.content'
```

All four must pass before starting. Open the Bifrost UI at `http://localhost:8080` in a second browser tab — keep it open on the **Logs** page throughout the demo.

---

## First-Time Setup (do once)

### 1. Open Open WebUI

Navigate to `http://localhost:3001` in your browser.

### 2. Create an admin account

On first launch you will be prompted to create a local admin account. Fill in any name, email, and password — this is local only, no external auth required.

### 3. Verify models are available

Click the model dropdown at the top of the chat window. You should see all models registered in Bifrost listed with the `openai/` prefix:

- `openai/qwen2.5:7b`
- `openai/qwen2.5-coder:7b`
- `openai/qwen2.5-coder:1.5b-base`
- `openai/qwen3-coder:30b`
- `openai/llama3.2:3b`
- `openai/gemma4:latest`

> ⚠️ If no models appear, confirm the Bifrost port-forward is running and that the `OPENAI_API_BASE_URL` env var in the Docker container points to `http://host.docker.internal:8080/v1`.

---

## Scenario 1 — Basic Chat (Any Model)

**What it demonstrates:** Open WebUI as a real user-facing chat interface backed by local Ollama models through Bifrost. No API keys, no curl — just a chat window.

### Steps

1. Open `http://localhost:3001`
2. Click **New Chat**
3. Select `openai/qwen2.5:7b` from the model dropdown
4. Type this prompt and send:

```
What are the three main benefits of running large language models locally rather than using a cloud API?
```

5. Watch the response stream in real time
6. Switch to the Bifrost UI tab (`http://localhost:8080/logs`)
7. Show the log entry — point out: provider `openai`, model `qwen2.5:7b`, latency, token count

**Talking point:** _"The user sees a familiar chat interface. Under the hood every message routes through Bifrost to a local Ollama model. Nothing leaves the machine."_

---

## Scenario 2 — Model Switching

**What it demonstrates:** Switching between models in the same chat session — no config changes, no restarts, just select a different model.

### Steps

1. Continue in the same chat or click **New Chat**
2. Select `openai/llama3.2:3b` from the model dropdown
3. Send the same prompt:

```
What are the three main benefits of running large language models locally rather than using a cloud API?
```

4. Compare the response — note the difference in style, depth, and speed
5. Switch to `openai/qwen2.5:7b` and send again
6. Point to the Bifrost Logs tab — show two separate log entries, each with different model names and latency figures

**Talking point:** _"One endpoint, one key, multiple models. The application doesn't change — just the model string."_

---

## Scenario 3 — Specialist Code Model

**What it demonstrates:** Routing to a code-specific model transparently, showing Bifrost can direct traffic to the right model for the task.

### Steps

1. Click **New Chat**
2. Select `openai/qwen2.5-coder:7b` from the model dropdown
3. Send this prompt:

```
Write a Python function that takes a Kubernetes pod status JSON object and returns a list of all containers that are not in the Running state, including the container name and current state.
```

4. Let the response complete — show the code output
5. Now switch to `openai/llama3.2:3b` and send the same prompt
6. Compare the output quality between a general model and a code-specialist model

**Talking point:** _"Bifrost lets you route different workloads to specialist models. Code tasks go to the code model, general queries to a lighter model — all through one gateway."_

---

## Scenario 4 — Multi-Model Comparison (Side by Side)

**What it demonstrates:** Open WebUI supports running multiple models in parallel on the same prompt, which makes it ideal for demonstrating model differences.

### Steps

1. Click **New Chat**
2. Click the **+** icon next to the model selector to add a second model
3. Select `openai/qwen2.5:7b` as model 1
4. Select `openai/llama3.2:3b` as model 2
5. Send this prompt:

```
Explain what a Kubernetes Deployment is in simple terms, as if explaining to a junior developer.
```

6. Both models respond side by side in real time
7. Switch to the Bifrost Logs tab — show two log entries appearing simultaneously, one per model

**Talking point:** _"Same prompt, two models, one request. Bifrost handles both in parallel. You can compare quality, speed, and style — and pick the right model for the job."_

---

## Scenario 5 — Access Control (Virtual Key Demo)

**What it demonstrates:** Bifrost enforces model-level access control via virtual keys. This scenario requires two keys set up in Bifrost — one unrestricted, one restricted to `llama3.2:3b` only.

### Setup (in Bifrost UI before the demo)

1. Go to `http://localhost:8080` → **Keys → Create Key**
2. Name it `demo-restricted`
3. Under Provider Configurations → OpenAI → Allowed Models, type `llama3.2:3b`
4. Under Allowed Keys, select `ollama-local`
5. Save and copy the key value

### Steps

**Part A — show the restricted key working:**

1. Open a terminal and run:

```bash
curl -s http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: <demo-restricted-key>" \
  -d '{
    "model": "openai/llama3.2:3b",
    "messages": [{"role":"user","content":"ping"}],
    "max_tokens": 10
  }' | jq '{model, response: .choices[0].message.content}'
```

Expected: success with `llama3.2:3b`

**Part B — show the restricted key blocked:**

```bash
curl -s http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: <demo-restricted-key>" \
  -d '{
    "model": "openai/qwen2.5:7b",
    "messages": [{"role":"user","content":"ping"}],
    "max_tokens": 10
  }' | jq .
```

Expected: `403 Model 'qwen2.5:7b' is not allowed for this virtual key`

**Part C — back in Open WebUI with the unrestricted key:**

Return to `http://localhost:3001` and show all models available — point out that the UI key (the unrestricted one) sees everything, while the restricted key in the curl only sees `llama3.2:3b`.

**Talking point:** _"Different teams or applications get different keys with different model access. A dev team might only get access to the lightweight models. A research team gets everything. Bifrost enforces this centrally."_

---

## Scenario 6 — Audit Trail

**What it demonstrates:** Every request through Bifrost is logged with full metadata, visible in the Bifrost UI.

### Steps

1. Run any chat in Open WebUI — a few messages across different models
2. Switch to `http://localhost:8080/logs`
3. Walk through the log entries — point out:
   - **Provider** — which backend served the request (`openai` = Ollama)
   - **Model** — exact model name
   - **Latency** — milliseconds end to end
   - **Tokens** — prompt tokens, completion tokens, total
   - **Timestamp** — when the request hit the gateway
4. Filter by model to show only `qwen2.5:7b` requests

**Talking point:** _"Every request is auditable. You know exactly which model was used, how long it took, and how many tokens were consumed — across every user and application hitting the gateway."_

---

## Demo Flow — Recommended Order

Run the scenarios in this order for a natural narrative arc:

| # | Scenario | Time | Key message |
|---|---|---|---|
| 1 | Basic chat | 2 min | "Local model, real chat interface" |
| 2 | Model switching | 2 min | "One endpoint, any model" |
| 3 | Code specialist | 3 min | "Right model for the right task" |
| 4 | Side by side | 3 min | "Compare models in parallel" |
| 5 | Access control | 3 min | "Per-key model governance" |
| 6 | Audit trail | 2 min | "Full visibility, every request" |

Total: ~15 minutes end to end.

---

## Troubleshooting

**No models in the Open WebUI dropdown:**
- Check the Bifrost port-forward is running: `lsof -i :8080 | grep kubectl`
- Check the Docker container env: `docker inspect open-webui | jq '.[0].Config.Env'`
- Confirm `OPENAI_API_BASE_URL` is `http://host.docker.internal:8080/v1`

**Model responds slowly on first message:**
- Normal — Ollama loads the model into memory on first request
- Pre-warm before the demo: `ollama run qwen2.5:7b "ping"`

**Bifrost logs not showing requests from Open WebUI:**
- The request went directly to Ollama, not through Bifrost
- Check `OPENAI_API_BASE_URL` — it must point at Bifrost (`:8080`), not Ollama (`:11434`)

**Port 3001 not accessible:**
- Check the container is running: `docker ps | grep open-webui`
- Restart if needed: `docker restart open-webui`
