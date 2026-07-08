{{/*
Frontend name
*/}}
{{- define "convogent-frontend.name" -}}
{{- .Values.frontend.name | default "convogentv2-frontend" -}}
{{- end -}}

{{- define "convogent-frontend.image" -}}
{{- $f := .Values.frontend -}}
{{- if not $f.image.tag -}}
{{- fail "frontend.image.tag is required" -}}
{{- end -}}
{{- printf "%s/%s:%s" (.Values.global.imageRegistry) $f.image.repository $f.image.tag -}}
{{- end -}}

{{- define "convogent-frontend.labels" -}}
app: {{ include "convogent-frontend.name" . }}
tier: frontend
environment: {{ .Values.global.environment }}
app.kubernetes.io/name: {{ include "convogent-frontend.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: frontend
app.kubernetes.io/part-of: convogent-v2
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{- define "convogent-frontend.selectorLabels" -}}
app: {{ include "convogent-frontend.name" . }}
tier: frontend
{{- end -}}

{{- define "convogent-frontend.namespace" -}}
{{- .Values.global.namespace | default .Release.Namespace -}}
{{- end -}}

{{- define "convogent-frontend.podSecurityContext" -}}
runAsNonRoot: true
runAsUser: 101
runAsGroup: 101
fsGroup: 101
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{- define "convogent-frontend.containerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: false
runAsNonRoot: true
capabilities:
  drop: ["ALL"]
{{- end -}}
