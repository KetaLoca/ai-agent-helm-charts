# Vendored CRD (reference)

`openclaw.rocks_openclawinstances.yaml` is the **OpenClawInstance** CRD this chart
targets, vendored for reference and (future) CI validation. It is **not** installed
by this chart and **not** packaged into the released chart (`.helmignore` excludes
`crd-schema/`).

- Source: `config/crd/bases/openclaw.rocks_openclawinstances.yaml` from the OpenClaw
  operator (`github.com/paperclipinc/openclaw-operator`, mirror: `openclaw-rocks`).
- Fetched: 2026-06-02. API: `openclaw.rocks/v1alpha1`.

## Regenerating / strict validation (future)

To validate rendered `OpenClawInstance` resources strictly with `kubeconform`,
convert this CRD to JSON schemas and point `kubeconform -schema-location` at them:

```bash
pip install openapi2jsonschema
openapi2jsonschema -o crd-json --kubernetes \
  charts/openclaw-instance/crd-schema/openclaw.rocks_openclawinstances.yaml
# then: kubeconform -schema-location 'crd-json/{{ .ResourceKind }}.json' ...
```

Until then, CI validates the CR structurally via `helm unittest`, and `kubeconform`
runs with `-ignore-missing-schemas` (the CR is skipped, other resources validated).
