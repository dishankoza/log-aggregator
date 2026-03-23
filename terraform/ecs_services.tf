resource "aws_service_discovery_service" "services" {
  for_each = {
    go_service            = "go-service"
    java_service          = "java-service"
    cpp_service           = "cpp-service"
    otel_collector        = "otel-collector"
    cassandra_store       = "cassandra-store"
    elasticsearch_indexer = "elasticsearch-indexer"
    ui_api                = "ui-api"
  }

  name = each.value

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.ecs.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_ecs_task_definition" "go_service" {
  family                   = "${local.name_prefix}-go-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.ecs_cpu_architecture
  }

  container_definitions = jsonencode([
    {
      name      = "go-service"
      image     = "${aws_ecr_repository.services["go-service"].repository_url}:${var.container_image_tag}"
      essential = true
      portMappings = [
        {
          containerPort = local.common_ports.go_service
          hostPort      = local.common_ports.go_service
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "PORT", value = tostring(local.common_ports.go_service) },
        { name = "JAVA_SERVICE_URL", value = "http://java-service.${local.service_discovery_domain}:${local.common_ports.java_service}/" },
        { name = "OTEL_EXPORTER_OTLP_ENDPOINT", value = "otel-collector.${local.service_discovery_domain}:${local.common_ports.otlp_grpc}" },
        { name = "OTEL_SERVICE_NAME", value = "go-service" },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "go-service"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "java_service" {
  family                   = "${local.name_prefix}-java-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.ecs_cpu_architecture
  }

  container_definitions = jsonencode([
    {
      name      = "java-service"
      image     = "${aws_ecr_repository.services["java-service"].repository_url}:${var.container_image_tag}"
      essential = true
      portMappings = [
        {
          containerPort = local.common_ports.java_service
          hostPort      = local.common_ports.java_service
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "SERVER_PORT", value = tostring(local.common_ports.java_service) },
        { name = "CPP_SERVICE_URL", value = "http://cpp-service.${local.service_discovery_domain}:${local.common_ports.cpp_service}/" },
        { name = "OTEL_EXPORTER_OTLP_ENDPOINT", value = "http://otel-collector.${local.service_discovery_domain}:${local.common_ports.otlp_http}" },
        { name = "OTEL_EXPORTER_OTLP_PROTOCOL", value = "http/protobuf" },
        { name = "OTEL_SERVICE_NAME", value = "java-service" },
        { name = "OTEL_TRACES_EXPORTER", value = "otlp" },
        { name = "OTEL_METRICS_EXPORTER", value = "otlp" },
        { name = "OTEL_LOGS_EXPORTER", value = "none" },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "java-service"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "cpp_service" {
  family                   = "${local.name_prefix}-cpp-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.ecs_cpu_architecture
  }

  container_definitions = jsonencode([
    {
      name      = "cpp-service"
      image     = "${aws_ecr_repository.services["cpp-service"].repository_url}:${var.container_image_tag}"
      essential = true
      portMappings = [
        {
          containerPort = local.common_ports.cpp_service
          hostPort      = local.common_ports.cpp_service
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "PORT", value = tostring(local.common_ports.cpp_service) },
        { name = "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT", value = "http://otel-collector.${local.service_discovery_domain}:${local.common_ports.otlp_http}/v1/traces" },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "cpp-service"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "otel_collector" {
  family                   = "${local.name_prefix}-otel-collector"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.ecs_cpu_architecture
  }

  container_definitions = jsonencode([
    {
      name      = "otel-collector"
      image     = "${aws_ecr_repository.services["otel-collector"].repository_url}:${var.container_image_tag}"
      essential = true
      portMappings = [
        {
          containerPort = local.common_ports.otlp_grpc
          hostPort      = local.common_ports.otlp_grpc
          protocol      = "tcp"
        },
        {
          containerPort = local.common_ports.otlp_http
          hostPort      = local.common_ports.otlp_http
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "otel-collector"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "cassandra_store" {
  family                   = "${local.name_prefix}-cassandra-store"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.ecs_cpu_architecture
  }

  container_definitions = jsonencode([
    {
      name      = "cassandra-store"
      image     = "${aws_ecr_repository.services["cassandra-store"].repository_url}:${var.container_image_tag}"
      essential = true
      command   = ["python", "/app/store_to_cassandra.py"]
      environment = [
        { name = "KAFKA_TOPIC", value = "otlp_spans" },
        { name = "KAFKA_BOOTSTRAP_SERVERS", value = "${aws_instance.stateful_host.private_ip}:${local.common_ports.kafka}" },
        { name = "KAFKA_GROUP_ID", value = "trace-cassandra-writer" },
        { name = "CASSANDRA_CONTACT_POINTS", value = aws_instance.stateful_host.private_ip },
        { name = "CASSANDRA_KEYSPACE", value = "observability" },
        { name = "CASSANDRA_TABLE", value = "trace_events" },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "cassandra-store"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "elasticsearch_indexer" {
  family                   = "${local.name_prefix}-elasticsearch-indexer"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.ecs_cpu_architecture
  }

  container_definitions = jsonencode([
    {
      name      = "elasticsearch-indexer"
      image     = "${aws_ecr_repository.services["elasticsearch-indexer"].repository_url}:${var.container_image_tag}"
      essential = true
      command   = ["python", "/app/store_to_elasticsearch.py"]
      environment = [
        { name = "KAFKA_TOPIC", value = "otlp_spans" },
        { name = "KAFKA_BOOTSTRAP_SERVERS", value = "${aws_instance.stateful_host.private_ip}:${local.common_ports.kafka}" },
        { name = "KAFKA_GROUP_ID", value = "trace-elasticsearch-writer" },
        { name = "ELASTICSEARCH_URL", value = "http://${aws_instance.stateful_host.private_ip}:${local.common_ports.elasticsearch}" },
        { name = "ELASTICSEARCH_INDEX", value = "trace_spans" },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "elasticsearch-indexer"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "ui_api" {
  family                   = "${local.name_prefix}-ui-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.ecs_cpu_architecture
  }

  container_definitions = jsonencode([
    {
      name      = "ui-api"
      image     = "${aws_ecr_repository.services["ui-api"].repository_url}:${var.container_image_tag}"
      essential = true
      portMappings = [
        {
          containerPort = local.common_ports.ui_api
          hostPort      = local.common_ports.ui_api
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "ELASTICSEARCH_URL", value = "http://${aws_instance.stateful_host.private_ip}:${local.common_ports.elasticsearch}" },
        { name = "ELASTICSEARCH_INDEX", value = "trace_spans" },
        { name = "CASSANDRA_CONTACT_POINTS", value = aws_instance.stateful_host.private_ip },
        { name = "CASSANDRA_KEYSPACE", value = "observability" },
        { name = "SEARCH_LIMIT", value = "30" },
        { name = "AI_CONTEXT_LIMIT", value = "8" },
        { name = "OPENAI_MODEL", value = var.ollama_model },
        { name = "OPENAI_BASE_URL", value = "http://${aws_instance.stateful_host.private_ip}:${local.common_ports.ollama}/v1" },
        { name = "OPENAI_API_KEY", value = "ollama" },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ui-api"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "go_service" {
  name            = "go-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.go_service.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = values(aws_subnet.private)[*].id
    security_groups  = [aws_security_group.ecs_services.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.go_service.arn
    container_name   = "go-service"
    container_port   = local.common_ports.go_service
  }

  service_registries {
    registry_arn = aws_service_discovery_service.services["go_service"].arn
  }

  depends_on = [aws_lb_listener.go_service]
}

resource "aws_ecs_service" "java_service" {
  name            = "java-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.java_service.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = values(aws_subnet.private)[*].id
    security_groups  = [aws_security_group.ecs_services.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.services["java_service"].arn
  }
}

resource "aws_ecs_service" "cpp_service" {
  name            = "cpp-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.cpp_service.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = values(aws_subnet.private)[*].id
    security_groups  = [aws_security_group.ecs_services.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.services["cpp_service"].arn
  }
}

resource "aws_ecs_service" "otel_collector" {
  name            = "otel-collector"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.otel_collector.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = values(aws_subnet.private)[*].id
    security_groups  = [aws_security_group.ecs_services.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.services["otel_collector"].arn
  }
}

resource "aws_ecs_service" "cassandra_store" {
  name            = "cassandra-store"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.cassandra_store.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = values(aws_subnet.private)[*].id
    security_groups  = [aws_security_group.ecs_services.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.services["cassandra_store"].arn
  }
}

resource "aws_ecs_service" "elasticsearch_indexer" {
  name            = "elasticsearch-indexer"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.elasticsearch_indexer.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = values(aws_subnet.private)[*].id
    security_groups  = [aws_security_group.ecs_services.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.services["elasticsearch_indexer"].arn
  }
}

resource "aws_ecs_service" "ui_api" {
  name            = "ui-api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.ui_api.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = values(aws_subnet.private)[*].id
    security_groups  = [aws_security_group.ecs_services.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ui_api.arn
    container_name   = "ui-api"
    container_port   = local.common_ports.ui_api
  }

  service_registries {
    registry_arn = aws_service_discovery_service.services["ui_api"].arn
  }

  depends_on = [aws_lb_listener.ui_api]
}
