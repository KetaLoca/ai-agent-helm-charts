# 03 — `openclaw-instance` Chart Specification

> Implementation-ready contract for the `openclaw-instance` chart. Reads with `00`, `01`, `04`.

## 1. Purpose & shape

This chart **declares an `OpenClawInstance` custom resource** (`openclaw.rocks/v1alpha1`) and lets users configure it through a friendly, validated values surface. It **does not** deploy OpenClaw pods directly — the **OpenClaw Operator** reconciles the CR into a StatefulSet/Service/PVC/NetworkPolicy/PDB/RBAC/etc. (`00` §7).

Goal: make it **easy and safe to declare per-tenant/per-project OpenClaw instances** (one release per instance), with secure defaults and full forward-compatibility with the evolving CRD.

```yaml
# Chart.yaml
apiVersion: v2
name: openclaw-instance
description: Unofficial community Helm chart that declares an OpenClawInstance CR for the OpenClaw Kubernetes Operator. Not affiliated with OpenClaw / openclaw.rocks / Paperclip Inc.
type: application
version: 0.1.0
appVersion: ""          # TODO(impl): the OpenClaw APP version this maps cleanly to, e.g. "2026.2.3"
kubeVersion: ">=1.28.0-0"   # operator requires >=1.28
home: https://github.com/KetaLoca/ai-agent-helm-charts
sources:
  - https://github.com/paperclipinc/openclaw-operator   # TODO(impl): confirm canonical org
keywords: [ai, agent, openclaw, operator, crd]
annotations:
  artifacthub.io/license: MIT
  artifacthub.io/operator: "false"   # this chart is NOT the operator; it produces a CR for it
```

## 2. Hard assumption: the operator is already installed

By default the chart **requires** the OpenClaw Operator + its CRDs to be present and does **not** install them (opt-in `operator.install=true` bundles them — see §13). Consequences (default mode):

- `helm template` always works (a CR is just YAML).
- `helm install` **fails** if the CRD is absent (`no matches for kind "OpenClawInstance"`). This is acceptable and documented.
- We provide a **preflight gate** and clear docs, not automation:
  - `operator.required: true` (default). When true, render a Helm **NOTES** check and optionally a `lookup`-based warning (guarded so it never blocks `helm template`) that the CRD exists.
  - **Decision:** do **not** use a hard `.Capabilities`/`lookup` failure in templates (breaks GitOps diff and `helm template`). Instead document the prerequisite, print a NOTES preflight, and let `helm install` surface the missing-CRD error naturally. Optionally offer `crds.checkJob: false` (an opt-in preflight Job) for non-GitOps users.

### Documenting operator install (not bundling)

`examples/openclaw/operator-notes.md` and `docs/` describe:
```bash
helm install openclaw-operator \
  oci://ghcr.io/paperclipinc/charts/openclaw-operator \
  --namespace openclaw-system --create-namespace \
  --set leaderElection.enabled=true
# Prereqs: Kubernetes >= 1.28; cert-manager only if enabling the webhook;
#          Prometheus Operator only if enabling ServiceMonitor.
# TODO(verify@impl): confirm canonical OCI path/version (paperclipinc vs openclaw-rocks).
```
A compatibility table (chart version ↔ operator/CRD version ↔ app version) lives in the chart README (`07`).

## 3. CRD schema of record (verified 2026-06-02)

`OpenClawInstance` `spec` **top-level fields** (verified against the operator `api/v1alpha1` reference + full sample). The chart maps a curated subset to friendly values and passes the rest through `extraSpec`.

