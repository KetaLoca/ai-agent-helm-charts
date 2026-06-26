# Reference — revisar-actualizaciones

Deep detail for the skill. `SKILL.md` stays lean; load this when you actually need the
file mapping, the version-scheme rules, or the manifest spec.

## Version-scheme gotchas (why we trust the script, not raw tag lists)

- **Two schemes, one release (Hermes).** `NousResearch/hermes-agent` tags each release
  both as CalVer (`v2026.6.19`) and SemVer (`v0.17.0`). The Docker Hub **image tag is
  the CalVer one, with the `v`** (`v2026.6.19`). Pin that, not `v0.17.0`.
- **`v` prefix differs per registry.** OpenClaw GitHub release tags carry a `v`
  (`v2026.6.10`); the **GHCR image tags do not** (`2026.6.10`). The manifest's
  `image.strip_v` handles this — `image.latest_tag` in the JSON is the *pullable* tag.
  Always pin from `image.latest_tag`, never from the displayed `latest`.
- **Betas exist and look newer.** OpenClaw ships `…-beta.N` ahead of stable. The checker
  filters prereleases (GitHub `prerelease` flag + a `-(alpha|beta|rc|pre|dev|…)` regex),
  so "latest" is the latest **stable**. Don't bump to a beta unless explicitly asked.
- **GHCR `tags/list` is paginated and unordered.** A naive `curl …/tags/list` returns a
  truncated page and can hide the newest tag (this bit us during manual checks). The
  engine follows the `Link: rel="next"` header to fetch all pages, then sorts. For the
  operator we therefore read the **OCI registry** (authoritative for what `helm
  dependency update` pulls), not GitHub Releases.
- **Operator may migrate.** Search results hint at a future home at
  `ghcr.io/openclaw-rocks/charts`. Today `paperclipinc` is active and current. If it
  goes stale, update `components[].latest.repo` (and `dependencies[].repository` in the
  chart) to the new registry.

## File → concern mapping (what to touch when a changelog flags something)

### hermes-agent (`charts/hermes-agent/`)
| Upstream change | Files to reconcile |
|---|---|
| Image version / digest | `Chart.yaml` (`appVersion`), `values.yaml` (`image.tag`/`image.digest`) |
| New / renamed / required env var | `values.yaml` (`env`, `apiServer.*`, `dashboard.*`), `templates/_helpers.tpl`, `templates/deployment.yaml`, `templates/secret.yaml`, `values.schema.json` |
| Health endpoint / port | `values.yaml` (`probes`, `service.port`/`targetPort`), `templates/service.yaml`, `templates/deployment.yaml` |
| Entrypoint / args | `values.yaml` (`command`, `args`) |
| Writable paths / read-only rootfs | `values.yaml` (`scratchPaths`, `securityContext.readOnlyRootFilesystem`, `persistence`) |
| Dashboard auth behavior | `values.yaml` (`dashboard.insecure`, `dashboard.insecureAcknowledgeRisk`), `_helpers.tpl` env mapping |
| Min K8s | `Chart.yaml` (`kubeVersion`) |

### openclaw-instance (`charts/openclaw-instance/`)
| Upstream change | Files to reconcile |
|---|---|
| App image version | `Chart.yaml` (`appVersion`), `values.yaml` (`image.*`) |
| Operator (subchart) version | `Chart.yaml` (`dependencies[].version`), then `helm dependency update` → `Chart.lock` + `charts/*.tgz` |
| CRD schema / apiVersion | `crd-schema/openclaw.rocks_openclawinstances.yaml`, `templates/openclawinstance.yaml`, `values.schema.json`, `values.yaml` (mapped fields) |
| Security-context fields curated by the CRD | `values.yaml` (`security.podSecurityContext`, `security.containerSecurityContext`) — the operator rejected `seccompProfile` in 0.36.x; re-check on operator bumps |
| Operator min K8s | `Chart.yaml` (`kubeVersion`) |
| All-in-one operator values | `values.yaml` (`openclaw-operator:` passthrough block) |

Always re-validate against the live CRD when the operator moves:
`kubectl apply --dry-run=server -f <rendered CR>` (matches how 0.2.1 was verified).

