# openclaw-instance

**Unofficial community Helm chart** that declares an `OpenClawInstance`
(`openclaw.rocks/v1alpha1`) custom resource for the [OpenClaw Kubernetes
Operator](https://github.com/paperclipinc/openclaw-operator).

> ⚠️ Not affiliated with OpenClaw / openclaw.rocks / Paperclip Inc. See
> [TRADEMARKS.md](../../TRADEMARKS.md).

## What it deploys

**Only** an `OpenClawInstance` custom resource (plus an optional dev `Secret`,
`ConfigMap`, and a supplementary `NetworkPolicy`). The **operator** reconciles the
CR into the actual StatefulSet / Service / PVC / RBAC / NetworkPolicy / PDB. This
chart is a friendly, validated mapper onto the CRD `spec`, with an `extraSpec`
escape hatch for fields it doesn't model yet.

## Prerequisites (important)

- The **OpenClaw operator and its CRDs must already be installed** — this chart does
  not install them. See [`examples/openclaw/operator-notes.md`](../../examples/openclaw/operator-notes.md).
  `helm install` fails with `no matches for kind "OpenClawInstance"` if the CRD is absent.
- Kubernetes **≥ 1.28** (operator requirement). Helm **≥ 3.8**.

## Install

```bash
# Verify the operator/CRD first:
kubectl get crd openclawinstances.openclaw.rocks

helm install oc oci://ghcr.io/ketaloca/charts/openclaw-instance --version 0.1.0 \
  -f my-values.yaml
# or: helm repo add ketaloca https://ketaloca.github.io/ai-agent-helm-charts

kubectl get openclawinstance oc-openclaw-instance
```

## Key decisions

- **Thin CR emitter.** We render the CR and let the operator do the rest. We do **not**
  re-create the StatefulSet/Service/PVC/RBAC the operator manages.
- **`extraSpec` (deep-merge, wins on conflict).** Any CRD field the chart doesn't model
  (e.g. `gateway`, `backup`, `workspace`, `initContainers`, `sidecars`) can be set via
  `extraSpec`; it is deep-merged into `spec` after the modeled fields and **overrides**
  them. Lists are replaced, not concatenated.
- **Secure defaults** (conservative vs. the upstream sample): `networking.ingress` off,
  `chromium` / `webTerminal` / `autoUpdate` / `selfConfigure` off,
  `security.networkPolicy` on, `serviceMonitor` off. Risky features are explicit opt-ins.
- **Don't fight the operator.** Unset/empty sections are pruned so the operator's own
  defaults apply; hardened `security` values and a `resources` floor are deliberate.
- **No floating tags.** `image.tag` falls back to `appVersion`; pin `image.digest` for prod.

## Values (selected)

| Key | Default | Description |
|---|---|---|
| `instance.name` | `""` | CR name (defaults to release fullname). |
| `image.repository` | `ghcr.io/openclaw/openclaw` | App image (used by the operator). |
| `image.tag` / `image.digest` | `""` / `""` | Tag falls back to `appVersion`; digest wins. |
| `config.raw` | `{}` | Inline OpenClaw config (`spec.config.raw`). |
| `config.fromFiles` | `{}` | Render a ConfigMap from files and wire `configMapRef`. |
| `skills` / `plugins` | `[]` | `spec.skills` / `spec.plugins`. |
| `env` / `envFrom` | `[]` | `spec.env` / `spec.envFrom`. |
| `secrets.existingSecret` | `""` | Prod: reference a Secret (appended to `envFrom`). |
| `secrets.create` / `secrets.data` | `false` / `{}` | Dev: render a Secret and wire it. |
| `resources` | req `500m/1Gi`, lim `4Gi` | `spec.resources`. |
| `persistence.enabled` | `true` | `spec.storage.persistence`. |
| `persistence.size` / `storageClass` / `existingClaim` | `10Gi` / `""` / `""` | |
| `persistence.orphan` | `true` | Retain the PVC when the CR is deleted (confirmed). |
| `security.podSecurityContext` | hardened (UID 1000) | |
| `security.containerSecurityContext` | drop ALL, no-priv-esc | |
| `security.networkPolicy.enabled` | `true` | Keep the operator's default-deny. |
| `security.networkPolicy.allowedIngressNamespaces` / `allowedIngressCIDRs` | `[]` | |
| `chromium.enabled` | `false` | Headless browser (egress/attack surface). |
| `tailscale.enabled` | `false` | Native tailnet exposure (passthrough fields). |
| `webTerminal.enabled` | `false` | Interactive shell into the pod. |
| `networking.service.type` | `ClusterIP` | |
| `networking.ingress.enabled` | `false` | Off — prefer Tailscale / a proxy. |
| `probes` | `{}` | Left to the operator unless overridden. |
| `observability.metrics.enabled` | `true` | `serviceMonitor.enabled` is `false`. |
| `availability.podDisruptionBudget.enabled` | `false` | |
| `autoUpdate.enabled` | `false` | Auto image updates (supply-chain risk). |
| `selfConfigure.enabled` | `false` | Agent self-modification (injects RBAC). |
| `extraNetworkPolicy.enabled` | `false` | Supplementary NetworkPolicy (advanced). |
| `extraSpec` | `{}` | Deep-merged into `spec` (wins on conflict). |

## Security & risks

- **Missing operator/CRD** → install fails by design; the NOTES print a preflight.
- **CRD churn** → use `extraSpec`; watch the compatibility table below.
- **`selfConfigure` / `autoUpdate`** → agent self-modification / auto image pulls; off by default.
- **`chromium` / `webTerminal`** → extra attack surface / egress; off by default.
- **Ingress + default-deny NetworkPolicy** → if you enable ingress, add the controller's
  namespace to `security.networkPolicy.allowedIngressNamespaces` or traffic is blocked.
- **Secrets** never in Git for prod; use `existingSecret` / External Secrets.

See [docs/security.md](../../docs/security.md) and the
[production checklist](../../docs/production-checklist.md).

## Compatibility

| Chart | CRD API | Operator | App image | Min K8s |
|---|---|---|---|---|
| `0.1.0` | `openclaw.rocks/v1alpha1` | `paperclipinc/openclaw-operator` (verify version) | `ghcr.io/openclaw/openclaw` (`appVersion: 2026.2.3`) | `>= 1.28` |

Unknown/newer CRD fields → route through `extraSpec` (no chart release needed). The
targeted CRD is vendored under `crd-schema/` for reference.

## Uninstall

```bash
helm uninstall oc
# The operator removes the instance's resources. With persistence.orphan=true (default)
# the PVC is RETAINED — delete it manually to remove data.
```
