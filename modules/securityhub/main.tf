data "aws_partition" "current" {}

data "aws_region" "current" {}

locals {
  region = coalesce(var.region, data.aws_region.current.region)

  standards_paths = {
    fsbp = "standards/aws-foundational-security-best-practices/v/1.0.0"
    cis  = "standards/cis-aws-foundations-benchmark/v/5.0.0"
  }
}

resource "aws_securityhub_account" "this" {
  region                    = var.region
  enable_default_standards  = false
  control_finding_generator = var.control_finding_generator
  auto_enable_controls      = var.auto_enable_controls
}

resource "aws_securityhub_standards_subscription" "this" {
  for_each = toset(var.standards)

  region        = var.region
  standards_arn = "arn:${data.aws_partition.current.partition}:securityhub:${local.region}::${local.standards_paths[each.key]}"

  depends_on = [aws_securityhub_account.this]
}

resource "aws_securityhub_finding_aggregator" "this" {
  count = var.finding_aggregator == null ? 0 : 1

  region            = var.region
  linking_mode      = var.finding_aggregator.linking_mode
  specified_regions = length(var.finding_aggregator.regions) == 0 ? null : toset(var.finding_aggregator.regions)

  depends_on = [aws_securityhub_account.this]
}

resource "aws_securityhub_organization_configuration" "this" {
  count = var.organization == null ? 0 : 1

  region                = var.region
  auto_enable           = var.organization.auto_enable
  auto_enable_standards = var.organization.auto_enable_standards

  organization_configuration {
    configuration_type = "LOCAL"
  }

  depends_on = [aws_securityhub_account.this]
}
