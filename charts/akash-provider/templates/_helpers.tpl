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
