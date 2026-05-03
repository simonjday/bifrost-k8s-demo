# Argo CD MCP Server — Deployment Guide

## Overview

Two Argo CD MCP servers exist. Use the **official one** from `argoproj-labs`:

| Server                           | Package                   | Maintainer   | Notes         |
| -------------------------------- | ------------------------- | ------------ | ------------- |
| **argoproj-labs/mcp-for-argocd** | `argocd-mcp@latest` (npm) | Argo CD team | ✅ Recommended |
| severity1/argocd-mcp             | Python/uv                 | Community    | Fewer tools   |

The official server exposes tools for listing, syncing, getting status, retrieving resource trees, logs, and events — everything in the Argo CD API.

------

## Architecture

```
Claude Desktop / Claude chat
    │
    ▼ stdio (Claude Desktop)
argocd-mcp process (npx argocd-mcp@latest stdio)
    │
    ▼ HTTP API calls
Argo CD server (argocd-server pod)
    │ port-forward: localhost:9080 → argocd-server:80 (via port-forwards.sh)
    └── Applications, Projects, Repos, Clusters
```

For Bifrost SSE (chat access), the same pattern as kubernetes-mcp-server applies — run the argocd-mcp server in HTTP mode and expose it via a Service + socat proxy (kind) or Endpoints (k3d).

**Port note**: Your `port-forwards.sh` forwards Argo CD to `localhost:9080` (HTTP port 80). The MCP server uses this HTTP endpoint — no TLS, no `--insecure` flag needed.

------

## Part 1 — Claude Desktop Setup (stdio)

### 1. Ensure the port-forward is running

Your `port-forwards.sh` already handles this. Verify it's active:

```bash
# Confirm port-forward is running
lsof -i :9080 | grep LISTEN

# Or run port-forwards.sh if not already running
./scripts/port-forwards.sh

# Verify Argo CD is reachable
curl -s http://localhost:9080/api/v1/applications | jq '.items | length'
```

### 2. Generate an Argo CD API token

```bash
# 1. Start the port-forward first
./scripts/port-forwards.sh

# 2. Get the admin password
PW=$(kubectl --context kind-devops-lab get secret argocd-initial-admin-secret \
  -n argocd -o jsonpath='{.data.password}' | base64 -d)

# 3. Generate a token via the REST API (avoids argocd CLI gRPC issues)
#    The argocd CLI sends gRPC probes that disrupt port-forwards — use REST instead
TOKEN=$(curl -s -X POST http://localhost:9080/api/v1/session \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"admin\",\"password\":\"${PW}\"}" | jq -r .token)

echo "Token: $TOKEN"
export ARGOCD_API_TOKEN=$TOKEN
```

### 2. Add to Claude Desktop config

Edit `~/Library/Application Support/Claude/claude_desktop_config.json`:

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
        "ARGOCD_API_TOKEN": "<your-token-here>"
      }
    }
  }
}
```

### 3. Restart Claude Desktop

```bash
osascript -e 'quit app "Claude"'
sleep 3
open -a Claude
```

### 4. Verify tools are loaded

In a new Claude chat, ask:

> "What Argo CD tools do you have available?"

You should see tools like `list_applications`, `get_application`, `sync_application`, `get_resource_tree`, `get_application_logs`, etc.

------

## Part 2 — Bifrost SSE Setup (chat via MCP endpoint)

This follows the same pattern as the kubernetes-mcp-server. The argocd-mcp server runs in HTTP mode on your Mac as a Launch Agent, exposed in-cluster via a Service.

### 1. Create the Launch Agent plist

Save as `scripts/com.local.mcp-argocd-sse.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.local.mcp-argocd-sse</string>

  <key>ProgramArguments</key>
  <array>
    <string>/opt/homebrew/bin/npx</string>
    <string>-y</string>
    <string>argocd-mcp@latest</string>
    <string>http</string>
    <string>--stateless</string>
    <string>--port</string>
    <string>8812</string>
  </array>

  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>
    <string>/Users/simonjday</string>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin</string>
    <key>ARGOCD_BASE_URL</key>
    <string>http://localhost:9080</string>
    <key>ARGOCD_API_TOKEN</key>
    <string>REPLACE_WITH_TOKEN</string>
  </dict>

  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>10</integer>
  <key>StandardOutPath</key>
  <string>/tmp/mcp-argocd-sse.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/mcp-argocd-sse.err</string>
</dict>
</plist>
```

**Important**: Replace `REPLACE_WITH_TOKEN` with your actual token. Port `8812` avoids conflict with kubernetes-mcp-server on `8811`. `--stateless` flag is required when running behind a load balancer/proxy.

### 2. Install the Launch Agent

```bash
# Edit the plist to add your token first
cp scripts/com.local.mcp-argocd-sse.plist ~/Library/LaunchAgents/
launchctl load -w ~/Library/LaunchAgents/com.local.mcp-argocd-sse.plist

# Verify it's running
lsof -i :8812 | grep LISTEN
curl -s http://localhost:8812/healthz && echo OK
```

### 3. Apply in-cluster Service (kind)

Save as `manifests/mcp-argocd-proxy-kind.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mcp-argocd-proxy
  namespace: ai-gateway
  labels:
    app: mcp-argocd-proxy
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mcp-argocd-proxy
  template:
    metadata:
      labels:
        app: mcp-argocd-proxy
    spec:
      containers:
      - name: socat
        image: alpine/socat:latest
        args:
        - TCP-LISTEN:8812,fork,reuseaddr
        - TCP:192.168.65.254:8812
        ports:
        - containerPort: 8812
          name: sse
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
          limits:
            cpu: 100m
            memory: 32Mi
