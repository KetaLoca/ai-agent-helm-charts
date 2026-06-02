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
Validate safety invariants. Fails the render with a clear message.
*/}}
{{- define "hermes-agent.validate" -}}
{{- if and .Values.persistence.enabled (gt (int .Values.replicaCount) 1) -}}
{{- fail "hermes-agent: persistence.enabled=true requires replicaCount=1 (single-writer /opt/data). Scale out with more releases, not more replicas." -}}
{{- end -}}
{{- if and .Values.persistence.enabled (eq .Values.strategy.type "RollingUpdate") -}}
{{- fail "hermes-agent: strategy.type=RollingUpdate is unsafe with persistence (RWO single-writer). Use Recreate (the default)." -}}
{{- end -}}
{{- if and .Values.dashboard.insecure (not .Values.dashboard.insecureAcknowledgeRisk) -}}
{{- fail "hermes-agent: dashboard.insecure=true exposes API keys/sessions without auth. Set dashboard.insecureAcknowledgeRisk=true to confirm you understand the risk." -}}
{{- end -}}
{{- if and .Values.ingress.enabled (not .Values.ingress.hosts) -}}
{{- fail "hermes-agent: ingress.enabled=true requires ingress.hosts to be non-empty." -}}
{{- end -}}
{{- end -}}
