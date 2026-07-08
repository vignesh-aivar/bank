{{- define "convogent-eval.name" -}}
{{- .Values.evalService.name | default "convogentv2-eval" -}}
{{- end -}}

{{- define "convogent-eval.image" -}}
{{- $s := .Values.evalService -}}
{{- if not $s.image.tag -}}
{{- fail "evalService.image.tag is required" -}}
{{- end -}}
{{- printf "%s/%s:%s" (.Values.global.imageRegistry) $s.image.repository $s.image.tag -}}
{{- end -}}

{{- define "convogent-eval.labels" -}}
app: {{ include "convogent-eval.name" . }}
tier: agent
service: eval
environment: {{ .Values.global.environment }}
app.kubernetes.io/name: {{ include "convogent-eval.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: eval-service
app.kubernetes.io/part-of: convogent-v2
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{- define "convogent-eval.selectorLabels" -}}
app: {{ include "convogent-eval.name" . }}
service: eval
{{- end -}}

{{- define "convogent-eval.namespace" -}}
{{- .Values.global.namespace | default .Release.Namespace -}}
{{- end -}}

{{- define "convogent-eval.podSecurityContext" -}}
runAsNonRoot: true
runAsUser: 1000
runAsGroup: 1000
fsGroup: 1000
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{- define "convogent-eval.containerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: false
runAsNonRoot: true
capabilities:
  drop: ["ALL"]
{{- end -}}
