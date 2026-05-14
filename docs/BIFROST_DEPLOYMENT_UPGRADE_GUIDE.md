# Supergateway Timeout Configuration Options

## Current Issue
Your deployment is using `--outputTransport streamableHttp` **in stateless mode** (default).
In stateless mode, each HTTP request spawns a NEW child process, which times out after initialization.

## The Solution: Enable Stateful Mode

### Stateless Mode (CURRENT - BROKEN)
```bash
node supergateway.js \
  --stdio "/shared/prometheus-mcp-server ..." \
  --outputTransport streamableHttp \
  --port 8080
```
**Problem:** Each HTTP request = new child process → initialization timeout

### Stateful Mode (RECOMMENDED FIX)
```bash
node supergateway.js \
  --stdio "/shared/prometheus-mcp-server ..." \
  --outputTransport streamableHttp \
  --stateful \
  --sessionTimeout 60000 \
  --port 8080
```

**How it works:**
1. `--stateful` — enables session persistence
2. `--sessionTimeout 60000` — keeps session alive for 60 seconds (60,000 ms)
3. Sessions reuse the SAME child process (no timeout on initialization)
4. Sessions auto-cleanup after 60s of inactivity

---

## Supergateway Timeout Parameters

| Flag | Type | Default | Purpose | Scope |
|------|------|---------|---------|-------|
| `--stateful` | boolean | `false` | Enable stateful sessions (reuse processes) | Stateful StreamableHttp only |
| `--sessionTimeout` | milliseconds | `60000` | How long to keep a session alive | Stateful StreamableHttp only |

---

## Key Difference: Stateless vs Stateful

### Stateless (Current)
```
HTTP Request 1 → Spawn child → Initialize → Timeout (4s) → Kill
HTTP Request 2 → Spawn child → Initialize → Timeout (4s) → Kill
HTTP Request 3 → Spawn child → Initialize → Timeout (4s) → Kill
```
Result: **Constant crashes** ❌

### Stateful (Recommended)
```
HTTP Request 1 (mcp-session-id: abc123) 
  → Spawn child → Initialize → Ready ✓
  
HTTP Request 2 (mcp-session-id: abc123)
  → Reuse existing child → Fast response ✓
  
HTTP Request 3 (mcp-session-id: abc123)
  → Reuse existing child → Fast response ✓
  
[60 seconds idle]
  → Auto-cleanup child (SessionAccessCounter) ✓
```
Result: **Persistent session, no timeout crashes** ✓

---

## Updated Deployment Args

Add these two lines to your deployment:

```yaml
args:
  - /usr/local/lib/node_modules/supergateway/dist/index.js
  - --stdio
  - "/shared/prometheus-mcp-server --prometheus.url=http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090 --web.listen-address=:0"
  - --outputTransport
  - streamableHttp
  - --stateful              ← ADD THIS
  - --sessionTimeout        ← ADD THIS
  - "60000"                 ← ADD THIS (milliseconds)
  - --port
  - "8080"
```

---

## Why 60 Seconds?

From supergateway docs:
> "Sessions are automatically cleaned up after 60 seconds of inactivity via SessionAccessCounter."

This is the default. You can adjust:
- **30000** (30s) — aggressive cleanup, less memory
- **60000** (60s) — default, balanced
- **300000** (5m) — long-lived sessions, more memory

---

## Reference

Source: https://github.com/supercorp-ai/supergateway/blob/main/README.md

```bash
# Example from official docs
npx -y supergateway \
  --stdio "npx -y @modelcontextprotocol/server-filesystem ./my-folder" \
  --outputTransport streamableHttp --stateful \
  --sessionTimeout 60000 --port 8000
```