---
apiVersion: v1
kind: Service
metadata:
  name: mcp-argocd-sse
  namespace: ai-gateway
  labels:
    app: mcp-argocd-sse
spec:
  type: ClusterIP
  selector:
    app: mcp-argocd-proxy
  ports:
  - name: sse
    port: 8812
    targetPort: 8812
    protocol: TCP
kubectl --context kind-devops-lab apply -f manifests/mcp-argocd-proxy-kind.yaml

# Clean up any stale EndpointSlices
kubectl --context kind-devops-lab delete endpointslice mcp-argocd-sse \
  -n ai-gateway 2>/dev/null || true

# Verify
kubectl --context kind-devops-lab exec -n ai-gateway bifrost-0 -- \
  wget -qO- http://mcp-argocd-sse.ai-gateway.svc.cluster.local:8812/healthz \
  && echo "In-cluster: OK"
```

### 4. Register in Bifrost UI

Go to `http://localhost:8080` → MCP → New MCP Server:

```
Name:            argocd_local
Connection Type: Server-Sent Events (SSE)
URL:             http://mcp-argocd-sse.ai-gateway.svc.cluster.local:8812/sse
Auth:            None
```

### 5. Verify

```bash
curl -s http://localhost:8080/api/mcp/clients | \
  jq '.clients[] | {name: .name, state: .state, tools: (.tools | length)}'
```

Expected:

```json
{ "name": "kubernetes_local", "state": "connected", "tools": 20 }
{ "name": "argocd_local",     "state": "connected", "tools": 15 }
```

------

## Part 3 — RBAC (Read-Only Token)

For demo safety, create a read-only Argo CD account instead of using admin:

```bash
# Add to argocd-cm ConfigMap
kubectl --context kind-devops-lab patch configmap argocd-cm -n argocd --patch '
data:
  accounts.mcp: apiKey,login
'

# Add read-only RBAC policy to argocd-rbac-cm
kubectl --context kind-devops-lab patch configmap argocd-rbac-cm -n argocd --patch '
data:
  policy.csv: |
    p, role:mcp-readonly, applications, get, */*, allow
    p, role:mcp-readonly, applications, list, */*, allow
    p, role:mcp-readonly, clusters, get, *, allow
    p, role:mcp-readonly, repositories, get, *, allow
    p, role:mcp-readonly, projects, get, *, allow
    g, mcp, role:mcp-readonly
'

# Generate token for the mcp account via REST API
TOKEN=$(curl -s -X POST http://localhost:9080/api/v1/session \
  -H "Content-Type: application/json" \
  -d '{"username":"mcp","password":"<mcp-account-password>"}' | jq -r .token)
echo $TOKEN
```

Use this token in the Launch Agent plist instead of the admin token.

------

## Example Prompts for Claude Chat

### Status & Health

```
What Argo CD applications do I have and what is their sync/health status?
Are there any OutOfSync or Degraded applications in Argo CD?
Show me the full resource tree for the guestbook application
What was the last sync result for the guestbook app — was it successful?
Which Argo CD apps have auto-sync enabled and which are manual?
```

### GitOps Drift Detection

```
Which applications have diffs between git and the cluster right now?
Compare the desired state in git vs live state for the guestbook application
Have any applications drifted from their last known good state?
```

### Troubleshooting

```
The guestbook app is OutOfSync — what resources are causing the diff?
Show me the recent sync history for all applications — any failures?
What events are associated with the argocd-application-controller in the last hour?
Which applications are in a Progressing health state and why?
```

### Multi-tool (Argo CD + Kubernetes combined)

```
Cross-reference: which Argo CD apps are Synced but have pods that are not Ready?
The guestbook Argo CD app is healthy but users are complaining — check pod logs 
and resource usage to see if there's a performance issue
List all Argo CD apps and for each one show me the pod count and CPU usage
```

### Governance & Demo Scenarios

```
Show me all applications and highlight any that don't have health checks configured
Which apps were last synced more than 24 hours ago?
Walk me through a GitOps incident: guestbook is OutOfSync — diagnose the diff, 
explain what changed, and tell me what would happen if I sync it now
```

------

## Gotchas

- **`port-forwards.sh` must be running first** — Argo CD is exposed at `localhost:9080` by `scripts/port-forwards.sh`. Run it before attempting any token generation or MCP connection. Verify with `lsof -i :9080 | grep LISTEN`.

- **Use REST API not the argocd CLI for token generation** — the `argocd login` CLI command sends gRPC probes that disrupt other active port-forwards. Use `curl -X POST http://localhost:9080/api/v1/session` instead — it talks pure REST over HTTP with no side effects.

- **MCP server uses HTTP REST** — `ARGOCD_BASE_URL=http://localhost:9080` works correctly. The argocd-mcp server uses the REST API, not gRPC, so it has none of the CLI's port-forward disruption issues.

- **`--stateless` flag** — required for HTTP mode when running behind the socat proxy. Without it, session affinity errors occur.

- **Token expiry** — Argo CD tokens don't expire by default but can be revoked. If the MCP stops working, regenerate the token and reload the Launch Agent.

- **Restart after kind restart** — like kubernetes-mcp-server, the argocd-mcp process caches the connection. Restart both Launch Agents after kind restarts:

  ```bash
  launchctl stop com.local.mcp-argocd-sselaunchctl start com.local.mcp-argocd-sse
  ```