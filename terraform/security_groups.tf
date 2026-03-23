resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Public access to the ALB."
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP UI"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP go-service demo"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-alb-sg"
  }
}

resource "aws_security_group" "ecs_services" {
  name        = "${local.name_prefix}-ecs-sg"
  description = "Security group for ECS services."
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "UI from ALB"
    from_port       = local.common_ports.ui_api
    to_port         = local.common_ports.ui_api
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "go-service from ALB"
    from_port       = local.common_ports.go_service
    to_port         = local.common_ports.go_service
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description = "east-west traffic between ECS tasks"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-ecs-sg"
  }
}

resource "aws_security_group" "stateful_host" {
  name        = "${local.name_prefix}-stateful-sg"
  description = "Access for Kafka, Cassandra, Elasticsearch, and Ollama on EC2."
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Kafka from ECS"
    from_port       = local.common_ports.kafka
    to_port         = local.common_ports.kafka
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_services.id]
  }

  ingress {
    description     = "Cassandra from ECS"
    from_port       = local.common_ports.cassandra
    to_port         = local.common_ports.cassandra
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_services.id]
  }

  ingress {
    description     = "Elasticsearch from ECS"
    from_port       = local.common_ports.elasticsearch
    to_port         = local.common_ports.elasticsearch
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_services.id]
  }

  ingress {
    description     = "Ollama from ECS"
    from_port       = local.common_ports.ollama
    to_port         = local.common_ports.ollama
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_services.id]
  }

  dynamic "ingress" {
    for_each = length(var.ssh_ingress_cidr_blocks) > 0 ? [1] : []

    content {
      description = "Optional SSH access"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.ssh_ingress_cidr_blocks
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-stateful-sg"
  }
}
