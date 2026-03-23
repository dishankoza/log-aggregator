resource "aws_ecr_repository" "services" {
  for_each = toset(var.ecr_repository_names)

  name                 = "${var.project_name}/${each.value}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
