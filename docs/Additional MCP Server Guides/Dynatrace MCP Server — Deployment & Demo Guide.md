# Dynatrace MCP Server — Deployment & Demo Guide

## Overview

Dynatrace provides two MCP server options:

|Option               |Type                                             |Status            |Best for                       |
|---------------------|-------------------------------------------------|------------------|-------------------------------|
|**Remote MCP Server**|Hosted by Dynatrace (Streamable HTTP)            |✅ GA              |Production use — no local setup|
|**OSS local server** |`npx @dynatrace-oss/dynatrace-mcp-server` (stdio)|⚠️ Maintenance mode|Customisation, extra tools     |

**Use the Remote server** unless you need features only in the OSS version
(workflows, notebooks, automation). Like Datadog, the remote server requires
no local process — just a token and a URL.

**Key differentiator vs Datadog/Prometheus**: Dynatrace uses **DQL (Dynatrace
Query Language)** and its **Grail** data lakehouse. The MCP server can generate
DQL from natural language — you don’t need to know DQL syntax. Davis AI
(Dynatrace’s causal AI) provides root-cause analysis beyond simple metric queries.

-----

## Architecture

### Remote (recommended)

```
Claude Desktop / Claude.ai
    │
    ▼ Streamable HTTP + Bearer token
Dynatrace hosted MCP gateway
    │ https://<tenant>.apps.dynatrace.com/platform-reserved/mcp-gateway/...
    ▼
Dynatrace Grail (logs, metrics, traces, events)
Davis AI (problems, anomalies, root cause)
Kubernetes events, vulnerabilities, entities
```

### OSS local (optional)

```
Claude Desktop (stdio)
    │
    ▼
npx @dynatrace-oss/dynatrace-mcp-server
    │ OAUTH_CLIENT_ID + OAUTH_CLIENT_SECRET
    ▼
Dynatrace API
```

-----

## Prerequisites

You need a Dynatrace SaaS environment (free trial available at dynatrace.com).
Your environment URL looks like: `https://abc12345.apps.dynatrace.com`

### Install the OneAgent on your kind cluster (recommended)

To get meaningful data into Dynatrace before using the MCP server:

```bash
# Go to Dynatrace UI → Kubernetes → Add cluster
# Follow the guided setup — it generates a helm install command like:

helm install dynatrace-operator \
  oci://public.ecr.aws/dynatrace/dynatrace-operator \
  --namespace dynatrace \
  --create-namespace \
  --context kind-devops-lab

# Then create the DynaKube resource with your credentials
# (copy from the Dynatrace UI guided setup)
```

Within ~5 minutes the cluster appears in Dynatrace with full Kubernetes observability.

-----

## Part 1 — Remote MCP Server Setup (Recommended)

### 1. Generate a Platform Token

In Dynatrace: Access Tokens → Generate new token

```
Token name:   claude-mcp-server
Expiry:       90 days

Required scopes:
  mcp-gateway:servers:read
  mcp-gateway:servers:invoke
  storage:logs:read
  storage:metrics:read
  storage:events:read
  storage:spans:read
  storage:bizevents:read
  entities:read
  problems:read
  securityProblems:read
```

Copy the token — it starts with `dt0s08.`.

### 2. Update claude_desktop_config.json

The remote server uses Streamable HTTP. For Claude Desktop, use `mcp-remote`
as a bridge (same pattern as Datadog):

```json
{
  "mcpServers": {
    "kubernetes-local": {
      "command": "npx",
      "args": ["-y", "kubernetes-mcp-server@latest"]
    },
    "github": {
      "command": "docker",
      "args": ["run", "-i", "--rm", "-e", "GITHUB_PERSONAL_ACCESS_TOKEN",
               "ghcr.io/github/github-mcp-server"],
      "env": { "GITHUB_PERSONAL_ACCESS_TOKEN": "<your-pat>" }
    },
    "dynatrace": {
      "command": "npx",
      "args": [
        "-y",
        "mcp-remote@latest",
        "https://<your-tenant>.apps.dynatrace.com/platform-reserved/mcp-gateway/v0.1/servers/dynatrace-mcp/mcp",
        "--header",
        "Authorization: Bearer ${DT_TOKEN}"
      ],
      "env": {
        "DT_TOKEN": "<your-platform-token>"
      }
    }
  }
}
```

Replace `<your-tenant>` with your Dynatrace environment ID (e.g. `abc12345`).

### 3. Claude.ai Custom Connector (Pro/Team/Enterprise — cleaner)

Settings → Connectors → Add custom connector:

```
Name: Dynatrace
URL:  https://<your-tenant>.apps.dynatrace.com/platform-reserved/mcp-gateway/v0.1/servers/dynatrace-mcp/mcp
Headers:
  Authorization: Bearer <your-platform-token>
```

### 4. Restart Claude Desktop

```bash
osascript -e 'quit app "Claude"'
sleep 3
open -a Claude
```

### 5. Verify

```
Get information about my connected Dynatrace environment
```

-----

## Part 2 — OSS Local Server (optional, extra tools)

Use this if you need: workflow automation, notebook creation, or features
not yet in the remote server.

```json
{
  "mcpServers": {
    "dynatrace-oss": {
      "command": "npx",
      "args": ["-y", "@dynatrace-oss/dynatrace-mcp-server"],
      "env": {
        "DT_ENVIRONMENT": "https://<your-tenant>.apps.dynatrace.com",
        "OAUTH_CLIENT_ID": "<your-oauth-client-id>",
        "OAUTH_CLIENT_SECRET": "<your-oauth-client-secret>",
        "DT_GRAIL_QUERY_BUDGET_GB": "10"
      }
    }
  }
}
```

Note: the OSS server uses OAuth credentials (not platform tokens). Create an
OAuth client in Dynatrace: Settings → OAuth clients → Create client.

