{{- define "app.env" -}}
DEPLOYMENT_ENV: {{ .Values.deploymentEnv }}
PORT: "3000"
OTEL_RESOURCE_ATTRIBUTES: >-
  namespace={{ .Release.Namespace }},
  service.version={{ .Values.appVersion }}
OTEL_SERVICE_NAME: {{ .Chart.Name | quote }}
OTEL_NODE_RESOURCE_DETECTORS: "env,host,container,process"
# --no-network-family-autoselection added because of https://r1ch.net/blog/node-v20-aggregateeerror-etimedout-happy-eyeballs and https://github.com/nodejs/node/issues/54359
NODE_OPTIONS: >-
  --no-network-family-autoselection
  --enable-source-maps
  --stack-trace-limit=25
{{- if ((.Values.nodeOptions).enabledOTEL) }}
  --require @opentelemetry/auto-instrumentations-node/register
{{- end }}
{{- end }}
