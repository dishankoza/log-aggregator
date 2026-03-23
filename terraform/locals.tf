locals {
  name_prefix              = "${var.project_name}-${var.environment}"
  service_discovery_domain = aws_service_discovery_private_dns_namespace.ecs.name
  common_ports = {
    ui_api        = 8000
    go_service    = 8080
    java_service  = 8081
    cpp_service   = 8082
    otlp_grpc     = 4317
    otlp_http     = 4318
    kafka         = 9092
    cassandra     = 9042
    elasticsearch = 9200
    ollama        = 11434
  }
}
