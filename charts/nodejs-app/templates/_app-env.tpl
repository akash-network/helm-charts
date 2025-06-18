{{- define "app.env" -}}
OTEL_RESOURCE_ATTRIBUTES: "namespace={{ .Release.Namespace }}"
OTEL_SERVICE_NAME: {{ .Chart.Name | quote }}
OTEL_NODE_RESOURCE_DETECTORS: "env,host,container,process"
# --no-network-family-autoselection added because of https://r1ch.net/blog/node-v20-aggregateeerror-etimedout-happy-eyeballs and https://github.com/nodejs/node/issues/54359
NODE_OPTIONS: >-
  --no-network-family-autoselection
  --enable-source-maps
  --require @opentelemetry/auto-instrumentations-node/register
{{- end }}
