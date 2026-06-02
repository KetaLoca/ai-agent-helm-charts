# Releasing & distribution

Charts are published to **two channels** plus **Artifact Hub** for discovery:

- **OCI** (primary): `oci://ghcr.io/ketaloca/charts/<chart>`
- **Classic repo** (GitHub Pages): `helm repo add ketaloca https://ketaloca.github.io/ai-agent-helm-charts`

Releases are **manual** — the `release` workflow only runs from the Actions tab
(`workflow_dispatch`). Nothing publishes automatically.

## One-time setup

1. **Make the repository public.** Required for free GitHub Pages (classic repo) and
   for Artifact Hub indexing. (OCI packages can be public even from a private repo,
   but the classic channel and Artifact Hub need a public repo.)
   ```bash
   gh repo edit KetaLoca/ai-agent-helm-charts \
     --visibility public --accept-visibility-change-consequences
   ```
2. **Create the `gh-pages` branch** (chart-releaser pushes `index.yaml` there):
   ```bash
   git checkout --orphan gh-pages
   git rm -rf . >/dev/null 2>&1 || true
   : > index.yaml && git add index.yaml
   git commit -m "init gh-pages" && git push origin gh-pages
   git checkout main
   ```
3. **Enable Pages:** Settings → Pages → Source = `Deploy from a branch` → `gh-pages` / `/`.
   The site serves at `https://ketaloca.github.io/ai-agent-helm-charts`.
4. **First release** (see below). Then **make the GHCR packages public:**
   Profile → Packages → `hermes-agent` / `openclaw-instance` → Package settings →
   Change visibility → Public.
5. **Artifact Hub:** add a repository at <https://artifacthub.io> pointing to either the
   OCI registry (`oci://ghcr.io/ketaloca/charts`) or the classic URL. Paste the
   generated `repositoryID` and your public contact email into `artifacthub-repo.yml`,
   then commit.

## Cutting a release

1. Bump the chart's `version` in `charts/<chart>/Chart.yaml` (SemVer) and update its
   `CHANGELOG.md`. (Bump `appVersion` / pin a new `image.digest` if the upstream image
   changed; add an `docs/upgrade.md` note if action is required.)
2. Merge to `main`.
3. Actions → **release** → **Run workflow**.

`chart-releaser` releases every chart whose `version` has no matching release yet
(classic repo `index.yaml` + a GitHub Release with the `.tgz`). The same packages are
then pushed to GHCR as OCI artifacts. Re-running is safe (`CR_SKIP_EXISTING`).

Verify:
```bash
helm install t oci://ghcr.io/ketaloca/charts/hermes-agent --version <X.Y.Z> --dry-run
helm repo add ketaloca https://ketaloca.github.io/ai-agent-helm-charts && helm repo update
helm search repo ketaloca
```

## Pinned tool/action versions

- Helm `v3.16.4`, `helm/chart-releaser-action@v1.6.0` (Renovate keeps these current).
- Trivy is installed via the official script (latest) in `security-scan`.

## Roadmap (Phase 5)

- **cosign** keyless signing of the OCI charts (the workflow already requests
  `id-token: write`); publish the signing key to Artifact Hub (`artifacthub.io/signKey`).
- SLSA provenance attestation; SARIF upload from `security-scan` once GitHub Advanced
  Security is available (public repo).
