#!/usr/bin/env bash
set -euo pipefail

PORT=8811
MANIFEST_DIR="$(cd "$(dirname "$0")/../manifests" && pwd)"
MANIFEST="$MANIFEST_DIR/mcp-kubernetes-host-svc.yaml"

# ── 1. Detect Mac LAN IP ────────────────────────────────────────────────────
HOST_IP=$(ipconfig getifaddr en0 2>/dev/null || true)
if [[ -z "$HOST_IP" ]]; then
  HOST_IP=$(ipconfig getifaddr en1 2>/dev/null || true)
fi
if [[ -z "$HOST_IP" ]]; then
  echo "ERROR: Could not detect Mac LAN IP via en0/en1. Set HOST_IP manually." >&2
  exit 1
fi

echo "Detected Mac LAN IP: $HOST_IP"

# ── 2. Apply Service + Endpoints manifest (with IP substituted) ─────────────
echo "Applying MCP Kubernetes SSE service manifest..."
sed "s/__HOST_IP__/$HOST_IP/" "$MANIFEST" | kubectl apply -f -
echo "Service mcp-kubernetes-sse → $HOST_IP:$PORT applied."

# ── 3. Start the MCP server ──────────────────────────────────────────────────
# --port starts both /sse and /mcp endpoints (no --transport flag in this version)
echo ""
echo "Starting kubernetes-mcp-server on port $PORT..."
npx -y kubernetes-mcp-server@latest --port "$PORT" &
MCP_PID=$!

# Give it a moment to bind
sleep 1

# ── 4. Verify SSE endpoint is up ────────────────────────────────────────────
echo "Verifying SSE endpoint..."
if curl -sf --max-time 3 "http://localhost:$PORT/sse" -o /dev/null; then
  echo "SSE server running on http://0.0.0.0:$PORT"
else
  echo "WARNING: SSE endpoint did not respond — server may still be starting."
fi

echo ""
echo "Reachable from k3d pods at: http://$HOST_IP:$PORT/sse"
echo ""
echo "Register in Bifrost UI → MCP → New MCP Server:"
echo "  Name:            kubernetes_local"
echo "  Connection Type: Server-Sent Events (SSE)"
echo "  URL:             http://mcp-kubernetes-sse.ai-gateway.svc.cluster.local:$PORT/sse"
echo "  Auth:            None"
echo ""
echo "Press Ctrl+C to stop the MCP server."
wait "$MCP_PID"
