# Upgrade

## Compatibility

| Chart | App (image) | Min K8s | Helm |
|---|---|---|---|
| `0.1.3` | `nousresearch/hermes-agent` (`appVersion: v2026.6.19`*) | `>= 1.25` | `>= 3.8` (4 supported) |

\* See "Image pinning" below.

## How to upgrade

```bash
helm upgrade my-hermes oci://ghcr.io/ketaloca/charts/hermes-agent \
  --version <new-chart-version> -f my-values.yaml
```

- Review the chart [`CHANGELOG.md`](../charts/hermes-agent/CHANGELOG.md) for breaking
  changes (MAJOR bumps rename/remove values or change defaults).
- The PVC is retained and reused across upgrades, so data survives.
- **Expect brief downtime:** `strategy: Recreate` stops the old pod before starting
  the new one (required because the RWO PVC has a single writer).

## Image pinning (important)

Upstream now publishes **versioned CalVer release tags** (e.g. `v2026.6.19`), so the
chart pins `appVersion` to a specific release instead of tracking `latest`. For
production, **also pin a digest** so the image is fully immutable and you control when
the agent changes:

```bash
# Find the current digest of the tag you've vetted:
docker buildx imagetools inspect nousresearch/hermes-agent:v2026.6.19 --format '{{json .Manifest}}' | jq -r .digest
# or:
crane digest nousresearch/hermes-agent:v2026.6.19
```

```yaml
image:
  digest: "sha256:<the-digest-you-vetted>"
  tag: ""
```

Renovate is configured to open (non-auto-merged) PRs when the upstream image changes,
so digest bumps are reviewed. Re-test in staging before promoting.

## Downgrade

`helm rollback my-hermes <revision>`. Data in the PVC is preserved; if a new app
version migrated on-disk state, a downgrade may not be clean — test first.
