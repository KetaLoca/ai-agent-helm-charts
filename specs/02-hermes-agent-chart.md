# 02 — `hermes-agent` Chart Specification

> Implementation-ready contract for the `hermes-agent` chart. Implementers should not need other context beyond `00`, `01`, `04`.

## 1. Purpose & shape

Deploy a **single Hermes Agent instance** (`nousresearch/hermes-agent`, `gateway run`) on Kubernetes as a `Deployment`, with optional persistence at `/opt/data`, a `ClusterIP` Service on `8642`, and **everything internet-facing off by default**. Multi-tenant = multiple releases, never multiple replicas (see `00` §6.5).

`Chart.yaml`:
```yaml
apiVersion: v2
name: hermes-agent
description: Unofficial community Helm chart for the Hermes Agent (Nous Research). Not affiliated with Nous Research.
type: application
version: 0.1.0            # chart SemVer
appVersion: ""           # TODO(impl): pin a verified-good upstream tag, e.g. "2026.x.y"
kubeVersion: ">=1.25.0-0"
home: https://github.com/KetaLoca/ai-agent-helm-charts
sources:
  - https://github.com/NousResearch/hermes-agent
keywords: [ai, agent, hermes, llm]
annotations:
  artifacthub.io/license: MIT
  # ...see 01 §8
```

## 2. Resources rendered

| Template | Condition | Notes |
|---|---|---|
| `deployment.yaml` | always | `replicas: {{ .Values.replicaCount }}`; strategy `Recreate` when `persistence.enabled` (see §5). |
| `service.yaml` | always (toggle `service.enabled`, default true) | ClusterIP, port 8642. |
| `serviceaccount.yaml` | `serviceAccount.create` | name from helper. |
| `pvc.yaml` | `persistence.enabled && not persistence.existingClaim` | RWO; honors `retain` via `helm.sh/resource-policy: keep`. |
| `secret.yaml` | `secrets.create` | **dev only**; holds `secrets.data`. |
| `configmap.yaml` | `config.enabled` (optional) | non-secret config / files. |
| `ingress.yaml` | `ingress.enabled` (default false) | with mandatory caveats; see §10. |
| `networkpolicy.yaml` | `networkPolicy.enabled` (default false) | default-deny + user rules. |
| `pdb.yaml` | `pdb.enabled` (default false) | `policy/v1`; only sensible with replicas=1 + Recreate caveat (§13). |
| `tests/test-connection.yaml` | always (for `helm test`) | wget/nc to Service:8642 health path. |
| `NOTES.txt` | always | disclaimer + safe-access guidance. |
| `_helpers.tpl` | always | naming/labels/sa-name/image ref. |

## 3. Container & command

- Image ref (helper `hermes-agent.image`): if `image.digest` set → `repository@digest` (preferred for prod immutability); else `repository:tag`; else `repository:.Chart.AppVersion`. **If `digest`, `tag`, AND `AppVersion` are all empty → `{{ fail }}` with a clear message.** Never silently resolve to `:latest`.
  > **Reality check (verified 2026-06-02):** upstream currently publishes `nousresearch/hermes-agent:latest` and no confirmed semver tag was found. Until a stable tag exists, production guidance is to **pin `image.digest`** (resolve the current `latest` digest); `Chart.yaml appVersion` documents the digest's human version. See `08` Q10.
- **Command/args:** default `command: []`, `args: ["gateway","run"]`.
  > **TODO(verify@impl):** if the upstream image `CMD` already defaults to `gateway run`, set `args: []` and document. Keep the explicit default until verified, to avoid a no-op container.
- Container port: `containerPort: {{ .Values.service.targetPort }}` (8642), name `gateway`.
- Optional second port `dashboard` (9119) only when `dashboard.enabled`.

## 4. Networking model (critical design point)

Hermes binds `API_SERVER_HOST=127.0.0.1` by default — reachable only **inside the container**. A Kubernetes `ClusterIP` Service forwards to the **pod IP**, so with the upstream default the Service would never connect.

**Decision:** when `service.enabled` (default), the chart sets `API_SERVER_HOST=0.0.0.0` **and `API_SERVER_ENABLED=true`** so the gateway is reachable on the pod network, **and the schema requires an auth key** (`secrets`/`existingSecret` providing `API_SERVER_KEY`, or `apiServer.key`). Binding `0.0.0.0` inside a pod is **cluster-internal**, not "the internet" — exposure beyond the cluster still requires Ingress (off) and is gated by NetworkPolicy (recommended). This keeps "secure by default" while making the Service actually work.

