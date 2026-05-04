#!/usr/bin/env zsh
# Demo 4: Argo CD Application Status via CRDs
# Pre-req: BIFROST_VIRTUAL_KEY set, argocd namespace with Applications

GATEWAY="http://localhost:8080"
KEY="${BIFROST_VIRTUAL_KEY:?BIFROST_VIRTUAL_KEY not set}"

echo "=== Demo: Argo CD Application Status via Bifrost MCP ==="
echo "No argocd CLI required — CRD queries via kubernetes_local MCP server"
echo ""

echo "--- All Argo CD Applications ---"
curl -s -X POST "$GATEWAY/mcp" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
      "name": "kubernetes_local-resources_list",
      "arguments": {
        "apiVersion": "argoproj.io/v1alpha1",
        "kind": "Application",
        "namespace": "argocd"
      }
    }
  }' | jq -r '.result.content[0].text'

echo ""
echo "--- platform-api-gateway-prod Application detail ---"
curl -s -X POST "$GATEWAY/mcp" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {
      "name": "kubernetes_local-resources_get",
      "arguments": {
        "apiVersion": "argoproj.io/v1alpha1",
        "kind": "Application",
        "name": "platform-api-gateway-prod",
        "namespace": "argocd"
      }
    }
  }' | jq -r '.result.content[0].text'
