locals {
  shared_input_strings = {
    vpc_id          = "infra/vpc_id"
    app_sg_id       = "infra/app_sg_id"
    bastion_sg_id   = "infra/bastion_sg_id"
    lambda_role_arn = "infra/lambda_role_arn"
    alarm_topic_arn = "infra/alarm_topic_arn"
  }

  shared_input_lists = {
    app_subnet_ids = "infra/app_subnet_ids"
  }
}

module "shared" {
  # Tree B: published by the bridge stack, or by someone else for envs listed in EXTERNAL_SHARED_ENVS (stacks.sh).
  source  = "app.terraform.io/libterty/ssm-read/aws"
  version = "~> 0.1.0"

  ssm_prefix = local.shared_ssm_prefix
  strings    = local.shared_input_strings
  lists      = local.shared_input_lists
}
