{{/*
Expand the name of the chart.
*/}}
{{- define "akash-gateway.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "akash-gateway.fullname" -}}
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
Common labels
*/}}
{{- define "akash-gateway.labels" -}}
helm.sh/chart: {{ include "akash-gateway.chart" . }}
app.kubernetes.io/name: {{ include "akash-gateway.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "akash-gateway.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
  Ingress base for the https-wildcard host: explicit gateway.https.domain, else top-level domain
  (same as akash-provider), else a placeholder.
*/}}
{{- define "akash-gateway.ingressBaseDomain" -}}
{{- .Values.gateway.https.domain | default .Values.domain | default "example.com" -}}
{{- end -}}

{{/*
  Host for https-wildcard: full wildcardHostname, or *.ingress.<ingressBaseDomain>.
*/}}
{{- define "akash-gateway.wildcardListenerHostname" -}}
{{- if .Values.gateway.https.wildcardHostname -}}
{{- .Values.gateway.https.wildcardHostname -}}
{{- else -}}
{{- printf "*.ingress.%s" (include "akash-gateway.ingressBaseDomain" .) -}}
{{- end -}}
{{- end -}}
