locals {
  shared_input_strings = {
    vpc_id          = "infra/vpc_id"
    alb_sg_id       = "infra/alb_sg_id"
    alarm_topic_arn = "infra/alarm_topic_arn"
    # Regional certificate for api.<zone> and origin-api.<zone>, issued by the certificate stack.
    alb_certificate_arn = "infra/alb_certificate_arn"
  }

  shared_input_lists = {
    public_subnet_ids = "infra/public_subnet_ids"
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
