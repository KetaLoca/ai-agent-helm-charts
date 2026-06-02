# 01 — Repository Architecture

> Defines layout, naming, Helm conventions, versioning, and distribution. Binding for all charts.

## 1. Repository layout

Working name: **`ai-agent-helm-charts`**.

```text
ai-agent-helm-charts/
  README.md                      # Project intro + disclaimer + chart index + quick start
  LICENSE                        # MIT (see §6)
  SECURITY.md                    # Reporting + supported versions + secure-use guidance
  CONTRIBUTING.md                # Dev workflow, lint/test, commit & release conventions
  CODE_OF_CONDUCT.md             # (optional, recommended for community repo)
  TRADEMARKS.md                  # Non-affiliation / trademark notice (or inline in README)
  artifacthub-repo.yml           # Artifact Hub repository metadata (repo root)
  .gitignore
  .editorconfig
  renovate.json                  # (or .github/dependabot.yml) image/tag/action bumps

  charts/
    hermes-agent/                # see 02
    openclaw-instance/           # see 03

  examples/
    hermes/
      minimal-values.yaml
      production-values.yaml
      private-gateway-values.yaml
      ingress-with-auth-values.yaml
      external-secrets-values.yaml
      tailscale-values.yaml
    openclaw/
      minimal-instance-values.yaml
      production-instance-values.yaml
      external-secrets-values.yaml
      tailscale-values.yaml
      operator-notes.md          # how to install the operator (not automated)

  docs/
    security.md
    production-checklist.md
    backup-restore.md
    upgrade.md
    troubleshooting.md
    external-secrets.md
    network-policies.md
    gitops.md                    # ArgoCD/Flux usage (added vs. original list — see §10)

  specs/                         # this folder (design specs; not shipped in charts)

  .github/
    workflows/
      lint-test.yaml
      release.yaml
      security-scan.yaml
    ISSUE_TEMPLATE/
    PULL_REQUEST_TEMPLATE.md
    CODEOWNERS
```

### Per-chart layout

```text
charts/<chart>/
  Chart.yaml
  values.yaml
  values.schema.json
  README.md                      # generated/maintained; helm-docs friendly
  LICENSE                        # (optional) copy or reference root license
  .helmignore
  templates/
    _helpers.tpl                 # REQUIRED (was missing from the original sketch)
    NOTES.txt
    ...                          # chart-specific (see 02 / 03)
    tests/
      test-connection.yaml       # `helm test` pod (where meaningful)
  tests/                         # helm-unittest specs (snapshot/unit) — see 06
    *_test.yaml
  ci/                            # CI-only values for chart-testing (ct)
    *-values.yaml
```

> **Decision (deviation from original sketch):** add `templates/_helpers.tpl` (every chart needs shared naming/label helpers), `tests/` (unit/snapshot), `ci/` (chart-testing install values), and `docs/gitops.md`. Rationale: the sketch omitted helpers (non-optional in practice) and a unit-test surface (required by `06`). No fields removed.

## 2. Naming conventions

| Thing | Convention | Example |
|---|---|---|
| Repo | kebab-case, descriptive, no "official" | `ai-agent-helm-charts` |
| Chart name | kebab-case; the agent + role | `hermes-agent`, `openclaw-instance` |
| Release name (user-chosen) | kebab-case; per tenant/instance | `hermes-alice`, `openclaw-team-x` |
| Template files | lowercase resource kind | `deployment.yaml`, `networkpolicy.yaml` |
| Helper templates | `<chart>.<thing>` | `hermes-agent.fullname`, `hermes-agent.labels` |
| Values keys | camelCase (Helm community norm) | `persistence.storageClass`, `extraEnv` |
| Kubernetes labels | `app.kubernetes.io/*` standard set | see §3 |
| Git branches | `main` (default), `feat/*`, `fix/*`, `chore/*` | |
| Git tags (releases) | `<chart>-vMAJOR.MINOR.PATCH` | `hermes-agent-v0.1.0` |

**Anti-affiliation naming rules:** no chart, image alias, label, or annotation may imply official endorsement. The Docker Hub/GHCR coordinates of upstream images are referenced verbatim; we never re-tag and republish them.

## 3. Helm conventions

- **Helm 3 only.** `Chart.yaml` `apiVersion: v2`.
- **Standard labels** on every rendered object, via a `<chart>.labels` helper:
  ```yaml
  app.kubernetes.io/name: {{ include "<chart>.name" . }}
  app.kubernetes.io/instance: {{ .Release.Name }}
  app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
  app.kubernetes.io/managed-by: {{ .Release.Service }}
  helm.sh/chart: {{ include "<chart>.chart" . }}
  app.kubernetes.io/part-of: ai-agent-helm-charts
  ```
  Selector labels are the stable subset (`name` + `instance`) and must **not** include `version` (otherwise rollouts orphan pods).
