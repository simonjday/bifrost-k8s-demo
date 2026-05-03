# Datadog MCP Server — Deployment & Demo Guide

## Overview

Datadog provides an official **remote** MCP server — no local process to run,
no Docker container. Your Claude Desktop connects directly to Datadog’s hosted
endpoint via Streamable HTTP. This is the cleanest MCP setup of all the servers
in this guide.

**Server type**: Remote (hosted by Datadog) — no local process needed
**Auth**: Datadog API key + Application key
**URL**: `https://mcp.datadoghq.com` (US) or `https://mcp.datadoghq.eu` (EU)

-----

## Prerequisites

You need a Datadog account with:

- At least one monitored host/container/service sending data
- An API key and Application key with appropriate scopes

If you don’t have Datadog, the free trial at datadoghq.com includes 14 days of
full access and can monitor your kind/k3d clusters via the Datadog Agent.

-----

## Setup

### 1. Generate API credentials

In Datadog: Organization Settings → API Keys → New Key

```
API Key name: claude-mcp-server
```

Then: Organization Settings → Application Keys → New Key

```
Application Key name:  claude-mcp-server
Scopes (read-only):
  - metrics_read
  - logs_read
  - apm_read
  - dashboards_read
  - monitors_read
  - incidents_read
  - events_read
```

Save both keys — you’ll need them in the config.

### 2. Update claude_desktop_config.json

For Claude Desktop, the remote MCP server requires the `mcp-remote` bridge
since Claude Desktop doesn’t yet natively support Streamable HTTP connectors
via JSON config (use the Claude.ai Custom Connectors UI instead — see below):

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
    "datadog": {
      "command": "npx",
      "args": [
        "-y",
        "mcp-remote@latest",
        "https://mcp.datadoghq.com/api/mcp/v1?toolsets=core,apm,alerting",
        "--header",
        "DD-API-KEY: ${DD_API_KEY}",
        "--header",
        "DD-APPLICATION-KEY: ${DD_APP_KEY}"
      ],
      "env": {
        "DD_API_KEY": "<your-api-key>",
        "DD_APP_KEY": "<your-application-key>"
      }
    }
  }
}
```

For EU region, replace the URL with `https://mcp.datadoghq.eu/api/mcp/v1`.

### 3. Alternatively — use Claude.ai Custom Connectors (Pro/Team/Enterprise)

If you have Claude Pro or above, this is cleaner than editing JSON:

Claude.ai → Settings → Connectors → Add custom connector

```
Name:   Datadog
URL:    https://mcp.datadoghq.com/api/mcp/v1?toolsets=all
Headers:
  DD-API-KEY:         <your-api-key>
  DD-APPLICATION-KEY: <your-application-key>
```

### 4. Restart Claude Desktop

```bash
osascript -e 'quit app "Claude"'
sleep 3
open -a Claude
```

-----

## Toolsets

Datadog organises tools into toolsets. Include only what you need to conserve
context window space. Pass as query parameter: `?toolsets=core,apm`

|Toolset            |Tools                                                                                    |
|-------------------|-----------------------------------------------------------------------------------------|
|`core`             |Logs, metrics, traces, dashboards, monitors, incidents, hosts, services, events (default)|
|`apm`              |APM services, traces, service maps, latency analysis                                     |
|`alerting`         |Monitor validation, creation, SLO search, monitor templates                              |
|`synthetics`       |Synthetic test results, locations, browser/API tests                                     |
|`software-delivery`|CI pipelines, test runs, deployment tracking                                             |
|`security`         |Security signals, vulnerabilities, findings                                              |
|`llmobs`           |LLM observability, prompt traces, model metrics                                          |
|`feature-flags`    |Feature flag tracking and evaluation data                                                |
|`cases`            |Case management, linking to Jira                                                         |

Use `toolsets=all` for full access (uses more context).

-----

## Installing the Datadog Agent on kind (optional but recommended)

To get your kind cluster data into Datadog for meaningful demo queries:

```bash
# Add Datadog Helm repo
helm repo add datadog https://helm.datadoghq.com
helm repo update

# Create API key secret
kubectl --context kind-devops-lab create secret generic datadog-agent \
  -n monitoring \
  --from-literal api-key=$DD_API_KEY \
  --from-literal app-key=$DD_APP_KEY

# Install Datadog Agent
helm install datadog-agent datadog/datadog \
  --namespace monitoring \
  --set datadog.apiKeyExistingSecret=datadog-agent \
  --set datadog.appKeyExistingSecret=datadog-agent \
  --set datadog.clusterName=kind-devops-lab \
  --set datadog.kubelet.tlsVerify=false \
  --set agents.tolerations[0].operator=Exists \
  --context kind-devops-lab
```

