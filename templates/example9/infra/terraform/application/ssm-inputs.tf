locals {
  ssm_input_strings = {
    api_repository_url     = "containerimage/api_repository_url"
    fn_repository_url      = "containerimage/fn_repository_url"
    kms_key_arn            = "foundation/kms_key_arn"
    vpc_id                 = "network/vpc_id"
    api_execution_role_arn = "iam/api_execution_role_arn"
    api_task_role_arn      = "iam/api_task_role_arn"
    fn_role_arn            = "iam/fn_role_arn"
    listener_arn           = "loadbalancer/listener_arn"
    alb_security_group_id  = "loadbalancer/security_group_id"
  }
  ssm_input_lists = {
    app_subnet_ids = "network/app_subnet_ids"
  }
}

module "in" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-read/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_input_strings
  lists      = local.ssm_input_lists
}
