#!/usr/bin/env zsh
# teardown.sh — Clean Bifrost teardown
# Dry-run by default. Pass --apply to execute.
# Usage: ./scripts/teardown.sh [--apply]

DRY_RUN=true
[[ "${1:-}" == "--apply" ]] && DRY_RUN=false

NS="ai-gateway"

if $DRY_RUN; then
  echo "[DRY-RUN] helm uninstall bifrost --namespace $NS"
  echo "[DRY-RUN] kubectl -n $NS delete secret bifrost-encryption-key"
  echo "[DRY-RUN] kubectl -n $NS delete servicemonitor bifrost"
  echo "[DRY-RUN] kubectl -n $NS delete svc mcp-kubernetes-sse"
  echo "[DRY-RUN] kubectl -n $NS delete endpoints mcp-kubernetes-sse"
  echo "[DRY-RUN] kubectl delete namespace $NS"
  echo "[DRY-RUN] pkill -f kubernetes-mcp-server"
  echo ""
  echo "Re-run with --apply to execute."
else
  helm uninstall bifrost --namespace $NS 2>/dev/null || true
  kubectl -n $NS delete secret bifrost-encryption-key --ignore-not-found=true
  kubectl -n $NS delete servicemonitor bifrost --ignore-not-found=true
  kubectl -n $NS delete svc mcp-kubernetes-sse --ignore-not-found=true
  kubectl -n $NS delete endpoints mcp-kubernetes-sse --ignore-not-found=true
  kubectl delete namespace $NS --ignore-not-found=true
  pkill -f "kubernetes-mcp-server" 2>/dev/null || true
  echo "Teardown complete."
fi
