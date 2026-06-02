{{/*
Chart name.
*/}}
{{- define "openclaw-instance.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Fully qualified app name.
*/}}
{{- define "openclaw-instance.fullname" -}}
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
The OpenClawInstance object name (and downstream resource prefix).
*/}}
{{- define "openclaw-instance.instanceName" -}}
{{- default (include "openclaw-instance.fullname" .) .Values.instance.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "openclaw-instance.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "openclaw-instance.labels" -}}
helm.sh/chart: {{ include "openclaw-instance.chart" . }}
app.kubernetes.io/name: {{ include "openclaw-instance.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: ai-agent-helm-charts
{{- end -}}

{{- define "openclaw-instance.secretName" -}}
{{- printf "%s-secret" (include "openclaw-instance.fullname" .) -}}
{{- end -}}

{{- define "openclaw-instance.configMapName" -}}
{{- printf "%s-config" (include "openclaw-instance.fullname" .) -}}
{{- end -}}

{{/*
Validate inputs (fails the render with a clear message).
*/}}
{{- define "openclaw-instance.validate" -}}
{{- if not .Values.image.repository -}}
{{- fail "openclaw-instance: image.repository is required." -}}
{{- end -}}
{{- if and .Values.networking.ingress.enabled (not .Values.networking.ingress.hosts) -}}
{{- fail "openclaw-instance: networking.ingress.enabled=true requires networking.ingress.hosts to be non-empty." -}}
{{- end -}}
{{- end -}}

{{/*
Build the modeled OpenClawInstance .spec from friendly values, as YAML.
Empty/unset sections are omitted so the operator's own defaults apply.
The caller deep-merges .Values.extraSpec on top (extraSpec wins).
*/}}
{{- define "openclaw-instance.modeledSpec" -}}
{{- with .Values.registry }}
registry: {{ . | quote }}
{{- end }}
image:
  repository: {{ .Values.image.repository | quote }}
  {{- if .Values.image.digest }}
  digest: {{ .Values.image.digest | quote }}
  {{- else if .Values.image.tag }}
  tag: {{ .Values.image.tag | quote }}
  {{- else if .Chart.AppVersion }}
  tag: {{ .Chart.AppVersion | quote }}
  {{- end }}
  pullPolicy: {{ .Values.image.pullPolicy }}
  {{- with .Values.image.pullSecrets }}
  pullSecrets:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- if or .Values.config.raw .Values.config.configMapRef .Values.config.fromFiles .Values.config.mergeMode .Values.config.format }}
config:
  {{- if .Values.config.fromFiles }}
  configMapRef: {{ include "openclaw-instance.configMapName" . }}
  {{- else if .Values.config.configMapRef }}
  configMapRef: {{ .Values.config.configMapRef | quote }}
  {{- end }}
  {{- with .Values.config.raw }}
  raw:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.config.mergeMode }}
  mergeMode: {{ . | quote }}
  {{- end }}
  {{- with .Values.config.format }}
  format: {{ . | quote }}
  {{- end }}
{{- end }}
{{- with .Values.skills }}
skills:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.plugins }}
plugins:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.env }}
env:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- $envFrom := default (list) .Values.envFrom }}
{{- if .Values.secrets.existingSecret }}{{- $envFrom = append $envFrom (dict "secretRef" (dict "name" .Values.secrets.existingSecret)) }}{{- end }}
{{- if .Values.secrets.create }}{{- $envFrom = append $envFrom (dict "secretRef" (dict "name" (include "openclaw-instance.secretName" .))) }}{{- end }}
{{- if $envFrom }}
envFrom:
  {{- toYaml $envFrom | nindent 2 }}
{{- end }}
{{- with .Values.resources }}
resources:
  {{- toYaml . | nindent 2 }}
{{- end }}
security:
  {{- with .Values.security.podSecurityContext }}
  podSecurityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.security.containerSecurityContext }}
  containerSecurityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  networkPolicy:
    enabled: {{ .Values.security.networkPolicy.enabled }}
    allowDNS: {{ .Values.security.networkPolicy.allowDNS }}
    {{- with .Values.security.networkPolicy.allowedIngressNamespaces }}
    allowedIngressNamespaces:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with .Values.security.networkPolicy.allowedIngressCIDRs }}
    allowedIngressCIDRs:
      {{- toYaml . | nindent 6 }}
    {{- end }}
  rbac:
    createServiceAccount: {{ .Values.security.rbac.createServiceAccount }}
  {{- with .Values.security.caBundle }}
  caBundle: {{ . | quote }}
  {{- end }}
