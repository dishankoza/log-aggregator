FROM otel/opentelemetry-collector-contrib:0.121.0

COPY config.yaml /etc/otel/config.yaml

ENTRYPOINT ["/otelcol-contrib", "--config=/etc/otel/config.yaml"]