| `spec` field | Type | Chart treatment |
|---|---|---|
| `registry` | string | optional value `registry` |
| `image` | `{repository, tag, digest, pullPolicy, pullSecrets}` | friendly `image.*` |
| `config` | `{configMapRef, raw, mergeMode, format}` | friendly `config.*` (raw passthrough) |
| `workspace` | `{configMapRef, initialFiles, initialDirectories, additionalWorkspaces, bootstrap}` | `extraSpec` (advanced) |
| `skills` | `[]string` | value `skills` |
| `plugins` | `[]string` | value `plugins` |
| `envFrom` | `[]EnvFromSource` | friendly `envFrom` |
| `env` | `[]EnvVar` | friendly `env` |
| `resources` | core ResourceRequirements | friendly `resources` |
| `security` | `{podSecurityContext, containerSecurityContext, networkPolicy{enabled,allowedIngressNamespaces,allowedIngressCIDRs,allowDNS}, rbac{createServiceAccount}, caBundle}` | friendly `security.*` |
| `shareProcessNamespace` | bool (default true) | `extraSpec` / advanced value |
| `storage` | `{persistence{enabled,storageClass,size,accessModes,existingClaim,orphan}}` | friendly `persistence.*` → `storage.persistence` |
| `chromium` | `{enabled,image,resources,persistence}` | friendly `chromium.*` (default disabled) |
| `tailscale` | `TailscaleSpec` | friendly `tailscale.*` |
| `ollama` | `OllamaSpec` | `extraSpec` / advanced value `ollama` |
| `webTerminal` | `WebTerminalSpec` | value `webTerminal` (default disabled) |
| `initContainers`/`sidecars`/`sidecarVolumes`/`extraVolumes`/`extraVolumeMounts` | core types | passthrough values |
| `networking` | `{service{type,annotations}, ingress{enabled,className,annotations,hosts,tls,security{forceHTTPS,enableHSTS,rateLimiting}}}` | friendly `networking.*` (ingress default disabled) |
| `probes` | `{liveness,readiness,startup}` | friendly `probes.*` |
| `observability` | `{metrics{enabled,port,serviceMonitor{enabled,interval,labels}}, logging{level,format}}` | friendly `observability.*` |
| `availability` | `{podDisruptionBudget, autoScaling, nodeSelector, tolerations, affinity, topologySpreadConstraints, runtimeClassName}` | friendly `availability.*` |
| `suspended` | bool (default false) | value `suspended` |
| `backup` | `BackupSpec` | `extraSpec` (TODO model later) |
| `restoreFrom` | string | value `restoreFrom` |
| `runtimeDeps` | `RuntimeDepsSpec` | `extraSpec` |
| `gateway` | `GatewaySpec` | `extraSpec` (TODO model later) |
| `autoUpdate` | `AutoUpdateSpec` | value `autoUpdate` (**default disabled** — security) |
| `selfConfigure` | `SelfConfigureSpec` | value `selfConfigure` (**default disabled** — security) |
| `podAnnotations` | object | value `podAnnotations` |

> **TODO(verify@impl):** pin the exact CRD version the chart targets, re-dump `api/v1alpha1` field schemas, and confirm sub-field names for `tailscale`, `ollama`, `gateway`, `autoUpdate`, `selfConfigure`, `backup`, `webTerminal`. Vendor the CRD's OpenAPI schema into `charts/openclaw-instance/crd-schema/` for CI validation (`06`). Do **not** invent sub-fields beyond what's verified — route the unknown through `extraSpec`.

## 4. The `extraSpec` escape hatch (core design)

`extraSpec` is an **arbitrary object deep-merged into `spec`** after the chart's modeled fields. This is the chart's forward-compatibility guarantee against CRD churn.

- Implementation: build the modeled `spec` map, then `merge`/`mergeOverwrite` with `.Values.extraSpec`, then `toYaml`. **Decision:** use `mergeOverwrite` so `extraSpec` wins on conflict (lets users override anything the chart models), and document that precedence clearly.
- Anything not yet modeled (`gateway`, `backup`, new vNext fields) is set via `extraSpec` without a chart release.
- `extraSpec` is typed as a free-form object in the schema (no inner validation) — the operator's own validating webhook is the source of truth.

## 5. Secure defaults (deviating from the upstream sample)

The verified sample is a *production* example with several things ON. The chart's **defaults are conservative**:

| Concern | Upstream sample | Chart default | Why |
|---|---|---|---|
| `networking.ingress.enabled` | true | **false** | No public exposure by default (`00` §6.2). |
| `security.networkPolicy.enabled` | true | **true** (keep on) | Operator default-deny is good; keep it. |
| `chromium.enabled` | true | **false** | Headless browser = egress + attack surface; opt-in. |
| `selfConfigure` / `autoUpdate` | (varies) | **disabled** | Agent self-modification / auto image bumps are security-sensitive; explicit opt-in (`04`). |
| `webTerminal` | (varies) | **disabled** | Interactive shell into the agent pod; opt-in only. |
| `observability.metrics.serviceMonitor.enabled` | true | **false** | Requires Prometheus Operator; off unless present. |
| `image.tag` | pinned | **must be set / pinned** | No `latest`; require explicit pin or inherit appVersion. |
| `security.containerSecurityContext.readOnlyRootFilesystem` | false | leave to operator default, expose override | Verify app compatibility before forcing. |

