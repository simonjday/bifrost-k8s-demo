#!/usr/bin/env zsh
# install.sh — Full Bifrost + MCP install on k3d
# Dry-run by default. Pass --apply to execute.
# Usage: ./scripts/install.sh [--apply]

set -euo pipefail

DRY_RUN=true
[[ "${1:-}" == "--apply" ]] && DRY_RUN=false

NS="ai-gateway"
BIFROST_VERSION="v1.4.24"
HELM_CHART_REPO="https://maximhq.github.io/bifrost/helm-charts"

run() {
  if $DRY_RUN; then
    echo "[DRY-RUN] $*"
  else
    eval "$*"
  fi
}

echo "==> Bifrost k3d Install"
echo "    Namespace: $NS"
echo "    Version:   $BIFROST_VERSION"
echo "    Dry-run:   $DRY_RUN"
echo ""

# 1. Add Helm repo
echo "--- Step 1: Helm repo"
run "helm repo add bifrost $HELM_CHART_REPO 2>/dev/null || true"
run "helm repo update"

# 2. Namespace
echo "--- Step 2: Namespace"
run "kubectl create namespace $NS --dry-run=client -o yaml | kubectl apply -f -"

# 3. Encryption key secret (mandatory — chart won't start without it)
echo "--- Step 3: Encryption key secret"
if ! kubectl -n $NS get secret bifrost-encryption-key &>/dev/null; then
  run "kubectl create secret generic bifrost-encryption-key \
    --namespace $NS \
    --from-literal=encryption-key=\"\$(openssl rand -base64 32)\""
else
  echo "    Secret already exists — skipping"
fi

# 4. Install Bifrost via Helm
echo "--- Step 4: Bifrost Helm install"
if helm -n $NS status bifrost &>/dev/null; then
  echo "    Release already installed — upgrading"
  run "helm upgrade bifrost bifrost/bifrost \
    --namespace $NS \
    -f manifests/bifrost-values-dev.yaml"
else
  run "helm install bifrost bifrost/bifrost \
    --namespace $NS \
    -f manifests/bifrost-values-dev.yaml"
fi

# 5. MCP host service
echo "--- Step 5: MCP host Service + Endpoints"
run "kubectl apply -f manifests/mcp-kubernetes-host-svc.yaml"

# 6. Wait for Bifrost to be ready
echo "--- Step 6: Wait for Bifrost pod"
if ! $DRY_RUN; then
  kubectl -n $NS rollout status statefulset/bifrost --timeout=120s
fi

# 7. Port-forward
echo "--- Step 7: Port-forward"
echo "    Run manually: kubectl -n $NS port-forward svc/bifrost 8080:8080 &"

echo ""
if $DRY_RUN; then
  echo "Dry-run complete. Re-run with --apply to execute."
else
  echo "Install complete."
  echo ""
  echo "Next steps:"
  echo "  1. kubectl -n $NS port-forward svc/bifrost 8080:8080 &"
  echo "  2. ./scripts/start-mcp-server.sh"
  echo "  3. Open http://localhost:8080 and configure:"
  echo "     - Providers: Add Anthropic key"
  echo "     - Providers: Add OpenAI provider with base_url http://192.168.1.21:11434"
  echo "     - MCP: Add kubernetes_local server"
  echo "     - Keys: Create virtual key with allowed tools"
  echo "  4. export BIFROST_VIRTUAL_KEY=<your-key>"
  echo "  5. ./demos/01-governance-block.sh"
fi
