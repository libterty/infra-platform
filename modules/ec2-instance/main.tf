data "aws_region" "current" {}

# Latest Amazon Linux 2023 for the chosen architecture. A data source rather than the SSM public parameter,
# because only ssm-read may read SSM parameters in this repo. Skipped when ami_id is given.
data "aws_ami" "al2023" {
  count = var.ami_id == null ? 1 : 0

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

locals {
  ami_id = var.ami_id != null ? var.ami_id : data.aws_ami.al2023[0].id
}

resource "aws_instance" "this" {
  ami                     = local.ami_id
  instance_type           = var.instance_type
  subnet_id               = var.subnet_id
  vpc_security_group_ids  = var.security_group_ids
  iam_instance_profile    = var.instance_profile_name
  user_data               = var.user_data
  disable_api_termination = var.disable_api_termination

  # Explicit false so a subnet that maps public IPs on launch cannot give the instance one.
  associate_public_ip_address = false

  # IMDSv2 only, and one hop so containers on the host cannot reach the metadata service.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume.size
    encrypted             = true
    kms_key_id            = var.root_volume.kms_key_arn
    delete_on_termination = true

    tags = merge(var.tags, { Name = var.name })
  }

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    # A newer AMI must not replace a running instance; replace it on purpose with -replace.
    ignore_changes = [ami]
  }
}

resource "aws_ebs_volume" "this" {
  for_each = var.ebs_volumes

  availability_zone = aws_instance.this.availability_zone
  size              = each.value.size
  type              = each.value.type
  encrypted         = true
  kms_key_id        = each.value.kms_key_arn

  tags = merge(var.tags, { Name = "${var.name}-${each.key}" })
}

resource "aws_volume_attachment" "this" {
  for_each = var.ebs_volumes

  device_name = each.value.device_name
  volume_id   = aws_ebs_volume.this[each.key].id
  instance_id = aws_instance.this.id
}

# Only with SNS topics (D16). The recover action restarts the instance on healthy hardware; SNS tells people.
resource "aws_cloudwatch_metric_alarm" "system_status" {
  count = length(var.sns_topic_arns) > 0 ? 1 : 0

  alarm_name          = "${var.name}-status-check-system"
  alarm_description   = "EC2 system status check failed for ${var.name}; the instance is recovered automatically."
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_System"
  dimensions          = { InstanceId = aws_instance.this.id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = concat(["arn:aws:automate:${data.aws_region.current.region}:ec2:recover"], var.sns_topic_arns)
  ok_actions    = var.sns_topic_arns

  tags = merge(var.tags, { Name = "${var.name}-status-check-system" })
}