Hardened security context defaults (`runAsNonRoot`, drop ALL, `allowPrivilegeEscalation: false`, seccomp RuntimeDefault) are passed through `security.*` mirroring `04`, unless the operator already enforces them (then we avoid fighting the operator — see §8).

## 6. Resources rendered by THIS chart

| Template | Condition | Notes |
|---|---|---|
| `openclawinstance.yaml` | always | the CR; `metadata.name` = `instance.name` || release fullname. |
| `secret.yaml` | `secrets.create` (DEV only) | API keys; referenced by the CR via `envFrom`. |
| `configmap.yaml` | `config.fromFiles` set (optional) | non-secret config/workspace files, referenced via `config.configMapRef`/`workspace.configMapRef`. |
| `networkpolicy-extra.yaml` | `extraNetworkPolicy.enabled` | **additional** NP beyond the operator's (e.g. tighter egress allow-list). Clearly labeled as supplementary. |
| `NOTES.txt` | always | disclaimer, operator-prereq preflight, how to check instance status. |
| `_helpers.tpl` | always | naming/labels. |

> The chart must **not** render Deployment/StatefulSet/Service/PVC/PDB/RBAC — those are the operator's outputs. `networkpolicy-extra.yaml` is the only K8s primitive we add, and only as a supplement.

## 7. Friendly `values.yaml` (target)

```yaml
instance:
  # -- Name of the OpenClawInstance (and downstream resources). Defaults to the release fullname.
  name: ""
  # -- Extra labels/annotations on the CR object itself.
  labels: {}
  annotations: {}

operator:
  # -- This chart REQUIRES the OpenClaw operator + CRDs to be installed already.
  required: true
  # -- Optional opt-in preflight Job that checks the CRD exists (non-GitOps convenience).
  preflightJob: false

registry: ""

image:
  repository: ghcr.io/openclaw/openclaw
  tag: ""               # REQUIRED in production (no latest). Empty inherits appVersion at render.
  digest: ""
  pullPolicy: IfNotPresent
  pullSecrets: []

# OpenClaw application config (maps to spec.config)
config:
  # -- Inline config object merged by the operator (spec.config.raw).
  raw: {}
  mergeMode: ""         # passthrough if set
  format: ""            # passthrough if set
  configMapRef: ""      # reference an existing ConfigMap instead of raw
  fromFiles: {}         # if set, chart renders a ConfigMap from these files and wires configMapRef

skills: []
plugins: []

env: []                 # []EnvVar
envFrom: []             # []EnvFromSource

secrets:
  create: false         # DEV ONLY — render a Secret and add it to envFrom
  existingSecret: ""    # PROD — reference a Secret (added to spec.envFrom as secretRef)
  data: {}

resources:
  requests: { cpu: "500m", memory: "1Gi" }
  limits:   { memory: "4Gi" }

persistence:            # → spec.storage.persistence
  enabled: true
  storageClass: ""
  size: 10Gi
  accessModes: [ReadWriteOnce]
  existingClaim: ""
  # -- Keep the PVC if the CR is deleted. Maps to spec.storage.persistence.orphan.
  # TODO(verify@impl): confirm orphan=true means RETAIN (not delete) before trusting this default.
  orphan: true

security:               # → spec.security
  podSecurityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    seccompProfile: { type: RuntimeDefault }
  containerSecurityContext:
    allowPrivilegeEscalation: false
    capabilities: { drop: [ALL] }
    # readOnlyRootFilesystem: omitted — leave operator default until app-verified
  networkPolicy:
    enabled: true
    allowDNS: true
    allowedIngressNamespaces: []
    allowedIngressCIDRs: []
  rbac:
    createServiceAccount: true
  caBundle: ""

chromium:
  enabled: false        # headless browser; egress/attack surface — opt-in
  # image/resources/persistence passthrough when enabled

tailscale:              # native CRD field — great for private access (04)
  enabled: false
  # authKey via existingSecret recommended; fields passthrough — TODO(verify@impl) exact schema

ollama: {}              # advanced passthrough (spec.ollama)

webTerminal:
  enabled: false        # interactive shell into the pod — opt-in only

networking:
  service:
    type: ClusterIP
    annotations: {}
  ingress:
    enabled: false
    className: ""
    annotations: {}
    hosts: []
    tls: []
    security:
      forceHTTPS: true
      enableHSTS: true
      rateLimiting: { enabled: false, requestsPerSecond: 50 }

probes: {}              # LEAVE UNSET by default: the operator knows the app's health endpoints
                        # and ships sane probe defaults (see §8 "avoid fighting the operator").
                        # Override only when needed, e.g.:
                        #   probes:
                        #     readiness: { enabled: true, initialDelaySeconds: 5, periodSeconds: 5 }

observability:
  metrics:
    enabled: true
    port: 9090
    serviceMonitor: { enabled: false, interval: 15s, labels: {} }
  logging: { level: info, format: json }

availability:
  podDisruptionBudget: { enabled: false, maxUnavailable: 1 }
  autoScaling: {}       # passthrough; document single-writer caveat (04)
  nodeSelector: {}
  tolerations: []
  affinity: {}
  topologySpreadConstraints: []
  runtimeClassName: ""

suspended: false
restoreFrom: ""
autoUpdate:   { enabled: false }   # security: explicit opt-in
selfConfigure: { enabled: false }  # security: explicit opt-in
podAnnotations: {}

# Supplementary (rendered by THIS chart, not the operator)
extraNetworkPolicy:
  enabled: false
  ingress: []
  egress: []

# Forward-compat: arbitrary object deep-merged into spec (mergeOverwrite — wins on conflict).
extraSpec: {}
```

