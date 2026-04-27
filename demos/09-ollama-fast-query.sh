#!/usr/bin/env zsh
# Demo 10: Ollama Fast Query — Sub-2s local inference with MCP tools
# Pre-req: BIFROST_VIRTUAL_KEY set, Ollama running with OLLAMA_HOST=0.0.0.0

GATEWAY="http://localhost:8080"
KEY="${BIFROST_VIRTUAL_KEY:?BIFROST_VIRTUAL_KEY not set}"

echo "=== Demo: Ollama Fast Local Query ==="
echo "Model: openai/qwen2.5:7b (zero cost, ~2s)"
echo ""

time curl -s -X POST "$GATEWAY/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -H "x-bf-mcp-include-clients: kubernetes_local" \
  -d '{
    "model": "openai/qwen2.5:7b",
    "messages": [{
      "role": "user",
      "content": "List all namespaces in the cluster and categorise them as system, infrastructure, or application namespaces."
    }]
  }' | jq -r '.choices[0].message.content'
