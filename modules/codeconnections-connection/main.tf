resource "aws_codeconnections_connection" "this" {
  region = var.region
  name   = var.name
  # provider_type conflicts with host_arn: a self-managed connection takes its type from the host.
  provider_type = var.host_arn == null ? var.provider_type : null
  host_arn      = var.host_arn

  tags = merge(var.tags, { Name = var.name })
}
