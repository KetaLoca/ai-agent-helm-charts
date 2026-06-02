# 08 — Implementation Plan

> Phased build plan with concrete tasks and acceptance criteria, plus the consolidated risk register and open questions. Another agent should be able to execute from here + the other specs.

## Phase 1 — Repository base

**Tasks**
- Create repo skeleton (`01` §1): root files, `charts/`, `examples/`, `docs/`, `.github/`.
- `README.md` (index + disclaimer + quick start placeholder), `LICENSE` (**MIT**, decided), `SECURITY.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `TRADEMARKS.md`, `artifacthub-repo.yml`, `.gitignore`, `.editorconfig`, `renovate.json`.
- `.github/workflows/lint-test.yaml` (lint + render + schema + kubeconform + unit, scoped to changed charts), minimal first pass.
- `.github/ct.yaml`, `CODEOWNERS`, issue/PR templates.
- Pin tool versions (helm, ct, kubeconform, helm-unittest, helm-docs).

**Acceptance**
- `helm lint` / `ct lint` run green on an empty/placeholder chart.
- CI triggers on PR and passes.
- README renders the disclaimer; license present.
- No secrets, no `latest`, no TODOs left unmarked.

## Phase 2 — `hermes-agent` chart

**Tasks (per `02`)**
- `Chart.yaml` (`appVersion` pinned to a verified Hermes tag), `.helmignore`.
- `templates/_helpers.tpl` (name/fullname/chart/labels/selectorLabels/serviceAccountName/image ref).
- Templates: `deployment.yaml` (Recreate-on-persistence, env wiring, security contexts, volumes incl. optional `/dev/shm`, probes), `service.yaml`, `serviceaccount.yaml`, `pvc.yaml` (retain), `secret.yaml` (dev), `configmap.yaml` (opt), `ingress.yaml`, `networkpolicy.yaml`, `pdb.yaml`, `tests/test-connection.yaml`, `NOTES.txt` (disclaimer + safe access + key reminder).
- `values.yaml` (the full target in `02` §15) with helm-docs `# --` comments.
- `values.schema.json` enforcing invariants (`02` §16), plus the `fail` guard for persistence+replicas.
- Resolve the verify-TODOs: image `CMD`/`args`, health endpoint path (enable probes if found), `readOnlyRootFilesystem`+scratch feasibility.
- `examples/hermes/*.yaml` (minimal, production, private-gateway, ingress-with-auth, external-secrets, tailscale).
- `charts/hermes-agent/README.md` (helm-docs) + compatibility table.
- `tests/*_test.yaml` (helm-unittest) + negative cases (`06` §3/§4).
- Wire docs: backup-restore, troubleshooting entries for Hermes.

**Acceptance**
- Default render valid; all examples render and pass `kubeconform` across the K8s matrix.
- Negative tests fail as expected (persistence+replicas>1, ingress w/o hosts, insecure dashboard w/o ack, missing key).
- Policy scan: restricted-PSS compliant modulo the documented `readOnlyRootFilesystem` exception.
- Kind install (stub image): objects + PVC + Service; `helm test` passes; uninstall retains PVC.
- helm-docs up to date; CHANGELOG entry; chart `version` set.

## Phase 3 — `openclaw-instance` chart

