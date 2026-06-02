# Backup & restore

Hermes keeps **irreplaceable state** in the PVC at `/opt/data`: `config.yaml`,
`.env` (keys), `SOUL.md`, `sessions/`, `memories/`, `skills/`, `logs/`. The chart
sets `persistence.retain: true` so `helm uninstall` keeps the PVC — but that is **not
a backup**. Back the volume up.

## What to back up

- The PVC `…-hermes-agent` (the `/opt/data` volume).
- Optionally the Kubernetes objects (Helm release / values) — but those are
  reproducible from your GitOps repo; the data is not.

## Velero (recommended)

```bash
# One-off backup of a namespace (with volume data via the Velero file-system backup / CSI snapshots)
velero backup create hermes-$(date +%F) \
  --include-namespaces my-namespace \
  --default-volumes-to-fs-backup

# Scheduled daily backup, 30-day retention
velero schedule create hermes-daily \
  --schedule "0 3 * * *" \
  --include-namespaces my-namespace \
  --default-volumes-to-fs-backup \
  --ttl 720h
```

CSI volume snapshots (if your StorageClass supports them) are faster and more
consistent than file-system backup.

## Consistency note

Hermes is a **single writer** and sqlite-like stores don't love being copied
mid-write. For a crash-consistent backup, either use a CSI snapshot, or quiesce
first:

```bash
kubectl scale deploy/my-hermes-hermes-agent --replicas=0   # stop the writer
# snapshot / back up the PVC
kubectl scale deploy/my-hermes-hermes-agent --replicas=1   # resume
```

## Restore

1. Restore the PVC (Velero restore, or provision a PVC from a snapshot).
2. Install/point the release at it:
   ```bash
   helm install my-hermes oci://ghcr.io/ketaloca/charts/hermes-agent --version 0.1.0 \
     --set persistence.existingClaim=my-restored-pvc
   ```
3. Verify: `kubectl logs deploy/my-hermes-hermes-agent` and `helm test my-hermes`.

**Test your restore** on a throwaway namespace before you need it.