- **Naming helpers:** `name`, `fullname` (respect `fullnameOverride`/`nameOverride`, truncate to 63 chars, trim trailing `-`), `chart`, `serviceAccountName`.
- **No `latest` defaults.** `image.tag` defaults to empty and falls back to `.Chart.AppVersion`; document digest pinning.
- **`values.schema.json` is mandatory** for both charts (fail-fast on bad input; encodes safety invariants like "persistence ⇒ replicaCount == 1"). JSON Schema draft-07 (Helm's supported dialect).
- **NOTES.txt** must print: disclaimer, what was (not) exposed, how to reach the service safely (port-forward first), and any required-secret reminders.
- **Capabilities/version gating:** use `.Capabilities.APIVersions.Has` for optional APIs (e.g. `policy/v1` PDB, `networking.k8s.io/v1`). Declare `kubeVersion` in `Chart.yaml`.
- **Determinism:** avoid `lookup` in render-critical paths (breaks `helm template`/GitOps diff). If used (e.g. autogenerate a dev secret), guard so absence degrades gracefully and never blocks `helm template`.
- **Hooks:** avoid install hooks that break `--dry-run`/ArgoCD diff. Prefer none in v0.x.
- **Comments:** every non-obvious value in `values.yaml` is documented inline (helm-docs compatible `# -- ` annotations) so chart READMEs can be generated.

## 4. Chart structure ownership

- `hermes-agent` **owns and renders** all its Kubernetes objects (it deploys a plain container).
- `openclaw-instance` **owns only** the `OpenClawInstance` CR (+ optional Secret/ConfigMap/extra NetworkPolicy). The **operator** owns the downstream StatefulSet/Service/PVC/etc. The chart must not duplicate those. See `03`.

## 5. Versioning (SemVer, per chart)

- Each chart is versioned **independently**. `Chart.yaml: version` is the **chart** SemVer; `appVersion` is the **upstream app** version it targets.
- **Chart `version` bumps:**
  - **MAJOR**: breaking values changes (renamed/removed keys, changed defaults that alter behavior, min K8s/operator bump).
  - **MINOR**: new opt-in features, new values keys with safe defaults, new templates.
  - **PATCH**: docs, template fixes that don't change the rendered contract, dependency-free fixes.
- **`appVersion`** tracks a verified-good upstream image tag. Bumping `appVersion` is at least a PATCH (often MINOR) chart bump, with a changelog note and an `upgrade.md` entry if action is needed.
- Every chart keeps a `CHANGELOG.md` (Keep a Changelog format). Release notes are generated from it.
- **Compatibility tables** (chart version ↔ appVersion ↔ min K8s ↔, for OpenClaw, operator/CRD version) live in each chart README and `docs/upgrade.md`. See `07`.

## 6. License

**Decision: MIT** (chosen by maintainer 2026-06-02).
- Rationale: simplest permissive license, minimal friction for a community charts repo.
- **Trade-off accepted:** MIT has **no explicit patent grant** (Apache-2.0 does). Acceptable here because the charts only template manifests and ship no original patentable code.
- Charts only template upstream images; they do **not** redistribute upstream code, so chart licensing is independent of Hermes/OpenClaw licenses. Document upstream image licenses in each chart README.
- Ship a top-level `LICENSE` (MIT) and set `artifacthub.io/license: MIT` in every `Chart.yaml`.

## 7. Publishing charts to GHCR as OCI

Helm charts are published as **OCI artifacts** to GitHub Container Registry.

- Registry path pattern: `oci://ghcr.io/ketaloca/charts/<chart>` — owner **`ketaloca`** (GitHub `KetaLoca`, **lowercased because OCI/GHCR references must be lowercase**). `<chart>` ∈ {`hermes-agent`, `openclaw-instance`}. Resolved 2026-06-02.
- Publish on tag push (`<chart>-vX.Y.Z`) via `release.yaml`:
  ```bash
  helm package charts/<chart>
  helm push <chart>-X.Y.Z.tgz oci://ghcr.io/ketaloca/charts
  ```
- Consume:
  ```bash
  helm install my-release oci://ghcr.io/ketaloca/charts/hermes-agent --version X.Y.Z
  ```
- Packages must be set **public** in GHCR package settings.
- Future: cosign keyless signing (`cosign sign` the OCI digest) + attach provenance (see `05`).
- **Secondary channel (chosen 2026-06-02):** classic HTTP `index.yaml` repo via GitHub Pages + `chart-releaser` (`cr`), giving the familiar `helm repo add https://ketaloca.github.io/ai-agent-helm-charts`. **OCI is primary; the classic repo is published alongside it** (both kept in sync by `release.yaml`).

## 8. Artifact Hub readiness

- Root `artifacthub-repo.yml` declares repo ownership (repository ID + owners) so the org can be verified.
- Each `Chart.yaml` carries Artifact Hub annotations:
  ```yaml
  annotations:
    artifacthub.io/license: MIT
    artifacthub.io/changes: |
      - kind: added
        description: ...
    artifacthub.io/links: |
      - name: source
        url: https://github.com/ketaloca/ai-agent-helm-charts
    artifacthub.io/maintainers: |
      - name: <maintainer>
        email: <email>
    artifacthub.io/signKey: |          # once cosign is enabled
      fingerprint: ...
      url: ...
    artifacthub.io/containsSecurityUpdates: "false"
    # Non-affiliation note surfaced on the listing:
    artifacthub.io/prerelease: "true"  # while v0.x
  ```
- A clear **"unofficial / not affiliated"** statement appears in the chart README (Artifact Hub renders it).

## 9. Examples organization

- `examples/<agent>/*.yaml` are **complete, copy-pasteable `-f` values files**, each opening with a comment block: what it demonstrates, what it assumes, and any safety caveats.
- Examples are **CI-rendered** (`helm template -f`) to guarantee they stay valid (see `06`). A subset feeds chart-testing installs (`ci/`).
- Naming mirrors capability: `minimal-`, `production-`, `private-gateway-`, `ingress-with-auth-`, `external-secrets-`, `tailscale-`.

## 10. Docs organization

- `docs/` holds cross-chart, task-oriented guides (security, production checklist, backup/restore, upgrade, troubleshooting, external-secrets, network-policies, gitops).
- Chart-specific reference (values table) lives in `charts/<chart>/README.md` (helm-docs generated from `values.yaml` comments + a hand-written intro).
- The root `README.md` is an index + quick start + disclaimer; it links into `docs/` and each chart README. Full plan in `07`.
