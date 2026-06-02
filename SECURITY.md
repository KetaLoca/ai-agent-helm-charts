# Security Policy

## Reporting a vulnerability

Please report security issues **privately** — do not open a public issue for an
unfixed vulnerability.

- Preferred: open a [GitHub Security Advisory](https://docs.github.com/en/code-security/security-advisories)
  on this repository (Security → Report a vulnerability), or
- Contact the repository owner privately.

Please include affected chart + version, a description, and reproduction steps.
This is a volunteer-maintained project; we will acknowledge and triage reports as
promptly as is reasonable.

## Supported versions

While the project is in `v0.x`, only the **latest minor** of each chart receives
fixes. Pre-`1.0` minors may include breaking changes (documented in each chart's
`CHANGELOG.md` and `docs/upgrade.md`).

| Chart | Supported |
|---|---|
| `hermes-agent` | latest `0.x` minor |

## Scope & shared responsibility

These charts harden the **deployment** of third-party AI agents. They **cannot**:

- fix vulnerabilities in the upstream agent code or container images;
- prevent **prompt-injection-driven tool misuse** — if you expose the agent to
  untrusted input and give it powerful tools, that is your risk to manage;
- make an intentionally exposed, unauthenticated gateway/dashboard safe.

You own the decisions about **tool permissions, channel trust, secret
management, network egress, and exposure**. The defaults are conservative; review
[docs/security.md](docs/security.md) and the
[production checklist](docs/production-checklist.md) before going to production.

## Good defaults you should keep

- No public Ingress; `ClusterIP` only; dashboard off.
- API key required for the gateway; secrets supplied externally (not in Git).
- `replicaCount: 1` with persistence; `Recreate` strategy.
- Hardened pod/container security context; no auto-mounted ServiceAccount token.
- Pinned images (prefer digests); NetworkPolicy with an egress allow-list in prod.