storage:
  persistence:
    enabled: {{ .Values.persistence.enabled }}
    {{- if .Values.persistence.enabled }}
    {{- with .Values.persistence.storageClass }}
    storageClass: {{ . | quote }}
    {{- end }}
    size: {{ .Values.persistence.size | quote }}
    accessModes:
      {{- toYaml .Values.persistence.accessModes | nindent 6 }}
    {{- with .Values.persistence.existingClaim }}
    existingClaim: {{ . | quote }}
    {{- end }}
    orphan: {{ .Values.persistence.orphan }}
    {{- end }}
{{- if .Values.chromium.enabled }}
chromium:
  {{- toYaml .Values.chromium | nindent 2 }}
{{- end }}
{{- if .Values.tailscale.enabled }}
tailscale:
  {{- toYaml .Values.tailscale | nindent 2 }}
{{- end }}
{{- with .Values.ollama }}
ollama:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- if .Values.webTerminal.enabled }}
webTerminal:
  {{- toYaml .Values.webTerminal | nindent 2 }}
{{- end }}
networking:
  service:
    type: {{ .Values.networking.service.type }}
    {{- with .Values.networking.service.annotations }}
    annotations:
      {{- toYaml . | nindent 6 }}
    {{- end }}
  {{- if .Values.networking.ingress.enabled }}
  ingress:
    {{- toYaml .Values.networking.ingress | nindent 4 }}
  {{- end }}
{{- with .Values.probes }}
probes:
  {{- toYaml . | nindent 2 }}
{{- end }}
observability:
  metrics:
    enabled: {{ .Values.observability.metrics.enabled }}
    {{- if .Values.observability.metrics.enabled }}
    port: {{ .Values.observability.metrics.port }}
    {{- if .Values.observability.metrics.serviceMonitor.enabled }}
    serviceMonitor:
      enabled: true
      interval: {{ .Values.observability.metrics.serviceMonitor.interval | quote }}
      {{- with .Values.observability.metrics.serviceMonitor.labels }}
      labels:
        {{- toYaml . | nindent 8 }}
      {{- end }}
    {{- end }}
    {{- end }}
  logging:
    level: {{ .Values.observability.logging.level | quote }}
    format: {{ .Values.observability.logging.format | quote }}
{{- $av := .Values.availability }}
{{- if or $av.podDisruptionBudget.enabled $av.nodeSelector $av.tolerations $av.affinity $av.topologySpreadConstraints $av.runtimeClassName $av.autoScaling }}
availability:
  {{- if $av.podDisruptionBudget.enabled }}
  podDisruptionBudget:
    enabled: true
    maxUnavailable: {{ $av.podDisruptionBudget.maxUnavailable }}
  {{- end }}
  {{- with $av.autoScaling }}
  autoScaling:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $av.nodeSelector }}
  nodeSelector:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $av.tolerations }}
  tolerations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $av.affinity }}
  affinity:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $av.topologySpreadConstraints }}
  topologySpreadConstraints:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $av.runtimeClassName }}
  runtimeClassName: {{ . | quote }}
  {{- end }}
{{- end }}
{{- if .Values.suspended }}
suspended: true
{{- end }}
{{- with .Values.restoreFrom }}
restoreFrom: {{ . | quote }}
{{- end }}
{{- if .Values.autoUpdate.enabled }}
autoUpdate:
  {{- toYaml .Values.autoUpdate | nindent 2 }}
{{- end }}
{{- if .Values.selfConfigure.enabled }}
selfConfigure:
  {{- toYaml .Values.selfConfigure | nindent 2 }}
{{- end }}
{{- with .Values.podAnnotations }}
podAnnotations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}
