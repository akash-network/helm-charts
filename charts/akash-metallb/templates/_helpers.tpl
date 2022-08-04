{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "akash-metallb.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "akash-metallb.fullname" -}}
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
{{- define "akash-metallb.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "akash-metallb.labels" -}}
helm.sh/chart: {{ include "akash-metallb.chart" . }}
{{ include "akash-metallb.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "akash-metallb.selectorLabels" -}}
app.kubernetes.io/name: {{ include "akash-metallb.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the controller service account to use
*/}}
{{- define "akash-metallb.controller.serviceAccountName" -}}
{{- if .Values.controller.serviceAccount.create }}
{{- default (printf "%s-controller" (include "akash-metallb.fullname" .)) .Values.controller.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.controller.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the name of the speaker service account to use
*/}}
{{- define "akash-metallb.speaker.serviceAccountName" -}}
{{- if .Values.speaker.serviceAccount.create }}
{{- default (printf "%s-speaker" (include "akash-metallb.fullname" .)) .Values.speaker.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.speaker.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the name of the settings Secret to use.
*/}}
{{- define "akash-metallb.secretName" -}}
    {{ default ( printf "%s-memberlist" (include "akash-metallb.fullname" .)) .Values.speaker.secretName | trunc 63 | trimSuffix "-" }}
{{- end -}}
