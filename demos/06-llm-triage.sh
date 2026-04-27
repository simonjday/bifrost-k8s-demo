#!/usr/bin/env zsh
# Demo 7: LLM-Driven Cluster Triage (Agent Mode)
# The LLM autonomously calls pods_list_in_namespace, pods_top, events_list
# and returns a structured health diagnosis of goose-test namespace.
#
# Pre-req:
#   - BIFROST_VIRTUAL_KEY set
#   - Anthropic provider configured in Bifrost
#   - kubernetes_local MCP client has tools_to_auto_execute: ["*"]
#   - goose-test namespace exists with mixed-health workloads

GATEWAY="http://localhost:8080"
KEY="${BIFROST_VIRTUAL_KEY:?BIFROST_VIRTUAL_KEY not set}"
MODEL="${BIFROST_MODEL:-anthropic/claude-sonnet-4-5-20250929}"

echo "=== Demo: LLM-Driven Namespace Health Diagnosis ==="
echo "Model: $MODEL"
echo "Namespace: goose-test (contains good-app, bad-app, ugly-app, single-app)"
echo ""
echo "Bifrost will autonomously:"
echo "  1. Call pods_list_in_namespace"
echo "  2. Call pods_top"
echo "  3. Call events_list"
echo "  4. Synthesise a structured health report"
echo ""

curl -s -X POST "$GATEWAY/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -H "x-bf-mcp-include-clients: kubernetes_local" \
  -d "{
    \"model\": \"$MODEL\",
    \"messages\": [{
      \"role\": \"user\",
      \"content\": \"Investigate the goose-test namespace. I have a mix of healthy and unhealthy workloads in there. List the pods, check their resource consumption, and look for any warning events. Tell me which apps are healthy, which are not, and what the likely cause is.\"
    }]
  }" | jq -r '.choices[0].message.content'
