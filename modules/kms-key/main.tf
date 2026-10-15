data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # The account root statement must stay first and must never be dropped, or IAM can no longer grant access to the key.
  root_statement = {
    Sid       = "EnableAccountRoot"
    Effect    = "Allow"
    Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
    Action    = "kms:*"
    Resource  = "*"
  }

  administrator_statements = length(var.administrator_arns) == 0 ? [] : [{
    Sid       = "AllowKeyAdministration"
    Effect    = "Allow"
    Principal = { AWS = var.administrator_arns }
    Action = [
      "kms:Create*", "kms:Describe*", "kms:Enable*", "kms:List*", "kms:Put*", "kms:Update*",
      "kms:Revoke*", "kms:Disable*", "kms:Get*", "kms:Delete*", "kms:TagResource", "kms:UntagResource",
      "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion",
    ]
    Resource = "*"
  }]

  # Sid allows letters and digits only.
  service_statements = [for principal, cfg in var.service_principals : merge(
    {
      Sid       = "AllowService${replace(principal, "/[^a-zA-Z0-9]/", "")}"
      Effect    = "Allow"
      Principal = { Service = principal }
      Action    = cfg.actions
      Resource  = "*"
    },
    length(cfg.conditions) == 0 ? {} : {
      Condition = {
        for t in distinct([for c in cfg.conditions : c.test]) :
        t => { for c in cfg.conditions : c.variable => c.values if c.test == t }
      }
    }
  )]
}

resource "aws_kms_key" "this" {
  description              = var.description
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  multi_region             = false
  enable_key_rotation      = true
  deletion_window_in_days  = var.deletion_window_in_days

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_kms_key_policy" "this" {
  key_id = aws_kms_key.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [local.root_statement],
      local.administrator_statements,
      local.service_statements,
    )
  })
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.name}"
  target_key_id = aws_kms_key.this.key_id
}
