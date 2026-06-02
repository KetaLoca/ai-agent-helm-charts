# Contributing

Thanks for helping improve these charts! This is an unofficial, community
project — see [TRADEMARKS.md](TRADEMARKS.md).

## Ground rules

- **Secure by default.** Don't make an exposing/secret-leaking option the default.
  New risky features must be opt-in and documented (see [specs/04-security-model.md](specs/04-security-model.md)).
- **No secrets in Git.** Examples use placeholders / `existingSecret`.
- **No `:latest` defaults.** Support tag and digest pinning.
- **Design is spec-driven.** Non-trivial changes should align with [`specs/`](specs/);
  update the relevant spec in the same PR when behavior changes.

## Local development

Requirements: `helm >= 3.8` (4 supported), `kubeconform`, `yamllint`,
`helm-unittest` plugin, optionally `helm-docs`, `chart-testing` (`ct`), and `kind`.

```bash
# Lint
helm lint charts/hermes-agent

# Render defaults + every example (must all succeed)
helm template charts/hermes-agent
for f in examples/hermes/*.yaml; do helm template charts/hermes-agent -f "$f" >/dev/null && echo "ok: $f"; done

# Validate rendered manifests
helm template charts/hermes-agent | kubeconform -strict -summary -ignore-missing-schemas

# Unit / snapshot tests
helm plugin install https://github.com/helm-unittest/helm-unittest || true
helm unittest charts/hermes-agent
```

CI (`.github/workflows/lint-test.yaml`) runs the same checks plus a `kubeconform`
matrix across Kubernetes versions and negative-value tests.

## Values & docs

- Document every value with a `# --` comment in `values.yaml` (helm-docs compatible).
- Keep `charts/<chart>/README.md` in sync (CI checks for drift if `helm-docs` runs).
- Add or update an `examples/<agent>/*.yaml` when you add a capability — examples
  are rendered in CI and double as documentation.
- Encode safety invariants in `values.schema.json` and add a negative test.

## Versioning, commits & releases

- **SemVer per chart.** Bump `Chart.yaml: version` on any chart change
  (MAJOR = breaking values/defaults, MINOR = new opt-in features, PATCH = fixes).
- `appVersion` tracks the upstream image; bumping it needs a `CHANGELOG.md` entry
  and a `docs/upgrade.md` note if action is required.
- Update the chart's `CHANGELOG.md` (Keep a Changelog format) in your PR.
- Releases are tag-driven: pushing `'<chart>-vX.Y.Z'` publishes to GHCR (OCI) and
  the classic Pages repo via CI.

## Pull requests

- Keep templates small and readable; match surrounding style.
- Ensure `helm lint`, render, schema, `kubeconform`, and unit tests pass.
- Fill in the PR checklist.
