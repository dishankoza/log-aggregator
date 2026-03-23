variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Project prefix used in resource names."
  type        = string
  default     = "log-aggregator"
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets."
  type        = list(string)
  default     = ["10.20.0.0/24", "10.20.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets."
  type        = list(string)
  default     = ["10.20.10.0/24", "10.20.11.0/24"]
}

variable "stateful_instance_type" {
  description = "Instance type for the EC2 stateful host."
  type        = string
  default     = "t3.small"
}

variable "stateful_root_volume_size" {
  description = "Root volume size in GiB for the stateful EC2 host."
  type        = number
  default     = 100
}

variable "ssh_ingress_cidr_blocks" {
  description = "Optional CIDR blocks allowed to SSH to the stateful host."
  type        = list(string)
  default     = []
}

variable "ecs_cpu_architecture" {
  description = "CPU architecture for ECS task definitions."
  type        = string
  default     = "X86_64"
}

variable "ecr_repository_names" {
  description = "Container repositories to create in ECR."
  type        = list(string)
  default = [
    "go-service",
    "java-service",
    "cpp-service",
    "otel-collector",
    "cassandra-store",
    "elasticsearch-indexer",
    "ui-api",
    "ollama",
  ]
}

variable "container_image_tag" {
  description = "Tag used for all application images pushed to ECR."
  type        = string
  default     = "latest"
}

variable "ollama_model" {
  description = "Model pulled by Ollama on the EC2 stateful host."
  type        = string
  default     = "gemma3:270m"
}
