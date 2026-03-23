# log-aggregator

## Terraform

Terraform scaffolding for the AWS hybrid deployment lives in [terraform/](/Users/dishankoza/Code/log-aggregator/terraform).

It provisions:
- VPC with two public and two private subnets
- one private EC2 host for stateful services like Kafka, Cassandra, Elasticsearch, and optional Ollama
- one ECS cluster for stateless services plus ECS task definitions/services for the application containers
- one public ALB
- security groups, IAM roles, CloudWatch log group, and ECR repositories

Usage:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

After apply:

1. Push application images to the created ECR repositories using the `latest` tag by default.
2. Re-run `terraform apply` after the images exist if ECS task startup initially fails.
3. Use the EC2 private IP output for stateful debugging only; ECS services are already wired to it automatically.
