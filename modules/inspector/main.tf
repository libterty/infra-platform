data "aws_caller_identity" "current" {}

resource "aws_inspector2_enabler" "this" {
  region         = var.region
  account_ids    = length(var.account_ids) == 0 ? [data.aws_caller_identity.current.account_id] : var.account_ids
  resource_types = var.resource_types
}

resource "aws_inspector2_organization_configuration" "this" {
  count = var.organization == null ? 0 : 1

  region = var.region

  auto_enable {
    ec2         = var.organization.auto_enable.ec2
    ecr         = var.organization.auto_enable.ecr
    lambda      = var.organization.auto_enable.lambda
    lambda_code = var.organization.auto_enable.lambda_code
  }

  # The delegated administrator must have Inspector enabled before it can configure the organization.
  depends_on = [aws_inspector2_enabler.this]
}
