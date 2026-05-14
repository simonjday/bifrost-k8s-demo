#!/bin/bash
# test-prometheus-connectivity.sh
# Validates Prometheus and prometheus-mcp connectivity and basic functionality
# Usage: ./test-prometheus-connectivity.sh

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROMETHEUS_NAMESPACE="monitoring"
PROMETHEUS_SERVICE="kube-prometheus-stack-prometheus"
PROMETHEUS_PORT="9090"
PROMETHEUS_MCP_SERVICE="prometheus-mcp"
PROMETHEUS_MCP_PORT="8080"

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║     Prometheus & prometheus-mcp Connectivity Test Suite       ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# Helper functions
pass() {
  echo -e "${GREEN}✓ PASS${NC}: $1"
}

fail() {
  echo -e "${RED}✗ FAIL${NC}: $1"
  exit 1
}

warn() {
  echo -e "${YELLOW}⚠ WARN${NC}: $1"
}

info() {
  echo -e "${YELLOW}ℹ${NC} $1"
}

# Test 1: Kubernetes connectivity
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 1: Kubernetes Connectivity"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if kubectl cluster-info &> /dev/null; then
  pass "kubectl cluster-info accessible"
else
  fail "kubectl cluster-info not accessible"
fi

if kubectl get namespace "$PROMETHEUS_NAMESPACE" &> /dev/null; then
  pass "Namespace '$PROMETHEUS_NAMESPACE' exists"
else
  fail "Namespace '$PROMETHEUS_NAMESPACE' not found"
fi

echo ""

# Test 2: Prometheus Deployment
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 2: Prometheus Deployment Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

PROM_PODS=$(kubectl get pods -n "$PROMETHEUS_NAMESPACE" -l app.kubernetes.io/name=prometheus --no-headers | wc -l)
if [ "$PROM_PODS" -gt 0 ]; then
  pass "Prometheus pod(s) found ($PROM_PODS running)"
  kubectl get pods -n "$PROMETHEUS_NAMESPACE" -l app.kubernetes.io/name=prometheus
else
  fail "No Prometheus pods found in namespace '$PROMETHEUS_NAMESPACE'"
fi

echo ""

# Test 3: Prometheus Service
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 3: Prometheus Service"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if kubectl get svc -n "$PROMETHEUS_NAMESPACE" "$PROMETHEUS_SERVICE" &> /dev/null; then
  PROM_ENDPOINT=$(kubectl get svc -n "$PROMETHEUS_NAMESPACE" "$PROMETHEUS_SERVICE" -o jsonpath='{.spec.clusterIP}')
  pass "Service '$PROMETHEUS_SERVICE' exists at $PROM_ENDPOINT:$PROMETHEUS_PORT"
else
  fail "Service '$PROMETHEUS_SERVICE' not found"
fi

echo ""

# Test 4: Prometheus API Health Check
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 4: Prometheus API Health Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

info "Running health check against Prometheus API..."
PROM_HEALTH=$(kubectl run --rm -it --restart=Never --image=curlimages/curl:latest \
  -n "$PROMETHEUS_NAMESPACE" prometheus-health-check \
  -- sh -c "curl -sf http://$PROMETHEUS_SERVICE:$PROMETHEUS_PORT/-/healthy" 2>/dev/null || echo "FAILED")

if [ "$PROM_HEALTH" != "FAILED" ]; then
  pass "Prometheus health check: OK"
else
  fail "Prometheus health check failed"
fi

echo ""

# Test 5: Prometheus Query Test
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 5: Prometheus Query Test"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

info "Testing simple metric query (up)..."
PROM_QUERY=$(kubectl run --rm -it --restart=Never --image=curlimages/curl:latest \
  -n "$PROMETHEUS_NAMESPACE" prometheus-query-test \
  -- sh -c "curl -sf 'http://$PROMETHEUS_SERVICE:$PROMETHEUS_PORT/api/v1/query?query=up'" 2>/dev/null | grep -q '"value"' && echo "OK" || echo "FAILED")

if [ "$PROM_QUERY" = "OK" ]; then
  pass "Prometheus query (up): OK"
else
  fail "Prometheus query failed"
fi

echo ""

