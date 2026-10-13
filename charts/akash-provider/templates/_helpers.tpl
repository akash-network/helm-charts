{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "provider.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "provider.fullname" -}}
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
{{- define "provider.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "provider.labels" -}}
helm.sh/chart: {{ include "provider.chart" . }}
{{ include "provider.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "provider.selectorLabels" -}}
app.kubernetes.io/name: {{ include "provider.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "provider.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "provider.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Extract storage class from provider attributes
Looks for capabilities/storage/[*]/class where persistent = true
Falls back to the Helm chart's storage class
*/}}
{{- define "provider.storageClass" -}}
{{- $storageClass := "" -}}
{{- if .Values.attributes -}}
  {{- range .Values.attributes -}}
    {{- if and (hasPrefix "capabilities/storage/" .key) (hasSuffix "/persistent" .key) (eq (toString .value) "true") -}}
      {{- $classKey := printf "%s/class" (trimSuffix "/persistent" .key) -}}
      {{- range $.Values.attributes -}}
        {{- if eq .key $classKey -}}
          {{- $storageClass = .value -}}
        {{- end -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- if $storageClass -}}
  {{- $storageClass -}}
{{- else -}}
  {{- .Values.letsEncrypt.storage.storageClass | default (printf "%s-local-storage" (include "provider.fullname" .)) -}}
{{- end -}}
{{- end }}

{{/*
Logging configuration as AP_LOG_* environment variables (ConfigMap data form).
Refs https://github.com/akash-network/provider/blob/main/_docs/logging.md
An unquoted `timestamp: off` is parsed by YAML as boolean false, so it (and "") is mapped to "off".
*/}}
{{- define "provider.loggingEnv" -}}
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
AP_LOG_LEVEL: {{ $l.level | default "info" | quote }}
AP_LOG_FORMAT: {{ $format | quote }}
AP_LOG_COLOR: {{ $l.color | default false | toString | quote }}
AP_LOG_TIMESTAMP: {{ $timestamp | quote }}
AP_TRACE: {{ $l.trace | default false | toString | quote }}
{{- end }}
