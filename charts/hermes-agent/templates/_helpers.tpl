{{/*
Expand the name of the chart.
*/}}
{{- define "hermes-agent.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name (truncated to 63 chars for DNS).
*/}}
{{- define "hermes-agent.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Chart name and version as used by the chart label.
*/}}
{{- define "hermes-agent.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels.
*/}}
{{- define "hermes-agent.labels" -}}
helm.sh/chart: {{ include "hermes-agent.chart" . }}
{{ include "hermes-agent.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: ai-agent-helm-charts
{{- end -}}

{{/*
Selector labels (stable subset — must NOT include version).
*/}}
{{- define "hermes-agent.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hermes-agent.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
ServiceAccount name to use.
*/}}
{{- define "hermes-agent.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "hermes-agent.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Name of the chart-managed (dev) Secret.
*/}}
{{- define "hermes-agent.secretName" -}}
{{- default (include "hermes-agent.fullname" .) .Values.secrets.name -}}
{{- end -}}

{{/*
Resolve the container image reference.
Precedence: digest > tag > Chart.AppVersion. Refuse to default to ":latest".
*/}}
{{- define "hermes-agent.image" -}}
{{- $repo := .Values.image.repository -}}
{{- if not $repo -}}
{{- fail "hermes-agent: image.repository is required" -}}
{{- end -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" $repo .Values.image.digest -}}
{{- else if .Values.image.tag -}}
{{- printf "%s:%s" $repo .Values.image.tag -}}
{{- else if .Chart.AppVersion -}}
{{- printf "%s:%s" $repo .Chart.AppVersion -}}
{{- else -}}
{{- fail "hermes-agent: set image.tag, image.digest, or Chart.appVersion (refusing to default to :latest)" -}}
{{- end -}}
{{- end -}}

{{/*
Non-empty when some dashboard auth provider source is configured. Secrets referenced by
name can't be inspected at render time, so any envFrom source counts as a candidate.
*/}}
{{- define "hermes-agent.dashboardAuthSource" -}}
{{- $providerKeys := list "HERMES_DASHBOARD_BASIC_AUTH_USERNAME" "HERMES_DASHBOARD_OIDC_ISSUER" "HERMES_DASHBOARD_OAUTH_CLIENT_ID" -}}
{{- $names := keys .Values.env -}}
{{- range .Values.extraEnv }}{{ $names = append $names .name }}{{ end -}}
{{- if .Values.secrets.create }}{{ $names = concat $names (keys .Values.secrets.data) }}{{ end -}}
{{- $found := or .Values.dashboard.auth.existingSecret .Values.secrets.existingSecret .Values.extraEnvFrom -}}
{{- range $providerKeys }}{{ if has . $names }}{{ $found = true }}{{ end }}{{ end -}}
{{- if $found }}true{{ end -}}
{{- end -}}

{{/*
Validate safety invariants. Fails the render with a clear message.
*/}}
{{- define "hermes-agent.validate" -}}
{{- if and .Values.persistence.enabled (gt (int .Values.replicaCount) 1) -}}
{{- fail "hermes-agent: persistence.enabled=true requires replicaCount=1 (single-writer /opt/data). Scale out with more releases, not more replicas." -}}
{{- end -}}
{{- if and .Values.persistence.enabled (eq .Values.strategy.type "RollingUpdate") -}}
{{- fail "hermes-agent: strategy.type=RollingUpdate is unsafe with persistence (RWO single-writer). Use Recreate (the default)." -}}
{{- end -}}
{{- if .Values.dashboard.insecure -}}
{{- fail "hermes-agent: dashboard.insecure was removed in chart 0.2.0 — upstream ignores HERMES_DASHBOARD_INSECURE since v2026.7.1 and the dashboard always requires an auth provider. Configure dashboard.auth instead (see docs/upgrade.md)." -}}
{{- end -}}
{{- if and .Values.dashboard.enabled (not (include "hermes-agent.dashboardAuthSource" .)) -}}
{{- fail "hermes-agent: dashboard.enabled=true requires an auth provider (upstream fails closed on a non-loopback bind). Set dashboard.auth.existingSecret, or provide HERMES_DASHBOARD_BASIC_AUTH_* / _OIDC_* / _OAUTH_CLIENT_ID via secrets.existingSecret, secrets.data, extraEnvFrom or env/extraEnv." -}}
{{- end -}}
{{- $keys := list .Values.apiServer.key -}}
{{- if .Values.secrets.create -}}
{{- $keys = append $keys (get .Values.secrets.data "API_SERVER_KEY" | default "" | toString) -}}
{{- end -}}
{{- range $keys -}}
{{- if and . (lt (len .) 16) -}}
{{- fail "hermes-agent: API_SERVER_KEY must be at least 16 characters (upstream refuses to start the API server otherwise). Generate one with `openssl rand -hex 32`." -}}
{{- end -}}
{{- end -}}
{{- if and .Values.ingress.enabled (not .Values.ingress.hosts) -}}
{{- fail "hermes-agent: ingress.enabled=true requires ingress.hosts to be non-empty." -}}
{{- end -}}
{{- end -}}
