output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = values(aws_subnet.public)[*].id
}

output "private_subnet_ids" {
  value = values(aws_subnet.private)[*].id
}

output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "ecs_service_discovery_namespace" {
  value = aws_service_discovery_private_dns_namespace.ecs.name
}

output "stateful_host_private_ip" {
  value = aws_instance.stateful_host.private_ip
}

output "stateful_host_id" {
  value = aws_instance.stateful_host.id
}

output "stateful_host_security_group_id" {
  value = aws_security_group.stateful_host.id
}

output "ecs_services_security_group_id" {
  value = aws_security_group.ecs_services.id
}

output "ecs_task_execution_role_arn" {
  value = aws_iam_role.ecs_task_execution.arn
}

output "ecs_task_role_arn" {
  value = aws_iam_role.ecs_task.arn
}

output "ecr_repository_urls" {
  value = { for name, repo in aws_ecr_repository.services : name => repo.repository_url }
}
