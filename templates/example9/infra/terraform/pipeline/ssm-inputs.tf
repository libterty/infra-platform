locals {
  ssm_input_strings = {
    kms_key_arn             = "foundation/kms_key_arn"
    artifact_bucket_name    = "foundation/artifact_bucket_name"
    alert_topic_arn         = "foundation/alert_topic_arn"
    connection_arn          = "foundation/connection_arn"
    api_repository_url      = "containerimage/api_repository_url"
    fn_repository_url       = "containerimage/fn_repository_url"
    api_build_role_arn      = "iam/api_build_role_arn"
    api_deploy_role_arn     = "iam/api_deploy_role_arn"
    fn_build_role_arn       = "iam/fn_build_role_arn"
    web_build_role_arn      = "iam/web_build_role_arn"
    web_invalidate_role_arn = "iam/web_invalidate_role_arn"
    pipeline_role_arn       = "iam/pipeline_role_arn"
    cluster_name            = "application/cluster_name"
    api_service_name        = "application/api_service_name"
    api_task_family         = "application/api_task_family"
    fn_function_name        = "application/fn_function_name"
    fn_alias_name           = "application/fn_alias_name"
    web_bucket_name         = "web/web_bucket_name"
    distribution_id         = "web/distribution_id"
  }
  ssm_input_lists = {}
}

module "in" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-read/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_input_strings
  lists      = local.ssm_input_lists
}