> Deviations from the original sketch (justified by the real CRD): the sketch's flat `ingress`, `networkPolicy`, `resources`, `env`, `envFrom`, `persistence`, `extraSpec` are preserved but re-nested to match the CRD's real shape (`networking.ingress`, `security.networkPolicy`, `storage.persistence`). Added `security`, `chromium`, `tailscale`, `webTerminal`, `probes`, `observability`, `availability`, `autoUpdate`, `selfConfigure`, `suspended`, `restoreFrom`, `extraNetworkPolicy` because they exist in the CRD and matter for secure/production use. `instance.name` and `operator.required` kept.

## 8. Avoid fighting the operator

The operator applies its own **defaulting** (and may have a validating/mutating webhook). The chart should:
- Only set fields the user explicitly opts into; leave others **unset** so the operator's defaults apply (don't emit empty objects that override good defaults — prune empties before `toYaml`).
- Prefer the operator's `security`/`networkPolicy` defaults; our hardened values are a *floor*, not a fight. Where the webhook would reject/override a value, document it.
- Never assume the operator's downstream resource names; reference the instance by `instance.name` and surface status via NOTES (`kubectl get openclawinstance`).

## 9. CRD version-skew strategy

- Pin a target CRD version in the chart README compatibility table and vendor its OpenAPI schema for CI.
- Unknown/newer fields → `extraSpec` (no chart release needed).
- Removed/renamed upstream fields → MAJOR chart bump + `upgrade.md` migration note; keep the old value mapping for one minor with a deprecation warning in NOTES where feasible.
- CI renders the CR and (when the vendored CRD schema is present) validates it with `kubeconform -schema-location <vendored>`. See `06`.

## 10. `values.schema.json` invariants

