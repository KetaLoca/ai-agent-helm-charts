# Changelog

All notable changes to the `hermes-agent` chart are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the chart follows
[SemVer](https://semver.org/) (independent of `appVersion`).

## [0.2.0] - 2026-10-08

### Changed
- **Bump the image** from `v2026.6.19` to `v0.21.6` (`image.digest` →
  `sha256:55e192fb…`). Upstream switched from CalVer to SemVer-only tags with this
  release (`v2026.9.24` was `v0.21.5`).
- **`/tmp` is a default `scratchPaths` tmpfs** (now `[/run, /tmp]`). The image sets
  `XDG_RUNTIME_DIR=/tmp/hermes-runtime`, baked root-owned `0700`, so the non-root user
  can't use it without a fresh tmpfs.
- **NOTES** explain that, with no API key supplied, Hermes generates one into
  `/opt/data/.env` (and how to read it). That `.env` value overrides an environment key
  added later.

### Added
- `dashboard.auth.existingSecret` — Secret with the dashboard auth provider (basic
  password / self-hosted OIDC / Nous OAuth), loaded via `envFrom`.
- `dashboard.publicUrl` → `HERMES_DASHBOARD_PUBLIC_URL` (OAuth/OIDC redirects and
  Host/Origin checks behind an ingress).
- Render-time checks: the dashboard requires an auth provider source, and
  `apiServer.key` / `secrets.data.API_SERVER_KEY` must be >= 16 chars (upstream refuses
  to start the API server otherwise; the schema enforces the same on `apiServer.key`).

### Removed
- **BREAKING: `dashboard.insecure` and `dashboard.insecureAcknowledgeRisk`.** Upstream
  ignores `HERMES_DASHBOARD_INSECURE` since v2026.7.1 and a non-loopback dashboard always
  requires an auth provider, failing closed (restart loop) without one. Setting
  `dashboard.insecure: true` now fails the render with a migration hint.

### Security
- v0.21.6 fixes four dashboard-auth issues reported by Tenable (TRA-725…728): native
  sign-in could send login codes to a non-loopback redirect (session takeover), spoofed
  `X-Forwarded-For` reset the password-login rate limit, unbounded auth audit-log writes,
  and no body-size limit on `/auth/`. Also: untrusted repos could run git
  `clean`/`smudge` filters, and an email-allowlist bypass via quoted display names.
- Earlier in the range: an IDOR on `/resume` / `/sessions`, cross-profile credential
  leaks under multiplex, OAuth token TOCTOU, dependency CVE floors (aiohttp,
  cryptography, starlette, python-multipart) and a concurrent-run cap on the API server.

### Upgrade notes
- **Back up the PVC first** (one-way `state.db` migrations). See
  [docs/upgrade.md](../../docs/upgrade.md#01x--020-app-v2026619--v0216).
- `v0.21.6` (the pinned tag) and upstream's `stable` alias currently point at different
  digests (`stable` = `rc.4-v0.21.6`). The chart pins the release tag. Upstream deferred
  the curated notes for this range to v0.22.0.

## [0.1.5] - 2026-06-26

### Changed
- **Pin the image by digest *by default*.** `values.yaml` now ships
  `image.digest` set to the multi-arch index digest of the pinned `appVersion`
  (`v2026.6.19` → `sha256:9f367c77…`), so every install is immutable out of the box —
  consumers no longer have to resolve and pin a digest themselves. The digest takes
  precedence over the tag (see the `hermes-agent.image` helper); set `image.digest: ""`
  to track the tag instead. **The digest MUST be refreshed together with `appVersion`**
  on every bump — the `revisar-actualizaciones` skill now tracks the pinned digest and
  flags drift, and Renovate keeps it current.

## [0.1.4] - 2026-06-26

### Added
- **`docs/model-providers.md`** — how to give the agent a brain after install. A fresh
  install runs the gateway but has **no model provider**, so it won't answer until you
  configure one. Documents the in-pod flow (`hermes auth add <id>` → `hermes model`), the
  headless OAuth login (`--no-browser --manual-paste`), which providers work with a
  **subscription and no API key** (`openai-codex`, Nous Portal, Copilot, Grok) vs which
  need a key, that Anthropic subscription OAuth is **not permitted** in third-party tools,
  and that credentials persist on the PVC (`HOME` = the data dir). Verified end-to-end on
  a live cluster against `appVersion v2026.6.19`.

### Changed
- **`NOTES.txt`** now points new installs to `docs/model-providers.md` so the
  "running gateway but no brain" state is obvious. No template/runtime behaviour change.

## [0.1.3] - 2026-06-26

### Changed
- **Pin the app image to a real upstream version.** `appVersion` is now `v2026.6.19`
  (Hermes Agent v0.17.0) instead of the floating `latest`. Upstream now publishes
  immutable CalVer release tags, so the chart pins one for reproducible deploys. No
  template/values changes; for stricter immutability still pin `image.digest` in
  production (see [`docs/upgrade.md`](../../docs/upgrade.md)).

### Notes
- v0.17.0 is a feature/security release (new iMessage/Raft/WhatsApp-Cloud channels,
  desktop app, dashboard auth hardening, CVE bumps for `urllib3`/`PyJWT`). It does
  **not** change the container contract this chart models — same gateway port `8642`,
  `/health` endpoint, writable `/run` scratch, and no new required env vars — so this
  is a drop-in pin.

## [0.1.2] - 2026-06-02

### Fixed
- **Boots the real upstream image.** The image's s6-overlay (PID 1) needs a writable
  tmpfs `/run` as the non-root user; the chart now ALWAYS mounts an `emptyDir{medium:
  Memory}` at `scratchPaths` (default `[/run]`). Without it the pod crash-looped with
  `s6-overlay-suexec: fatal ... /run ... unworkable permissions` (affected 0.1.0/0.1.1).
  Verified end-to-end on a live k3s cluster (non-root uid 10000, gateway `/health` 200).

### Added
- Liveness/readiness/startup probes are **enabled by default** against the gateway's
  `/health` endpoint (port 8642, HTTP 200, no auth) — also fixes pods reporting Ready
  while crash-looping.
- `scratchSizeLimit` value (default `128Mi`) for the scratch tmpfs mounts.

## [0.1.1] - 2026-06-02

### Added
- Experimental opt-in: `securityContext.readOnlyRootFilesystem: true` now auto-mounts
  writable `emptyDir` scratch at `scratchPaths` (default `/run`, `/tmp`) so s6-overlay
  can still boot. Example: `examples/hermes/readonly-rootfs-values.yaml`.

### Changed
- Release artifacts are now **cosign-signed** with SLSA build provenance. (`0.1.0`
  was published unsigned due to a registry-auth bug in the release workflow.)

## [0.1.0] - 2026-06-02

### Added
- Initial release of the `hermes-agent` chart.
- `Deployment` running the Hermes gateway with `Recreate` strategy and a hardened
  pod/container security context (`runAsNonRoot` UID 10000, drop `ALL`,
  `allowPrivilegeEscalation: false`, `seccompProfile: RuntimeDefault`).
- Optional `PersistentVolumeClaim` at `/opt/data` (RWO, retained by default),
  optional `/dev/shm` for browser tools.
- `ClusterIP` `Service` on `8642`; gateway binds `0.0.0.0` in-pod with a required
  API key (`apiServer.*`, `secrets.*`, `extraEnvFrom`).
- Optional `Ingress` (off), `NetworkPolicy` (default-deny + egress allow-list),
  `PodDisruptionBudget`, dedicated `ServiceAccount` (no auto-mounted token), and a
  `helm test` connection probe.
- `values.schema.json` and render-time guards enforcing safety invariants:
  `persistence ⇒ replicaCount == 1`, `RollingUpdate` blocked with persistence,
  ingress requires hosts, insecure dashboard requires acknowledgement, and no silent
  `:latest` image reference.
- Examples: minimal, production, private-gateway, ingress-with-auth, external-secrets,
  tailscale.

### Notes
- ConfigMap-based file injection into `/opt/data` is intentionally **deferred** (it
  would collide with the persistence mount). Hermes manages its config inside the data dir.
- Liveness/readiness/startup probes ship **disabled** pending confirmation of the
  upstream health endpoint.
- `appVersion` is `latest` because upstream publishes only `:latest`; **pin `image.digest`**
  for production.