- `apiServer.key` may be set inline **for dev only**; production supplies it via `existingSecret` (see §7). NOTES and schema enforce that *some* key source exists whenever `service.enabled && apiServer.requireKey` (default true).
- `apiServer.requireKey: true` default. Setting it false (e.g. NetworkPolicy-only isolation) requires an explicit opt-out and prints a warning in NOTES.
- CORS (`API_SERVER_CORS_ORIGINS`) defaults unset (most restrictive); configurable via `apiServer.corsOrigins`.

## 5. Deployment strategy, replicas, persistence interplay

- `replicaCount` default **1**. **Schema invariant:** if `persistence.enabled == true` **and** `persistence.existingClaim` is RWO/empty, `replicaCount` **must be 1** (validated; see §12). Rationale: single-writer data dir (`00` §7) — two pods corrupt `sessions/`/`memories/`.
- `strategy.type` default **`Recreate`** whenever `persistence.enabled`; `RollingUpdate` only allowed (and only meaningful) when persistence is off or an external shared store is used. Recreate prevents old+new pods writing the same RWO PVC during rollout.
- Persistence default **`enabled: true`** (losing memory/keys/skills is the worse failure). PVC: `ReadWriteOnce`, `size: 10Gi`, `mountPath: /opt/data`, optional `storageClass`, optional `existingClaim`.
- `persistence.retain: true` (default) → PVC carries `helm.sh/resource-policy: keep` so `helm uninstall` does **not** delete state. Documented in NOTES + `backup-restore.md`.

## 6. Security context (see `04` for the model)

Defaults (image runs as `hermes` UID 10000, non-root):

```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 10000
  runAsGroup: 10000
  fsGroup: 10000           # so the PVC mount is writable by UID 10000
  fsGroupChangePolicy: OnRootMismatch
  seccompProfile:
    type: RuntimeDefault

securityContext:           # container-level
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: false   # see note
  capabilities:
    drop: [ALL]
  # runAsNonRoot inherited from pod-level
```

