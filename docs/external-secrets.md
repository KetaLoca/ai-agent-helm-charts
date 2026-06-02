# External secrets

Never commit API keys. Produce a Kubernetes `Secret` (named e.g. `hermes-secrets`)
from your secret manager, then reference it:

```yaml
secrets:
  existingSecret: hermes-secrets   # must contain API_SERVER_KEY (+ provider keys)
# or, for several managed secrets:
extraEnvFrom:
  - secretRef: { name: hermes-gateway-key }
  - secretRef: { name: llm-provider-keys }
```

The chart loads these via `envFrom`, so the keys become environment variables
(`API_SERVER_KEY`, `ANTHROPIC_API_KEY`, …).

## External Secrets Operator (ESO)

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: hermes-secrets
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: my-store        # your SecretStore/ClusterSecretStore (Vault, AWS, GCP, …)
    kind: ClusterSecretStore
  target:
    name: hermes-secrets  # -> secrets.existingSecret: hermes-secrets
  data:
    - secretKey: API_SERVER_KEY
      remoteRef: { key: hermes/gateway, property: api_server_key }
    - secretKey: ANTHROPIC_API_KEY
      remoteRef: { key: hermes/providers, property: anthropic }
```

## Sealed Secrets

```bash
kubectl create secret generic hermes-secrets \
  --from-literal=API_SERVER_KEY="$(openssl rand -hex 24)" \
  --dry-run=client -o yaml \
| kubeseal --format yaml > hermes-sealedsecret.yaml   # safe to commit
```
Apply the SealedSecret; the controller materializes `hermes-secrets`.

## SOPS (with Flux or the helm-secrets plugin)

Encrypt a values/secret file with `sops` (age/KMS) and decrypt at apply time
(Flux `decryption.provider: sops`, or `helm secrets`). Commit only the encrypted file.

> Whichever tool you use, the chart just consumes the resulting `Secret`. Keep
> `apiServer.key` empty in production.
