# 04 — Security Model

> The security contract for both charts. Defaults defined here are binding; `02`/`03` implement them. This is intentionally opinionated.

## 1. Why agents are a distinct threat class

These are not stateless web apps. An AI agent:
- **Holds long-lived credentials** (LLM provider keys, Telegram/Slack tokens, sometimes cloud creds) on disk (`/opt/data/.env` for Hermes; Secrets for OpenClaw).
- **Has tools that act** (run code, browse the web, exec shells, call APIs) — so a compromise is RCE-equivalent, and **prompt injection from any channel it reads is an untrusted input that can drive those tools**.
- **Persists memory/skills** that can be poisoned to influence future behavior.
- **Often wants a gateway/dashboard** that, if exposed, hands an attacker the keys and the tools at once.

The charts must make the safe configuration the default and the dangerous one a deliberate, acknowledged choice.

## 2. Threat model (primary threats → mitigations)

| # | Threat | Vector | Chart mitigation (default) |
|---|---|---|---|
| T1 | **Accidental public exposure** of gateway/dashboard | `ingress.enabled`, `LoadBalancer`, dashboard insecure mode | `ingress.enabled: false`; `service.type: ClusterIP`; `dashboard.enabled: false`; `dashboard.insecure` requires explicit ack; NOTES tells users to `port-forward`, not expose. |
| T2 | **API key / secret theft** | Secrets in Git/values, world-readable mounts, exposed dashboard | Prod path = `existingSecret`/External Secrets; in-chart secret creation is dev-only & loudly flagged; dashboard off; `automountServiceAccountToken: false`. |
| T3 | **Prompt injection → tool abuse** | Malicious content via web/chat channels driving dangerous tools | Out of chart scope to fully fix, but: restrict **egress** (NetworkPolicy) so a hijacked agent can't reach arbitrary hosts; keep dangerous tools (chromium, webTerminal, docker) off by default; document the risk prominently. |
| T4 | **Dangerous tools enabled by default** | Headless browser, shell, code exec, docker socket | `chromium`/`webTerminal` off (OpenClaw); **never** mount the Docker socket or `hostPath`; no `HERMES_DOCKER_EXEC_AS_ROOT`. |
| T5 | **Filesystem tampering / escape** | Writable rootfs, privilege escalation, capabilities | `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `runAsNonRoot`, `seccompProfile: RuntimeDefault`; `readOnlyRootFilesystem` where compatible. |
| T6 | **Unrestricted egress** | Agent exfiltrates data / reaches internal services / C2 | NetworkPolicy with **egress allow-list** (DNS + only the LLM/provider endpoints needed); documented examples. |
| T7 | **Unsafe scaling / shared state** | `replicaCount>1` on one RWO PVC; two writers corrupt state | Schema forbids `persistence.enabled + replicaCount>1` (Hermes); `Recreate` strategy; document operator StatefulSet single-writer for OpenClaw. |
| T8 | **Mutable/`latest` images** | Supply-chain drift, surprise breakage | No `latest` default; tag inherits `appVersion`; **digest pinning** supported; Renovate PRs reviewed. |
| T9 | **K8s API abuse from the pod** | Mounted SA token + RBAC lets a hijacked agent touch the cluster | `automountServiceAccountToken: false`; no extra RBAC unless explicitly required and scoped. |
| T10 | **Agent self-modification / auto-update** | `selfConfigure`/`autoUpdate` let the agent change config or pull new images | Off by default (OpenClaw); documented as a privilege escalation / supply-chain surface. |
| T11 | **State loss masquerading as security event** | `helm uninstall` deletes PVC with keys/memory | `retain`/`orphan: true` defaults; backup guidance. |
| T12 | **Cross-tenant bleed** | Shared namespace/secrets across instances | One release per tenant; per-instance Secret; namespace-scoped NetworkPolicy; document namespace-per-tenant. |

## 3. Secure-by-default settings (the floor)

Both charts ship these unless the user explicitly opts out:

- **Exposure:** `ingress.enabled: false`; ClusterIP services; dashboards/terminals off.
- **Secrets:** external by default; dev-only in-chart creation is flagged; CORS most-restrictive.
- **Pod security (target: restricted PSS):**
  - `runAsNonRoot: true` (Hermes UID 10000; OpenClaw 1000 — adjustable)
  - `allowPrivilegeEscalation: false`
  - `capabilities.drop: [ALL]`
  - `seccompProfile.type: RuntimeDefault`
  - `fsGroup` set so PVC is writable
  - `readOnlyRootFilesystem`: see §4 (Hermes s6 caveat)
- **Identity:** `automountServiceAccountToken: false`; dedicated ServiceAccount per release; no cluster RBAC granted.
- **Network:** NetworkPolicy available; for OpenClaw the operator ships **default-deny** (kept on). Egress allow-listing documented.
- **Images:** pinned (tag→digest), `IfNotPresent`.
- **Agent autonomy:** self-config / auto-update / extra tools off by default.

> **Target compliance:** renders should pass the **Pod Security Standards "restricted"** profile and common Kyverno/OPA baselines *except* where an explicit, documented opt-out is taken (e.g. `readOnlyRootFilesystem: false` for Hermes s6). CI runs a policy scan (`05`/`06`).

## 4. What hardening can break — and the explicit override

Hardening that can break the agent, with the safety valve:

| Hardening | What may break | Override / mitigation |
|---|---|---|
| `readOnlyRootFilesystem: true` | **Hermes s6-overlay (PID 1) writes to `/run`**; breaks boot. OpenClaw may write scratch. | Default **off** for Hermes. Offer opt-in that auto-mounts `emptyDir` at `/run` + `/tmp`; **TODO(verify@impl)**. For OpenClaw, leave operator default; expose override. |
| `runAsNonRoot` / fixed `runAsUser` | If PVC has root-owned data from a prior run, UID 10000 can't write. | `fsGroup` + `fsGroupChangePolicy: OnRootMismatch`; or `HERMES_UID/GID` remap (keep values + env consistent). |
| `capabilities.drop:[ALL]` | Tools needing specific caps (rare) fail. | `securityContext.capabilities.add: [...]` override, documented as a regression of posture. |
| **NetworkPolicy egress allow-list** | Agent can't reach an LLM/provider endpoint or a tool's target → silent tool failures. | Ship example egress rules for common providers; document how to add hosts; `allowDNS: true`. |
| Strict CORS / `requireKey` | Browser dashboards / external clients blocked. | Configurable `corsOrigins`; key via secret. |
| `automountServiceAccountToken: false` | A skill that needs the K8s API fails. | Explicit opt-in + scoped Role; treated as an audited change. |
| `seccompProfile: RuntimeDefault` | Rarely blocks syscalls (e.g. some FUSE/ptrace tools). | Override to `Unconfined` only with justification. |
| `shm` not mounted | Playwright/Chromium crash (no `/dev/shm`). | `shm.enabled: true` (Hermes) / `chromium` resources (OpenClaw). |

**Principle:** every hardened default is **overridable through values**, but the *default* is the safe one and the override is documented as a deliberate trade-off.

## 5. Recommended architecture (beyond the chart)

The charts deliberately make raw public Ingress the hard path. Recommended access patterns, in `docs/security.md`:

- **Access / authN (instead of public Ingress):**
  - **Tailscale** (OpenClaw has a native `tailscale` CRD field; Hermes via a Tailscale sidecar / subnet router) — preferred for personal/small-team.
  - **Cloudflare Tunnel + Cloudflare Access** (identity-aware, no open inbound).
  - **Authelia / oauth2-proxy** in front of an internal Ingress (forward-auth annotations).
  - Plain VPN / WireGuard to a private ClusterIP.
  - If Ingress is unavoidable: TLS + auth annotation + IP allow-list + rate limiting, and **still** require the gateway API key.
- **Secrets management:**
  - **External Secrets Operator** (AWS/GCP/Vault/etc.), **Sealed Secrets**, or **SOPS** (+ Flux/Argo plugin). Examples in `docs/external-secrets.md`. Never commit plaintext.
- **Backups:**
  - **Velero** (+ restic/Kopia) for the PVC (`/opt/data`, OpenClaw data PVC). Schedule + test restores. `docs/backup-restore.md`.
- **Do-not list (enforced by defaults/docs):**
  - **No `hostPath`** mounts (save narrowly justified, documented cases).
  - **No Docker socket** mount; no `HERMES_DOCKER_EXEC_AS_ROOT`.
  - **No cluster RBAC** for the agent SA unless a specific skill needs it, scoped to the namespace.
  - **No privileged/`hostNetwork`/`hostPID`** pods.
  - **No `latest`** in production.

## 6. Egress policy reference (T6) — example

Ship as a documented example (`docs/network-policies.md`), enabled via `networkPolicy.egress` (Hermes) / `extraNetworkPolicy` (OpenClaw):

```yaml
# Allow only DNS + HTTPS to named LLM providers; deny everything else.
egress:
  - to: []                      # DNS
    ports: [{ protocol: UDP, port: 53 }, { protocol: TCP, port: 53 }]
  - to:
      - ipBlock: { cidr: 0.0.0.0/0 }   # NOTE: K8s NP can't match by hostname.
    ports: [{ protocol: TCP, port: 443 }]
    # For true per-host egress control, use a CNI/L7 policy (Cilium FQDN, Istio) — documented.
