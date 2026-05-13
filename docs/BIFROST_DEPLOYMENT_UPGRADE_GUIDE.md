# Bifrost Deployment & Upgrade Guide

## Overview

Bifrost is deployed via Helm with version management via CLI flags. The values file (`manifests/bifrost-values-dev.yaml`) is version-agnostic — version is always specified at install/upgrade time.

---

## Architecture

| Component | Type | Namespace | Notes |
|-----------|------|-----------|-------|
| Bifrost | StatefulSet | ai-gateway | Single replica, SQLite backend |
| MCP Proxy | Deployment | ai-gateway | socat proxy for kind clusters |
| Prometheus | ServiceMonitor | monitoring | Metrics scraping every 15s |

---

## Version Management

### How Versions Work

- **Values file** (`manifests/bifrost-values-dev.yaml`): Version-agnostic, no hardcoded `image.tag`
- **Version specification**: Always passed via `--set image.tag=<version>` to Helm
- **Default**: `v1.5.0` (in install.sh)
- **Configurable**: Via CLI flag `--bifrost-version` or env var `BIFROST_VERSION`

### Version History

| Version | Release | Status | Notes |
|---------|---------|--------|-------|
| v1.5.2 | 2024-05-13 | Current | Better MCP stability, faster init |
| v1.5.1 | 2024-05-01 | Superseded | Bug fix release |
| v1.5.0 | 2024-04-15 | LTS | Initial production release |

---

## Fresh Install

### Default (v1.5.0)

```bash
./install.sh --apply
```

Installs v1.5.0 (the default).

### Specific Version

```bash
./install.sh --apply --bifrost-version v1.5.2
```

Or via environment variable:

```bash
BIFROST_VERSION=v1.5.2 ./install.sh --apply
```

### Dry-Run First

Always dry-run before applying:

```bash
./install.sh --bifrost-version v1.5.2
# Review output, then:
./install.sh --apply --bifrost-version v1.5.2
```

---

## Upgrade Flow

### Scenario: Upgrade v1.5.0 → v1.5.2

#### Step 1: Dry-Run

```bash
helm upgrade bifrost bifrost/bifrost \
  --namespace ai-gateway \
  -f manifests/bifrost-values-dev.yaml \
  --set image.tag=v1.5.2 \
  --dry-run --debug
```

Review the output. Should show:
- StatefulSet spec update
- Pod rolling update (old pod terminating, new pod starting)
- No other changes

#### Step 2: Apply Upgrade

```bash
helm upgrade bifrost bifrost/bifrost \
  --namespace ai-gateway \
  -f manifests/bifrost-values-dev.yaml \
  --set image.tag=v1.5.2 \
  --wait --timeout 5m
```

`--wait`: Helm waits until pod is Ready (1/1)  
`--timeout 5m`: Fail if not ready within 5 minutes

#### Step 3: Verify

```bash
# Check image tag updated
kubectl get sts -n ai-gateway bifrost -o jsonpath='{.spec.template.spec.containers[0].image}'
# Expected: bifrostai/bifrost:v1.5.2

# Check pod status
kubectl get pod -n ai-gateway bifrost-0
# Expected: Running, Ready 1/1

# Check logs for errors
kubectl logs -n ai-gateway bifrost-0 -f --tail=30

# Health check
kubectl port-forward -n ai-gateway svc/bifrost 8080:8080 &
curl http://localhost:8080/health
# Expected: {"status":"healthy"}
pkill -f port-forward
```

---

## Rollback

If an upgrade fails or introduces issues:

### Option 1: Helm Rollback (Fastest)

```bash
# List previous releases
helm history bifrost -n ai-gateway

# Rollback to previous release
helm rollback bifrost 0 -n ai-gateway

# Monitor rollback
kubectl rollout status sts/bifrost -n ai-gateway -w
```

Reverts to v1.5.0 in ~2 minutes.

### Option 2: Manual Downgrade

```bash
helm upgrade bifrost bifrost/bifrost \
  --namespace ai-gateway \
  -f manifests/bifrost-values-dev.yaml \
  --set image.tag=v1.5.0 \
  --wait --timeout 5m
```

