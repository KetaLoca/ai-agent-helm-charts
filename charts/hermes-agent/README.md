# hermes-agent

**Unofficial community Helm chart** for the [Hermes Agent](https://github.com/NousResearch/hermes-agent)
(`nousresearch/hermes-agent`). Hardened and **private by default**.

> ⚠️ Not affiliated with Nous Research. The container image is pulled from its
> upstream registry under its own license. See [TRADEMARKS.md](../../TRADEMARKS.md).

## What it deploys

A single Hermes Agent instance as a `Deployment` running the `gateway`, with an
optional `PersistentVolumeClaim` at `/opt/data`, a `ClusterIP` `Service` on `8642`,
and optional `Secret`, `Ingress`, `NetworkPolicy`, `PodDisruptionBudget`, and
`ServiceAccount`. Everything internet-facing is **off by default**.

**Scale out = more releases (one per tenant), never more replicas.** Hermes holds
single-writer state (`sessions/`, `memories/`, `skills/`) in `/opt/data`, so the
chart forbids `replicaCount > 1` with persistence and uses the `Recreate` strategy.

## Prerequisites

- Kubernetes **≥ 1.25**, Helm **≥ 3.8** (Helm 4 supported).
- A `StorageClass` providing `ReadWriteOnce` volumes (for persistence).

## Install

```bash
# OCI (no helm repo add needed)
helm install my-hermes oci://ghcr.io/ketaloca/charts/hermes-agent --version 0.1.5 \
  -f my-values.yaml

# …or the classic repo
helm repo add ketaloca https://ketaloca.github.io/ai-agent-helm-charts
helm install my-hermes ketaloca/hermes-agent --version 0.1.5 -f my-values.yaml
```

Reach it locally — the gateway is **not** exposed publicly by default:

```bash
kubectl port-forward svc/my-hermes-hermes-agent 8642:8642
# OpenAI-compatible API at http://127.0.0.1:8642 (send your API key)
```

> **Give the agent a brain.** A fresh install runs but has **no model provider**, so it
> won't answer until you configure one (subscription OAuth logins need **no API key**).
> See [docs/model-providers.md](../../docs/model-providers.md).

See [`examples/hermes/`](../../examples/hermes/): `minimal`, `production`,
`private-gateway`, `ingress-with-auth`, `external-secrets`, `tailscale`.

## Key decisions (and why)

- **Gateway binds `0.0.0.0` inside the pod** (`API_SERVER_HOST=0.0.0.0`) so the
  `ClusterIP` Service can reach it. This is **cluster-internal**, not the internet.
  Exposure beyond the cluster still needs Ingress (off) + the API key + (recommended)
  a NetworkPolicy.
- **API key required** for non-loopback access. Supply it via `secrets.existingSecret`
  / `extraEnvFrom` in production; `apiServer.key` is dev-only.
- **Single-writer / `Recreate`** — see above. `persistence.enabled + replicaCount>1`
  is rejected at render time.
- **Pinned by digest by default** — the image is `digest > tag > appVersion`; an
  all-empty reference fails. `appVersion` is an upstream CalVer release (`v2026.6.19`)
  and `values.yaml` ships the **matching `image.digest`**, so installs are immutable out
  of the box. The digest is refreshed together with `appVersion` on every bump; set
  `image.digest: ""` to track the tag instead.
- **Hardened by default** — `runAsNonRoot` (UID 10000), `allowPrivilegeEscalation: false`,
  `capabilities: drop [ALL]`, `seccompProfile: RuntimeDefault`, no auto-mounted SA token.
  `readOnlyRootFilesystem` is **off** by default (opt-in); the chart always mounts a tmpfs `/run` so the image's s6-overlay (PID 1) boots as the non-root user.
- **Dashboard off by default** — it stores/exposes API keys; opt-in and never on a
  public Service.

## Values

| Key | Default | Description |
|---|---|---|
| `replicaCount` | `1` | Must stay `1` with persistence (single-writer). |
| `image.repository` | `nousresearch/hermes-agent` | Image repo. |
| `image.tag` | `""` | Falls back to `appVersion`. Avoid `latest` in prod. |
| `image.digest` | `sha256:…` (matches `appVersion`) | **Pinned by default** for immutability (wins over tag). Set `""` to track the tag. |
| `image.pullPolicy` | `IfNotPresent` | |
| `command` / `args` | `[]` / `[gateway, run]` | Entry/args (image runs `gateway run` via s6). |
| `apiServer.requireKey` | `true` | Warn if the Service is on but no key source exists. |
| `apiServer.key` | `""` | **Dev-only** inline `API_SERVER_KEY`. |
| `apiServer.corsOrigins` | `""` | `API_SERVER_CORS_ORIGINS` (empty = most restrictive). |
| `env` | `{}` | Plain env as a name→value map. |
| `extraEnv` / `extraEnvFrom` | `[]` | Full `EnvVar` / `envFrom` entries (wire External Secrets here). |
| `secrets.create` | `false` | **Dev-only**: render a Secret from `secrets.data`. |
| `secrets.existingSecret` | `""` | **Prod**: reference a pre-existing Secret (`envFrom`). |
| `persistence.enabled` | `true` | Persist `/opt/data`. |
| `persistence.existingClaim` | `""` | Use an existing PVC. |
| `persistence.storageClass` | `""` | `""` = cluster default. |
| `persistence.accessModes` | `[ReadWriteOnce]` | |
| `persistence.size` | `10Gi` | |
| `persistence.mountPath` | `/opt/data` | Upstream data dir. |
| `persistence.retain` | `true` | Keep PVC on `helm uninstall`. |
| `shm.enabled` / `shm.size` | `false` / `1Gi` | Mount `/dev/shm` (needed for browser tools). |
| `service.enabled` | `true` | Create the gateway Service. |
| `service.type` | `ClusterIP` | Keep ClusterIP; don't expose via LoadBalancer. |
| `service.port` / `targetPort` | `8642` / `8642` | |
| `dashboard.enabled` | `false` | Enable the web dashboard (stores keys). |
| `dashboard.insecure` | `false` | Disable OAuth gate — **dangerous** (needs `insecureAcknowledgeRisk: true`). |
| `dashboard.port` | `9119` | |
| `dashboard.service` | `false` | Add 9119 to the Service (else port-forward). |
| `ingress.enabled` | `false` | **Off.** Exposing is dangerous (auth + TLS required). |
| `ingress.className` / `hosts` / `tls` / `annotations` | `""` / `[]` / `[]` / `{}` | |
| `resources` | `req 250m/1Gi, lim 2Gi` | No CPU limit (avoid throttling). |
| `podSecurityContext` | hardened (UID 10000) | |
| `securityContext` | drop ALL, no-priv-esc | `readOnlyRootFilesystem: false` (s6). |
| `serviceAccount.create` | `true` | |
| `serviceAccount.automountServiceAccountToken` | `false` | Agent doesn't need the K8s API. |
| `networkPolicy.enabled` | `false` | Default-deny + `allowDNS` + your rules (needs enforcing CNI). |
| `networkPolicy.allowDNS` / `ingress` / `egress` | `true` / `[]` / `[]` | NP is L4-only (no hostnames). |
| `probes.{liveness,readiness,startup}` | enabled on `/health` | HTTP probes vs the gateway `/health` (port 8642, no auth). |
| `scratchPaths` / `scratchSizeLimit` | `[/run]` / `128Mi` | Always-mounted tmpfs scratch; `/run` is required for s6-overlay to boot. |
| `strategy.type` | `Recreate` | Forced with persistence. |
| `pdb.enabled` | `false` | Beware `minAvailable:1` at replicas=1 blocks drains. |
| `nodeSelector` / `tolerations` / `affinity` / `topologySpreadConstraints` | `{}` / `[]` / `{}` / `[]` | |
| `podAnnotations` / `podLabels` | `{}` | |
| `priorityClassName` | `""` | |
| `terminationGracePeriodSeconds` | `30` | |
| `extraVolumes` / `extraVolumeMounts` / `extraObjects` | `[]` | Escape hatches. |

## Security & risks

- Never scale up or share `/opt/data` across pods.
- `secrets.create` / `apiServer.key` write secrets into the release — dev only.
- Ingress / dashboard are dangerous; keep off or front with auth + TLS.
- The PVC holds irreplaceable memory/skills/keys — **back it up** ([backup-restore](../../docs/backup-restore.md)).

See [docs/security.md](../../docs/security.md) and the
[production checklist](../../docs/production-checklist.md).

## Compatibility

| Chart | App (image) | Min K8s | Helm |
|---|---|---|---|
| `0.1.5` | `nousresearch/hermes-agent` (`appVersion: v2026.6.19`*) | `>= 1.25` | `>= 3.8` |

\* Pinned to an upstream CalVer release, with the matching `image.digest` pinned by default. See [docs/upgrade.md](../../docs/upgrade.md).

## Uninstall

```bash
helm uninstall my-hermes
# The PVC is retained by default (helm.sh/resource-policy: keep). To delete data:
kubectl delete pvc my-hermes-hermes-agent
```
