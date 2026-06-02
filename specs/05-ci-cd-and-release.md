# 05 — CI/CD and Release

> Defines GitHub Actions pipelines, gating, versioning, and distribution. Implementable as-is.

## 1. Pipeline overview

Three workflows under `.github/workflows/`:

| Workflow | Trigger | Purpose |
|---|---|---|
| `lint-test.yaml` | PR + push to `main` | Quality gate: lint, schema, render, policy, unit, Kind install. Blocks merge. |
| `security-scan.yaml` | PR + push + weekly `schedule` | Trivy config/misconfig + secret scan; optional Checkov; SARIF upload. |
| `release.yaml` | push of tag `*-vX.Y.Z` (and/or manual `workflow_dispatch`) | Package + push charts to GHCR OCI; create GitHub Release with notes; (future) cosign sign. |

All workflows pin actions by **major tag or SHA**, set least-privilege `permissions:`, and use concurrency cancellation on PRs. Renovate keeps actions/images current.

## 2. `lint-test.yaml` (quality gate)

Runs on `ubuntu-latest`. Detect changed charts (e.g. `chart-testing`'s `ct list-changed` or a path filter) to scope work, but always run on `main`.

Jobs / steps:

1. **Setup:** checkout (full history for `ct`), install `helm` (v3.14+), `python` (for `ct`), `chart-testing` (`ct`), `kubeconform`, `yamllint`, `helm-unittest` plugin, `helm-docs`.
2. **Lint YAML/Helm:**
   - `yamllint` on chart sources + examples.
   - `ct lint --config .github/ct.yaml` (validates `Chart.yaml`, version bump on changed charts, maintainers, `values.schema.json` presence, lints with multiple values via `ci/`).
   - `helm lint charts/* --strict`.
3. **Schema validation:** validate that `values.yaml` passes `values.schema.json` (helm does this on `template`); add explicit **negative tests** (see `06`) asserting bad values are rejected.
4. **Render (`helm template`):** render each chart with default values **and every** `examples/<chart>/*.yaml` and `ci/*.yaml`. Fail on template errors. This guarantees examples never rot.
5. **Manifest validation (`kubeconform`):**
   - Hermes: `helm template ... | kubeconform -strict -summary -schema-location default -schema-location <CRD/k8s versions>` against several `KUBERNETES_VERSION`s (e.g. 1.25, 1.28, 1.31).
   - OpenClaw: render the CR and validate against the **vendored CRD OpenAPI schema** (`charts/openclaw-instance/crd-schema/`) via `-schema-location`. If the schema isn't vendored yet, validate structure only and mark TODO.
6. **Policy / security render checks:** run the render through a PSS/Kyverno/conftest check (see `06` §policy) to assert "restricted" compliance modulo documented exceptions.
7. **Unit/snapshot tests:** `helm unittest charts/*` (helm-unittest) — see `06`.
8. **helm-docs drift:** run `helm-docs` and fail if `README.md` is out of date vs `values.yaml` (keeps docs honest).
9. **Kind smoke test (matrix, best-effort gate):** see §3.

`.github/ct.yaml` config: `target-branch: main`, `chart-dirs: [charts]`, `validate-maintainers: true`, `check-version-increment: true`.

## 3. Kind smoke test

A dedicated job (can be `continue-on-error: false` for renderable installs, but **must not** depend on pulling large/unavailable upstream images — see `06` §"image independence"):

- Spin up `kind` (matrix over a couple of K8s versions).
- Install a CNI that enforces NetworkPolicy only if NP tests are in scope (e.g. Calico) — otherwise default kindnet.
- **Hermes:** `helm install` with a **stubbed image** (override `image.repository` to a tiny HTTP server, or set `command/args` to a no-op) and assert: objects created, PVC bound, Service present, pod schedules. Optionally a second install with the real image guarded behind a label/secret (don't gate PRs on Docker Hub availability).
- **OpenClaw (chosen mode — operator-in-Kind, decided 2026-06-02):** install the **operator** (from its GHCR OCI chart, reliable to pull) + CRDs into Kind, then `helm install openclaw-instance` and assert the CR is **Accepted** and the operator **reconciles child objects** (StatefulSet/Service/PVC appear). Do **not** require the OpenClaw *app* pod to reach Running (its image pull is heavy/flaky) — object creation + CR conditions is enough. **CRD-only** (apply just the CRD, assert the CR validates/creates without reconcile) is kept **only as a resilience fallback** for when the operator chart/registry is unavailable, so PRs don't wedge on upstream outages.
- `helm test <release>` where defined.
- Always `helm uninstall` + assert retained PVCs behave per `retain`/`orphan`.

> **Decision:** Kind install is a required gate **only** for the parts that don't need upstream images (render, CRD acceptance, object creation with stubs). Full real-image runtime is a **nightly/optional** job to avoid flaky external dependencies blocking PRs.

## 4. `security-scan.yaml`

- **Trivy config** (`trivy config`) over rendered manifests + chart sources → misconfiguration findings (SARIF → GitHub code scanning).
- **Trivy fs / secret scan** → catch accidental secrets committed.
- **Checkov** (optional) over rendered manifests for additional K8s policies.
- **Image scan (informational):** `trivy image` on the pinned upstream tags (Hermes, OpenClaw) — reported, not gating (we don't own those images), surfaced in `docs`/release notes so users know.
- Weekly `schedule` re-runs to catch newly disclosed CVEs in pinned images.

## 5. Versioning & changelog

- Per-chart SemVer (`01` §5). `ct` enforces a version bump when a chart changes.
- Each chart has `CHANGELOG.md` (Keep a Changelog). PRs touching a chart must update its changelog (CI can check via a label or a changed-file assertion — start as a soft check).
- `appVersion` bumps tracked separately; a bump that needs user action requires an `upgrade.md` entry.
- Artifact Hub `artifacthub.io/changes` annotation generated from the changelog at release.

## 6. `release.yaml` (publish to GHCR OCI)

Trigger: pushing an annotated tag `^(hermes-agent|openclaw-instance)-v[0-9]+\.[0-9]+\.[0-9]+$` (or `workflow_dispatch` with a chart input). Per-chart tags allow independent releases.

Permissions: `contents: write` (release), `packages: write` (GHCR), `id-token: write` (future cosign keyless).

Steps:
1. Derive chart + version from the tag.
2. `helm lint` + re-render (defense in depth).
3. `helm package charts/<chart> --version <X.Y.Z>` (version must equal the tag; verify).
4. `helm registry login ghcr.io` (using `GITHUB_TOKEN`).
5. `helm push <chart>-<X.Y.Z>.tgz oci://ghcr.io/ketaloca/charts`.
6. **(Future) cosign:** `cosign sign --yes ghcr.io/ketaloca/charts/<chart>:<X.Y.Z>` (keyless OIDC); record fingerprint for `artifacthub.io/signKey`.
7. Create a **GitHub Release** with notes generated from the chart `CHANGELOG.md`; attach the `.tgz` + `provenance`/SBOM (future).
8. Ensure the GHCR package visibility is **public** (one-time manual setup + documented).

**Secondary channel (chosen 2026-06-02):** also publish a classic repo via `helm/chart-releaser-action` (`cr`) → `index.yaml` on **GitHub Pages** at `https://ketaloca.github.io/ai-agent-helm-charts`, enabling `helm repo add ketaloca …`. **OCI stays primary**; both channels are produced by the same release run and kept in sync. Docs document both install methods.

## 7. Dependency automation

- **Renovate** (`renovate.json`) preferred over Dependabot for richer Helm/Docker support:
  - Track upstream image tags in `values.yaml`/`Chart.yaml appVersion` (custom managers/regex for `image.repository`+`tag`) → PRs to bump `appVersion` (reviewed; never auto-merged for app images).
  - Track GitHub Actions versions, `kubeconform`/tool versions, and the OpenClaw operator OCI version reference in docs.
  - Group + schedule (e.g. weekly) to reduce noise; security updates prioritized.
- If Renovate isn't desired, `.github/dependabot.yml` covers Actions + (limited) Docker; note its weaker Helm support.

## 8. Branch protection & required checks

- `main` protected: require `lint-test` (and the non-flaky Kind sub-jobs), `security-scan` (non-gating findings allowed but reported), 1 review, linear history.
- Tags are created from `main` only; release runs off the tag.
- `CODEOWNERS` routes chart changes to maintainers.

## 9. Provenance / supply chain (phased)

- **v0.x:** pinned actions, least-privilege tokens, SBOM optional.
- **Later:** cosign keyless signing of OCI charts; SLSA provenance attestation (`actions/attest-build-provenance`); publish signing key/fingerprint to Artifact Hub; `helm verify`/policy docs for consumers.

## 10. Open items for impl

- **Resolved (2026-06-02):** GHCR owner = `ketaloca` (personal account; GHCR path lowercased) — drives all OCI paths.
- **Resolved (2026-06-02):** publish **both** — OCI (primary) + classic GitHub Pages repo (`chart-releaser`).
- **Resolved (2026-06-02):** gate PRs on operator-in-Kind; CRD-only is the upstream-outage fallback only.
- **TODO:** pin tool versions (`helm`, `ct`, `kubeconform`, `helm-unittest`, Trivy) in a central place (`.tool-versions`/workflow env).
