# Latest Amazon Linux 2023 for the chosen architecture. A data source rather than the SSM public parameter,
# because only ssm-read may read SSM parameters in this repo.
data "aws_ami" "al2023" {
  owners      = ["amazon"]
  most_recent = true

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-*-${var.architecture}"]
  }

  filter {
    name   = "architecture"
    values = [var.architecture]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

resource "aws_instance" "this" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  iam_instance_profile   = var.instance_profile_name

  # Explicit false so a subnet that maps public IPs on launch cannot give the bastion one.
  associate_public_ip_address = false

  # IMDSv2 only, and one hop so containers on the host cannot reach the metadata service.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true

    tags = merge(var.tags, { Name = var.name })
  }

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    # A newer AMI must not replace a running bastion; replace it on purpose with -replace.
    ignore_changes = [ami]
  }
}
