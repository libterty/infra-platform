locals {
  ssm_input_strings = {
    signing_private_key_secret_arn = "foundation/signing_private_key_secret_arn"
    signing_public_key_secret_arn  = "foundation/signing_public_key_secret_arn"
    agent_runtimes                 = "containerimage/agent_runtimes"
    ecr_repository_arns            = "containerimage/ecr_repository_arns"
    db_secret_arn                  = "database/db_secret_arn"
  }
}

module "in" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-read/aws"
  version = "~> 0.1.0"

  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_input_strings
}
