# Troubleshooting

## Pod won't start / CrashLoopBackOff
- `kubectl logs deploy/<release>-hermes-agent` and `kubectl describe pod ...`.
- **Image pull errors:** with the floating tag you may be rate-limited or offline;
  pin `image.digest` and set `imagePullSecrets` for private registries.
- **`runAsNonRoot` / permission denied writing `/opt/data`:** the volume must be
  writable by UID 10000. The chart sets `fsGroup: 10000`; if you reuse an old PVC
  with root-owned files, fix ownership or keep `fsGroupChangePolicy: OnRootMismatch`.
- Do **not** set `securityContext.readOnlyRootFilesystem: true` — s6-overlay (PID 1)
  writes to `/run`.

## PVC stuck Pending
- No default `StorageClass`, or it can't provide `ReadWriteOnce`. Set
  `persistence.storageClass` to a valid RWO class, or `kubectl get storageclass`.

## Gateway unreachable
- It only listens on the pod network when `service.enabled` (sets `API_SERVER_HOST=0.0.0.0`).
- Test from your laptop with port-forward, not Ingress:
  `kubectl port-forward svc/<release>-hermes-agent 8642:8642`.
- **401 / auth errors:** you need `API_SERVER_KEY`. Provide it via `apiServer.key`
  (dev) or `secrets.existingSecret` / `extraEnvFrom` (prod), and send it as the
  bearer token.

## Tools fail / can't reach LLM provider
- If `networkPolicy.enabled` with an egress allow-list, the agent can only reach the
  CIDRs/ports you allowed. Add the provider (port 443) and keep `allowDNS: true`.
  Remember NP is **L4-only** — it can't match hostnames ([network-policies.md](network-policies.md)).
- Browser/Playwright tools need shared memory: set `shm.enabled: true`.

## "I scaled to 2 and it broke" / render rejected
- By design. Hermes is single-writer; `persistence.enabled + replicaCount>1` is
  rejected. Run **more releases** (one per tenant), not more replicas.

## Rollout has downtime
- Expected: `strategy.type: Recreate` (the old pod must release the RWO PVC before
  the new one starts). This is required for data safety.

## Dashboard
- It's off by default and, when on, not on the Service. Reach it via port-forward to
  port 9119, or set `dashboard.service: true` (still keep it off the public internet).
