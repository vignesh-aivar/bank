{{- define "convogent-chat.name" -}}
{{- .Values.chatService.name | default "convogentv2-chat" -}}
{{- end -}}

{{- define "convogent-chat.image" -}}
{{- $s := .Values.chatService -}}
{{- if not $s.image.tag -}}
{{- fail "chatService.image.tag is required" -}}
{{- end -}}
{{- printf "%s/%s:%s" (.Values.global.imageRegistry) $s.image.repository $s.image.tag -}}
{{- end -}}

{{- define "convogent-chat.labels" -}}
app: {{ include "convogent-chat.name" . }}
tier: agent
service: chat
environment: {{ .Values.global.environment }}
app.kubernetes.io/name: {{ include "convogent-chat.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: chat-service
app.kubernetes.io/part-of: convogent-v2
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{- define "convogent-chat.selectorLabels" -}}
app: {{ include "convogent-chat.name" . }}
service: chat
{{- end -}}

{{- define "convogent-chat.namespace" -}}
{{- .Values.global.namespace | default .Release.Namespace -}}
{{- end -}}

{{- define "convogent-chat.podSecurityContext" -}}
runAsNonRoot: true
runAsUser: 1000
runAsGroup: 1000
fsGroup: 1000
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{- define "convogent-chat.containerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: false
runAsNonRoot: true
capabilities:
  drop: ["ALL"]
{{- end -}}
