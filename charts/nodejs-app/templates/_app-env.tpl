{{- define "app.env" -}}
{{- $otelCollectorBaseUrl := (default "http://otel-collector-opentelemetry-collector.monitoring.svc.cluster.local:4318" ((.Values.otel).baseUrl)) }}

DEPLOYMENT_ENV: {{ .Values.deploymentEnv }}
PORT: "3000"
# --no-network-family-autoselection added because of https://r1ch.net/blog/node-v20-aggregateeerror-etimedout-happy-eyeballs and https://github.com/nodejs/node/issues/54359
NODE_OPTIONS: >-
  --no-network-family-autoselection
  --enable-source-maps
  --stack-trace-limit=25
OTEL_SERVICE_NAME: {{ .Chart.Name | quote }}
OTEL_RESOURCE_ATTRIBUTES: >-
  namespace={{ .Release.Namespace }},
  service.version={{ .Values.appVersion }}
OTEL_NODE_RESOURCE_DETECTORS: "env,host,container,process"
{{- if ((.Values.otel).enabled) }}
OTEL_LOGS_EXPORTER: none
OTEL_NODE_DISABLED_INSTRUMENTATIONS: dns, aws-lambda, amqplib, kafkajs, cassandra-driver, mongodb, mongoose, mysql, mysql2, redis, redis-4, ioredis, memcached, knex, tedious, socket.io, express, koa, hapi, fastify, restify, router, connect, nestjs-core, aws-sdk,bunyan,cucumber,dataloader,generic-pool,graphql,grpc,winston,lru-memoizer
OTEL_METRICS_EXPORTER: otlp
OTEL_EXPORTER_OTLP_TRACES_ENDPOINT: {{ $otelCollectorBaseUrl }}/v1/traces
OTEL_EXPORTER_OTLP_METRICS_ENDPOINT: {{ $otelCollectorBaseUrl }}/v1/metrics
{{- end }}
{{- end }}
