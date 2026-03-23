data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "stateful_host" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.stateful_instance_type
  subnet_id                   = aws_subnet.private["0"].id
  vpc_security_group_ids      = [aws_security_group.stateful_host.id]
  iam_instance_profile        = aws_iam_instance_profile.stateful_host.name
  associate_public_ip_address = false

  user_data = templatefile("${path.module}/templates/stateful-user-data.sh.tftpl", {
    project_name = var.project_name
    environment  = var.environment
    ollama_model = var.ollama_model
    compose_template = templatefile("${path.module}/templates/stateful-compose.yml.tftpl", {
      project_name = var.project_name
      environment  = var.environment
      ollama_model = var.ollama_model
    })
  })

  root_block_device {
    volume_size           = var.stateful_root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name            = "${local.name_prefix}-stateful-host"
    Role            = "stateful"
    BootstrapVersion = "v2"
  }
}