1. `image.repository` non-empty; `tag`/`digest` strings; warn if both empty (no pin).
2. `persistence.size` quantity regex; `accessModes` enum subset.
3. `networking.ingress.enabled ⇒ networking.ingress.hosts` non-empty.
4. `secrets.create` and `secrets.existingSecret` are mutually-exclusive-ish (if both set, `existingSecret` wins; warn).
5. `chromium.enabled`, `webTerminal.enabled`, `autoUpdate.enabled`, `selfConfigure.enabled` booleans; default false (security).
6. `observability.serviceMonitor.enabled ⇒ requires Prometheus Operator` (doc note; can't validate cluster).
7. `extraSpec` typed `object` (free-form).
8. `availability.autoScaling`: if it would scale replicas >1, print the single-writer caveat in NOTES (operator may already guard via StatefulSet semantics — verify).
9. Enumerations for `pullPolicy`, `service.type`, `logging.level`, `logging.format`.

## 11. Risks & warnings (README/NOTES)

- **Missing operator/CRD** → `helm install` fails by design; NOTES preflight explains.
- **CRD churn** → use `extraSpec`; pin a target version; watch the compatibility table.
- **`selfConfigure`/`autoUpdate`** = agent can change its own config / pull new images → supply-chain & behavior risk; off by default (`04`).
- **`chromium`/`webTerminal`** = extra attack surface/egress; off by default.
- **Ingress** off by default; prefer `tailscale` (native) or an identity-aware proxy.
- **Ingress + default-deny NetworkPolicy interaction:** with `security.networkPolicy.enabled: true` (default) **and** `networking.ingress.enabled: true`, you **must** add the ingress controller's namespace to `security.networkPolicy.allowedIngressNamespaces` (and/or its pod CIDR), or default-deny will block the controller from reaching the pod. Surfaced in NOTES + `network-policies.md`.
- **State** is single-writer (operator uses a StatefulSet/RWO PVC); don't force RWX/HPA without understanding it.
- **Secrets** never in Git for prod; `existingSecret` / External Secrets.
- **`orphan`/`retain`** controls whether the PVC survives CR deletion — verify the exact field name + default (`storage.persistence.orphan`) at impl.

## 12. `helm test`

Light `helm test`: assert the `OpenClawInstance` object exists and reached a `Ready`/`Reconciled` condition (`kubectl wait --for=condition=Ready openclawinstance/<name>`), gated so it only runs when the operator is present. Do not depend on pulling the OpenClaw image in CI (`06`).

## 13. All-in-one / bundled operator (opt-in) — added 0.2.x

Goal: honor the maintainer's intent that the chart be installable with a single `helm install`,
**no manual cluster prep**, for single-tenant/homelab/demo use — without sacrificing the
default multi-tenant CR-emitter posture.

**Shape.** A new value `operator.install` (**default `false`**). When `true`, the chart pulls the
**official operator chart** as a conditional dependency and installs the operator + its CRDs
alongside this `OpenClawInstance`:

```yaml
# Chart.yaml
dependencies:
  - name: openclaw-operator
    version: "0.36.5"                          # pinned; Renovate tracks it
    repository: "oci://ghcr.io/paperclipinc/charts"
    condition: operator.install                # not rendered when false
```

When `false`, the dependency is **not rendered** and behavior is exactly the pre-0.2 CR emitter.
Operator settings are overridable under the `openclaw-operator:` values key (e.g.
`openclaw-operator.watchNamespaces`, `.crds.install`). CI/release resolve the dependency with a
`helm dependency update` step; the chart's `.helmignore` must **not** exclude `charts/*.tgz`
(only `/*.tgz` at root) so the subchart is packaged.

**Why a post-install hook for the CR (critical).** Helm validates the whole main manifest against
the live API **before** applying it. With the operator's CRDs delivered as subchart *templates*
(`templates/crds/`, not the special `crds/` dir), the `OpenClawInstance` kind does not exist yet at
that point, so a plain co-install fails with `no matches for kind "OpenClawInstance"` (this shipped
broken in `0.2.0`). Fix (`0.2.1`): when `operator.install=true`, render the CR with
`helm.sh/hook: post-install,post-upgrade` (+ `hook-weight`) so it is applied **after** the main
phase (operator + CRDs) — Helm v3.16/v4 refresh discovery between phases, so the CR maps cleanly.
Verified end-to-end on `personal-k3s` (2026-06-25): fresh single `helm install --set operator.install=true`
→ operator `1/1`, CR `Running`/`Ready`, operator reconciled StatefulSet + Service (18789/18793/9090) +
bound 10Gi PVC + default-deny NetworkPolicy. The operator's **admission webhook is off by default**
(`webhook.enabled: false`), so co-installing the CR is safe (no webhook-not-ready failure).

**Single-tenant / once-per-cluster.** The operator is a cluster-wide singleton (ClusterRole +
leader election) that owns cluster-scoped CRDs. `operator.install=true` is therefore for **one**
install per cluster; for multiple instances, install the operator once and keep `operator.install=false`
on the rest.

**CRD-schema alignment (found via real-cluster validation).** The operator `0.36.x` CRD **curates**
`spec.security.podSecurityContext` and rejects `seccompProfile` (the operator applies seccomp itself);
the chart's default sent it, so even the default CR-emitter mode produced a CR the operator rejected.
Removed in `0.2.1`. Lesson: validate the rendered CR against the **live** CRD
(`kubectl apply --dry-run=server`), since `kubeconform` skips the CR. Allowed `podSecurityContext`
keys (0.36.x): `fsGroup`, `fsGroupChangePolicy`, `runAsGroup`, `runAsNonRoot`, `runAsUser`.

**Uninstall ordering (documented wart).** Because the CR is a hook (not tracked by the release) and
`helm uninstall` removes the bundled operator, deleting the CR after the operator is gone strands its
`openclaw.rocks/finalizer`. Procedure for all-in-one: `kubectl delete openclawinstance <name>` **first**
(operator finalizes it), **then** `helm uninstall`. The CRDs carry `helm.sh/resource-policy: keep` and
survive uninstall by design.
