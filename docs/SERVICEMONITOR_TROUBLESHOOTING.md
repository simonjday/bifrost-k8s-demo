# Bifrost ServiceMonitor — Troubleshooting & Prevention

## What Broke

**After Bifrost 1.5.0 → 1.5.2 upgrade**, Prometheus stopped scraping Bifrost metrics.

**Root Causes:**

1. **Label mismatch**: ServiceMonitor had `release: prometheus`, but Prometheus expects `release: kube-prometheus-stack`
2. **Selector mismatch**: ServiceMonitor looked for `app: bifrost`, but Service has `app.kubernetes.io/name: bifrost`

---

## Why It Happened

The original `manifests/bifrost-servicemonitor.yaml` was created with incorrect labels and selectors:

```yaml
# OLD (broken)
labels:
  release: prometheus  # ❌ Wrong — Prometheus won't match this
selector:
  matchLabels:
    app: bifrost  # ❌ Wrong — Service doesn't have this label
```

This worked initially by accident (manual fixes), but broke on upgrade because Helm re-applied the incorrect manifest.

---

## The Fix

**Correct ServiceMonitor YAML:**

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: bifrost
  namespace: ai-gateway
  labels:
    app: bifrost
    release: kube-prometheus-stack  # ✅ Matches Prometheus selector
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: bifrost  # ✅ Matches Service labels
  endpoints:
  - port: http
    path: /metrics
    interval: 15s
    scheme: http
```

**Key points:**
- `release: kube-prometheus-stack` — Required for Prometheus to discover the ServiceMonitor
- `app.kubernetes.io/name: bifrost` — Matches the Service selector
- Port named `http` must exist on Service
- Path `/metrics` is where Bifrost exposes metrics

---

## How to Verify It's Working

```bash
# 1. ServiceMonitor exists with correct labels
kubectl get servicemonitor -n ai-gateway bifrost -o yaml | grep -A 3 'release:'

# Expected: release: kube-prometheus-stack

# 2. Selector matches Service
kubectl get servicemonitor -n ai-gateway bifrost -o yaml | grep -A 3 'selector:'
kubectl get svc -n ai-gateway bifrost -o yaml | grep -A 3 'labels:'

# 3. Prometheus discovers target
curl -s 'http://localhost:9090/api/v1/targets?state=active' | \
  jq '.data.activeTargets[] | select(.labels.job=="bifrost") | .health'

# Expected: "up"

# 4. Metrics appear in Prometheus
curl -s 'http://localhost:9090/api/v1/query?query=bifrost_requests_total' | jq '.data.result | length'

# Expected: > 0
```

---

## Prevention: Update install.sh

Add validation after applying ServiceMonitor:

```bash
# Step 7b: Observability manifests
echo "--- Step 7b: Observability manifests"

# Apply ServiceMonitor
run "kubectl_cmd apply -f $REPO_ROOT/manifests/bifrost-servicemonitor.yaml"

# Validate labels are correct
if ! $DRY_RUN; then
  echo "    Validating ServiceMonitor configuration..."
  
  RELEASE_LABEL=$(kubectl_cmd get servicemonitor -n $NS bifrost -o jsonpath='{.metadata.labels.release}' 2>/dev/null || echo "")
  if [[ "$RELEASE_LABEL" != "kube-prometheus-stack" ]]; then
    echo "    ⚠ WARNING: ServiceMonitor release label is '$RELEASE_LABEL', expected 'kube-prometheus-stack'"
    echo "    Fix: kubectl patch servicemonitor bifrost -n $NS --type merge -p '{\"metadata\":{\"labels\":{\"release\":\"kube-prometheus-stack\"}}}'"
  else
    echo "    ✓ ServiceMonitor labels correct"
  fi
fi
```

---

## If This Breaks Again

### Diagnosis

```bash
# 1. Check ServiceMonitor exists
kubectl get servicemonitor -n ai-gateway bifrost

# 2. Check labels match Prometheus selector
kubectl get prometheus -n monitoring kube-prometheus-stack-prometheus -o yaml | \
  grep -A 5 'serviceMonitorSelector:'

# 3. Check selector matches Service
kubectl get servicemonitor -n ai-gateway bifrost -o yaml | grep -A 3 'selector:'
kubectl get svc -n ai-gateway bifrost -o yaml | grep -A 3 'labels:'

# 4. Check if Prometheus sees it
curl -s 'http://localhost:9090/api/v1/targets?state=active' | \
  jq '.data.activeTargets[] | select(.labels.job=="bifrost")'

# 5. Check Prometheus logs
kubectl logs -n monitoring prometheus-kube-prometheus-stack-prometheus-0 --tail=50 | \
  grep -i bifrost
```

### Quick Fix

```bash
# Apply corrected manifest
kubectl apply -f manifests/bifrost-servicemonitor.yaml

# Restart Prometheus
kubectl rollout restart statefulset/prometheus-kube-prometheus-stack-prometheus -n monitoring
kubectl rollout status statefulset/prometheus-kube-prometheus-stack-prometheus -n monitoring -w

# Verify
curl -s 'http://localhost:9090/api/v1/targets?state=active' | \
  jq '.data.activeTargets[] | select(.labels.job=="bifrost") | .health'
```

---

## Checklist for Future Upgrades

- [ ] After upgrade, verify ServiceMonitor labels: `kubectl get servicemonitor -n ai-gateway bifrost -o yaml | grep release:`
- [ ] Verify Prometheus sees target: `curl -s 'http://localhost:9090/api/v1/targets?state=active' | jq '.data.activeTargets[] | select(.labels.job=="bifrost")'`
- [ ] If missing, apply corrected manifest: `kubectl apply -f manifests/bifrost-servicemonitor.yaml`
- [ ] Restart Prometheus if needed: `kubectl rollout restart statefulset/prometheus-kube-prometheus-stack-prometheus -n monitoring`

---

## Summary

| Issue | Cause | Fix |
|-------|-------|-----|
| Prometheus doesn't scrape Bifrost | Wrong `release` label | Change to `kube-prometheus-stack` |
| ServiceMonitor doesn't match Service | Wrong selector | Change to `app.kubernetes.io/name: bifrost` |
| Metrics don't appear after fix | Prometheus caching | Restart Prometheus StatefulSet |
| Breaks on every upgrade | Manifest has incorrect values | Keep manifests correct, validate in install.sh |
