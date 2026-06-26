# GitOps (Argo CD / Flux)

The charts render deterministically and publish to both an **OCI registry** and a
**classic Helm repo**, so either tool works. Keep secrets out of Git (use External
Secrets / SOPS — see [external-secrets.md](external-secrets.md)).

## Argo CD (OCI)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: hermes
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ghcr.io/ketaloca/charts          # OCI registry (no scheme)
    chart: hermes-agent
    targetRevision: 0.1.3
    helm:
      valueFiles: []
      values: |
        secrets:
          existingSecret: hermes-secrets
        persistence:
          size: 20Gi
  destination:
    server: https://kubernetes.default.svc
    namespace: hermes
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
```

## Flux (OCI)

```yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: ketaloca
  namespace: flux-system
spec:
  type: oci
  url: oci://ghcr.io/ketaloca/charts
  interval: 1h
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: hermes
  namespace: hermes
spec:
  interval: 30m
  chart:
    spec:
      chart: hermes-agent
      version: "0.1.3"
      sourceRef:
        kind: HelmRepository
        name: ketaloca
        namespace: flux-system
  values:
    secrets:
      existingSecret: hermes-secrets
```

## Notes

- Pin `targetRevision` / `version` (and `image.digest`) — don't float.
- The chart uses no install hooks, so `--dry-run`/diff is clean.
- The PVC carries `helm.sh/resource-policy: keep`; deleting the Application/HelmRelease
  retains data (delete the PVC manually to remove it).
- For OpenClaw later, the operator's CRDs must exist before the `OpenClawInstance`
  syncs — use Argo sync waves / Flux `dependsOn`.
