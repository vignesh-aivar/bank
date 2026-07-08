{{/*
Backend name
*/}}
{{- define "convogent-backend.name" -}}
{{- .Values.backend.name | default "convogentv2-backend" -}}
{{- end -}}

{{/*
Full image: registry/repository:tag (fails fast if tag not set)
*/}}
{{- define "convogent-backend.image" -}}
{{- $b := .Values.backend -}}
{{- if not $b.image.tag -}}
{{- fail "backend.image.tag is required — do not use 'latest' in production" -}}
{{- end -}}
{{- printf "%s/%s:%s" (.Values.global.imageRegistry) $b.image.repository $b.image.tag -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "convogent-backend.labels" -}}
app: {{ include "convogent-backend.name" . }}
tier: backend
environment: {{ .Values.global.environment }}
app.kubernetes.io/name: {{ include "convogent-backend.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: backend
app.kubernetes.io/part-of: convogent-v2
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{/*
Selector labels (MUST remain stable across upgrades — selectors are immutable)
*/}}
{{- define "convogent-backend.selectorLabels" -}}
app: {{ include "convogent-backend.name" . }}
tier: backend
{{- end -}}

{{/*
Namespace
*/}}
{{- define "convogent-backend.namespace" -}}
{{- .Values.global.namespace | default .Release.Namespace -}}
{{- end -}}

{{/*
Pod security context (defaults prioritize security)
*/}}
{{- define "convogent-backend.podSecurityContext" -}}
runAsNonRoot: {{ ((.Values.backend.podSecurityContext).runAsNonRoot) | default true }}
runAsUser: {{ ((.Values.backend.podSecurityContext).runAsUser) | default 1000 }}
runAsGroup: {{ ((.Values.backend.podSecurityContext).runAsGroup) | default 1000 }}
fsGroup: {{ ((.Values.backend.podSecurityContext).fsGroup) | default 1000 }}
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{/*
Container security context
*/}}
{{- define "convogent-backend.containerSecurityContext" -}}
allowPrivilegeEscalation: {{ ((.Values.backend.containerSecurityContext).allowPrivilegeEscalation) | default false }}
readOnlyRootFilesystem: {{ ((.Values.backend.containerSecurityContext).readOnlyRootFilesystem) | default false }}
runAsNonRoot: true
capabilities:
  drop: ["ALL"]
{{- end -}}
