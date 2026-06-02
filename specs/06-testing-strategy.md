# 06 — Testing Strategy

> Test layers, tools, and the specific cases each chart must cover. Drives `lint-test.yaml` (`05`).

## 1. Test pyramid

| Layer | Tool | Speed | Gates PR? | What it proves |
|---|---|---|---|---|
| Lint | `helm lint --strict`, `ct lint`, `yamllint` | fast | yes | Chart metadata, version bump, basic correctness. |
| Schema | `values.schema.json` (+ negative cases) | fast | yes | Bad values fail fast; safety invariants hold. |
| Unit/snapshot | `helm-unittest` | fast | yes | Specific rendered fields are exactly right; regressions caught. |
| Render | `helm template` (defaults + all examples + `ci/`) | fast | yes | Every supported config renders; examples never rot. |
| Manifest validation | `kubeconform` (+ vendored CRD) | fast | yes | Output is valid against K8s + CRD OpenAPI across versions. |
| Policy | conftest/Kyverno/PSS or Trivy config | fast | yes | "restricted" PSS compliance modulo documented exceptions. |
| Install smoke | `kind` + `helm install`/`test` | slow | partial | Objects create, PVC binds, CR accepted/reconciles (stubbed images). |
| Runtime (real image) | `kind` + real upstream image | slow/flaky | **no** (nightly/optional) | The actual agent boots & serves. |

## 2. Render tests (must pass for every change)

- `helm template <chart>` with **default** values.
- `helm template <chart> -f examples/<chart>/<each>.yaml` for **every** example file.
- `helm template <chart> -f ci/<each>.yaml` (CI-specific permutations).
- Assert non-empty output and zero template errors. This is the cheapest guard against breakage and keeps `examples/` authoritative.

## 3. Schema tests (positive + negative)

Positive: default `values.yaml` and all examples validate.

**Negative tests (must FAIL render/validation):**

Hermes:
- `persistence.enabled: true` + `replicaCount: 2` → rejected (T7 invariant).
- `ingress.enabled: true` + empty `hosts` → rejected.
- `dashboard.insecure: true` without `dashboard.insecureAcknowledgeRisk: true` → rejected.
- `service.enabled: true` + `apiServer.requireKey: true` + no key source → rejected (or hard NOTES failure).
- Missing `image.repository` → rejected.
- Invalid `service.port` (e.g. 70000) → rejected.
- `strategy.type: RollingUpdate` + `persistence.enabled` (RWO) → rejected/blocked.

OpenClaw:
- `networking.ingress.enabled: true` + empty `hosts` → rejected.
- Wrong type for `extraSpec` (non-object) → rejected.
- Invalid `accessModes`/`persistence.size` → rejected.

Implement negative tests as a script that runs `helm template`/schema and asserts a **non-zero exit** + expected error substring. (helm-unittest can also assert `failedTemplate`/schema failures.)

## 4. Unit / snapshot tests (`helm-unittest`)

Per chart, `tests/*_test.yaml`. Assert exact rendered values for the safety-critical and easily-regressed parts:

Hermes (`tests/deployment_test.yaml`, etc.):
- Default render sets `strategy.type: Recreate` when persistence on.
- Default securityContext: `runAsNonRoot: true`, `runAsUser: 10000`, `allowPrivilegeEscalation: false`, `capabilities.drop:[ALL]`, `seccompProfile.type: RuntimeDefault`.
- `API_SERVER_HOST=0.0.0.0` + `API_SERVER_ENABLED=true` present when `service.enabled`.
- `automountServiceAccountToken: false`.
- PVC carries `helm.sh/resource-policy: keep` when `retain: true`; mountPath `/opt/data`.
- `existingSecret` wired into `envFrom`; `secrets.create` renders a Secret + `envFrom`.
- Ingress absent by default; present with hosts when enabled.
- `/dev/shm` emptyDir present only when `shm.enabled`.
- Labels/selector: selector excludes `version`.