**Tasks (per `03`)**
- Vendor the CRD OpenAPI schema → `charts/openclaw-instance/crd-schema/` and pin the target CRD/operator version; confirm canonical OCI path (`paperclipinc` vs `openclaw-rocks`).
- `Chart.yaml`, `_helpers.tpl`.
- Templates: `openclawinstance.yaml` (modeled `spec` + `mergeOverwrite` `extraSpec`, with empty-pruning), `secret.yaml` (dev), `configmap.yaml` (opt), `networkpolicy-extra.yaml`, optional `preflight-job.yaml`, `NOTES.txt` (operator preflight + status hints), `tests/`.
- `values.yaml` (the friendly target in `03` §7) with helm-docs comments + secure defaults.
- `values.schema.json` (`03` §10).
- `examples/openclaw/*.yaml` + `operator-notes.md`.
- `charts/openclaw-instance/README.md` + compatibility table + `extraSpec` policy.
- `tests/*_test.yaml`: CR shape, friendly→CRD path mapping, secure defaults, `extraSpec` precedence, empty-pruning.
- Re-verify all `03` field TODOs against the pinned CRD; route anything unverified through `extraSpec` (don't invent).

**Acceptance**
- CR renders with `openclaw.rocks/v1alpha1`/`OpenClawInstance`; validates against vendored CRD schema.
- Friendly values map to correct CRD paths (unit tests green); secure defaults confirmed (ingress off, chromium/webTerminal/selfConfigure/autoUpdate off, NP on).
- `extraSpec` overrides modeled fields (test).
- Kind: **operator-in-Kind** install reconciles (operator creates child objects); CRD-only kept only as an upstream-outage fallback.
- Docs: operator install + compatibility + risks complete.

## Phase 4 — Release & distribution

**Tasks (per `05`)**
- `release.yaml`: tag-driven `helm package`+`push` to `oci://ghcr.io/<OWNER>/charts`; GitHub Release from CHANGELOG.
- Make GHCR packages public; document consume commands.
- `artifacthub-repo.yml` + per-chart Artifact Hub annotations; verify listing.
- Renovate fully configured (image/appVersion/actions/operator-version).
- `security-scan.yaml` (Trivy config/secret + weekly schedule).
- Decide classic `index.yaml` channel (yes/no).

**Acceptance**
- Pushing `hermes-agent-vX.Y.Z` publishes a pullable OCI chart; `helm install oci://...` works.
- Artifact Hub shows both charts with disclaimer + values + links.
- Renovate opens a test bump PR.
- Security scan runs and uploads SARIF.

## Phase 5 — Advanced hardening

**Tasks (per `04`)**
- External Secrets examples (ESO + Sealed Secrets + SOPS) for both charts + `docs/external-secrets.md`.
- Advanced NetworkPolicy (egress allow-list, ingress-from-controller) + `docs/network-policies.md` incl. L4-limit note and a Cilium FQDN pointer.
- Private-access examples: Tailscale (OpenClaw native field; Hermes sidecar), Cloudflare Tunnel+Access, Authelia/oauth2-proxy.
- Velero/restic backup examples + restore drill in `docs/backup-restore.md`.
- cosign keyless signing + SLSA provenance in `release.yaml`; publish signKey to Artifact Hub.
- (If validated) Hermes `readOnlyRootFilesystem: true` opt-in with scratch emptyDirs.

**Acceptance**
- Each example renders/installs (stub) in CI.
- Signed releases verify with `cosign verify`; Artifact Hub shows signed.
- Backup/restore drill documented and dry-run-tested in Kind where feasible.

## Sequencing & dependencies

- Phase 1 → 2 → (3 ∥ 4-partial) → 4 → 5. Hermes (2) first because it's self-contained (no operator dependency). OpenClaw (3) needs the vendored CRD + operator-in-CI decision. Release (4) can start once one chart is green. Phase 5 is incremental and non-blocking.

---

## Risk register (critical review)

| # | Risk | Severity | Mitigation / decision |
|---|---|---|---|
| R1 | **Upstream churn breaks charts** (Hermes env/flags; OpenClaw CRD fields). | High | Escape hatches (`extraEnv/From`, `extraVolumes`, `extraSpec`, `extraObjects`); pin `appVersion`/CRD version; Renovate PRs reviewed; vendored CRD schema; forward-compat policy in `01`/`03`. |
| R2 | **Legal/naming — looking official.** | High | `00` §5 disclaimer everywhere; `TRADEMARKS.md`; no "official"/brand logos; reference (don't republish) images; Artifact Hub "unofficial" note. |
| R3 | **Insecure-by-accident exposure** (gateway/dashboard/keys). | High | Ingress/dashboard off; `requireKey`; external secrets; NP available; loud NOTES/docs; PSS-restricted CI gate. |
| R4 | **Shared-state corruption** if users scale up. | High | Schema-block persistence+replicas>1 (Hermes); Recreate; document OpenClaw StatefulSet single-writer; warn on `autoScaling`. |
| R5 | **CI hostage to upstream images / Docker Hub limits.** | Medium | Stub-image PR gate; real-image runs nightly/optional/non-gating; pin tags; CRD-only fallback for OpenClaw. |
| R6 | **`readOnlyRootFilesystem` vs Hermes s6** misconfig. | Medium | Default off + documented; opt-in only after verification with scratch emptyDirs. |
| R7 | **NetworkPolicy false sense of security** (L4 only, no FQDN). | Medium | Document the limitation; point to Cilium FQDN/mesh for real egress control. |
| R8 | **PDB wedging node drains** at replicas=1. | Medium | Default off; document the `minAvailable:1` sharp edge. |
| R9 | **Data loss on uninstall.** | Medium | `retain`/`orphan: true` defaults + `helm.sh/resource-policy: keep`; backup docs; explain how to actually delete. |
| R10 | **`helm install` fails without operator/CRD** (OpenClaw). | Medium | By design; NOTES preflight; optional preflight Job; clear prereq docs; never break `helm template`. |
| R11 | **Maintenance burden** (two fast-moving upstreams, multi-version matrix). | Medium | Keep charts minimal; lean on operator for OpenClaw; automate via Renovate + CI; compatibility tables; small reviewable templates. |
| R12 | **Agent autonomy risks** (`selfConfigure`/`autoUpdate`/tools). | Medium | Off by default; documented as security-relevant opt-ins. |
| R13 | **Secret sprawl across tenants.** | Low/Med | Per-release secrets; namespace-per-tenant guidance; External Secrets. |
| R14 | **GHCR owner/path unset** blocks release wiring. | Low | Resolve owner early (open question Q1); parametrize `<OWNER>`. |
| R15 | **Operator org ambiguity** (`paperclipinc` vs `openclaw-rocks`). | Low | Verify canonical OCI path/version at Phase 3; document both; pin one. |

## Fields deliberately kept flexible (forward-compat)

- Hermes: `extraEnv`, `extraEnvFrom`, `extraVolumes`, `extraVolumeMounts`, `extraObjects`, free-form `securityContext`/`resources`/`affinity`.
- OpenClaw: `extraSpec` (deep-merge, wins), `config.raw`, `ollama`, `workspace`, `gateway`, `backup` routed through passthrough until modeled; per-field passthrough for `tailscale`/`autoUpdate`/`selfConfigure` sub-fields pending CRD re-verification.

## Open questions (need a human decision)

- **Q1 — GHCR owner. RESOLVED (2026-06-02):** maintainer's **personal GitHub account**. *Still needed:* the exact GitHub handle to fill `<OWNER>` — blocks Phase 4 wiring until provided.
- **Q2 — License. RESOLVED (2026-06-02): MIT.**
- **Q3 — Repo name. RESOLVED (2026-06-02):** keep `ai-agent-helm-charts`.
- **Q4 — Spec/doc language.** English specs + English docs (current default) — OK? Want a Spanish README translation in scope?
- **Q5 — OpenClaw CI depth. RESOLVED (2026-06-02):** operator-in-Kind is the gate; CRD-only is the upstream-outage fallback only.
- **Q6 — Distribution channel.** OCI only, or also classic `index.yaml` via GitHub Pages?
- **Q7 — Hermes probes.** OK to ship probes off until the health path is verified, then default readiness on?
- **Q8 — cosign timing.** Sign from v0.1.0, or defer to Phase 5 as planned?
- **Q9 — Scope confirm.** Two charts only for v0.x (no operator chart, no umbrella) — confirmed?
- **Q10 — Hermes `appVersion` pin.** Which specific upstream tag is the verified-good baseline (image moves fast; `latest` only currently confirmed)?
