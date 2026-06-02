# 09 — Critical Review Notes (second pass)

> Senior Helm/Kubernetes review of specs `00`–`08`, performed 2026-06-02. Records maintainer decisions baked in, real defects found and fixed inline, items deliberately left as-is, and what remains open. This is an audit trail — the corrections themselves live in the specs they touch.

## A. Maintainer decisions applied

| # | Decision | Specs updated |
|---|---|---|
| D1 | **License = MIT** (was "recommend Apache-2.0"). Trade-off noted: no patent grant. | `01` §6/§8, `02`/`03` `Chart.yaml`, `08` Phase 1 + Q2. |
| D2 | **GHCR owner = `ketaloca`** (personal account; GitHub `KetaLoca`, GHCR lowercased). Handle provided; placeholders filled. | `01` §7, `05`, `08` Q1. |
| D3 | **OpenClaw CI = operator-in-Kind** (chosen gate); CRD-only is an upstream-outage fallback only. | `05` §3/§10, `06` §7, `08` Phase 3 + Q5. |
| D4 | **Repo name kept** `ai-agent-helm-charts`. | `08` Q3. |

## B. Defects found & fixed inline

| # | Finding | Severity | Fix |
|---|---|---|---|
| F1 | **All-empty image ref → silent `:latest`.** With `image.tag`, `image.digest`, and `Chart.yaml appVersion` all empty, the chart would render `repository` with no tag → `:latest`, violating the "no latest" principle. Compounded by the fact that **upstream Hermes only publishes `:latest`** (no semver tag found). | High | `02` §3: image helper `fail`s on all-empty; prod guidance = **pin `image.digest`**. Mirrored in §16 inv.3 and §17. |
| F2 | **ConfigMap mount collides with the PVC.** `02` proposed a ConfigMap mounted at `/opt/data`, the same path as the persistence PVC — Kubernetes can't mount both at one path, and a CM volume would shadow the data dir. | Med | `02` §15 `config`: switch to `subPath` per-file injection (advanced/fragile) and **defer** the feature in v0.x (Hermes manages its own config inside `/opt/data`). |
| F3 | **Internal contradiction in `03`.** §8 says "don't fight the operator; leave fields unset so operator defaults apply," but §7 shipped opinionated `probes` values (enabled + delays), which would override the operator. | Med | `03` §7: `probes: {}` by default (operator owns health checks); override only when needed. |
| F4 | **Ingress vs default-deny NetworkPolicy (OpenClaw).** With `security.networkPolicy.enabled: true` (default) and ingress on, the ingress controller is blocked unless its namespace/CIDR is allow-listed. Silent connectivity failure. | Med | `03` §11: explicit interaction note → must set `allowedIngressNamespaces`; surfaced in NOTES + docs. |
| F5 | **Dashboard had no Service exposure path.** `02` enabled dashboard container port 9119 but the Service only defined 8642, so an enabled dashboard was unreachable in-cluster with no documented way to expose it. | Low/Med | `02` §11/§15: add `dashboard.service` (default false → port-forward); container port added when enabled. |
| F6 | **Schema feasibility over-stated as impossible.** `02` §16 claimed the "persistence ⇒ replicaCount==1" rule couldn't be expressed in JSON Schema. It can (draft-07 `if/then` + `const`), which Helm supports. | Low | `02` §16 inv.2: implement in schema **and** keep the template `fail` guard for RWX edge cases. |
| F7 | **`orphan` semantics unverified but stated as fact.** `03` asserted `orphan: true` ⇒ "keep PVC" without confirming the field's direction. | Low | `03` §7: added `TODO(verify@impl)` to confirm `orphan=true` means RETAIN before trusting the default. |
| F8 | **Overstated value of `topologySpreadConstraints` at replicas=1.** | Trivial | `02` §12: reworded to "no-op at replicas=1; for future multi-replica modes." |

## C. Considered and deliberately NOT changed (with rationale)

- **Hermes `networkPolicy.enabled: false` default** while `04` checklist requires it on in prod. Kept off: not all CNIs enforce NP, and enabling it silently does nothing on some clusters (surprising). The split (off by default, required by the production checklist) is intentional and now explicit.
- **Hermes binds `API_SERVER_HOST=0.0.0.0` by default.** Reconsidered for safety; kept, because inside a pod this is cluster-internal (a ClusterIP Service can't reach `127.0.0.1`), and exposure beyond the cluster still needs Ingress (off) + the mandatory API key + (recommended) NetworkPolicy. Binding loopback would make the Service non-functional.
- **OpenClaw `resources` shipped with a floor** even though §8 says "leave to operator." Kept: an explicit resource floor is good hygiene (prevents unbounded pods) and is a deliberate, documented override — unlike probes, where the operator genuinely knows better.
- **No CPU limit on Hermes** (memory limit only). Kept intentionally to avoid CFS throttling of a bursty agent; documented.
- **`helm install` fails when the OpenClaw CRD is absent.** Kept by design (no hard `lookup`/`Capabilities` gate, which would break `helm template`/GitOps diff); a NOTES preflight + optional Job explain it.

## D. Remaining open questions (still need a human)

Carried from `08` (Q1's account is decided; its handle is still pending):

- **Q1 (handle): RESOLVED (2026-06-02)** — owner handle is `ketaloca`; placeholder filled across specs.
- **Q4:** Spanish translation of README/quick-start in scope, or English-only for v0.x?
- **Q6: RESOLVED (2026-06-02)** — both: OCI primary + classic GitHub Pages repo (+ Artifact Hub for discovery).
- **Q7:** ship Hermes probes off until the health path is verified, then default readiness on — OK?
- **Q8:** cosign signing from v0.1.0, or defer to Phase 5 as planned?
- **Q9:** confirm v0.x scope = two charts only (no operator chart, no umbrella).
- **Q10:** Hermes `appVersion`/image pin — since only `:latest` is published, confirm the **digest** to pin as the verified baseline.

## E. Verdict

Specs `00`–`08` are internally consistent after this pass and **ready to drive implementation of Phase 1 (repo base) + Phase 2 (`hermes-agent`)**. OpenClaw (Phase 3) is also well-specified against the verified CRD, with the few unverified sub-fields (`tailscale`/`ollama`/`gateway`/`autoUpdate`/`selfConfigure`/`backup` internals, `orphan` semantics) routed through `extraSpec` and clearly marked `TODO(verify@impl)` — no invented fields.

**Recommended next action:** provide the GitHub handle (Q1), then proceed to implement Phase 1 + 2.
