# ai-agent-helm-charts

**Unofficial community Helm charts for deploying AI agents on Kubernetes** —
opinionated, secure-by-default, and production-aware.

> ⚠️ **Unofficial / not affiliated.** This project is **not affiliated with,
> endorsed by, or sponsored by** Nous Research, Hermes Agent, OpenClaw,
> openclaw.rocks, Paperclip Inc., or their maintainers. All trademarks belong to
> their respective owners — see [TRADEMARKS.md](TRADEMARKS.md). The container
> images are pulled from their **upstream** registries under their own licenses;
> this project does **not** redistribute them.

## Charts

| Chart | Deploys | Status |
|---|---|---|
| [`hermes-agent`](charts/hermes-agent) | The Hermes Agent (`nousresearch/hermes-agent`) as a Deployment + PVC + Service, hardened and private by default. | alpha — `v0.1.x` |
| [`openclaw-instance`](charts/openclaw-instance) | An `OpenClawInstance` custom resource for the OpenClaw Kubernetes Operator. The operator must be pre-installed, or use the opt-in all-in-one mode (`operator.install=true`) to bundle it. | alpha — `v0.2.x` |

## Quick start (safe by default)

**Prerequisites:** a Kubernetes cluster, Helm **≥ 3.8** (Helm 4 supported), and a
default `StorageClass` that provides `ReadWriteOnce` volumes.

Install from the **OCI registry** (no `helm repo add` needed):

```bash
helm install my-hermes \
  oci://ghcr.io/ketaloca/charts/hermes-agent \
  --version 0.1.2 \
  --set apiServer.key="$(openssl rand -hex 24)"   # dev only — see secrets in the chart README
```

…or via the **classic repository**:

```bash
helm repo add ketaloca https://ketaloca.github.io/ai-agent-helm-charts
helm repo update
helm install my-hermes ketaloca/hermes-agent --version 0.1.2
```

Reach it **locally** — the gateway is **not** exposed publicly by default:

```bash
kubectl port-forward svc/my-hermes-hermes-agent 8642:8642
# then talk to the OpenAI-compatible API at http://127.0.0.1:8642 using your API key
```

> The gateway requires an API key for non-loopback access. For production, supply
> it through an existing Secret / External Secrets — **never commit keys to Git**.
> See [`charts/hermes-agent/README.md`](charts/hermes-agent/README.md).

## Security posture (defaults)

- **No public exposure** — `ingress.enabled: false`, `ClusterIP` Service, dashboard off. Reach it with `port-forward` or an identity-aware proxy / VPN.
- **Secrets external** — production uses `existingSecret` / External Secrets; in-chart secret creation is dev-only and flagged.
- **Single-writer state** — `replicaCount: 1` with persistence (enforced); scale out with **more releases**, not more replicas. Rollouts use `Recreate`.
- **Pinned images** — no silent `:latest`; tag/digest pinning supported (digest recommended).
- **Hardened pod** — `runAsNonRoot`, `allowPrivilegeEscalation: false`, `capabilities: drop [ALL]`, `seccompProfile: RuntimeDefault`, no auto-mounted ServiceAccount token.

→ [docs/security.md](docs/security.md) · [docs/production-checklist.md](docs/production-checklist.md)

## Compatibility

| Chart | Chart version | Targets (image) | Min K8s | Helm |
|---|---|---|---|---|
| `hermes-agent` | `0.1.2` | `nousresearch/hermes-agent` (`appVersion: latest`*) | `>= 1.25` | `>= 3.8` (4 supported) |
| `openclaw-instance` | `0.2.1` | CRD `openclaw.rocks/v1alpha1` · app `ghcr.io/openclaw/openclaw` (`appVersion: 2026.2.3`) | `>= 1.28` | `>= 3.8` |

\* Upstream Hermes currently ships only `:latest`; pin `image.digest` for production. See the chart README and `docs/upgrade.md`.
The `openclaw-instance` chart requires the [OpenClaw operator](charts/openclaw-instance/README.md) and its CRDs to be installed first — or set `operator.install=true` for the opt-in all-in-one mode that bundles the operator (incl. its CRDs) as a subchart, so a single `helm install` brings up operator + instance (single-tenant / once per cluster).

## Documentation

- [Security model](docs/security.md) · [Production checklist](docs/production-checklist.md)
- [Backup & restore](docs/backup-restore.md) · [Upgrade](docs/upgrade.md) · [Troubleshooting](docs/troubleshooting.md)
- [External secrets](docs/external-secrets.md) · [Network policies](docs/network-policies.md) · [GitOps](docs/gitops.md) · [Releasing](docs/releasing.md)
- Design specs live in [`specs/`](specs/).

## Contributing & security

See [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), and
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## License

[MIT](LICENSE). Covers the charts and docs only — upstream images keep their own
licenses (see [TRADEMARKS.md](TRADEMARKS.md)).

---

_Unofficial community project. Not affiliated with the upstream agent projects._
