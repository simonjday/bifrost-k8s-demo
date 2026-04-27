#!/usr/bin/env zsh
# Demo 5: Governance Block — Destructive tools blocked at Bifrost gateway
# Pre-req: BIFROST_VIRTUAL_KEY set, virtual key has read-only allow-list

GATEWAY="http://localhost:8080"
KEY="${BIFROST_VIRTUAL_KEY:?BIFROST_VIRTUAL_KEY not set}"

echo "=== Demo: Governance Block ==="
echo "Attempting 3 destructive operations against kubernetes_local MCP server."
echo "All should be blocked at Bifrost — the MCP server is never contacted."
echo ""

echo "--- Attempt 1: Delete bifrost-0 pod ---"
curl -s -X POST "$GATEWAY/mcp" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
      "name": "kubernetes_local-pods_delete",
      "arguments": {"name": "bifrost-0", "namespace": "ai-gateway"}
    }
  }' | jq '{attempt: "pods_delete", blocked: .error.message}'

echo ""
echo "--- Attempt 2: Scale StatefulSet to zero ---"
curl -s -X POST "$GATEWAY/mcp" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {
      "name": "kubernetes_local-resources_scale",
      "arguments": {
        "apiVersion": "apps/v1",
        "kind": "StatefulSet",
        "name": "bifrost",
        "namespace": "ai-gateway",
        "scale": 0
      }
    }
  }' | jq '{attempt: "resources_scale", blocked: .error.message}'

echo ""
echo "--- Attempt 3: Exec into pod ---"
curl -s -X POST "$GATEWAY/mcp" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": {
      "name": "kubernetes_local-pods_exec",
      "arguments": {
        "name": "bifrost-0",
        "namespace": "ai-gateway",
        "command": ["cat", "/etc/passwd"]
      }
    }
  }' | jq '{attempt: "pods_exec", blocked: .error.message}'

echo ""
echo "==> All three blocked at Bifrost gateway."
echo "==> Check http://localhost:8080 → Logs for the audit trail."
