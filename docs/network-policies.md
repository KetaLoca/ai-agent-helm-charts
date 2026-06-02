# Network policies

`networkPolicy.enabled: true` renders a **default-deny** policy (ingress + egress)
scoped to the pod, then adds the rules you specify. Requires a CNI that **enforces**
NetworkPolicy (Calico, Cilium, …); on others it silently does nothing.

## Egress allow-list (DNS + HTTPS)

```yaml
networkPolicy:
  enabled: true
  allowDNS: true          # egress to kube-dns on 53
  ingress: []             # deny all ingress (reach via port-forward)
  egress:
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
      ports:
        - protocol: TCP
          port: 443
```

## ⚠️ L4-only limitation

Native Kubernetes NetworkPolicy matches **IPs/ports, not hostnames**. The rule above
allows HTTPS to *anywhere*, not "only api.anthropic.com". For real per-provider egress:

- **Cilium FQDN policies** (`toFQDNs: [{matchName: api.anthropic.com}]`),
- an **egress gateway** with an allow-list, or
- a **service mesh** (Istio/Linkerd) egress policy.

Model these with `extraObjects` or your platform's policy CRDs; the chart's L4 rules
are a floor, not full containment.

## Allowing an ingress controller

If you enable `ingress`, the default-deny policy will block the controller unless you
allow its namespace/pods:

```yaml
networkPolicy:
  enabled: true
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress-nginx
      ports:
        - protocol: TCP
          port: 8642
```

## Restricting to the Tailscale operator

When exposing via Tailscale, allow only the operator namespace to reach the pod
(same pattern as above, with the tailscale operator's namespace).
