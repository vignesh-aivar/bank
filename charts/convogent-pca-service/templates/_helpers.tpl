{{- define "convogent-pca.name" -}}
{{- .Values.pcaService.name | default "convogentv2-pca" -}}
{{- end -}}

{{- define "convogent-pca.image" -}}
{{- $s := .Values.pcaService -}}
{{- if not $s.image.tag -}}
{{- fail "pcaService.image.tag is required" -}}
{{- end -}}
{{- printf "%s/%s:%s" (.Values.global.imageRegistry) $s.image.repository $s.image.tag -}}
{{- end -}}

{{- define "convogent-pca.labels" -}}
app: {{ include "convogent-pca.name" . }}
tier: agent
service: pca
environment: {{ .Values.global.environment }}
app.kubernetes.io/name: {{ include "convogent-pca.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: pca-service
app.kubernetes.io/part-of: convogent-v2
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{- define "convogent-pca.selectorLabels" -}}
app: {{ include "convogent-pca.name" . }}
service: pca
{{- end -}}

{{- define "convogent-pca.namespace" -}}
{{- .Values.global.namespace | default .Release.Namespace -}}
{{- end -}}

{{- define "convogent-pca.podSecurityContext" -}}
runAsNonRoot: true
runAsUser: 1000
runAsGroup: 1000
fsGroup: 1000
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{- define "convogent-pca.containerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: false
runAsNonRoot: true
capabilities:
  drop: ["ALL"]
{{- end -}}
