# ServiceMonitor Debugging & Fix — Quick Reference

**Problem:** Prometheus shows "No active targets" for a ServiceMonitor even though it was discovered.

---

## The Core Issue

ServiceMonitor has **two matching systems:**

1. **ServiceMonitor label selector** (for Prometheus operator to find this ServiceMonitor)
   ```yaml
   metadata:
     labels:
       release: kube-prometheus-stack  ← Prometheus operator requires this
   ```

2. **Service label selector** (for ServiceMonitor to find which services to scrape)
   ```yaml
   spec:
     selector:
       matchLabels:
         app.kubernetes.io/name: bifrost  ← Must match service labels
   ```

---

## Debug Checklist

### Step 1: Verify service exists and has labels

```bash
kubectl -n ai-gateway get svc bifrost -o yaml | grep -A 10 "labels:"

# Expected output:
#   labels:
#     app.kubernetes.io/instance: bifrost
#     app.kubernetes.io/managed-by: Helm
#     app.kubernetes.io/name: bifrost          ← THIS LABEL
#     app.kubernetes.io/version: 1.5.0
#     helm.sh/chart: bifrost-2.1.15
```

**Note:** Helm standard labels use dots, not underscores: `app.kubernetes.io/name`

### Step 2: Verify service has endpoints (pod is selected)

```bash
kubectl -n ai-gateway get endpoints bifrost

# Expected:
# NAME      ENDPOINTS          AGE
# bifrost   10.244.1.21:8080   3h
```

If endpoints is empty, service selector is wrong (but this is a separate issue).

### Step 3: Check ServiceMonitor selector matches service labels

```bash
kubectl -n ai-gateway get servicemonitor bifrost -o yaml | grep -A 5 "selector:"

# Expected:
#   spec:
#     selector:
#       matchLabels:
#         app.kubernetes.io/name: bifrost
```

**Common mistake:** Using `app: bifrost` when service only has `app.kubernetes.io/name: bifrost`

### Step 4: Check ServiceMonitor has release label

```bash
kubectl -n ai-gateway get servicemonitor bifrost -o yaml | grep -A 2 "labels:"

# Expected:
#   labels:
#     release: kube-prometheus-stack
#     app: bifrost
```

This label must match Prometheus's `serviceMonitorSelector.matchLabels.release`.

```bash
kubectl -n monitoring get prometheus kube-prometheus-stack-prometheus -o yaml | grep -A 3 "serviceMonitorSelector:"

# Expected:
#   serviceMonitorSelector:
#     matchLabels:
#       release: kube-prometheus-stack
```

### Step 5: Verify Prometheus discovered the ServiceMonitor

```bash
kubectl -n monitoring logs prometheus-kube-prometheus-stack-prometheus-0 --tail=50 | grep -i "bifrost\|servicemonitor"

# Expected:
# level=INFO source=kubernetes.go:323 component="discovery manager scrape" 
# discovery=kubernetes config=serviceMonitor/ai-gateway/bifrost/0
```

### Step 6: Check if target appears in Prometheus

```bash
curl -s http://localhost:9090/api/v1/targets | \
  jq '.data.activeTargets[] | select(.labels.job=="bifrost") | {health, instance}'

# Expected:
# {
#   "health": "up",
#   "instance": "10.244.1.21:8080"
# }
```

If still empty, restart Prometheus:

```bash
kubectl -n monitoring delete pod prometheus-kube-prometheus-stack-prometheus-0
sleep 30
# Re-run the curl above
```

---

## Common Failures & Fixes

### Problem: ServiceMonitor Discovered But Target Missing

**Symptom:**
```
Prometheus logs show: config=serviceMonitor/ai-gateway/bifrost/0
But curl http://localhost:9090/api/v1/targets shows no bifrost target
```

**Diagnosis:**
1. Check if service has the matched label:
   ```bash
   kubectl -n ai-gateway get svc bifrost -o yaml | grep "app.kubernetes.io/name"
   ```

2. Check if ServiceMonitor selector matches:
   ```bash
   kubectl -n ai-gateway get servicemonitor bifrost -o yaml | grep -A 3 "matchLabels:"
   ```

