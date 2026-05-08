# Azure MCP Server — Deployment & Demo Guide

## Overview

Microsoft provides two distinct Azure MCP servers. Use both:

|Server              |Package                           |What it does                                                                   |
|--------------------|----------------------------------|-------------------------------------------------------------------------------|
|**Azure MCP Server**|`.mcpb` bundle or `npx @azure/mcp`|100+ Azure services — Storage, Cosmos DB, Key Vault, App Service, AKS, and more|
|**Azure DevOps MCP**|`npx @azure-devops/mcp`           |Repos, work items, pipelines, PRs, wikis                                       |

The Azure MCP Server now ships as a `.mcpb` bundle — the easiest install method
for Claude Desktop, requiring no Node.js or runtime setup.

-----

## Part 1 — Azure MCP Server (infrastructure)

### Option A: .mcpb Bundle (Recommended — no runtime needed)

The Azure MCP Server is now available as an MCP Bundle, making it easier than ever to connect Claude Desktop to over 100 Azure services — no Node.js, Python, or .NET runtime required.

```bash
# Download the .mcpb for Apple Silicon Mac
curl -L -o azure-mcp-server-osx-arm64.mcpb \
  https://github.com/Azure/azure-mcp/releases/latest/download/azure-mcp-server-osx-arm64.mcpb
```

Then drag and drop the `.mcpb` file into the Claude Desktop window, or:

- Open Claude Desktop → File → Settings → Extensions
- Drag the `.mcpb` file onto the Extensions page
- Review and click Install

### Option B: npx (manual config)

```json
{
  "mcpServers": {
    "azure": {
      "command": "npx",
      "args": ["-y", "@azure/mcp@latest", "server", "start"],
      "env": {
        "AZURE_SUBSCRIPTION_ID": "<your-subscription-id>",
        "AZURE_TENANT_ID": "<your-tenant-id>"
      }
    }
  }
}
```

### Authentication

The Azure MCP server uses your Azure CLI credentials — the easiest approach:

```bash
# Install Azure CLI
brew install azure-cli

# Login (opens browser for auth)
az login

# Verify — list subscriptions
az account list --output table

# Set default subscription
az account set --subscription "<your-subscription-id>"
```

-----

## Part 2 — Azure DevOps MCP

If you use Azure DevOps for repos, pipelines, or work items:

```json
{
  "mcpServers": {
    "azure-devops": {
      "command": "npx",
      "args": ["-y", "@azure-devops/mcp", "<your-org-name>"]
    }
  }
}
```

Replace `<your-org-name>` with your Azure DevOps organisation name
(e.g. `contoso` from `dev.azure.com/contoso`).

Authentication uses your Azure CLI credentials automatically — no separate
token needed if you’re already logged in via `az login`.

-----

## Full claude_desktop_config.json

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
    "azure": {
      "command": "npx",
      "args": ["-y", "@azure/mcp@latest", "server", "start"],
      "env": {
        "AZURE_SUBSCRIPTION_ID": "<your-subscription-id>",
        "AZURE_TENANT_ID": "<your-tenant-id>"
      }
    },
    "azure-devops": {
      "command": "npx",
      "args": ["-y", "@azure-devops/mcp", "<your-org>"]
    }
  }
}
```

-----

## Tools Available

### Azure MCP Server

|Category                |Operations                                           |
|------------------------|-----------------------------------------------------|
|**Resource Groups**     |List, create, delete resource groups                 |
|**AKS**                 |List clusters, get credentials, describe node pools  |
|**Storage**             |List accounts, containers, blobs; read/write objects |
|**Cosmos DB**           |List accounts, databases, containers; query documents|
|**Key Vault**           |List vaults, get/set secrets, manage certificates    |
|**App Service**         |List apps, get config, check deployment status       |
|**Monitor**             |Query metrics, logs, alerts, action groups           |
|**Virtual Networks**    |List VNets, subnets, NSGs, peering                   |
|**Azure CLI generation**|Generate `az` commands for any task                  |
|**Bicep/Terraform**     |Template generation and infrastructure guidance      |

### Azure DevOps MCP

|Category      |Operations                                 |
|--------------|-------------------------------------------|
|**Repos**     |List repos, browse files, view commits, PRs|
|**Work Items**|Create, update, query issues and tasks     |
|**Pipelines** |List runs, trigger builds, view logs       |
|**Wikis**     |Read and search wiki pages                 |

-----

## Demo Prompts

### AKS & Kubernetes

```
List all AKS clusters in my Azure subscription and show me their
Kubernetes version, node count, and current health status
```

```
Compare my kind-devops-lab local cluster to any AKS clusters I have —
what differences in configuration should I be aware of?
```

```
Show me the Azure Monitor metrics for my AKS cluster over the last hour —
any node pressure or pod eviction events?
```

### Storage & Data

```
List all Storage accounts in my subscription and check which ones have
blob public access enabled — that should be disabled
```

```
Show me the Cosmos DB accounts in my subscription and their consistency
levels and replication regions
```

### Cost & Governance

```
What is the Azure resource group structure in my subscription and which
ones are running the most resources?
```

```
List all resources without a required tag like 'Environment' or 'Owner'
— these violate our tagging policy
```

```
Are there any unused resources in my subscription? Look for stopped VMs,
unattached disks, and empty resource groups
```

### Security

```
List all Key Vaults in my subscription and check which secrets are
expiring in the next 30 days
```

```
Show me the Network Security Groups in my subscription and flag any
rules allowing inbound traffic from 0.0.0.0/0 on sensitive ports
```

### Azure DevOps (if configured)

```
List all open PRs in my Azure DevOps organisation that have been waiting
for review for more than 3 days
```

```
Show me the last 10 pipeline runs for the main branch — any failures?
```

```
Create a work item in Azure DevOps for "Add Azure MCP integration to
bifrost-k8s-demo" in the current sprint
```

### Infrastructure as Code

```
Generate a Bicep template to deploy a basic AKS cluster with a single
node pool, RBAC enabled, and Azure Monitor integration
```

```
What Terraform resources would I need to replicate the bifrost-k8s-demo
stack on AKS?
```

-----

## Gotchas

- **`.mcpb` is the easiest install** — avoids Node.js PATH issues in Claude
  Desktop’s minimal launch environment. Use it unless you need to customise.
- **`az login` before starting Claude Desktop** — Azure credentials are read
  from the CLI session at startup. If you log in after starting Claude, restart.
- **Azure CLI token expiry** — tokens expire after 1 hour by default. If tools
  start failing mid-session, run `az account get-access-token` to refresh, then
  restart Claude Desktop.
- **Subscription context** — the server uses whatever subscription is set as
  default in the Azure CLI. Run `az account show` to verify before using.
- **Azure DevOps auth** — uses the same Azure AD identity as the Azure CLI.
  Ensure your account has the appropriate Azure DevOps project permissions.
- **Remote Azure DevOps MCP** — Microsoft also offers a hosted remote MCP at
  `https://mcp.dev.azure.com/{org}` but Claude Desktop support requires OAuth
  registration not yet available. Use the local `npx` version for now.