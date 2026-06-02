# Changelog

All notable changes to the `hermes-agent` chart are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the chart follows
[SemVer](https://semver.org/) (independent of `appVersion`).

## [Unreleased]

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
