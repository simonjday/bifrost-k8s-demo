#!/usr/bin/env zsh
# start-mcp-server.sh — Start kubernetes-mcp-server in SSE mode on port 8811
# This exposes the MCP server over HTTP so Bifrost pods can connect to it
# via the mcp-kubernetes-sse Service + Endpoints in-cluster.
#
# IMPORTANT: Use kubernetes-mcp-server (Red Hat), NOT mcp-server-kubernetes (Flux159).
# The Flux159 package only supports a single concurrent connection and crashes
# when Bifrost holds a persistent SSE connection.

pkill -f "kubernetes-mcp-server" 2>/dev/null || true
pkill -f "mcp-server-kubernetes" 2>/dev/null || true
sleep 1

echo "Starting kubernetes-mcp-server on port 8811..."

ENABLE_UNSAFE_SSE_TRANSPORT=1 \
PORT=8811 \
HOST=0.0.0.0 \
npx -y kubernetes-mcp-server@latest &

sleep 3

echo "Verifying SSE endpoint..."
curl -s --max-time 3 http://localhost:8811/sse; echo ""
echo ""
echo "SSE server running on http://0.0.0.0:8811"
echo "Reachable from k3d pods at: http://192.168.1.21:8811/sse"
echo ""
echo "Register in Bifrost UI → MCP → New MCP Server:"
echo "  Name:            kubernetes_local"
echo "  Connection Type: Server-Sent Events (SSE)"
echo "  URL:             http://mcp-kubernetes-sse.ai-gateway.svc.cluster.local:8811/sse"
echo "  Auth:            None"