OpenClaw (`tests/openclawinstance_test.yaml`):
- Emits `apiVersion: openclaw.rocks/v1alpha1`, `kind: OpenClawInstance`.
- `metadata.name` = `instance.name` or release fullname.
- Friendly values land at the right CRD paths: `persistence.*` → `spec.storage.persistence.*`; `networkPolicy.*` → `spec.security.networkPolicy.*`; `ingress.*` → `spec.networking.ingress.*`.
- Defaults: `chromium.enabled`, `webTerminal.enabled`, `autoUpdate.enabled`, `selfConfigure.enabled` all **false**; `networking.ingress.enabled: false`; `security.networkPolicy.enabled: true`.
- **`extraSpec` deep-merge** wins on conflict (`mergeOverwrite`): set a modeled field via `extraSpec` and assert it overrides.
- Empty/unset friendly fields are **pruned** (not emitted as empty objects that would clobber operator defaults).

Snapshot tests for full-render stability where helpful (review diffs on change).

## 5. Manifest validation (`kubeconform`)

- Run across `KUBERNETES_VERSION` matrix (e.g. 1.25/1.28/1.31 for Hermes; ≥1.28 for OpenClaw).
- Hermes: standard K8s schemas; assert PDB renders under `policy/v1`, NetworkPolicy under `networking.k8s.io/v1`.
- OpenClaw: validate the CR against the **vendored CRD OpenAPI schema** at `charts/openclaw-instance/crd-schema/openclaw.rocks_openclawinstances.json` (converted from the operator's CRD). If not yet vendored → structural-only check + TODO. Keeping the schema vendored also documents the targeted CRD version.

## 6. Policy tests

- Run rendered output through one of: `conftest` with PSS-restricted Rego, Kyverno CLI with the PSS-restricted policies, or `trivy config`.
- Assert restricted compliance **except** an allow-list of documented exceptions (e.g. Hermes `readOnlyRootFilesystem: false`). Exceptions live in a small `tests/policy-exceptions.yaml` with justifications, reviewed in PRs.

## 7. Install smoke tests (Kind)

See `05` §3. Key cases:

- **Hermes (stubbed image):** install → PVC Bound, Deployment available (with a no-op/stub container or tiny HTTP server), Service reachable in-cluster, `helm test` connection passes. Negative: attempt `replicaCount:2`+persistence install should be impossible (blocked at template).
- **Hermes (real image, nightly/optional):** install real image, wait for gateway, hit health/`/v1/models` with the API key; assert 200. Guarded so Docker Hub flakiness/limits don't fail PRs.
- **OpenClaw (chosen mode — operator in Kind):** install operator+CRDs in Kind → install `openclaw-instance` → assert CR `Accepted` and the operator creates child objects (StatefulSet/Service/PVC). Do not gate on the app pod reaching Running (image pull heavy/flaky).
- **OpenClaw (CRD-only):** resilience fallback only — apply CRD only → assert CR is created/validated by the API server (no reconcile). Used when the operator chart/registry is unavailable so PRs stay green.
- Uninstall: assert retained PVCs survive (`retain`/`orphan: true`) and non-retained are cleaned.

## 8. Image independence in CI (important)

CI must not be hostage to upstream registries:
- **Default PR gate uses stubs** (override `image.repository`/`command`/`args`, or a local `registry`/`kind load` of a tiny image) so render + object-creation + CRD-acceptance run without pulling Hermes/OpenClaw.
- **Real images** run in a **nightly** or **manually dispatched** job, allowed to fail without blocking merges, and report status.
- Pin tags (no `latest`) so nightly runs are reproducible; surface upstream image CVE scans informationally (`05` §4).
- For OpenClaw, pulling the **operator** chart from GHCR is generally reliable; still allow the CRD-only fallback to keep PRs green during upstream outages.

## 9. Test data & fixtures

- `examples/` doubles as the positive corpus.
- `ci/` holds permutations not worth shipping as examples (e.g. `networkpolicy-on-values.yaml`, `external-secret-stub-values.yaml`, `stub-image-values.yaml`).
- Negative cases live under `tests/negative/` (or inline in helm-unittest) with expected error assertions.

## 10. Acceptance: a change is "tested" when

- Lint + schema (incl. negatives) + unit + render + kubeconform + policy all pass in `lint-test.yaml`.
- Affected examples render and (where applicable) install in Kind with stubs.
- For OpenClaw CRD-affecting changes, the vendored schema is updated and the CR validates against it.
- Real-image nightly remains green (or known-failures are triaged), not a merge blocker.
