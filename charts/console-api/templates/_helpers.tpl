{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "console-api.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "console-api.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- printf "%s-%s-%s" .Release.Name $name .Values.environment | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "console-api.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "console-api.labels" -}}
helm.sh/chart: {{ include "console-api.chart" . }}
{{ include "console-api.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: console-api
app.kubernetes.io/environment: {{ .Values.environment }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "console-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "console-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of doppler secret
*/}}
{{- define "console-api.dopplerSecretName" -}}
{{- printf "%s-secret" (include "console-api.fullname" .) }}
{{- end }}

{{/*
Create the doppler config name based on environment
*/}}
{{- define "console-api.dopplerConfig" -}}
{{- printf "staging-%s" .Values.environment }}
{{- end }}
