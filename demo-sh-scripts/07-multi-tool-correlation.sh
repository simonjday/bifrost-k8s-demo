#!/usr/bin/env zsh
# Demo 8: Multi-Tool Correlation — Pods + Argo CD + Kargo
# Correlates runtime state with GitOps state in a single governed session.
# Pre-req: BIFROST_VIRTUAL_KEY set

GATEWAY="http://localhost:8080"
KEY="${BIFROST_VIRTUAL_KEY:?BIFROST_VIRTUAL_KEY not set}"

echo "=== Demo: Multi-Tool Correlation (Pods + Argo CD + Kargo) ==="
echo "One endpoint, one virtual key, three resource types."
echo ""

echo "--- Step 1: platform-prod pod resource consumption ---"
curl -s -X POST "$GATEWAY/mcp" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
      "name": "kubernetes_local-pods_top",
      "arguments": {"namespace": "platform-prod", "all_namespaces": false}
    }
  }' | jq -r '.result.content[0].text'

echo ""
echo "--- Step 2: Argo CD Application managing platform-prod ---"
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
        "name": "platform-demo-prod",
        "namespace": "argocd"
      }
    }
  }' | jq -r '.result.content[0].text'

echo ""
echo "--- Step 3: Kargo Stage that promoted the current freight ---"
curl -s -X POST "$GATEWAY/mcp" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{
    "jsonrpc": "2.0",
    "id": 3,
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
