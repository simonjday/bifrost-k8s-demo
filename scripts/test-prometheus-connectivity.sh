#!/bin/bash
# Test Prometheus connectivity from prometheus-mcp pod context

set -e

PROM_URL="http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090"
TIMEOUT=10

echo "========================================="
echo "Prometheus MCP Connectivity Debug"
echo "========================================="
echo ""

echo "Target URL: $PROM_URL"
echo ""

# Test 1: Health check
echo "=== TEST 1: Health Check (/-/healthy) ==="
echo "Timeout: ${TIMEOUT}s"
if timeout $TIMEOUT curl -s -w "\nHTTP %{http_code}\n" "$PROM_URL/-/healthy"; then
    echo "✓ Health check passed"
else
    echo "✗ Health check failed or timed out"
fi
echo ""

# Test 2: Ready check
echo "=== TEST 2: Ready Check (/-/ready) ==="
echo "Timeout: ${TIMEOUT}s"
if timeout $TIMEOUT curl -s -w "\nHTTP %{http_code}\n" "$PROM_URL/-/ready"; then
    echo "✓ Ready check passed"
else
    echo "✗ Ready check failed or timed out"
fi
echo ""

# Test 3: TSDB status
echo "=== TEST 3: TSDB Status (api/v1/status/tsdb) ==="
echo "Timeout: ${TIMEOUT}s"
if timeout $TIMEOUT curl -s "$PROM_URL/api/v1/status/tsdb" | python3 -m json.tool 2>&1 | head -20; then
    echo "✓ TSDB status query succeeded"
else
    echo "✗ TSDB status query failed or timed out"
fi
echo ""

# Test 4: Simple up query
echo "=== TEST 4: Simple Query (query=up) ==="
echo "Timeout: ${TIMEOUT}s"
if timeout $TIMEOUT curl -s "$PROM_URL/api/v1/query?query=up" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'Status: {d.get(\"status\")}'); print(f'Results: {len(d.get(\"data\",{}).get(\"result\",[]))}')"; then
    echo "✓ Simple query succeeded"
else
    echo "✗ Simple query failed or timed out"
fi
echo ""

# Test 5: Bifrost metric query
echo "=== TEST 5: Bifrost Metric Query (bifrost_success_requests_total) ==="
echo "Timeout: ${TIMEOUT}s"
START_TIME=$(date +%s)
if timeout $TIMEOUT curl -s "$PROM_URL/api/v1/query?query=bifrost_success_requests_total" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'Status: {d.get(\"status\")}'); print(f'Results: {len(d.get(\"data\",{}).get(\"result\",[]))}'); [print(f'  - {r[\"metric\"][\"model\"]}: {r[\"value\"][1]}') for r in d.get('data',{}).get('result',[])[:5]]"; then
    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))
    echo "✓ Bifrost query succeeded (${ELAPSED}s)"
else
    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))
    echo "✗ Bifrost query failed or timed out (${ELAPSED}s)"
fi
echo ""

# Test 6: Range query with aggregation
echo "=== TEST 6: Range Query with Aggregation (5m rate) ==="
echo "Timeout: ${TIMEOUT}s"
if timeout $TIMEOUT curl -s "$PROM_URL/api/v1/query_range?query=sum(rate(bifrost_success_requests_total%5B5m%5D))&start=$(($(date +%s) - 300))&end=$(date +%s)&step=60" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'Status: {d.get(\"status\")}'); print(f'Series: {len(d.get(\"data\",{}).get(\"result\",[]))}')"; then
    echo "✓ Range query succeeded"
else
    echo "✗ Range query failed or timed out"
fi
echo ""

echo "========================================="
echo "Test complete"
echo "========================================="
