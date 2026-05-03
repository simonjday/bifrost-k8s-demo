# GitHub MCP Server — Deployment & Demo Guide

## Overview

The official GitHub MCP server (`github/github-mcp-server`) is the most widely
deployed DevOps MCP in the ecosystem. It runs via Docker and gives Claude direct
access to your repositories, issues, pull requests, and Actions.

**Package**: `ghcr.io/github/github-mcp-server` (official Go binary, v1.0+)
**Note**: The old npm package `@modelcontextprotocol/server-github` was archived
in April 2025. Always use the Docker image.

-----

## Architecture

```
Claude Desktop (stdio)
    │
    ▼
Docker container: ghcr.io/github/github-mcp-server
    │ GITHUB_PERSONAL_ACCESS_TOKEN
    ▼
GitHub API (api.github.com)
    └── Repos: simonjday/bifrost-k8s-demo
                simonjday/devops-lab-repo
```

-----

## Part 1 — Claude Desktop Setup

### 1. Create a GitHub Personal Access Token

Go to https://github.com/settings/personal-access-tokens/new (fine-grained PAT):

```
Token name:     claude-mcp-server
Expiration:     90 days
Repositories:   bifrost-k8s-demo, devops-lab-repo (or All repositories)

Permissions (read-only to start):
  Contents:           Read
  Issues:             Read
  Pull requests:      Read
  Metadata:           Read (mandatory)
  Actions:            Read (for CI/CD queries)
  Commit statuses:    Read
```

For write access (creating issues, PRs), also add:

```
  Contents:           Read and write
  Issues:             Read and write
  Pull requests:      Read and write
```

Copy the token — you won’t see it again.

### 2. Update claude_desktop_config.json

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
        "ARGOCD_BASE_URL": "https://localhost:8443",
        "ARGOCD_API_TOKEN": "<your-argocd-token>"
      }
    },
    "github": {
      "command": "docker",
      "args": [
        "run", "-i", "--rm",
        "-e", "GITHUB_PERSONAL_ACCESS_TOKEN",
        "ghcr.io/github/github-mcp-server"
      ],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "<your-pat-here>"
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

### 4. Verify

Ask Claude: “What GitHub tools do you have available?” — you should see tools
like `list_repos`, `get_file_contents`, `create_issue`, `list_pull_requests`, etc.

-----

## Part 2 — Bifrost SSE Setup (optional)

The GitHub MCP server is Docker-based (stdio). To expose it via Bifrost SSE,
wrap it with a socat proxy or use the `--transport sse` flag if available.
For this demo environment, **stdio via Claude Desktop is sufficient** — GitHub
is accessed from your Mac, not from inside the cluster.

-----

## Tools Available

|Tool                 |Description                   |
|---------------------|------------------------------|
|`search_repositories`|Search GitHub repos           |
|`get_file_contents`  |Read any file from a repo     |
|`list_commits`       |Commit history with diffs     |
|`list_pull_requests` |Open/merged PRs               |
|`get_pull_request`   |Full PR details including diff|
|`list_issues`        |Issues with labels/assignees  |
|`create_issue`       |Open a new issue              |
|`create_pull_request`|Open a PR                     |
|`push_files`         |Commit files to a branch      |
|`list_workflows`     |GitHub Actions workflows      |
|`list_workflow_runs` |CI run history and status     |

-----

## Demo Prompts

### Repository & Code

```
What files are in the simonjday/bifrost-k8s-demo repo and what has changed
in the last week?
```

```
Show me the contents of manifests/mcp-kubernetes-host-svc.yaml in my
bifrost-k8s-demo repo
```

```
Search my repos for any files that reference 192.168.1.21 — I need to
audit all hardcoded IPs
```

### GitOps Loop (GitHub + Argo CD + Kubernetes combined)

```
A new commit was just pushed to devops-lab-repo. Check what changed in the
last commit, confirm Argo CD has synced it, and verify the affected pods
are healthy in the cluster
```

```
Compare the guestbook deployment.yaml in git vs what's currently running
in the cluster — are they in sync?
```

```
Walk me through the full GitOps flow for the last change to the guestbook app:
what changed in git, did Argo CD pick it up, and what's the current pod status?
```

### Issues & PRs

```
Are there any open issues in bifrost-k8s-demo? Summarise them and suggest
which to prioritise
```

```
Create a GitHub issue in bifrost-k8s-demo titled "Add Grafana MCP server
to the demo stack" with a description of the steps needed
```

```
Review the last merged PR in devops-lab-repo — what did it change and
were there any potential issues with the changes?
```

### CI/CD

```
Show me the last 5 GitHub Actions runs for bifrost-k8s-demo — any failures?
```

```
Which workflows are configured in my devops-lab-repo and when did they
last run successfully?
```

-----

## Gotchas

- **Docker must be running** — the GitHub MCP server runs in a Docker container.
  If Docker Desktop is stopped, the MCP tool will fail silently.
- **Fine-grained PATs over classic tokens** — fine-grained PATs scope to specific
  repos and are more secure. Classic tokens have broad access.
- **Rate limiting** — GitHub API has rate limits (5000 req/hr for authenticated
  users). Heavy MCP usage during demos can approach this. Monitor with:
  `curl -H "Authorization: Bearer $PAT" https://api.github.com/rate_limit`
- **Token expiry** — PATs expire. Set a calendar reminder to rotate before expiry
  or the MCP will silently stop working.
- **Restart Claude Desktop after token rotation** — the Docker container inherits
  env vars at launch time.