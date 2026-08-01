{{- define "ideai-devpod.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "ideai-devpod.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "ideai-devpod.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "ideai-devpod.labels" -}}
app.kubernetes.io/name: {{ include "ideai-devpod.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
ideai.dev/devpod: "true"
{{- end -}}

{{- define "ideai-devpod.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ideai-devpod.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
