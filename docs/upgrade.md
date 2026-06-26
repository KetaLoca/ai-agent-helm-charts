# Upgrade

Both charts upgrade with `helm upgrade`, and **persistent data is designed to survive
upgrades** (and even `helm uninstall`). The two charts differ in *who* applies the
change: `hermes-agent` is managed directly by the chart, while `openclaw-instance` is
reconciled by the OpenClaw operator.

> Golden rules for any upgrade: **pass your own values** (`-f my-values.yaml` or
> `--reuse-values`), **read the chart `CHANGELOG.md`** (a MAJOR bump may rename/remove
> values), and **back up before a big jump** (see [backup-restore.md](backup-restore.md)).

## Compatibility

| Chart | Chart version | App (image) | Operator | Min K8s | Helm |
|---|---|---|---|---|---|
| `hermes-agent` | `0.1.3` | `nousresearch/hermes-agent` (`appVersion: v2026.6.19`*) | — | `>= 1.25` | `>= 3.8` (4 supported) |
| `openclaw-instance` | `0.2.2` | `ghcr.io/openclaw/openclaw` (`appVersion: 2026.6.10`) | `openclaw-operator 0.36.5` (bundled when `operator.install=true`) | `>= 1.28` | `>= 3.8` |

\* Pinned to an upstream CalVer release. Pin `image.digest` too for maximum immutability
(see "Image pinning").

---

## hermes-agent (managed directly by the chart)

```bash
# See available chart versions (classic repo):
helm repo update && helm search repo ketaloca/hermes-agent --versions
# Upgrade:
helm upgrade my-hermes oci://ghcr.io/ketaloca/charts/hermes-agent \
  --version <new-chart-version> -f my-values.yaml
```

- Review the chart [`CHANGELOG.md`](../charts/hermes-agent/CHANGELOG.md) for breaking
  changes (MAJOR bumps rename/remove values or change defaults).
- **Your data survives.** The PVC is a separate object with a stable name (the release
  name) and carries `helm.sh/resource-policy: keep` (from `persistence.retain: true`),
  so Helm never deletes it — not on upgrade, not on uninstall. The new pod mounts the
  **same** claim and sees `/opt/data` intact (sessions, memory, skills, config, keys).
- **Expect brief downtime:** `strategy: Recreate` stops the old pod before starting the
  new one (required because the RWO PVC has a single writer).
- **Single-writer:** keep `replicaCount: 1`; scale out with **more releases**, not more
  replicas.
- **Gotcha:** changing `persistence.size` on upgrade does **not** resize an existing PVC
  (depends on your StorageClass; usually a manual expansion).

### Image pinning (important)

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

---

## openclaw-instance (managed by the OpenClaw operator)

This chart declares an `OpenClawInstance` CR; the **operator** does the actual work
(creates the pod/PVC, runs rollouts, reconciles). There are two install/upgrade modes:

- **Instance-only** (default): the operator + CRDs are installed separately; this chart
  ships only the CR.
- **All-in-one** (`operator.install=true`): the operator (incl. its CRDs) is bundled as
  a subchart, so a single release manages operator + instance. **Single-tenant /
  once-per-cluster** (the operator is a cluster-wide singleton).

```bash
helm repo update && helm search repo ketaloca/openclaw-instance --versions
helm upgrade my-openclaw oci://ghcr.io/ketaloca/charts/openclaw-instance \
  --version <new-chart-version> -f my-values.yaml          # add --set operator.install=true for all-in-one
```

**What gets updated:**
- **The app image** (`appVersion` → `spec.image`): the upgrade re-applies the CR (a
  post-upgrade hook) and the operator rolls the pod to the new image.
- **In all-in-one, the operator too** — its Deployment **and its CRDs**. The CRDs ship
  as Helm **templates** (`templates/crds/…`), so `helm upgrade` *does* update them (it
  would not for the legacy `crds/` dir). `crds.keep: true` means even an uninstall keeps
  the CRDs.
- **Important:** the operator moves to the version **pinned in the chart**
  (`dependencies: openclaw-operator`), **not** automatically to the latest upstream. It
  only changes when you install a **newer chart version** that bumps that dependency —
  the chart version is your control point.

**What survives:**
- **Your data survives.** The instance PVC is managed by the operator with
  `persistence.orphan: true` (RETAIN). The operator is **stateless**, so updating it
  doesn't touch your data; on upgrade the operator reconciles the same CR and **reuses
  the same PVC**. Double safety net: `orphan` retains the PVC, `crds.keep` retains the
  schema.

**Care:**
- A large operator jump may change the CR schema — when *that* happens the chart bumps
  its vendored `crd-schema/` and reconciles values, so prefer the published chart
  version over mixing versions yourself.
- **Downgrades:** because CRDs are templates, a `helm rollback` may try to revert the CR
  schema. Test first.

### Which model should I use?

The operator (all-in-one / instance-only) earns its complexity when you want its
**production lifecycle features** — managed backups/restore, self-config, native
Tailscale, managed auto-update, observability, per-instance RBAC, cluster defaults, and
orderly multi-instance. For a single simple instance that you just want to `helm
upgrade` like any app, that complexity (cluster-wide singleton, CRDs, RBAC) may not pay
off. Choose by whether you'll actually use what the operator provides.

---

## Downgrade

`helm rollback <release> <revision>`. Data in the PVC is preserved, but:
- if a newer app version migrated on-disk state, a downgrade may not be clean;
- for `openclaw-instance`, rolling back can also revert CRD schema (see above).

Test downgrades in staging first.
