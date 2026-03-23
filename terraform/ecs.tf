resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_service_discovery_private_dns_namespace" "ecs" {
  name        = "${var.environment}.${var.project_name}.local"
  description = "Private namespace for ECS service-to-service discovery."
  vpc         = aws_vpc.main.id
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/aws/ecs/${local.name_prefix}"
  retention_in_days = 14
}
