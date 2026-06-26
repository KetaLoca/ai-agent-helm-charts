---
name: check-upstream-versions
description: >-
  Check whether this repo's charts pin the latest stable upstream versions (Hermes
  Agent image, OpenClaw app image, OpenClaw operator subchart) and, on request, drive
  the update. Use when asked things like: are we on the latest version, check upstream
  / new releases, is hermes or openclaw up to date, check for chart updates, are the
  charts outdated, bump appVersion / image / digest, or update the charts to the latest.
  Runs a deterministic checker (OCI registries + GitHub Releases), then reads the
  changelogs to flag breaking changes that affect the charts.
allowed-tools:
  - Read
  - Grep
  - Glob
  - WebFetch
  - Bash(python3:*)
  - Bash(gh:*)
  - Bash(curl:*)
  - Bash(helm:*)
---

# Check upstream versions

Keep the charts current with their upstream projects. Two phases: **Review** runs by
default; **Update** runs only after the user explicitly approves a bump.

The tracked artifacts and where they're pinned are declared in
[`sources.json`](sources.json) — that file is the single source of truth and the
extension point. Don't hard-code component knowledge here; read it from the manifest.

---

## Phase 1 — Review (default)

Run this and base everything on its output. Never eyeball versions by hand.

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/check_versions.py            # human table
python3 ${CLAUDE_SKILL_DIR}/scripts/check_versions.py --json     # structured, for you to parse
```

The script reads what each chart pins (from `Chart.yaml`), resolves the latest
**stable** version from the real source of truth (GitHub Releases or the OCI registry,
with pagination and prerelease filtering), and prints `current → latest` with a status:

- **OK** — pinned and up to date. Nothing to do.
- **OUT** — pinned but a newer stable release exists.
- **PIN** — unpinned (a floating tag like `latest`). Treat as actionable: recommend pinning.
- **???** — could not resolve upstream (network/repo moved). Investigate before concluding.

What the script does **not** do — this is your job:

1. For every **OUT/PIN** component, open its changelog and read the release notes
   **between `current` and `latest`**. The `--json` output gives `newer_releases`
   (exact tags to read) and `changelog` (URL). Use `WebFetch` on the changelog URL.
2. Classify each relevant change as **chart-affecting or not**. A change matters to us
   only if it touches something the chart models. Look specifically for:
   - **Env vars** added/renamed/removed or newly required → `values.yaml`, `_helpers.tpl`, secret/env wiring.
   - **Ports / health endpoints** changed → `service.yaml`, `probes`.
   - **Entrypoint / args** changed → `deployment.yaml` `command`/`args`.
   - **Writable paths / read-only-rootfs / volumes** → `scratchPaths`, `persistence`.
   - **Security-context** fields newly accepted or rejected (esp. the operator's curated
     CRD) → `securityContext` / `security.podSecurityContext`.
   - **CRD schema / apiVersion** changes (OpenClaw) → `crd-schema/`, `openclawinstance.yaml`, `values.schema.json`.
   - **Min Kubernetes / Helm** version → `Chart.yaml` `kubeVersion`.
   - **Security fixes / CVEs** → call these out; they raise update priority.
3. **Report to the user** (in Spanish): a table of `current → latest`, the
   chart-affecting changes per component with risk level, security/CVE highlights, and a
   recommendation. Then **stop** — do not edit files unless they ask for the update.

See [`reference.md`](reference.md) for the exact file→concern mapping per chart and the
version-scheme gotchas (calver vs semver, the `v` prefix, GHCR pagination).

---

## Phase 2 — Update (only after explicit approval)

Per the repo and global conventions, **never** push/commit and never apply a bump
without an explicit go-ahead. When approved, do it per component. Full checklist in
[`reference.md`](reference.md); the essentials:

**hermes-agent (image bump / pin)**
- Set `appVersion` in `charts/hermes-agent/Chart.yaml` to the new tag (and/or pin
  `image.digest` from the `--digests` run for production immutability).
- Apply any chart-affecting changes found in Phase 1 (new env values, probes, etc.).
- Bump the chart `version` (SemVer: patch/minor/major by impact) and add a
  [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) entry in the chart's `CHANGELOG.md`.
- Update the root `README.md` compatibility table.

**openclaw-instance (app bump)**
- Set `appVersion` in `charts/openclaw-instance/Chart.yaml` to the new app version.
- Usually low-risk (same operator/CRD), but verify the CRD didn't change.
- Bump chart `version`, add a `CHANGELOG.md` entry, update the README table.

**openclaw-instance (operator subchart bump)**
- Update the `openclaw-operator` entry under `dependencies:` in `Chart.yaml`, then
  `helm dependency update charts/openclaw-instance` to refresh `Chart.lock` and the
  vendored `.tgz`.
- If the operator's CRD changed, re-vendor `crd-schema/` and reconcile
  `values.yaml` / `values.schema.json` / templates.

**Validate every bump before reporting done**
```bash
helm lint charts/<chart>
helm template t charts/<chart> >/dev/null            # default values render
# render any examples/* that exercise changed values, too
```
Run the chart's `helm unittest` tests if present (`charts/*/tests/`). Re-run the
checker to confirm the component now shows **OK**. Follow `docs/releasing.md` for the
actual release/tagging flow — this skill prepares the change, it does not publish it.

---

## Extending

To track another chart or image, add a component to [`sources.json`](sources.json)
(see [`reference.md`](reference.md) for the field spec). The engine needs no changes.
Supported `latest.method`: `github-release`, `ghcr-tags`. The checker uses authenticated
`gh` when available (falls back to the anonymous GitHub API) and anonymous GHCR/Docker
Hub tokens for public registries.
