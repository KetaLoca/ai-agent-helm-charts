# Model providers — give the agent a brain

`helm install` brings up a hardened, running Hermes **gateway** — but a fresh install has
**no model provider configured**, so it will accept connections yet won't actually answer
until you wire one. This is by design: the chart deploys the runtime, while Hermes keeps
its application config (model, credentials, channels) **inside its data dir**, not in the
chart (see [why](#why-this-isnt-a-chart-value)).

This page shows how to configure the provider after install, including
**subscription-based logins that need no paid API key**.

> Replace `my-hermes` with your release name and `<ns>` with its namespace throughout.
> The pod/Deployment is `<release>-hermes-agent`.

## TL;DR

```bash
# 1) Open a shell in the running pod
kubectl -n <ns> exec -it deploy/my-hermes-hermes-agent -- /bin/sh

# 2) Add a credential for a provider (interactive). Example: OpenAI/ChatGPT "Codex"
#    subscription via OAuth — no API key. See the provider table below for ids.
hermes auth add openai-codex --type oauth --no-browser --manual-paste

# 3) Pick the default provider + model
hermes model

# 4) Leave the shell, restart so the gateway reloads config
kubectl -n <ns> rollout restart deploy/my-hermes-hermes-agent
```

## Providers: subscription (no API key) vs API key

Hermes can authenticate several providers with an OAuth login tied to an existing
**subscription**, so you don't pay per token. Others need an API key. The table reflects
upstream behaviour at the pinned `appVersion` — always re-check `hermes model` for the
current list.

| Provider (`auth add <id>`) | Subscription login (no API key) | Notes |
|---|---|---|
| `openai-codex` | ✅ OAuth (ChatGPT Plus/Pro) | OpenAI supports Codex OAuth in third-party tools. |
| `nous` (Nous Portal) | ✅ OAuth | First-party portal; also `hermes setup --portal`. |
| `github-copilot` | ✅ OAuth (device code) | Uses a Copilot subscription. |
| `xai` (Grok) | ✅ OAuth (SuperGrok/Premium+) | |
| `openrouter` | ❌ API key only | One key, many models. |
| `anthropic` (Claude) | ⛔ **Not permitted** | Anthropic prohibits subscription (Pro/Max) OAuth in third-party tools (enforced 2026-04-04). Use an **API key** (paid) or Bedrock/Vertex if you need Claude. |

## The headless OAuth flow (no browser in the pod)

The pod has no browser, so OAuth uses `--no-browser --manual-paste`:

1. Run `hermes auth add <id> --type oauth --no-browser --manual-paste`.
2. It prints an authorization URL — open it **on your own machine** and approve.
3. The browser redirects to a `http://127.0.0.1:.../callback?...` URL that **fails to
   load** (that listener lives in the pod, not your machine). Copy that **full** URL.
4. Paste it back into the pod prompt. Done.

Verify:

```bash
hermes auth list
hermes auth status <id>          # e.g. "openai-codex: logged in"
```

### Persistence

Inside the container `HOME` is the data dir (the mounted PVC at `persistence.mountPath`,
default `/opt/data`). Credentials, `config.yaml`, sessions, memory and skills all live
there, so **a provider you configure once survives pod restarts and chart upgrades** (the
PVC is retained — see [upgrade.md](upgrade.md) and [backup-restore.md](backup-restore.md)).

## Pick the model

```bash
hermes model            # interactive: choose provider, then a model
# or the focused wizard:
hermes setup model
```

This sets `model.provider` (and the model) in `config.yaml`. Restart the Deployment so the
gateway reloads it.

## Smoke test

```bash
# In-pod one-shot (no gateway/auth needed):
kubectl -n <ns> exec -it deploy/my-hermes-hermes-agent -- hermes -z "Reply with: OK"

# Or via the gateway API:
kubectl -n <ns> port-forward deploy/my-hermes-hermes-agent 8642:8642
# then POST to http://127.0.0.1:8642 with your API key (OpenAI-compatible).
```

## Fallback chain (resilience / rate limits)

Subscription logins have usage windows. Add fallbacks that Hermes tries when the primary
is exhausted:

```bash
hermes fallback add        # same picker as `hermes model`
hermes fallback list
```

## Channels (Telegram, etc.)

To talk to the agent from a messaging platform, configure the channel in the pod
(`hermes setup gateway`, `hermes whatsapp`, `hermes slack`, …) and **set an allowlist**
(e.g. `TELEGRAM_ALLOWED_USERS=<your_id>`). By default Hermes **denies all users** until an
allowlist exists — keep it that way. Prefer injecting channel tokens via the chart's
`extraEnvFrom` → a Secret rather than plaintext in the data dir.

## Caveats

- **Subscription limits.** Subscription-backed inference has interactive-style usage
  windows (e.g. 5h / weekly). An always-on agent with cron can hit them — pace scheduled
  jobs and configure a fallback.
- **Terms of service.** Subscription OAuth is a provider-specific allowance; running an
  unattended 24/7 agent may stretch the intended use. Check each provider's terms.
- **No bundled `codex` CLI.** The upstream image does not ship the standalone `codex`
  binary, so features that shell out to it aren't available — but `openai-codex` as an
  **inference provider** works regardless. A custom image bundling Codex CLI would be
  needed for the full harness.

## Why this isn't a chart value

ConfigMap-based file injection into the data dir is intentionally **not** shipped: it
would collide with the persistence mount, and Hermes owns `config.yaml` / `SOUL.md` and
rewrites them itself. Configuring the provider in-pod (where it lands on the PVC) is the
supported path. See the chart README "Key decisions".
