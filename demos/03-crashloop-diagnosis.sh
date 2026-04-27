#!/usr/bin/env zsh
# Demo 3: CrashLoopBackOff Diagnosis
# Uses existing bad-app pods in goose-test namespace.
# Pre-req: BIFROST_VIRTUAL_KEY set

GATEWAY="http://localhost:8080"
KEY="${BIFROST_VIRTUAL_KEY:?BIFROST_VIRTUAL_KEY not set}"
NS="goose-test"

echo "=== Demo: CrashLoopBackOff Diagnosis ==="
echo "Namespace: $NS"
echo ""

echo "--- Step 1: List pods (get actual generated pod names) ---"
curl -s -X POST "$GATEWAY/mcp" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"kubernetes_local-pods_list_in_namespace\",\"arguments\":{\"namespace\":\"$NS\"}}}" \
  | jq -r '.result.content[0].text'

echo ""
echo "--- Step 2: Get bad-app pod detail (update pod name if hash changed) ---"
# Get first bad-app pod name dynamically
POD_NAME=$(curl -s -X POST "$GATEWAY/mcp" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"kubernetes_local-pods_list_in_namespace\",\"arguments\":{\"namespace\":\"$NS\"}}}" \
  | jq -r '.result.content[0].text' | grep "bad-app" | grep -v "completed" | awk '{print $4}' | head -1)

echo "Using pod: $POD_NAME"
curl -s -X POST "$GATEWAY/mcp" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"kubernetes_local-pods_get\",\"arguments\":{\"name\":\"$POD_NAME\",\"namespace\":\"$NS\"}}}" \
  | jq -r '.result.content[0].text'

echo ""
echo "--- Step 3: Pod logs ---"
curl -s -X POST "$GATEWAY/mcp" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"kubernetes_local-pods_log\",\"arguments\":{\"name\":\"$POD_NAME\",\"namespace\":\"$NS\",\"tail\":30}}}" \
  | jq -r '.result.content[0].text'

echo ""
echo "--- Step 4: Namespace events ---"
curl -s -X POST "$GATEWAY/mcp" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $KEY" \
  -d "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"kubernetes_local-events_list\",\"arguments\":{\"namespace\":\"$NS\"}}}" \
  | jq -r '.result.content[0].text'
