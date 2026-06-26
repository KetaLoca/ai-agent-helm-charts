# Changelog

All notable changes to the `hermes-agent` chart are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the chart follows
[SemVer](https://semver.org/) (independent of `appVersion`).

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
