locals {
  ssm_input_strings = {
    alb_arn_suffix            = "loadbalancer/alb_arn_suffix"
    target_group_arn_suffixes = "loadbalancer/target_group_arn_suffixes"
    waf_web_acl_name          = "loadbalancer/waf_web_acl_name"
    cluster_name              = "application/cluster_name"
    api_service_name          = "application/api_service_name"
    worker_service_name       = "application/worker_service_name"
    api_log_group_name        = "application/api_log_group_name"
    agent_runtime_arns        = "agent/agent_runtime_arns"
  }

  shared_input_strings = {
    alarm_topic_arn = "infra/alarm_topic_arn"
    stream_redis_id = "infra/stream_redis_id"
  }
}

module "in" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-read/aws"
  version = "~> 0.1.0"

  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_input_strings
}

module "shared" {
  # Tree B: published by the bridge stack, or by someone else for envs listed in EXTERNAL_SHARED_ENVS (stacks.sh).
  source  = "app.terraform.io/libterty/ssm-read/aws"
  version = "~> 0.1.0"

  ssm_prefix = local.shared_ssm_prefix
  strings    = local.shared_input_strings
}
