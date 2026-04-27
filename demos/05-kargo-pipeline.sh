#!/usr/bin/env zsh
# Demo 6: Kargo Pipeline Status
# Pre-req: BIFROST_VIRTUAL_KEY set, kargo namespace with Stages and Freight

GATEWAY="http://localhost:8080"
KEY="${BIFROST_VIRTUAL_KEY:?BIFROST_VIRTUAL_KEY not set}"

echo "=== Demo: Kargo Pipeline Status ==="
echo "Promotion pipeline state across dev/staging/prod — no kargo CLI required"
echo ""

echo "--- Kargo Stages: platform-demo ---"
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
        "apiVersion": "kargo.akuity.io/v1alpha1",
        "kind": "Stage",
        "namespace": "platform-demo"
      }
    }
  }' | jq -r '.result.content[0].text'

echo ""
echo "--- prod Stage detail ---"
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
        "apiVersion": "kargo.akuity.io/v1alpha1",
        "kind": "Stage",
        "name": "prod",
        "namespace": "platform-demo"
      }
    }
  }' | jq -r '.result.content[0].text'

echo ""
echo "--- Current Freight in pipeline ---"
curl -s -X POST "$GATEWAY/mcp" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": {
      "name": "kubernetes_local-resources_list",
      "arguments": {
        "apiVersion": "kargo.akuity.io/v1alpha1",
        "kind": "Freight",
        "namespace": "platform-demo"
      }
    }
  }' | jq -r '.result.content[0].text'
