{{- define "llm-session.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "llm-session.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "llm-session.name" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "llm-session.labels" -}}
app.kubernetes.io/name: {{ include "llm-session.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