## Full update checklist (Phase 2)

1. Confirm the user approved the specific bump(s).
2. Apply the version change(s) in `Chart.yaml` (`appVersion`). **If the chart pins a
   digest (`digest_pin`, e.g. hermes-agent `values.yaml image.digest`), refresh it to the
   new tag in the SAME bump** — resolve with `crane digest <repo>:<tag>` or
   `docker buildx imagetools inspect <repo>:<tag> --format '{{json .Manifest}}' | jq -r .digest`.
   A stale digest silently pins the OLD image; `--digests` reports it as drift.
3. Apply chart-affecting changes from the changelog (env, probes, CRD, security ctx…).
4. For an operator bump: `helm dependency update charts/openclaw-instance`; re-vendor
   `crd-schema/` if the CRD changed.
5. Bump the chart's own `version` (SemVer by impact: patch = pure version pin, minor =
   new values/behavior, major = breaking values changes).
6. Add a `CHANGELOG.md` entry (Keep a Changelog format; the repo already follows it).
7. Update the root `README.md` compatibility table (chart versions, `appVersion`, min K8s).
8. Update affected `examples/*` and chart `tests/*` (helm-unittest).
9. Validate: `helm lint`, `helm template`, render touched examples, run unit tests.
10. Re-run the checker → component should read **OK**. Report; do not commit/push/release
    unless asked (see `docs/releasing.md`).

## Manifest spec (`sources.json`)

```jsonc
{
  "components": [
    {
      "id":   "short-id",                       // stable identifier
      "title":"Human name (image)",             // shown in the table
      "chart":"hermes-agent",                    // chart dir under charts/
      "kind": "image" | "helm-dependency",
      "current": {                               // where WE pin it (read locally)
        "file":  "charts/<chart>/Chart.yaml",
        "field": "appVersion"                    // a top-level YAML scalar …
        // …OR: "dependency": "openclaw-operator" // a dependencies[].version entry
      },
      "digest_pin": {                            // optional; verify a pinned image digest
        "file": "charts/<chart>/values.yaml",    // (with --digests) matches appVersion
        "key":  "image.digest"                   // "parent.child" or a top-level scalar
      },
      "latest": {                                // upstream source of truth
        "method": "github-release" | "ghcr-tags",
        "repo":   "OWNER/REPO"  or  "ns/charts/name"
      },
      "image": {                                 // optional; for kind=image
        "registry": "dockerhub" | "ghcr",
        "repo":     "ns/name",
        "strip_v":  false                        // true if registry tag drops the v
      },
      "changelog": "https://…/releases",         // where the model reads notes
      "version_scheme": "free text (informational)",
      "notes": "free text shown to the model"
    }
  ]
}
```

Adding a component is the whole extension story — the engine is generic. If a new source
needs a method we don't have yet (e.g. a classic Helm repo `index.yaml`, or Docker Hub
tag listing for "latest"), add a `latest_from_*` resolver in `scripts/check_versions.py`
and wire it in `resolve_latest()`.

## Engine notes (`scripts/check_versions.py`)

- **No third-party deps** (stdlib only): `urllib`, `json`, `re`, `subprocess`.
- **Auth:** GitHub via `gh api` when present (5000 req/h), else anonymous API (60/h).
  GHCR/Docker Hub use anonymous pull tokens (fine for public repos).
- **Flags:** `--json` (structured), `--digests` (resolve image digests for flagged
  components — Docker Hub `tags/<t>` field, GHCR `Docker-Content-Digest` header — AND, for
  components with `digest_pin`, verify the pinned digest matches the CURRENT appVersion,
  reporting `digest_drift`), `--manifest PATH`, `--repo-root PATH`.
- **Exit codes:** `0` all pinned & current · `1` something outdated/unpinned/digest-drift
  (CI-friendly) · `2` manifest/load error.
- **Local read:** targeted parser for top-level scalars, `dependencies[].version`, and
  nested `parent.child` scalars (`read_nested_scalar`, used for `values.yaml image.digest`)
  — no YAML lib needed; robust to comments/quotes/reordering for these simple fields.
