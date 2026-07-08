{{- define "convogent-voice.name" -}}
{{- .Values.voiceService.name | default "convogentv2-voice" -}}
{{- end -}}

{{- define "convogent-voice.image" -}}
{{- $s := .Values.voiceService -}}
{{- if not $s.image.tag -}}
{{- fail "voiceService.image.tag is required" -}}
{{- end -}}
{{- printf "%s/%s:%s" (.Values.global.imageRegistry) $s.image.repository $s.image.tag -}}
{{- end -}}

{{- define "convogent-voice.labels" -}}
app: {{ include "convogent-voice.name" . }}
tier: agent
service: voice
environment: {{ .Values.global.environment }}
app.kubernetes.io/name: {{ include "convogent-voice.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: voice-service
app.kubernetes.io/part-of: convogent-v2
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{- define "convogent-voice.selectorLabels" -}}
app: {{ include "convogent-voice.name" . }}
service: voice
{{- end -}}

{{- define "convogent-voice.namespace" -}}
{{- .Values.global.namespace | default .Release.Namespace -}}
{{- end -}}

{{- define "convogent-voice.podSecurityContext" -}}
runAsNonRoot: true
runAsUser: 1000
runAsGroup: 1000
fsGroup: 1000
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{- define "convogent-voice.containerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: false
runAsNonRoot: true
capabilities:
  drop: ["ALL"]
{{- end -}}
