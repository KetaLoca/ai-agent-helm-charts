# 00 — Project Overview

> **Status:** Draft for review. Spec-driven; no chart code is to be written until specs are approved.
> **Spec language:** English (the repository is public/community-facing; all artifacts — README, docs, disclaimers, values — are English). Conversational/review summaries with the maintainer may be in Spanish.

## 1. Goal

Build a **public, community-maintained repository of Helm charts** for deploying AI agents on Kubernetes. The charts are **opinionated, secure-by-default, auditable, and production-aware** — not just "make it boot."

The first two targets:

1. **`hermes-agent`** — packages the [Hermes Agent](https://github.com/NousResearch/hermes-agent) container (`nousresearch/hermes-agent`) as a first-class Kubernetes Deployment.
2. **`openclaw-instance`** — a thin, friendly chart that emits an `OpenClawInstance` custom resource (`openclaw.rocks/v1alpha1`) for the existing **OpenClaw Kubernetes Operator**. It does **not** install OpenClaw directly and does **not** bundle the operator.

## 2. Problem it solves

| Problem | How these charts help |
|---|---|
| Hermes is documented for Docker/Compose only; no clean, auditable K8s path. | A real, hardened Deployment chart with correct persistence, security context, and "do not expose by default" posture. |
| Running an agent that holds API keys, memory, and a gateway is easy to misconfigure into a public, unauthenticated foothold. | Secure defaults: ingress off, dashboard off, auth key enforced, NetworkPolicy available, secrets external. |
| The OpenClaw `OpenClawInstance` CRD is powerful but verbose; declaring per-tenant instances by hand is error-prone. | A friendly values surface that maps to the CRD `spec`, with an `extraSpec` escape hatch for forward-compatibility. |
| GitOps teams want versioned, reviewable, OCI-distributed charts with provenance. | SemVer charts published to GHCR (OCI), CI lint/test, Artifact Hub metadata, future cosign signing. |

## 3. Target audience

- Platform / DevOps engineers self-hosting AI agents on their own clusters (homelab → small prod).
- Teams running **multi-tenant** agent instances (one release per tenant/project).
- GitOps users (Argo CD / Flux) who want declarative, reviewable agent deployments.
- Security-conscious operators who want hardening knobs without hand-rolling manifests.

**Not** targeted: turnkey internet-exposed SaaS, or users who want a one-click public endpoint (we deliberately make that the hard path).

## 4. Scope of the first version (v0.1.x → v0.x)

**In scope (v0.x):**

- `hermes-agent` chart: Deployment, Service, optional PVC, optional Secret/ConfigMap, optional Ingress, optional NetworkPolicy, optional PDB, ServiceAccount, NOTES, `values.schema.json`.
- `openclaw-instance` chart: `OpenClawInstance` CR template, optional Secret/ConfigMap, optional extra NetworkPolicy, NOTES, `values.schema.json`, `extraSpec` passthrough.
- `examples/` for both charts (minimal, production, private-gateway, external-secrets, etc.).
- `docs/` (security, production checklist, backup/restore, upgrade, troubleshooting, external secrets, network policies, GitOps).
- CI: lint, `helm template`, schema validation, `kubeconform`, chart-testing, Kind smoke test, Trivy config scan.
- Release: GHCR OCI publishing, SemVer, changelog, Renovate/Dependabot for image tags.

**Out of scope (initially) — explicitly deferred:**

- Bundling/installing the **OpenClaw operator** or its CRDs *by default* — the chart stays a CR emitter and assumes they exist. **Update (0.2.x):** an **opt-in** `operator.install=true` now bundles the official operator chart as a subchart for a single `helm install` (single-tenant / once-per-cluster); see `03 §13`. Documented, not automated, in default mode.
- Re-implementing the OpenClaw operator's behavior (NetworkPolicy/PDB/RBAC/StatefulSet generation) — that is the operator's job.
- A Hermes "cluster"/multi-replica/HA story with shared state (architecturally unsafe — see §6).
- An umbrella/meta-chart or shared library chart as the *default* shape. **Update (0.2.x):** `openclaw-instance` gained an **optional** subchart dependency (the operator) gated behind `operator.install` (not rendered by default). A shared library chart across both charts is still deferred (see `01`).
- cosign signing & SLSA provenance (planned as a later hardening phase, see `05`).
- Bundling LLM backends (Ollama, vLLM) as dependencies — referenced via config only.

## 5. Positioning — unofficial community project

This is an **unofficial, community** project with **no affiliation** to upstream. Every chart README, the repo README, and `NOTES.txt` must carry a disclaimer:

```text
Unofficial community Helm charts for deploying AI agents on Kubernetes.
This project is NOT affiliated with, endorsed by, or sponsored by Nous Research,
Hermes Agent, OpenClaw, openclaw.rocks, Paperclip Inc., or their maintainers.
All trademarks belong to their respective owners. Container images are pulled
from upstream registries and are governed by their own licenses and terms.
```

Naming rules (see `01` and risk register in `08`):

- Repo/chart names describe **what they deploy** ("hermes-agent", "openclaw-instance"), never imply official status (avoid "official", "nous-", brand logos).
- Do **not** redistribute upstream container images; reference them by registry coordinates.
- Keep a `TRADEMARKS.md`/disclaimer block and link upstream sources.

## 6. Design principles

These are binding constraints, referenced throughout the other specs.

1. **Secure by default.** Nothing that exposes secrets, gateways, or dashboards is on without an explicit, informed opt-in. Defaults assume a hostile network.
2. **No public exposure by default.** `ingress.enabled: false`; gateway/dashboard not internet-reachable; auth required before any exposure. Recommend identity-aware proxies / VPN (Cloudflare Access, Authelia, Tailscale) over raw Ingress.
3. **No secrets in Git.** Production path uses `existingSecret` / External Secrets / Sealed Secrets / SOPS. In-chart secret creation exists only for throwaway dev and is documented as such.
4. **Explicit persistence.** Persistence is opt-in-visible (default on for Hermes because losing memory/keys is worse), with explicit `mountPath`, access modes, and a `retain`/orphan policy so a `helm uninstall` doesn't silently delete state.
5. **No horizontal scaling with shared state.** Hermes and OpenClaw both hold single-writer state (sessions, memory, sqlite-like stores). `replicaCount > 1` against one `ReadWriteOnce` PVC is forbidden by schema/validation. Scale **out = more releases (tenants)**, never **up = more replicas of one instance**. Use `strategy: Recreate` to avoid two pods writing concurrently during rollout.
6. **GitOps friendly.** Pure templated manifests, deterministic rendering, no `lookup`-dependent logic in the critical path, no install-time hooks that break `--dry-run`/diff. Charts must render cleanly with `helm template` even when the cluster/CRD is absent.
7. **Minimal but production-aware.** Don't ship a kitchen sink, but every production concern (probes, PDB, resources, security context, anti-affinity, backups) is reachable through values and documented.
8. **Pin, don't float.** Never default to `latest` for production guidance. Support tag **and** digest pinning. `appVersion` tracks a known-good upstream version.
9. **Auditable & reviewable.** Small, readable templates; `values.schema.json` to fail fast; examples that double as documentation; CI that proves rendering + policy.
10. **Forward-compatible with upstream churn.** Both upstreams move fast. Provide escape hatches (`extraEnv`, `extraVolumes`, `extraSpec`, raw passthroughs) so users aren't blocked when upstream adds a field before the chart models it.

## 7. Upstream facts of record (verified 2026-06-02)

These underpin the chart specs. Re-verify at implementation time; upstreams move fast.

### Hermes Agent
- Image: `nousresearch/hermes-agent` (Docker Hub). Repo: `github.com/NousResearch/hermes-agent`. Docs: `hermes-agent.nousresearch.com/docs`.
- Runs as **non-root `hermes`, UID 10000**; **s6-overlay v3 is PID 1** (entrypoint `/init`); long-running command `gateway run`.
- Data dir **`/opt/data`** holds `.env`, `config.yaml`, `SOUL.md`, `sessions/`, `memories/`, `skills/`, `home/`, `logs/`.
- Ports: **8642** gateway (OpenAI-compatible API), **9119** dashboard.
- Env: `API_SERVER_ENABLED`, `API_SERVER_HOST` (default `127.0.0.1`), `API_SERVER_KEY` (≥8 chars; required for non-loopback access), `API_SERVER_CORS_ORIGINS`, `HERMES_DASHBOARD`, `HERMES_DASHBOARD_HOST/PORT` (9119), `HERMES_DASHBOARD_INSECURE` (disables auth — dangerous), `HERMES_UID`/`HERMES_GID` (a.k.a. `PUID`/`PGID`), `HERMES_ALLOW_ROOT_GATEWAY`, `ANTHROPIC_API_KEY`/`OPENAI_API_KEY`/`TELEGRAM_BOT_TOKEN`.
- Resource floor ~1 GB; 2–4 GB recommended; browser tools need ≥2 GB and **`--shm-size=1g`** (→ `/dev/shm` emptyDir in K8s).
- **Concurrency hazard:** "Never run two gateway containers against the same data directory." → single writer.
- **TODO(verify@impl):** exact health endpoint path; whether image `CMD` already defaults to `gateway run` (affects chart `args`); behavior under `readOnlyRootFilesystem` given s6 writes to `/run`.

### OpenClaw Operator
- CRD group/version **`openclaw.rocks/v1alpha1`**; kinds **`OpenClawInstance`** (primary), `OpenClawSelfConfig`, `OpenClawClusterDefaults`.
- Operator install (Helm OCI): `oci://ghcr.io/paperclipinc/charts/openclaw-operator` (org also appears as `openclaw-rocks`; **TODO(verify@impl)** canonical path + version). Requires K8s ≥ 1.28; cert-manager only if webhook enabled; Prometheus Operator only for ServiceMonitor.
- Per `OpenClawInstance`, the **operator** creates: ServiceAccount+Role+RoleBinding, ConfigMap, PVC (10Gi default), PDB, **default-deny NetworkPolicy**, StatefulSet, Service (ports **18789/18793**), auto-generated gateway-token Secret, optional Ingress, optional ServiceMonitor.
- App image: `ghcr.io/openclaw/openclaw` (e.g. `2026.2.3`).
- Verified `spec` top-level fields and a full sample are captured in `03`.

## 8. Related specs

- `01-repository-architecture.md` — layout, naming, versioning, OCI/Artifact Hub.
- `02-hermes-agent-chart.md` — the Hermes chart contract.
- `03-openclaw-instance-chart.md` — the OpenClaw CR-emitter chart contract.
- `04-security-model.md` — threats, defaults, hardening, production checklist.
- `05-ci-cd-and-release.md`, `06-testing-strategy.md`, `07-documentation-plan.md`, `08-implementation-plan.md`.
- `09-review-notes.md` — second-pass critical review: decisions applied, defects fixed, open items.
