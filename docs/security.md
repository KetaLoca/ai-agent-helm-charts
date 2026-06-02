# Security

Why AI agents are a distinct threat class, and how these charts mitigate it.
Full design rationale: [`specs/04-security-model.md`](../specs/04-security-model.md).

## The short version

An agent holds **long-lived credentials**, has **tools that act** (code, web,
shells), and **persists memory/skills**. So: a compromised gateway hands an
attacker the keys *and* the tools, and **prompt injection from any channel it reads
is untrusted input that can drive those tools**. Treat exposure and tool-permission
decisions as security-critical.

## Secure-by-default settings (keep them)

- **No public exposure:** `ingress.enabled: false`, `ClusterIP` Service, dashboard off.
- **API key required** for the gateway; secrets supplied externally (not in Git).
- **Single-writer:** `replicaCount: 1` with persistence; `Recreate` strategy.
- **Hardened pod:** `runAsNonRoot` (UID 10000), `allowPrivilegeEscalation: false`,
  `capabilities: drop [ALL]`, `seccompProfile: RuntimeDefault`, `fsGroup` for the PVC.
- **No K8s API access:** `automountServiceAccountToken: false`, no cluster RBAC.
- **Pinned images:** no silent `:latest` (pin `image.digest` for prod).

These renders aim to pass the **Pod Security Standards "restricted"** profile, except
`readOnlyRootFilesystem: false` (s6-overlay writes to `/run`) — a documented exception.

## Recommended access (instead of a public Ingress)

- **Tailscale** — expose the Service only on your tailnet ([example](../examples/hermes/tailscale-values.yaml)).
- **Cloudflare Tunnel + Access** — identity-aware, no open inbound.
- **Authelia / oauth2-proxy** in front of an internal Ingress ([example](../examples/hermes/ingress-with-auth-values.yaml)).
- **VPN / WireGuard** to a private ClusterIP, or just `kubectl port-forward`.

If you must use a raw Ingress: TLS + auth annotation + IP allow-list **and** still
require the gateway API key.

## Egress control

Enable `networkPolicy` with an **egress allow-list** so a hijacked agent can't reach
arbitrary hosts. **Limitation:** native Kubernetes NetworkPolicy is **L3/L4 only — it
cannot allow-list by hostname.** For per-provider egress use a CNI with FQDN policies
(Cilium), an egress gateway, or a service mesh. See [network-policies.md](network-policies.md).

## Do-not list

- No `hostPath` mounts, no Docker socket, no privileged / `hostNetwork` / `hostPID`.
- No cluster RBAC for the agent SA unless a specific skill needs it (scope it).
- No `:latest` in production.
- Don't enable the dashboard on a public Service; don't set `dashboard.insecure` off a VPN.

## Cloudflare Tunnel (no open inbound)

Expose the gateway through Cloudflare with **zero open inbound ports**: run
`cloudflared` in the cluster pointing at the ClusterIP Service, and gate it with
**Cloudflare Access**.

```yaml
# cloudflared tunnel config (sketch) — deploy via Cloudflare's chart or your manifest.
ingress:
  - hostname: hermes.example.com
    service: http://my-hermes-hermes-agent:8642
  - service: http_status:404
```

Create a Cloudflare Access application for `hermes.example.com` requiring your identity
provider. The chart's `ingress` stays disabled and you still set the gateway API key —
defense in depth.

→ Next: the [production checklist](production-checklist.md).
