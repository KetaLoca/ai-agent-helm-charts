# Changelog

All notable changes to the `openclaw-instance` chart are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the chart follows
[SemVer](https://semver.org/) (independent of the operator/app versions).

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
