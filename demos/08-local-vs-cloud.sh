#!/usr/bin/env zsh
# Demo 9: Local vs Cloud Model Comparison
# Same query, same endpoint, same MCP tools — three different models.
# Shows quality/cost/latency tradeoff.
#
# Pre-req:
#   - BIFROST_VIRTUAL_KEY set
#   - Ollama running: OLLAMA_HOST=0.0.0.0 ollama serve
#   - openai provider registered in Bifrost (base_url: http://192.168.1.21:11434)
#   - qwen3-coder:30b pre-warmed: ./scripts/warmup-ollama.sh

GATEWAY="http://localhost:8080"
KEY="${BIFROST_VIRTUAL_KEY:?BIFROST_VIRTUAL_KEY not set}"
QUERY="Investigate the goose-test namespace and tell me which apps are unhealthy and why."

echo "=== Demo: Local vs Cloud Model Comparison ==="
echo "Same query, same endpoint, same MCP governance."
echo ""

echo "--- LOCAL: openai/qwen2.5:7b (fast, zero cost) ---"
time curl -s -X POST "$GATEWAY/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -H "x-bf-mcp-include-clients: kubernetes_local" \
  -d "{\"model\":\"openai/qwen2.5:7b\",\"messages\":[{\"role\":\"user\",\"content\":\"$QUERY\"}]}" \
  | jq -r '.choices[0].message.content'

echo ""
echo "--- LOCAL: openai/qwen3-coder:30b (best local quality, zero cost) ---"
time curl -s -X POST "$GATEWAY/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -H "x-bf-mcp-include-clients: kubernetes_local" \
  -d "{\"model\":\"openai/qwen3-coder:30b\",\"messages\":[{\"role\":\"user\",\"content\":\"$QUERY\"}]}" \
  | jq -r '.choices[0].message.content'

echo ""
echo "--- CLOUD: anthropic/claude-sonnet-4-5-20250929 (~\$0.003/call) ---"
time curl -s -X POST "$GATEWAY/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -H "x-bf-mcp-include-clients: kubernetes_local" \
  -d "{\"model\":\"anthropic/claude-sonnet-4-5-20250929\",\"messages\":[{\"role\":\"user\",\"content\":\"$QUERY\"}]}" \
  | jq -r '.choices[0].message.content'

echo ""
echo "=== Summary ==="
echo "qwen2.5:7b       ~2s   \$0    Basic identification"
echo "qwen3-coder:30b  ~18s  \$0    Moderate — misses policy detail"
echo "claude-sonnet    ~4.5s ~\$0.003  Full diagnosis: Kyverno, probes, security context"
