#!/usr/bin/env zsh
# install.sh — Full Bifrost + MCP install on k3d or kind
# Dry-run by default. Pass --apply to execute.
# Usage: ./scripts/install.sh [--apply] [--context <kubectl-context>]
#
# Auto-detects cluster type (k3d vs kind) and applies the correct MCP networking:
#   k3d  → ClusterIP + manual Endpoints (Mac LAN IP 192.168.1.21)
#   kind → socat proxy Deployment (forwards via 192.168.65.254 / host.docker.internal)

set -euo pipefail

DRY_RUN=true
CONTEXT=""

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)   DRY_RUN=false; shift ;;
    --context) CONTEXT="$2"; shift 2 ;;
    *)         echo "Unknown arg: $1"; exit 1 ;;
  esac
done

NS="ai-gateway"
BIFROST_VERSION="v1.5.0-prerelease7"
HELM_CHART_REPO="https://maximhq.github.io/bifrost/helm-charts"
KUBECTL="kubectl${CONTEXT:+ --context $CONTEXT}"

run() {
  if $DRY_RUN; then
    echo "[DRY-RUN] $*"
  else
    eval "$*"
  fi
}

# ── Detect cluster type ───────────────────────────────────────────────────────
detect_cluster_type() {
  local ctx="${CONTEXT:-$(kubectl config current-context 2>/dev/null)}"
  if [[ "$ctx" == k3d-* ]]; then
    echo "k3d"
  elif [[ "$ctx" == kind-* ]]; then
    echo "kind"
  else
    # Fallback: check server URL pattern
    local server
    server=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || true)
    if [[ "$server" == *"6443"* ]]; then
      echo "k3d"
    else
      echo "kind"
    fi
  fi
}

CLUSTER_TYPE=$(detect_cluster_type)

echo "==> Bifrost Install"
echo "    Namespace:    $NS"
echo "    Version:      $BIFROST_VERSION"
echo "    Context:      ${CONTEXT:-$(kubectl config current-context)}"
echo "    Cluster type: $CLUSTER_TYPE"
echo "    Dry-run:      $DRY_RUN"
echo ""

# ── Step 1: Helm repo ─────────────────────────────────────────────────────────
echo "--- Step 1: Helm repo"
run "helm repo add bifrost $HELM_CHART_REPO 2>/dev/null || true"
run "helm repo update"

# ── Step 2: Namespace ─────────────────────────────────────────────────────────
echo "--- Step 2: Namespace"
run "$KUBECTL create namespace $NS --dry-run=client -o yaml | $KUBECTL apply -f -"

# ── Step 3: Encryption key secret ────────────────────────────────────────────
echo "--- Step 3: Encryption key secret"
if ! $DRY_RUN && $KUBECTL -n $NS get secret bifrost-encryption-key &>/dev/null; then
  echo "    Secret already exists — skipping"
else
  run "$KUBECTL create secret generic bifrost-encryption-key \
    --namespace $NS \
    --from-literal=encryption-key=\"\$(openssl rand -base64 32)\""
fi

# ── Step 4: Bifrost Helm install ──────────────────────────────────────────────
echo "--- Step 4: Bifrost Helm install"
if ! $DRY_RUN && helm ${CONTEXT:+--kube-context $CONTEXT} -n $NS status bifrost &>/dev/null; then
  echo "    Release already installed — upgrading"
  run "helm ${CONTEXT:+--kube-context $CONTEXT} upgrade bifrost bifrost/bifrost \
    --namespace $NS \
    -f manifests/bifrost-values-dev.yaml"
else
  run "helm ${CONTEXT:+--kube-context $CONTEXT} install bifrost bifrost/bifrost \
    --namespace $NS \
    -f manifests/bifrost-values-dev.yaml"
fi

# ── Step 5: MCP networking ────────────────────────────────────────────────────
echo "--- Step 5: MCP host networking ($CLUSTER_TYPE)"

if [[ "$CLUSTER_TYPE" == "k3d" ]]; then
  echo "    Applying ClusterIP + Endpoints (Mac LAN IP) for k3d..."
  run "$KUBECTL apply -f manifests/mcp-kubernetes-host-svc.yaml"

elif [[ "$CLUSTER_TYPE" == "kind" ]]; then
  echo "    Applying socat proxy Deployment + Service for kind..."
  run "$KUBECTL apply -f manifests/mcp-kubernetes-proxy-kind.yaml"

  # Clean up any stale manual EndpointSlices — they conflict with the
  # controller-managed one and break kube-proxy routing
  echo "    Cleaning up stale manual EndpointSlices..."
  if ! $DRY_RUN; then
    # Delete any EndpointSlice named exactly 'mcp-kubernetes-sse' (manual ones
    # have no pod-template-hash suffix; controller-managed ones do)
    if $KUBECTL -n $NS get endpointslice mcp-kubernetes-sse &>/dev/null; then
      $KUBECTL -n $NS delete endpointslice mcp-kubernetes-sse && \
        echo "    Deleted stale EndpointSlice mcp-kubernetes-sse" || true
    else
      echo "    No stale EndpointSlice found — OK"
    fi
  else
    echo "[DRY-RUN] kubectl -n $NS delete endpointslice mcp-kubernetes-sse (if exists)"
  fi
