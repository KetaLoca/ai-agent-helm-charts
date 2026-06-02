<!-- Thanks for contributing! Unofficial community project — see TRADEMARKS.md. -->

## What & why

<!-- Describe the change and the motivation. Link issues. -->

## Checklist

- [ ] `helm lint`, render, schema, `kubeconform`, and `helm unittest` pass locally.
- [ ] Bumped the affected chart's `version` (SemVer) and updated its `CHANGELOG.md`.
- [ ] Updated `values.yaml` `# --` comments and the chart `README.md` (helm-docs).
- [ ] Added/updated an `examples/` file if a capability changed (rendered in CI).
- [ ] Added a negative test if a new safety invariant was introduced.
- [ ] No secrets, no `:latest` defaults, no new exposing option enabled by default.
- [ ] Updated the relevant `specs/` doc if behavior changed.