```

> **Limitation (document it):** native Kubernetes NetworkPolicy is L3/L4 only — it **cannot allow-list by hostname**. True per-provider egress requires Cilium FQDN policies, an egress gateway, or a service mesh. The chart provides L4 rules and clearly states this limit so users don't get a false sense of containment.

## 7. Production security checklist

Mirrored in `docs/production-checklist.md`; CI policy-scans enforce the mechanizable subset.

- [ ] Image pinned by **digest** (not tag, never `latest`).
- [ ] Secrets via `existingSecret` / External Secrets; **no plaintext in Git or values**.
- [ ] `ingress.enabled: false` **or** fronted by identity-aware proxy + TLS + auth + rate-limit.
- [ ] Gateway **API key set** (Hermes `API_SERVER_KEY`); dashboard off or behind auth.
- [ ] `replicaCount: 1` with persistence (Hermes); single-writer respected (OpenClaw StatefulSet).
- [ ] `strategy: Recreate` with persistence (Hermes).
- [ ] PodSecurityContext: `runAsNonRoot`, `fsGroup`, `seccompProfile: RuntimeDefault`.
- [ ] ContainerSecurityContext: `allowPrivilegeEscalation: false`, `drop:[ALL]`.
- [ ] `readOnlyRootFilesystem` evaluated (on where compatible; off documented for Hermes s6).
- [ ] `automountServiceAccountToken: false`; no cluster RBAC for the agent.
- [ ] NetworkPolicy enabled; **egress allow-list** in place (+ awareness of L4 limitation).
- [ ] No `hostPath`, no Docker socket, no privileged/hostNetwork.
- [ ] `chromium`/`webTerminal`/`selfConfigure`/`autoUpdate` **off** unless explicitly needed.
- [ ] Resource requests/limits set; `/dev/shm` provided if browser tools used.
- [ ] PVC `retain`/`orphan: true`; **backups scheduled and a restore tested**.
- [ ] Namespace-per-tenant (or strong NetworkPolicy isolation) for multi-tenant.
- [ ] PDB sized so it doesn't wedge node drains (beware `minAvailable:1` at replicas 1).
- [ ] Monitoring/log shipping; alert on pod restarts and egress anomalies.
- [ ] Upgrade tested in staging; changelog/`upgrade.md` reviewed for breaking changes.

## 8. SECURITY.md (repo)

- Coordinated disclosure contact + response expectations.
- Supported versions table (which chart minors get security fixes).
- Explicit statement: charts harden **deployment**; they cannot fix vulnerabilities in upstream agent code or prevent prompt-injection-driven tool misuse — users own tool-permission and channel-trust decisions.
- Link to this spec's checklist.
