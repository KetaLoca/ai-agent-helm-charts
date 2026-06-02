# Production checklist

Work through this before exposing `hermes-agent` to anything real.

## Images
- [ ] `image.digest` pinned (not a floating tag, never `:latest`).
- [ ] `image.pullPolicy: IfNotPresent`; pull secrets set if the registry is private.

## Secrets
- [ ] API key + provider keys via `secrets.existingSecret` / `extraEnvFrom` (External Secrets).
- [ ] **No plaintext secrets** in Git or in `values.yaml` (`secrets.create`/`apiServer.key` are dev-only).

## Exposure
- [ ] `ingress.enabled: false`, or fronted by an identity-aware proxy + TLS + auth + rate limiting.
- [ ] `service.type: ClusterIP` (no LoadBalancer/NodePort to the internet).
- [ ] Dashboard off, or behind a VPN; `dashboard.insecure` not used.
- [ ] `apiServer.requireKey: true` and a key source is actually configured.

## State & availability
- [ ] `replicaCount: 1` with persistence; `strategy.type: Recreate`.
- [ ] `persistence.enabled: true`, `retain: true`, sized appropriately, on a fast RWO StorageClass.
- [ ] **Backups scheduled and a restore tested** (see [backup-restore.md](backup-restore.md)).
- [ ] PDB sized so it doesn't wedge node drains (avoid `minAvailable:1` at replicas=1).

## Pod hardening
- [ ] `runAsNonRoot`, `fsGroup`, `seccompProfile: RuntimeDefault` (defaults — keep them).
- [ ] `allowPrivilegeEscalation: false`, `capabilities: drop [ALL]` (defaults).
- [ ] `automountServiceAccountToken: false`; no cluster RBAC granted.
- [ ] `resources.requests/limits` set; `shm.enabled: true` if browser tools are used.

## Network
- [ ] `networkPolicy.enabled: true` with a DNS + HTTPS **egress allow-list**.
- [ ] Aware that NP is L4-only; FQDN egress needs Cilium/mesh if required.
- [ ] If Ingress is used, the controller namespace is allowed in the NetworkPolicy.

## Operations
- [ ] Monitoring + log shipping; alert on pod restarts and egress anomalies.
- [ ] Multi-tenant: one release per tenant, namespace isolation, per-instance secrets.
- [ ] Upgrade tested in staging; `CHANGELOG.md` / [upgrade.md](upgrade.md) reviewed.