- **`readOnlyRootFilesystem: false` by default.** s6-overlay (PID 1) writes to `/run` (and `/var/run`, scratch). **TODO(verify@impl):** confirm whether `readOnlyRootFilesystem: true` works when `emptyDir` volumes are mounted at `/run` and `/tmp`; if so, offer a `securityContext.readOnlyRootFilesystem: true` opt-in with auto-mounted scratch emptyDirs. Document as advanced/experimental until verified.
- `fsGroup: 10000` is required for the PVC to be writable; if a user remaps via `HERMES_UID`/`HERMES_GID`, `podSecurityContext` and those env vars must agree (documented; schema can't easily cross-check).
- All security values are **overridable** (e.g. set `runAsUser` to match a remapped UID, or relax for debugging) — but defaults are hardened.

## 7. Secrets & environment

Layered, with production pushing secrets out of Git:

```yaml
# Plain (non-secret) env, rendered as name/value:
env: {}                 # map form, e.g. { API_SERVER_CORS_ORIGINS: "https://app.example" }
extraEnv: []            # list form (full EnvVar, incl. valueFrom)
extraEnvFrom: []        # list of envFrom sources (configMapRef/secretRef)

secrets:
  create: false         # DEV ONLY — render a Secret from `data`
  name: ""              # name of the chart-managed secret (defaults to fullname)
  existingSecret: ""    # PROD — reference a pre-existing Secret (envFrom)
  data: {}              # { API_SERVER_KEY: "...", ANTHROPIC_API_KEY: "..." } (dev)

apiServer:
  key: ""               # DEV convenience; prefer existingSecret/extraEnvFrom
  requireKey: true
  corsOrigins: ""
```

**Wiring rules:**
- If `secrets.existingSecret` set → add it to `envFrom` (`secretRef`).
- If `secrets.create` → render `secret.yaml` from `secrets.data`, add via `envFrom`. NOTES warns this stores secrets in the release/values.
- `apiServer.key` (dev) → injected as `API_SERVER_KEY` env (after warning).
- `extraEnvFrom` lets users wire External Secrets / Sealed Secrets output (`docs/external-secrets.md`).
- **Schema:** when `service.enabled && apiServer.requireKey`, at least one key source must be configured (`existingSecret` || `secrets.create+data.API_SERVER_KEY` || `apiServer.key` || an `extraEnvFrom`). If none and not provable, NOTES prints a hard warning (schema can verify the first three; `extraEnvFrom` is the documented escape).
- **Never** put real API keys in `values.yaml` for production — stated in README, NOTES, `04`, `external-secrets.md`.

## 8. Persistence & scratch volumes

- Main: PVC (or `existingClaim`) mounted at `persistence.mountPath` (`/opt/data`).
- **`/dev/shm`:** optional `shm.enabled` (default false) → `emptyDir{medium: Memory, sizeLimit: shm.size (default 1Gi)}` mounted at `/dev/shm`. **Required** if Hermes browser/Playwright tools are used (`00` §7). Document: enable for browser tools.
- Scratch for read-only-rootfs (future): `emptyDir` at `/run`, `/tmp` (only when that opt-in lands).
- `extraVolumes` / `extraVolumeMounts` escape hatches.

## 9. Probes

Defaults **off** until the health path is verified:

```yaml
probes:
  liveness:  { enabled: false }
  readiness: { enabled: false }
  startup:   { enabled: false }
```

- **TODO(verify@impl):** confirm the gateway health endpoint (docs mention "Health endpoint at gateway API server"; likely `GET /health` or `/v1/models` on 8642 — verify, and whether it requires the auth key). Once verified, ship documented, ready-to-enable probe blocks (httpGet on 8642) and consider defaulting `readiness` on.
- Each probe is fully configurable (type httpGet/tcpSocket/exec, path, port, delays, thresholds). Provide a `tcpSocket:8642` fallback example that needs no auth.

## 10. Ingress (default OFF)

```yaml
ingress:
  enabled: false
  className: ""
  annotations: {}
  hosts: []          # [{host, paths:[{path, pathType}]}]
  tls: []            # [{secretName, hosts:[]}]
```

- When enabled, NOTES + README **must** warn: exposing the gateway/dashboard publicly is dangerous; require auth in front (`API_SERVER_KEY`, and an identity-aware proxy / basic-auth annotation). `docs/security.md` recommends Cloudflare Access / Authelia / Tailscale instead of raw Ingress.
- Targets the **gateway** Service by default; dashboard Ingress is a separate, even-more-discouraged opt-in.
- Schema: if `ingress.enabled`, `hosts` must be non-empty.

## 11. Dashboard (default OFF)

```yaml
dashboard:
  enabled: false      # sets HERMES_DASHBOARD=1, adds container port 9119
  insecure: false     # HERMES_DASHBOARD_INSECURE — DANGEROUS, schema-discouraged
  insecureAcknowledgeRisk: false
  port: 9119
  service: false      # expose 9119 on the Service too? Default false → use port-forward
```

- The dashboard stores/exposes API keys & sessions (`00` §7). Default off. `insecure: true` (disables OAuth) prints a loud NOTES warning and should be blocked behind an explicit acknowledgement value (e.g. `dashboard.insecureAcknowledgeRisk: true` required, else schema/NOTES error). Recommended only on trusted networks behind a VPN.
- Exposure: enabling the dashboard adds `containerPort: 9119`; the **Service** forwards 9119 only when `dashboard.service: true` (default false → reach it via `kubectl port-forward`, never Ingress).

## 12. ServiceAccount, scheduling, misc

```yaml
serviceAccount:
  create: true
  name: ""
  annotations: {}
  automountServiceAccountToken: false   # agent doesn't need API access by default (04)

nodeSelector: {}
tolerations: []
affinity: {}
topologySpreadConstraints: []   # for future multi-replica/stateless modes; no-op at replicas=1
podAnnotations: {}
podLabels: {}
priorityClassName: ""
terminationGracePeriodSeconds: 30
```

- `automountServiceAccountToken: false` by default — the agent has no reason to talk to the K8s API; mounting a token is an unnecessary privilege (`04`).

## 13. PodDisruptionBudget

```yaml
pdb:
  enabled: false
  minAvailable: ""      # or maxUnavailable
```

- With `replicaCount: 1` + `Recreate`, a PDB of `minAvailable: 1` **blocks voluntary evictions/drains entirely** (can wedge node maintenance). Document this sharp edge; default off. Only meaningful if a future RWX/stateless mode allows >1 replica.

## 14. NetworkPolicy

```yaml
networkPolicy:
  enabled: false
  # When enabled, default-deny ingress+egress, then allow:
  allowDNS: true                 # egress to kube-dns
  ingress: []                    # extra NetworkPolicyIngressRule entries
  egress: []                     # extra NetworkPolicyEgressRule entries (e.g. LLM API egress)
```

- Default off (not all clusters have a CNI that enforces NP; enabling silently does nothing or, worse, surprises users). When on: deny-all baseline + `allowDNS` + user-supplied ingress (e.g. from an ingress-controller namespace) and egress (e.g. to `api.anthropic.com:443`). `docs/network-policies.md` gives ready examples. See `04`.

## 15. Full default `values.yaml` (target)

```yaml
# -- Number of Hermes instances. MUST stay 1 when persistence.enabled (single-writer state).
replicaCount: 1

image:
  repository: nousresearch/hermes-agent
  # -- Image tag. Empty falls back to .Chart.AppVersion. Avoid "latest" in production.
  tag: ""
  # -- Pin by digest for immutability (takes precedence over tag).
  digest: ""
  pullPolicy: IfNotPresent
imagePullSecrets: []

# -- Override the entrypoint/args. Image runs `gateway run` via s6 (/init).
command: []
args: ["gateway", "run"]   # TODO(impl): set [] if image CMD already defaults to this

# Gateway API server
apiServer:
  # -- Require an API key whenever the Service is enabled. Strongly recommended.
  requireKey: true
  # -- DEV ONLY inline key. Prefer secrets.existingSecret / extraEnvFrom in production.
  key: ""
  # -- API_SERVER_CORS_ORIGINS. Empty = most restrictive.
  corsOrigins: ""

# Plain environment (non-secret)
env: {}
extraEnv: []
extraEnvFrom: []

secrets:
  create: false
  name: ""
  existingSecret: ""
  data: {}

config:
  # ConfigMap file injection. NOTE: a ConfigMap volume mounted AT /opt/data would COLLIDE with
  # the PVC mounted there (can't mount both at one path; the CM would shadow the dir). So when
  # enabled, files are injected via `subPath` into individual paths under /opt/data (no live
  # updates) — advanced/fragile. Hermes manages config.yaml/SOUL.md inside /opt/data itself.
  enabled: false        # DEFER: keep off in v0.x unless subPath injection is proven at impl
  files: {}             # { "SOUL.md": "..." } -> mounted at /opt/data/SOUL.md via subPath

persistence:
  enabled: true
  existingClaim: ""
  storageClass: ""
  accessModes: [ReadWriteOnce]
  size: 10Gi
  mountPath: /opt/data
  # -- Keep the PVC on `helm uninstall` (adds helm.sh/resource-policy: keep).
  retain: true

shm:
  enabled: false        # mount /dev/shm emptyDir (Memory). Enable for browser/Playwright tools.
  size: 1Gi

service:
  enabled: true
  type: ClusterIP
  port: 8642
  targetPort: 8642
  annotations: {}

dashboard:
  enabled: false
  insecure: false
  insecureAcknowledgeRisk: false
  port: 9119
  service: false

ingress:
  enabled: false
  className: ""
  annotations: {}
  hosts: []
  tls: []

resources:
  # Sensible default floor (browser tools need ≥2Gi). Tune per workload.
  requests: { cpu: "250m", memory: "1Gi" }
  limits:   { memory: "2Gi" }     # CPU limit intentionally unset (avoid throttling); document.

podSecurityContext:
  runAsNonRoot: true
  runAsUser: 10000
  runAsGroup: 10000
  fsGroup: 10000
  fsGroupChangePolicy: OnRootMismatch
  seccompProfile: { type: RuntimeDefault }

securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: false
  capabilities:
    drop: [ALL]

serviceAccount:
  create: true
  name: ""
  annotations: {}
  automountServiceAccountToken: false

networkPolicy:
  enabled: false
  allowDNS: true
  ingress: []
  egress: []

probes:
  liveness:  { enabled: false }
  readiness: { enabled: false }
  startup:   { enabled: false }

strategy:
  # -- Recreate is forced when persistence.enabled (single-writer). RollingUpdate otherwise.
  type: Recreate

pdb:
  enabled: false
  minAvailable: ""
  maxUnavailable: ""

nodeSelector: {}
tolerations: []
affinity: {}
topologySpreadConstraints: []
podAnnotations: {}
podLabels: {}
priorityClassName: ""
terminationGracePeriodSeconds: 30

nameOverride: ""
fullnameOverride: ""
extraVolumes: []
extraVolumeMounts: []
extraObjects: []        # raw extra manifests (advanced escape hatch)
```

> Deviations from the original sketch (justified): `apiServer.*` (networking correctness, §4), `dashboard.*` (real upstream feature with a sharp security edge, §11), `shm.*` (browser tools, §8), `config.*`, `strategy.type` surfaced, `topologySpreadConstraints`, `automountServiceAccountToken: false`, non-empty default `resources`, `extraVolumes/Mounts`, `extraObjects`. The sketch's `env: {}` (map) and `extraEnv: []`/`extraEnvFrom: []` (lists) are kept as-is. Probes kept off by default per §9.

## 16. `values.schema.json` invariants (must enforce / validate)

1. `replicaCount` integer ≥ 1.
2. **`persistence.enabled == true` ⇒ `replicaCount == 1`** (the core safety rule). This **is** expressible in JSON Schema draft-07 (Helm supports `if/then`): `if persistence.enabled const true → then replicaCount const 1`. Implement it in the schema **and** add a belt-and-suspenders `{{- if and .Values.persistence.enabled (gt (int .Values.replicaCount) 1) }}{{ fail ... }}` template guard (covers the RWX / `persistence.allowSharedWriters` edge cases the simple schema rule can't express).
3. `image.repository` required, non-empty string. `tag`/`digest` strings. Template `fail`s when `tag`, `digest`, and `.Chart.AppVersion` are **all** empty (no silent `:latest`).
4. `service.port`, `service.targetPort`, `dashboard.port` integers 1–65535.
5. `persistence.size` matches a quantity regex; `accessModes` enum subset of `[ReadWriteOnce, ReadWriteOncePod, ReadWriteMany]` (warn that RWM defeats single-writer; still require replicaCount==1 unless an explicit `persistence.allowSharedWriters` ack).
6. `apiServer.requireKey` boolean; if true + `service.enabled`, a key source must exist (validate the in-schema cases; document `extraEnvFrom` escape).
7. `ingress.enabled ⇒ ingress.hosts` non-empty.
8. `dashboard.insecure == true ⇒ dashboard.insecureAcknowledgeRisk == true` (else fail).
9. `strategy.type` enum `[Recreate, RollingUpdate]`; warn/forbid `RollingUpdate` when `persistence.enabled` with RWO.
10. Enumerations for `pullPolicy`, `service.type`.
11. `resources`, `nodeSelector`, `affinity`, `tolerations`, `securityContext`, `podSecurityContext` typed as objects/arrays (free-form but type-checked).

## 17. Risks & warnings (surface in README/NOTES)

- **Single-writer state.** Never scale up; never share `/opt/data` across pods. Rollouts use `Recreate` (brief downtime).
- **Secret exposure.** `secrets.create` / `apiServer.key` put secrets in the release; prod must use external secrets.
- **Public exposure.** Ingress/dashboard are dangerous; default off; auth required.
- **`latest` drift.** Upstream currently ships only `:latest` (no confirmed semver tag). The template refuses an all-empty image ref; **pin by `image.digest`** for prod. Never recommend `:latest`.
- **`readOnlyRootFilesystem`** likely incompatible with s6 unless scratch emptyDirs mounted — keep off until verified.
- **Resource starvation.** Browser tools need ≥2Gi + `/dev/shm`; document.
- **Backups.** PVC holds irreplaceable memory/skills; `retain: true` + Velero/restic guidance (`backup-restore.md`).
- **K8s API token** not mounted by default; if a skill needs cluster access, that's an explicit, audited change.

## 18. `helm test`

`tests/test-connection.yaml`: a short-lived pod that `wget`/`nc` the Service on 8642 (TCP connect, or the verified health path with the API key from the secret). Annotated `helm.sh/hook: test`. Must not require internet/LLM access.
