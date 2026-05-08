# AWS MCP Server — Deployment & Demo Guide

## Overview

AWS provides a suite of official MCP servers under `awslabs/mcp`. Rather than
one monolithic server, AWS breaks capabilities into focused servers per domain.
The two most useful for this demo environment are:

|Server               |Package                               |What it does                                               |
|---------------------|--------------------------------------|-----------------------------------------------------------|
|**AWS API**          |`awslabs.aws-api-mcp-server`          |Full AWS CLI access — any AWS API call via natural language|
|**AWS Documentation**|`awslabs.aws-documentation-mcp-server`|Search and read AWS docs in real time                      |
|**AWS IaC**          |`awslabs.aws-iac-mcp-server`          |CloudFormation/CDK validation and generation               |
|**AWS Network**      |`awslabs.aws-network-mcp-server`      |VPC, Transit Gateway, network troubleshooting              |

**Key note**: AWS dropped SSE support from all their MCP servers on May 26, 2025.
They are stdio-only until Streamable HTTP support ships. These run on your Mac
via Claude Desktop — not inside the cluster via Bifrost.

-----

## Prerequisites

```bash
# Install uv (required — awslabs servers use uvx)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Install AWS CLI
brew install awscli

# Configure credentials (use SSO or named profiles — never hardcode keys)
aws configure sso
# Or for a standard profile:
aws configure --profile bifrost-demo
```

### IAM permissions (read-only to start)

Create an IAM policy for the MCP server:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "eks:Describe*", "eks:List*",
        "s3:List*", "s3:GetBucketLocation",
        "cloudwatch:GetMetricData", "cloudwatch:ListMetrics",
        "logs:DescribeLogGroups", "logs:GetLogEvents",
        "iam:List*", "iam:Get*",
        "pricing:GetProducts"
      ],
      "Resource": "*"
    }
  ]
}
```

-----

## Setup

### 1. Update claude_desktop_config.json

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
    "aws-api": {
      "command": "uvx",
      "args": ["awslabs.aws-api-mcp-server@latest"],
      "env": {
        "AWS_PROFILE": "bifrost-demo",
        "AWS_REGION": "eu-west-1",
        "FASTMCP_LOG_LEVEL": "ERROR"
      }
    },
    "aws-docs": {
      "command": "uvx",
      "args": ["awslabs.aws-documentation-mcp-server@latest"],
      "env": {
        "AWS_DOCUMENTATION_PARTITION": "aws",
        "FASTMCP_LOG_LEVEL": "ERROR"
      }
    }
  }
}
```

**Note**: `aws-docs` needs no AWS credentials — it reads public documentation only.

### 2. Restart Claude Desktop

```bash
osascript -e 'quit app "Claude"'
sleep 3
open -a Claude
```

### 3. Verify

```
List all EKS clusters in my AWS account in eu-west-1
```

-----

## Optional: AWS IaC and Network servers

Add these if you want CloudFormation/CDK support or network troubleshooting:

```json
"aws-iac": {
  "command": "uvx",
  "args": ["awslabs.aws-iac-mcp-server@latest"],
  "env": {
    "AWS_PROFILE": "bifrost-demo",
    "FASTMCP_LOG_LEVEL": "ERROR"
  }
},
"aws-network": {
  "command": "uvx",
  "args": ["awslabs.aws-network-mcp-server@latest"],
  "env": {
    "AWS_PROFILE": "bifrost-demo",
    "AWS_REGION": "eu-west-1",
    "FASTMCP_LOG_LEVEL": "ERROR"
  }
}
```

-----

## Tools Available (aws-api)

The AWS API server wraps the AWS CLI — effectively every AWS API is available.
Key tools for this environment:

|Domain            |Example operations                                |
|------------------|--------------------------------------------------|
|**EKS**           |List clusters, describe nodegroups, get kubeconfig|
|**EC2**           |Describe instances, VPCs, security groups, AMIs   |
|**S3**            |List buckets, get objects, check bucket policies  |
|**CloudWatch**    |Query metrics, get log events, describe alarms    |
|**IAM**           |List roles, policies, users, check permissions    |
|**ECR**           |List repos, describe images, scan results         |
|**CloudFormation**|List stacks, describe resources, get events       |
|**Cost Explorer** |Query spend by service, tag, account              |

-----

## Demo Prompts

### Infrastructure Discovery

```
List all EKS clusters in my AWS account and for each one show me the
Kubernetes version, nodegroup count, and current status
```

```
What EC2 instances are running in eu-west-1? Show me instance type,
state, and any Name tags
```

```
List all S3 buckets in my account and flag any that have public access enabled
```

### Cloud + Kubernetes Cross-Reference

```
I have a kind-devops-lab cluster locally — compare its workload pattern
to any EKS clusters I have in AWS. Are there any resources I should be
running in the cloud instead of locally?
```

```
Check if there's an ECR repository for the guestbook app image and whether
the latest image has any vulnerability scan findings
```

### Cost & Optimisation

```
Show me my AWS spend for the last 30 days broken down by service — which
services are driving the most cost?
```

```
Are there any EC2 instances in my account that have been stopped for more
than 7 days? They may be costing money via EBS volumes
```

```
List any unused Elastic IPs or unattached EBS volumes — these are common
sources of wasted spend
```

### IAM & Security

```
List all IAM roles in my account that have AdministratorAccess and tell
me when they were last used
```

```
Check the security groups in my default VPC — are any of them allowing
0.0.0.0/0 inbound on port 22 or 3389?
```

### Documentation

```
Search the AWS EKS documentation for best practices on running Argo CD
on EKS — what does AWS recommend?
```

```
Find the AWS documentation for EKS Pod Identity and explain how it
differs from IRSA
```

### Multi-cloud (AWS + Kubernetes combined)

```
Walk me through what it would take to move the bifrost-k8s-demo stack
from kind to EKS — what AWS resources would I need and what would the
rough monthly cost be?
```

-----

## Gotchas

- **SSE removed May 2025** — all `awslabs` servers are stdio-only. Bifrost
  SSE integration is not currently possible with the latest versions. Use
  an older pinned version if you need SSE support via Bifrost.
- **Use named profiles, not env vars** — `AWS_PROFILE` in the config allows
  credential rotation without editing `claude_desktop_config.json`.
- **SSO credentials expire** — if using AWS SSO, run `aws sso login --profile bifrost-demo` before starting Claude Desktop or tool calls will 401.
- **`uvx` required** — all `awslabs` servers use `uvx`, not `npx`. Install
  `uv` first: `curl -LsSf https://astral.sh/uv/install.sh | sh`
- **Multiple servers = multiple processes** — each `awslabs.*` entry in the
  config launches a separate Python process. Four servers = four processes.
  Use only the ones you need.
- **Context window** — AWS API responses can be large. The servers truncate
  output, but complex queries (large CloudWatch time ranges, full IAM policies)
  can consume significant context. Be specific in your queries.