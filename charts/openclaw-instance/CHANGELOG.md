# Changelog

All notable changes to the `openclaw-instance` chart are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the chart follows
[SemVer](https://semver.org/) (independent of the operator/app versions).

## [0.3.0] - 2026-10-08

### Changed
- **Bump the targeted OpenClaw app image** from `2026.6.10` to `2026.8.35` (latest
  `extended-stable` of the 2026.8 line). **Not 2026.9.x yet:** 2026.9.x `fchmod`s its
  state directory — the PVC root, owned by `root` on block storage — so `doctor --fix`
  fails with `EPERM` and the pod crash-loops with operator `0.40.0`. The fix
  (openclaw-operator #608, an `init-data-owner` init container) is merged upstream but
  unreleased; the chart moves to 2026.9.x with the operator release that ships it.
- **Bump the bundled operator** (`operator.install=true`) from `openclaw-operator`
  `0.36.5` to `0.40.0`, and re-vendor `crd-schema/` from the operator `v0.40.0` CRD (the
  vendored copy predated 0.36.5). The CRD change is additive only: new optional fields
  (`probes.diskReadiness`, `workspace.fileUpdatePolicy`/`managedFiles`, `netbird`,
  `gateway.image`/`resources`, `runtimeDeps.uvImage`, metrics collector, …), nothing
  removed or newly required; `podSecurityContext`/`containerSecurityContext` keys are
  unchanged (still no `seccompProfile`).
- **Startup probe budget widened** to 10 min (`probes.startup.failureThreshold: 120`,
  was the operator default of 300s): the gateway applies doctor config migrations and
  one-way state migrations at startup.

### Fixed
- **Chromium + new app crash-loop.** Operator `0.36.x` injects browser config keys
  (`browser.remoteCdpTimeoutMs`, `browser.profiles.*.color`) that OpenClaw `>= 2026.8.1`
  rejects; operator `0.40.0` stops emitting them. In instance-only mode, upgrade your
  operator to `>= 0.40.0` together with this chart.

### Security
- The app range carries many hardening fixes: browser relay/CDP credential and host
  pinning, device tokens sent only to loopback, credential egress closed at run end,
  exec deny failing closed, a patched DOMPurify (GHSA-cmwh-pvxp-8882) and dependency CVE
  updates (Sharp/libheif, Undici, Nodemailer); the 2026.8.33–8.35 backports add secret
  egress, scoped node tokens and Prometheus scrape authorization fixes. 2026.6.11 also
  fixes a gateway stall in Kubernetes pods with many injected env vars.

### Upgrade notes
- **Back up the PVC first** — one-way state migrations; no rollback to 2026.6.x.
- **Control UI browsers now need a one-time device pairing** (operator `0.40.0` stops
  injecting the retired `gateway.controlUi.dangerouslyDisableDeviceAuth`).
- Retired keys in `config.raw` crash-loop the pod (the operator re-applies them after
  doctor strips them), and several defaults became more permissive. See
  [docs/upgrade.md](../../docs/upgrade.md#02x--030-app-2026610--2026835-operator-0365--0400).
- Validated on a real cluster (k3s, `local-path` PVC): all-in-one install with operator
  `0.40.0` + app `2026.8.35` → instance `Running`/`Ready`, `/healthz` and `/readyz` 200.

## [0.2.2] - 2026-06-26

### Changed
- **Bump the targeted OpenClaw app image** from `2026.2.3` to `2026.6.10`. The chart is
  a thin CR emitter, so this only changes `spec.image`; the CR schema is governed by the
  operator (`0.36.5`, unchanged) and remains valid. Low-risk drop-in — no CRD, values,
  or template changes.

### Notes
- The range (≈25 releases) is feature/fix work plus a security round (rejects unsafe
  OAuth/token lifetimes and oversized response bodies, DOMPurify XSS patch in the UI,
  `configure` fails closed without a TTY). No new required env vars, ports, probes, or
  `securityContext` fields; `seccompProfile` stays operator-curated (still omitted here).
- Heads-up if you back the PVC with **NFS**: newer OpenClaw avoids SQLite WAL on network
  filesystems; the default RWO block volume is unaffected.

## [0.2.1] - 2026-06-25

### Fixed
- **All-in-one install now works.** When `operator.install=true`, the `OpenClawInstance`
  is applied as a `post-install`/`post-upgrade` hook so it lands **after** the bundled
  operator CRDs exist (Helm validates the main manifest before the CRD is created, which
  made `0.2.0` fail with `no matches for kind "OpenClawInstance"`).
- **CR rejected by the operator's CRD schema.** Removed `security.podSecurityContext.seccompProfile`
  from the defaults: openclaw-operator `0.36.x` curates `podSecurityContext` and does not
  accept that field (it applies seccomp itself). Validated against the live CRD with
  `kubectl apply --dry-run=server`. This affected the default CR-emitter mode too.

## [0.2.0] - 2026-06-25

### Added
- **All-in-one mode** (`operator.install`, default `false`): optionally bundle and install
  the official OpenClaw operator (incl. its CRDs) as a subchart dependency, so a single
  `helm install` brings up the operator and this instance. Tune it via the
  `openclaw-operator:` values key. **Single-tenant / once-per-cluster** — the operator is a
  cluster-wide singleton; for multi-tenant keep this off and install the operator once.
- Example `examples/openclaw/allinone-values.yaml`.

### Notes
- Default behaviour is unchanged: with `operator.install=false` the chart remains a pure
  CR emitter and the dependency is not rendered. The operator's admission webhook is off by
  default, so co-installing the CR in one release is safe.

## [0.1.1] - 2026-06-02

### Changed
- Release artifacts are now **cosign-signed** with SLSA build provenance. (`0.1.0`
  was published unsigned due to a registry-auth bug in the release workflow.) No chart changes.

## [0.1.0] - 2026-06-02

### Added
- Initial release of the `openclaw-instance` chart.
- Emits an `OpenClawInstance` (`openclaw.rocks/v1alpha1`) from a friendly, validated
  values surface mapped onto the CRD `spec` (verified against the operator's CRD).
- `extraSpec` escape hatch: an arbitrary object deep-merged into `spec` (overrides
  modeled fields) for forward-compatibility with unmodeled/newer CRD fields.
- Empty/unset sections are pruned so the operator's own defaults apply.
- Conservative secure defaults: `networking.ingress` off; `chromium`, `webTerminal`,
  `autoUpdate`, `selfConfigure` off; `security.networkPolicy` on; `serviceMonitor` off.
- Optional dev `Secret`, file-based `ConfigMap`, and a supplementary `NetworkPolicy`.
- Render-time guards: `image.repository` required; `networking.ingress` requires hosts.
- Vendored target CRD under `crd-schema/` (reference; excluded from the packaged chart).
- Examples: minimal, production, external-secrets, tailscale; operator install notes.

### Notes
- This chart does **not** install the operator or its CRDs (assumed present).
- A `helm test` and strict `kubeconform` CRD validation are deferred: the former needs
  the operator + RBAC; the latter needs the CRD converted to JSON schema. The CR is
  validated structurally via `helm unittest`.
- `appVersion` (`2026.2.3`) is the targeted OpenClaw app image; pin `image.digest` for prod.
- Sub-fields of `tailscale`, `autoUpdate`, `selfConfigure`, `chromium`, `gateway`,
  `backup`, `workspace` are passed through (not individually modeled) — verify against
  your operator's CRD version or use `extraSpec`.