---

## ConfigMap Management

### How Bifrost Config Works

- **Source**: `manifests/bifrost-config.json` (git-controlled)
- **Deployment**: Bifrost Helm chart creates ConfigMap from `bifrost-config.json`
- **Content**: Includes logging, audit, telemetry, storage configs

### ConfigMap Conflicts on Upgrade

When upgrading Bifrost, you may see:
```
Error: conflict occurred while applying object ai-gateway/bifrost-config
conflict with "kubectl-client-side-apply"
```

**Cause**: Old ConfigMap was created by `kubectl apply`, Helm's server-side apply conflicts with it.

**Solution**: `install.sh` Step 7 automatically deletes the old ConfigMap before Helm upgrade. Helm recreates it fresh from the source file.

**Important**: This is safe because:
- ConfigMap content is version-controlled in `manifests/bifrost-config.json`
- Helm manages it consistently across upgrades
- No loss of configuration

### Customizing Bifrost Config

To modify Bifrost configuration:

1. **Edit source file**: `manifests/bifrost-config.json`
2. **Commit to git**
3. **Redeploy**: Run `install.sh` or `helm upgrade`

Example (enable governance header):
```json
{
  "client": {
    "enforce_governance_header": true
  }
}
```

Then:
```bash
./scripts/install.sh --apply --bifrost-version v1.5.2
```

ConfigMap updates automatically.

---

## Troubleshooting

### ConfigMap Conflict on Upgrade

**Error**:
```
Error: conflict occurred while applying object ai-gateway/bifrost-config
conflict with "kubectl-client-side-apply"
```

**Cause**: Old ConfigMap from `kubectl apply` conflicts with Helm's server-side apply.

**Solution**: `install.sh` Step 7 handles this automatically by deleting the old ConfigMap before upgrade. Helm recreates it from `manifests/bifrost-config.json`.

**Manual fix if needed**:
```bash
# Verify ConfigMap content is safe to delete
kubectl get configmap bifrost-config -n ai-gateway -o jsonpath='{.data.config\.json}' > /tmp/current.json
diff manifests/bifrost-config.json /tmp/current.json

# If identical, delete old ConfigMap
kubectl delete configmap bifrost-config -n ai-gateway

# Retry upgrade
./scripts/install.sh --apply --bifrost-version v1.5.2
```

No data loss — ConfigMap is recreated from git-controlled source file.

### Pod stuck in `ImagePullBackOff`

```bash
# Check Helm repo is accessible
helm repo list

# Check image exists in repo
helm search repo bifrost/bifrost

# Pod events
kubectl describe pod bifrost-0 -n ai-gateway
```

### Pod not becoming Ready

```bash
# Check logs
kubectl logs bifrost-0 -n ai-gateway -f

# Check pod events
kubectl describe pod bifrost-0 -n ai-gateway

# Check Helm release status
helm status bifrost -n ai-gateway

# Check resource requirements
kubectl top pod bifrost-0 -n ai-gateway
```

### MCP connectivity failing after upgrade

```bash
# Wait 10s for MCP connections to establish
sleep 10

# Test MCP endpoint from pod
kubectl -n ai-gateway exec bifrost-0 -- \
  wget -qO- http://mcp-kubernetes-sse.ai-gateway.svc.cluster.local:8811/healthz

# Check socat proxy (kind only)
kubectl get pod -n ai-gateway -l app=mcp-kubernetes-proxy
kubectl logs -n ai-gateway -l app=mcp-kubernetes-proxy
```

### Prometheus not scraping metrics

```bash
# Confirm ServiceMonitor exists
kubectl get servicemonitor -n monitoring

# Check Prometheus targets
curl http://localhost:9090/api/v1/targets?state=active | \
  jq '.data.activeTargets[] | select(.labels.namespace=="ai-gateway")'

# Check Bifrost metrics endpoint
kubectl port-forward -n ai-gateway bifrost-0 9091:9091 &
curl http://localhost:9091/metrics | grep bifrost_requests_total
pkill -f port-forward
```

---

## Quick Reference

### View Current Version