fi


# ── Step 6: Metrics Server ───────────────────────────────────────────────────
echo "--- Step 6: Metrics Server (required for pods_top / nodes_top)"

METRICS_URL="https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"

if ! $DRY_RUN; then
  if $KUBECTL -n kube-system get deployment metrics-server &>/dev/null; then
    echo "    Metrics Server already installed — skipping"
  else
    echo "    Installing Metrics Server..."
    $KUBECTL apply -f "$METRICS_URL"

    if [[ "$CLUSTER_TYPE" == "kind" ]]; then
      # kind uses self-signed kubelet certs — patch to skip TLS verification
      echo "    Patching for kind (--kubelet-insecure-tls)..."
      $KUBECTL patch deployment metrics-server -n kube-system \
        --type=json \
        -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
    fi

    echo "    Waiting for Metrics Server to be ready (up to 90s)..."
    $KUBECTL -n kube-system rollout status deployment/metrics-server --timeout=90s && \
      echo "    ✓ Metrics Server ready" || \
      echo "    ✗ Metrics Server not ready — pods_top may fail for a few minutes"
  fi
else
  echo "[DRY-RUN] kubectl apply -f $METRICS_URL"
  if [[ "$CLUSTER_TYPE" == "kind" ]]; then
    echo "[DRY-RUN] kubectl patch deployment metrics-server -n kube-system (--kubelet-insecure-tls)"
  fi
fi

# ── Step 7: Wait for Bifrost ──────────────────────────────────────────────────
echo "--- Step 7: Wait for Bifrost pod"
if ! $DRY_RUN; then
  $KUBECTL -n $NS rollout status statefulset/bifrost --timeout=120s

  if [[ "$CLUSTER_TYPE" == "kind" ]]; then
    echo "    Waiting for socat proxy pod..."
    $KUBECTL -n $NS rollout status deployment/mcp-kubernetes-proxy --timeout=60s
  fi
fi

# ── Step 8: Verify MCP connectivity ──────────────────────────────────────────
echo "--- Step 8: Verify MCP connectivity"
if ! $DRY_RUN; then
  BIFROST_POD=$($KUBECTL -n $NS get pod -l app=bifrost -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "bifrost-0")
  echo "    Testing from pod $BIFROST_POD..."
  if $KUBECTL -n $NS exec "$BIFROST_POD" -- \
      wget -qO- --timeout=5 http://mcp-kubernetes-sse.${NS}.svc.cluster.local:8811/healthz &>/dev/null; then
    echo "    ✓ MCP SSE endpoint reachable in-cluster"
  else
    echo "    ✗ MCP SSE endpoint not reachable — check logs:"
    echo "      tail -f /tmp/mcp-kubernetes-sse.err"
    if [[ "$CLUSTER_TYPE" == "kind" ]]; then
      echo "      $KUBECTL -n $NS logs deploy/mcp-kubernetes-proxy"
    fi
  fi
fi

# ── Step 9: Port-forward info ─────────────────────────────────────────────────
echo "--- Step 9: Port-forward"
if [[ "$CLUSTER_TYPE" == "k3d" ]]; then
  echo "    Run: $KUBECTL -n $NS port-forward svc/bifrost 8080:8080 &"
  PF_PORT=8080
else
  echo "    Run: $KUBECTL -n $NS port-forward svc/bifrost 8080:8080 &"
  echo "    (only run one cluster at a time)"
  PF_PORT=8080
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
if $DRY_RUN; then
  echo "Dry-run complete. Re-run with --apply to execute."
else
  echo "Install complete."
  echo ""
  echo "Next steps:"
  echo "  1. Start MCP server (if not already running via Launch Agent):"
  echo "     launchctl list com.local.mcp-kubernetes-sse || \\"
  echo "       launchctl load -w ~/Library/LaunchAgents/com.local.mcp-kubernetes-sse.plist"
  echo ""
  echo "  2. Port-forward Bifrost:"
  if [[ "$CLUSTER_TYPE" == "k3d" ]]; then
    echo "     kubectl --context ${CONTEXT:-$(kubectl config current-context)} -n $NS port-forward svc/bifrost 8080:8080 &"
  else
    echo "     kubectl --context ${CONTEXT:-$(kubectl config current-context)} -n $NS port-forward svc/bifrost 8080:8080 &"
  fi
  echo ""
  echo "  3. Open http://localhost:$PF_PORT and configure:"
  echo "     - Providers: Add Anthropic key"
  echo "     - Providers: Add OpenAI provider pointing to Ollama:"
  echo "       base_url: http://192.168.1.21:11434"
  echo "     - MCP: Add kubernetes_local server:"
  echo "       URL: http://mcp-kubernetes-sse.${NS}.svc.cluster.local:8811/sse"
  echo "       Type: SSE, Auth: None"
  echo "     - Keys: Create virtual key"
  echo ""
  echo "  4. Verify MCP connected:"
  echo "     curl -s http://localhost:$PF_PORT/api/mcp/clients | \\"
  echo "       jq '{state: .clients[0].state, tool_count: (.clients[0].tools | length)}'"
  echo ""
  echo "  5. export BIFROST_VIRTUAL_KEY=<your-key>"
  echo "  6. ./demos/01-governance-block.sh"
fi