3. If they match, restart Prometheus to force reload:
   ```bash
   kubectl -n monitoring delete pod prometheus-kube-prometheus-stack-prometheus-0
   sleep 60
   curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="bifrost")'
   ```

### Problem: Metrics Not Appearing

**Symptom:**
```
Target health is "up" but query returns 0 results
curl -s 'http://localhost:9090/api/v1/query?query=my_metric' | jq '.data.result'
# Returns: []
```

**Diagnosis:**
1. Check if the pod is actually exporting metrics:
   ```bash
   kubectl -n ai-gateway exec bifrost-0 -- wget -qO- http://localhost:8080/metrics | grep "my_metric"
   ```

2. If no metrics, generate traffic:
   ```bash
   bash scripts/bifrost-sim.sh 50
   sleep 30
   # Re-query Prometheus
   ```

3. If metrics exist in pod but not in Prometheus, wait for scrape interval:
   - Default: 15s
   - Check last scrape time in Prometheus UI
   - Or restart Prometheus to force immediate scrape

### Problem: ServiceMonitor Not Discovered

**Symptom:**
```
Prometheus logs show NO config=serviceMonitor lines for your service
```

**Diagnosis:**
1. Check ServiceMonitor label:
   ```bash
   kubectl -n ai-gateway get servicemonitor bifrost -o yaml | grep -A 2 "labels:"
   # Must have: release: kube-prometheus-stack
   ```

2. Check Prometheus serviceMonitorSelector:
   ```bash
   kubectl -n monitoring get prometheus kube-prometheus-stack-prometheus -o yaml | grep -A 3 "serviceMonitorSelector:"
   # Must match the label above
   ```

3. Fix and reapply:
   ```bash
   kubectl -n ai-gateway delete servicemonitor bifrost
   kubectl -n ai-gateway apply -f manifests/bifrost-servicemonitor.yaml
   kubectl -n monitoring delete pod prometheus-kube-prometheus-stack-prometheus-0
   sleep 30
   ```

---

## The Correct Pattern

```yaml
---
# SERVICE: defines what gets scraped
apiVersion: v1
kind: Service
metadata:
  name: bifrost
  namespace: ai-gateway
  labels:
    app.kubernetes.io/name: bifrost  ← SERVICE LABEL
spec:
  selector:
    app: bifrost  ← SELECTS THE POD (different from service labels!)
  ports:
  - name: http
    port: 8080

---
# SERVICEMONITOR: tells Prometheus to scrape this service
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: bifrost
  namespace: ai-gateway
  labels:
    release: kube-prometheus-stack  ← FOR PROMETHEUS OPERATOR
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: bifrost  ← MATCHES SERVICE LABEL ABOVE
  endpoints:
  - port: http
    interval: 15s
    path: /metrics
```

**Key insight:** ServiceMonitor selector matches **service labels**, not pod labels.

---

## Validation Command

Copy & run to validate your setup:

```bash
#!/bin/bash
NAMESPACE="ai-gateway"
SERVICE="bifrost"

echo "=== Service Labels ==="
kubectl -n $NAMESPACE get svc $SERVICE -o yaml | grep -A 10 "^  labels:"

echo -e "\n=== ServiceMonitor Selector ==="
kubectl -n $NAMESPACE get servicemonitor $SERVICE -o yaml | grep -A 3 "selector:"

echo -e "\n=== ServiceMonitor Release Label ==="
kubectl -n $NAMESPACE get servicemonitor $SERVICE -o yaml | grep -B 2 "release: kube-prometheus"

echo -e "\n=== Prometheus ServiceMonitorSelector ==="
kubectl -n monitoring get prometheus kube-prometheus-stack-prometheus -o yaml | grep -A 3 "serviceMonitorSelector:"

echo -e "\n=== Active Target ==="
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="'$SERVICE'") | {health, instance}'
```

---

## References

- [Prometheus Operator - ServiceMonitor](https://github.com/prometheus-operator/prometheus-operator/blob/main/Documentation/user-guides/getting-started.md)
- [Kubernetes Label Conventions](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/)
- [Helm Standard Labels](https://helm.sh/docs/chart_best_practices/labels-and-annotations/)

---

**Last Updated:** 2026-05-12  
**Related Session:** SESSION_RECAP_2026-05-12-prometheus-bifrost-fix.md