```bash
kubectl get sts -n ai-gateway bifrost -o jsonpath='{.spec.template.spec.containers[0].image}'
```

### View Helm Status

```bash
helm status bifrost -n ai-gateway
helm history bifrost -n ai-gateway
```

### View Logs

```bash
# Follow logs
kubectl logs -n ai-gateway bifrost-0 -f

# Last 50 lines
kubectl logs -n ai-gateway bifrost-0 --tail=50
```

### Port-Forward to Bifrost

```bash
kubectl port-forward -n ai-gateway svc/bifrost 8080:8080 &

# Test
curl http://localhost:8080/health

# Stop
pkill -f port-forward
```

### Check Resources

```bash
kubectl top pod bifrost-0 -n ai-gateway
kubectl get pvc -n ai-gateway
```

---

## Common Upgrade Scenarios

### Scenario 1: Minor Version Bump (e.g., 1.5.0 → 1.5.2)

**Risk**: Low (patch version, no breaking changes)  
**Downtime**: ~2 minutes (rolling update)

```bash
helm upgrade bifrost bifrost/bifrost \
  --namespace ai-gateway \
  -f manifests/bifrost-values-dev.yaml \
  --set image.tag=v1.5.2 \
  --wait --timeout 5m
```

### Scenario 2: Major Version Bump (e.g., 1.5.x → 2.0.0)

**Risk**: High (may have breaking changes)  
**Steps**:
1. Read release notes for v2.0.0
2. Check for values file changes or new required fields
3. Test in isolated environment first
4. Plan rollback if issues occur

```bash
# Check what changed in the chart
helm diff upgrade bifrost bifrost/bifrost \
  --namespace ai-gateway \
  -f manifests/bifrost-values-dev.yaml \
  --set image.tag=v2.0.0

# Then upgrade
helm upgrade bifrost bifrost/bifrost \
  --namespace ai-gateway \
  -f manifests/bifrost-values-dev.yaml \
  --set image.tag=v2.0.0 \
  --wait --timeout 5m
```

### Scenario 3: Emergency Downgrade

```bash
# Quick rollback
helm rollback bifrost 0 -n ai-gateway

# Or explicit downgrade to older version
helm upgrade bifrost bifrost/bifrost \
  --namespace ai-gateway \
  -f manifests/bifrost-values-dev.yaml \
  --set image.tag=v1.5.0 \
  --force --wait
```

---

## Helm Cheat Sheet

| Command | Purpose |
|---------|---------|
| `helm status bifrost -n ai-gateway` | Current release status |
| `helm history bifrost -n ai-gateway` | All past releases |
| `helm rollback bifrost 0 -n ai-gateway` | Rollback to previous release |
| `helm get values bifrost -n ai-gateway` | Show applied values |
| `helm upgrade --dry-run --debug ...` | Preview changes |
| `helm repo update` | Refresh chart repos |

---

## Best Practices

1. **Always dry-run first** — Review changes before applying
2. **Use `--wait` flag** — Ensures pod is ready before returning
3. **Monitor logs** — Watch for errors after upgrade: `kubectl logs -f bifrost-0 -n ai-gateway`
4. **Test MCP connectivity** — Verify tools work post-upgrade
5. **Keep values file version-agnostic** — Version belongs on the CLI, not in the values
6. **Document upgrades** — Note time, version, and any issues in logs/wiki

---

## Support & References

- **Bifrost Helm Chart**: https://github.com/maximhq/bifrost/tree/main/helm
- **Kubernetes Documentation**: https://kubernetes.io/docs/
- **Helm Documentation**: https://helm.sh/docs/

---

## Version Upgrade Timeline

| Version | Release Date | End of Support | Notes |
|---------|--------------|----------------|-------|
| v1.5.2 | 2024-05-13 | 2024-08-13 | Current (3-month support) |
| v1.5.1 | 2024-05-01 | 2024-08-01 | Superseded by 1.5.2 |
| v1.5.0 | 2024-04-15 | 2024-07-15 | Initial release, LTS |

Check [Bifrost Releases](https://github.com/maximhq/bifrost/releases) for latest versions.