Within ~5 minutes you’ll see the kind cluster in Datadog’s infrastructure map.

-----

## Tools Available (core toolset)

|Tool             |Description                               |
|-----------------|------------------------------------------|
|`get_logs`       |Search logs with Datadog query syntax     |
|`get_metrics`    |Query timeseries metrics                  |
|`get_traces`     |Fetch APM traces by service/operation     |
|`list_monitors`  |List alert monitors with status           |
|`get_monitor`    |Get detailed monitor config and state     |
|`list_incidents` |Active and recent incidents               |
|`get_incident`   |Full incident timeline and signals        |
|`list_dashboards`|All dashboards with metadata              |
|`get_dashboard`  |Dashboard panel queries and config        |
|`list_hosts`     |Infrastructure hosts with tags and metrics|
|`list_services`  |APM service catalogue                     |
|`search_events`  |Event stream search                       |

-----

## Demo Prompts

### Logs & Traces

```
Search Datadog logs for any errors from the guestbook service in the
last 30 minutes — show me the most common error messages
```

```
Show me APM traces for the bifrost service — what's the p99 latency
and are there any traces with errors?
```

```
Get the last 50 error logs from the ai-gateway namespace and group
them by error type
```

### Monitors & Alerting

```
List all Datadog monitors that are currently in ALERT or WARN state —
show me the name, severity, and how long they've been triggered
```

```
Are there any monitors for my Kubernetes cluster? If not, what monitors
would you recommend I create for a production cluster?
```

```
Show me the SLO status for all services — which ones are below their
error budget?
```

### Incidents

```
List all active incidents in Datadog — who is assigned and what is
the current severity and status of each?
```

```
Get the full timeline for the most recent incident — what triggered it,
what actions were taken, and when was it resolved?
```

### Infrastructure

```
Show me all hosts in my Datadog infrastructure and their current CPU
and memory utilisation — flag any that are above 80%
```

```
List all Kubernetes nodes visible to Datadog and compare their resource
usage to the limits set in Kubernetes
```

### Multi-tool (Datadog + Kubernetes + Prometheus)

```
Full incident investigation:
1. Check Datadog for any active monitors firing on the guestbook service
2. Correlate with Prometheus metrics for the same time window
3. Check Kubernetes for any pod restarts or OOMKilled events
Give me a root cause hypothesis
```

```
The on-call team got paged about high latency. Use Datadog APM to find
the slowest traces in the last 15 minutes, then check the Kubernetes pods
involved to see if there are any resource constraints
```

```
Compare what Datadog and Prometheus are both telling us about guestbook
performance — are they consistent or showing different signals?
```

### Software Delivery (if using Datadog CI)

```
Show me the CI pipeline results for the last 10 runs of the main branch
— what's the pass rate and average duration?
```

```
Which test suites are failing most frequently in CI? Show me the flaky
tests that are causing the most noise
```

-----

## Gotchas

- **Remote server — no local process** — unlike all other MCP servers in this
  guide, Datadog’s server is hosted by Datadog. No Launch Agent, no Docker,
  no port-forward needed. Just API credentials.
- **`mcp-remote` bridge for Claude Desktop** — Claude Desktop’s JSON config
  doesn’t yet support native Streamable HTTP. The `mcp-remote` npm package
  bridges this gap. Claude.ai Custom Connectors (Pro+) is cleaner.
- **Toolsets = context management** — start with `toolsets=core` and add more
  only as needed. Each toolset adds ~10-20 tool definitions that consume context
  window space on every request.
- **EU vs US endpoint** — use `mcp.datadoghq.eu` if your Datadog account is on
  the EU site. Check your Datadog URL — `.eu` suffix = EU site.
- **Application key scopes** — create a scoped Application key with only the
  permissions you need. Avoid using your personal Application key with full admin
  access in any automated/AI system.
- **No cluster data without the Agent** — Datadog MCP can only query data that’s
  been sent to Datadog. Install the Datadog Agent on your kind cluster first or
  queries will return empty results for infrastructure and Kubernetes tools.
- **HIPAA-eligible** — Datadog’s MCP server is HIPAA-eligible if you need to
  discuss this with compliance teams in a demo context.