**Set `DT_GRAIL_QUERY_BUDGET_GB`** — Grail queries cost money based on GB
scanned. The default budget is 1000 GB. Set a lower limit to prevent runaway
costs during demos.

-----

## Tools Available

### Remote server

|Tool                                |Description                                                      |
|------------------------------------|-----------------------------------------------------------------|
|`execute_dql`                       |Execute DQL queries against Grail (logs, metrics, traces, events)|
|`generate_dql_from_natural_language`|Convert plain English to DQL                                     |
|`explain_dql`                       |Explain a DQL statement in plain English                         |
|`list_problems`                     |All active/recent Davis AI problems                              |
|`get_problem`                       |Full problem details with root cause                             |
|`list_vulnerabilities`              |Active security vulnerabilities                                  |
|`get_k8s_events`                    |Kubernetes events for a cluster                                  |
|`get_entity`                        |Entity details by name or ID                                     |
|`list_davis_analyzers`              |Available Davis AI analyzers                                     |
|`execute_davis_analyzer`            |Run forecasting, anomaly detection, correlation                  |
|`chat_with_davis_copilot`           |Ask Davis AI any observability question                          |

### OSS server (additional tools)

|Tool                              |Description                              |
|----------------------------------|-----------------------------------------|
|`create_notebook`                 |Create a Dynatrace notebook with analysis|
|`create_workflow_for_notification`|Create alerting workflow                 |
|`send_slack_message`              |Send Slack notification via workflow     |
|`get_ownership`                   |Entity ownership information             |
|`list_exceptions`                 |Recent application exceptions            |

-----

## Demo Prompts

### Problems & Root Cause (Davis AI)

```
List all active problems in my Dynatrace environment — what is the root
cause and impact of each?
```

```
Get the most recent problem in Dynatrace and explain the causal chain —
what triggered it, what was affected, and what is Davis AI recommending?
```

```
Are there any anomalies detected in my Kubernetes cluster by Davis AI
in the last hour?
```

### DQL Queries (natural language → DQL)

```
Show me error logs from the guestbook service in the last 30 minutes —
group them by error message and show me the count for each
```

```
Generate and execute a DQL query to show me the p50, p95, and p99
response times for all services in the last hour
```

```
Query Dynatrace Grail for CPU usage spikes across all Kubernetes nodes
in the last 2 hours — show me the top 5 worst periods
```

```
Explain this DQL query to me in plain English:
fetch logs | filter k8s.namespace.name == "ai-gateway" | summarize count(), by: {log.level, k8s.pod.name}
```

### Kubernetes Observability

```
Get all Kubernetes events from my kind-devops-lab cluster in the last
30 minutes — any warnings or errors?
```

```
Which pods in my Dynatrace-monitored cluster have had the most restarts
today? Use DQL to query the Kubernetes events data
```

```
Show me the resource consumption trends for the ai-gateway namespace
over the last 4 hours using Dynatrace metrics
```

### Security & Vulnerabilities

```
List all active security vulnerabilities detected by Dynatrace in my
monitored services — sorted by severity
```

```
Are there any critical CVEs affecting container images running in my
cluster right now? Show me the affected entities
```

### Davis AI — Advanced Analysis

```
List all available Davis analyzers and then run a forecast analyzer on
the guestbook service's request rate — will it exceed capacity in the
next 24 hours?
```

```
Run a correlation analyzer to determine if the pod restart events in
Kubernetes correlate with any application errors in the logs
```

```
Ask Davis CoPilot: why did the guestbook service have elevated error
rates between 14:00 and 14:30 today?
```

### Multi-tool (Dynatrace + Kubernetes + GitHub)

```
Full incident timeline:
1. List active Dynatrace problems for the guestbook app
2. Get the Kubernetes events for that period
3. Check GitHub for any commits pushed in the last 2 hours to devops-lab-repo
Correlate all three to determine if a recent deployment caused the issue
```

```
Dynatrace detected an anomaly in the ai-gateway namespace. Cross-reference
with Kubernetes pod status and resource usage to determine if this is a
capacity issue or an application bug
```

```
Compare what Dynatrace Davis AI says about cluster health vs what
Prometheus metrics show — are they telling the same story?
```

-----

## Gotchas

- **Remote vs OSS** — the remote server is GA and officially supported.
  The OSS local server is in maintenance mode — it still works but new features
  go to the remote server first. Use remote unless you need workflow automation.
- **Platform token vs OAuth** — the remote server uses platform tokens
  (`dt0s08.*`). The OSS server uses OAuth client credentials (`dt0s02.*`).
  They are different credential types — don’t mix them up.
- **Grail query costs** — using `execute_dql` and other Grail tools may incur
  additional costs based on GB scanned. Set `DT_GRAIL_QUERY_BUDGET_GB=10`
  in the OSS server config for demos. Start with short time windows (1-2h)
  to keep costs low.
- **`mcp-remote` bridge for Claude Desktop** — same pattern as Datadog. The
  Claude.ai Custom Connector (Pro+) is cleaner if available.
- **Token expiry** — platform tokens have a configurable expiry. Set it to
  90 days and add a calendar reminder. The OSS server also supports short-lived
  OAuth tokens but these expire in 5 minutes — use platform tokens instead.
- **No data without OneAgent** — like Datadog, the MCP server can only query
  data that’s been ingested. Install the Dynatrace Operator on your kind cluster
  first for meaningful demo results.
- **DQL syntax** — you don’t need to know DQL. Use
  `generate_dql_from_natural_language` first, then `verify_dql`, then
  `execute_dql`. The MCP server handles the full pipeline.
- **Restart Claude Desktop after kind cluster restart** — same rule as all
  other MCP servers.