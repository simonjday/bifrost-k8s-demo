#!/usr/bin/env zsh
# Demo 2: Namespace Cost Attribution
# Pre-req: BIFROST_VIRTUAL_KEY set

GATEWAY="http://localhost:8080"
KEY="${BIFROST_VIRTUAL_KEY:?BIFROST_VIRTUAL_KEY not set}"

echo "=== Demo: Namespace Cost Attribution ==="
echo ""

echo "--- Step 1: List namespaces ---"
curl -s -X POST "$GATEWAY/mcp" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"kubernetes_local-namespaces_list","arguments":{}}}' \
  | jq -r '.result.content[0].text'

echo ""
echo "--- Step 2: Resource consumption across all namespaces ---"
curl -s -X POST "$GATEWAY/mcp" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"kubernetes_local-pods_top","arguments":{"all_namespaces":true}}}' \
  | jq -r '.result.content[0].text'

echo ""
echo "==> Check http://localhost:8080 → Logs — both calls logged with tool name, virtual key, latency."
