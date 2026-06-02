# Installing the OpenClaw operator (prerequisite)

This chart only **declares** an `OpenClawInstance`. The OpenClaw **operator** and its
CRDs must be installed **first** — this chart does not install them.

## Install the operator (Helm OCI)

```bash
helm install openclaw-operator \
  oci://ghcr.io/paperclipinc/charts/openclaw-operator \
  --namespace openclaw-system --create-namespace \
  --set leaderElection.enabled=true
```

Prerequisites:
- Kubernetes **>= 1.28**
- cert-manager — only if you enable the validating/defaulting webhook
- Prometheus Operator — only if you enable ServiceMonitors

> **TODO(verify):** confirm the canonical OCI path and version for your target
> operator release. The mirror `github.com/openclaw-rocks/openclaw-operator`
> publishes the same CRD (`openclaw.rocks/v1alpha1`).

## Verify the CRD before installing instances

```bash
kubectl get crd openclawinstances.openclaw.rocks
```

If this returns the CRD, you can install `openclaw-instance` releases. If not,
`helm install openclaw-instance ...` fails with `no matches for kind "OpenClawInstance"`.

## GitOps ordering

Install the operator and let its CRDs become Established **before** syncing
`openclaw-instance` releases — use Argo CD sync waves or Flux `dependsOn`.
