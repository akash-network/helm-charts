{{/*
Expand the name of the chart.
*/}}
{{- define "akash-ip-operator.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "akash-ip-operator.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "akash-ip-operator.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "akash-ip-operator.labels" -}}
helm.sh/chart: {{ include "akash-ip-operator.chart" . }}
{{ include "akash-ip-operator.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "akash-ip-operator.selectorLabels" -}}
app.kubernetes.io/name: {{ include "akash-ip-operator.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "akash-ip-operator.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "akash-ip-operator.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Logging configuration as AP_LOG_* environment variables (container env list form).
Refs https://github.com/akash-network/provider/blob/main/_docs/logging.md
An unquoted `timestamp: off` is parsed by YAML as boolean false, so it (and "") is mapped to "off".
*/}}
{{- define "akash-ip-operator.loggingEnv" -}}
{{- $l := .Values.logging | default dict -}}
{{- $format := $l.format | default "json" | toString | lower -}}
{{- if not (has $format (list "plain" "json")) -}}
{{- fail (printf "logging.format %q is invalid: allowed values plain|json" $format) -}}
{{- end -}}
{{- $timestamp := "rfc3339" -}}
{{- if hasKey $l "timestamp" -}}
{{- $timestamp = ternary "off" ($l.timestamp | toString | lower) (or (kindIs "bool" $l.timestamp) (empty $l.timestamp)) -}}
{{- end -}}
{{- if not (has $timestamp (list "off" "rfc3339" "rfc3339nano" "kitchen")) -}}
{{- fail (printf "logging.timestamp %q is invalid: allowed values off|rfc3339|rfc3339nano|kitchen" $timestamp) -}}
{{- end -}}
- name: AP_LOG_LEVEL
  value: {{ $l.level | default "info" | quote }}
- name: AP_LOG_FORMAT
  value: {{ $format | quote }}
- name: AP_LOG_COLOR
  value: {{ $l.color | default false | toString | quote }}
- name: AP_LOG_TIMESTAMP
  value: {{ $timestamp | quote }}
- name: AP_TRACE
  value: {{ $l.trace | default false | toString | quote }}
{{- end }}