# Test 6: prometheus-mcp Deployment
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 6: prometheus-mcp Deployment Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if kubectl get pods -n "$PROMETHEUS_NAMESPACE" -l app=prometheus-mcp &> /dev/null; then
  MCP_PODS=$(kubectl get pods -n "$PROMETHEUS_NAMESPACE" -l app=prometheus-mcp --no-headers | wc -l)
  if [ "$MCP_PODS" -gt 0 ]; then
    pass "prometheus-mcp pod(s) found ($MCP_PODS running)"
    kubectl get pods -n "$PROMETHEUS_NAMESPACE" -l app=prometheus-mcp
    
    # Check if Ready
    MCP_READY=$(kubectl get pods -n "$PROMETHEUS_NAMESPACE" -l app=prometheus-mcp -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}')
    if [ "$MCP_READY" = "True" ]; then
      pass "prometheus-mcp pod is Ready (1/1)"
    else
      warn "prometheus-mcp pod is not Ready yet (may still be starting)"
    fi
  else
    warn "No prometheus-mcp pods found (is it deployed? See manifests/prometheus-mcp-stateful-5min.yaml)"
  fi
else
  warn "prometheus-mcp pods not found (optional component)"
fi

echo ""

# Test 7: prometheus-mcp Service
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 7: prometheus-mcp Service"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if kubectl get svc -n "$PROMETHEUS_NAMESPACE" "$PROMETHEUS_MCP_SERVICE" &> /dev/null; then
  MCP_ENDPOINT=$(kubectl get svc -n "$PROMETHEUS_NAMESPACE" "$PROMETHEUS_MCP_SERVICE" -o jsonpath='{.spec.clusterIP}')
  pass "Service '$PROMETHEUS_MCP_SERVICE' exists at $MCP_ENDPOINT:$PROMETHEUS_MCP_PORT"
else
  warn "Service '$PROMETHEUS_MCP_SERVICE' not found (is it deployed?)"
fi

echo ""

# Test 8: prometheus-mcp Connectivity (if running)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 8: prometheus-mcp MCP Connectivity"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if kubectl get svc -n "$PROMETHEUS_NAMESPACE" "$PROMETHEUS_MCP_SERVICE" &> /dev/null; then
  info "Testing MCP ping request..."
  MCP_PING=$(kubectl run --rm -it --restart=Never --image=curlimages/curl:latest \
    -n "$PROMETHEUS_NAMESPACE" prometheus-mcp-ping \
    -- sh -c "curl -sf -X POST 'http://$PROMETHEUS_MCP_SERVICE:$PROMETHEUS_MCP_PORT/' \
      -H 'Content-Type: application/json' \
      -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\",\"params\":{}}' | grep -q '\"id\":1' && echo 'OK' || echo 'FAILED'" 2>/dev/null)
  
  if [ "$MCP_PING" = "OK" ]; then
    pass "prometheus-mcp ping: OK"
  else
    warn "prometheus-mcp ping failed (pod may not be fully initialized yet)"
  fi
else
  info "Skipping prometheus-mcp connectivity test (service not found)"
fi

echo ""

# Test 9: prometheus-mcp Pod Stability
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 9: prometheus-mcp Pod Stability (Restart Count)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if kubectl get pods -n "$PROMETHEUS_NAMESPACE" -l app=prometheus-mcp &> /dev/null; then
  MCP_RESTARTS=$(kubectl get pods -n "$PROMETHEUS_NAMESPACE" -l app=prometheus-mcp -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}')
  if [ "$MCP_RESTARTS" = "0" ]; then
    pass "prometheus-mcp restarts: $MCP_RESTARTS (stable)"
  else
    warn "prometheus-mcp restarts: $MCP_RESTARTS (pod has restarted)"
  fi
else
  info "prometheus-mcp pod not found, skipping restart check"
fi

echo ""

# Summary
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                    Test Summary                               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo -e "${GREEN}✓ Core infrastructure tests passed${NC}"
echo ""
echo "Next Steps:"
echo "  1. If prometheus-mcp is not deployed:"
echo "     kubectl apply -f manifests/prometheus-mcp-stateful-5min.yaml"
echo ""
echo "  2. Configure Bifrost MCP client:"
echo "     URL: http://prometheus-mcp.monitoring.svc.cluster.local:8080/"
echo ""
echo "  3. Test with Postman or curl (20+ queries):"
echo "     - Queries should succeed continuously"
echo "     - Auto-recovery every ~45-60s (transparent to user)"
echo ""
echo "  4. Monitor pod stability:"
echo "     kubectl get pods -n monitoring -l app=prometheus-mcp -w"
echo ""
