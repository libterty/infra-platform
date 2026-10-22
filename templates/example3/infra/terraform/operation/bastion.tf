locals {
  bastion_name = "${local.name_prefix}-bastion"

  bastion_trust = {
    service_principals = toset(["ec2.amazonaws.com"])
    source_account     = var.expected_account_id
  }

  # What the SSM agent needs to register and to open Session Manager sessions. None of these actions supports
  # resource-level permissions, so the only valid Resource is "*".
  bastion_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SessionManagerAgent"
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssm:ListInstanceAssociations",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply",
        ]
        Resource = "*"
      },
    ]
  }
}

module "bastion_role" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/iam-role/aws"
  version = "~> 0.2.0"

  count = var.bastion_enabled ? 1 : 0

  name                  = local.bastion_name
  trust                 = local.bastion_trust
  inline_policies       = { session_manager = jsonencode(local.bastion_policy) }
  instance_profile_name = local.bastion_name
}

module "bastion" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ec2-bastion/aws"
  version = "~> 0.1.0"

  count = var.bastion_enabled ? 1 : 0

  name                  = local.bastion_name
  subnet_id             = module.shared.lists["app_subnet_ids"][0]
  security_group_ids    = [module.shared.strings["bastion_sg_id"]]
  instance_profile_name = module.bastion_role[0].instance_profile_name
  instance_type         = var.bastion_instance_size
}
