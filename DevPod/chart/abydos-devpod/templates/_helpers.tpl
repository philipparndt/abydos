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

{{/*
Which kind of routing object to create.

Worked out from the cluster's own API groups rather than asked for, because
the answer is a property of the cluster and the person installing this wants
a URL, not a taxonomy lesson.
*/}}
{{- define "ideai-devpod.ingressKind" -}}
{{- $mode := .Values.ingress.mode | default "auto" -}}
{{- if ne $mode "auto" -}}
{{- $mode -}}
{{- else if and (.Capabilities.APIVersions.Has "gateway.networking.k8s.io/v1") .Values.ingress.gateway.name -}}
gateway
{{- else if .Capabilities.APIVersions.Has "traefik.io/v1alpha1" -}}
traefik
{{- else -}}
ingress
{{- end -}}
{{- end -}}

{{/* The container port the route sends traffic to. */}}
{{- define "ideai-devpod.routePort" -}}
{{- $name := .Values.ingress.port -}}
{{- $port := 0 -}}
{{- range .Values.app.ports -}}
{{- if eq .name $name -}}{{- $port = .containerPort -}}{{- end -}}
{{- end -}}
{{- if eq (int $port) 0 -}}
{{- fail (printf "ingress.port %q is not one of app.ports" $name) -}}
{{- end -}}
{{- $port -}}
{{- end -}}
