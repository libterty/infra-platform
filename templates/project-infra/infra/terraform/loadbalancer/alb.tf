locals {
  alb_wiring = {
    subnet_ids         = module.in.lists["subnet_ids_public"]
    security_group_ids = [module.in.strings["sg_alb_id"]]
    sns_topic_arns     = [module.in.strings["alarm_topic_arn"]]
    access_logs        = var.access_logs_enabled ? { bucket = module.in.strings["alb_log_bucket_name"], prefix = local.name_prefix } : null
  }
}

module "alb" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/alb/aws"
  version = "~> 0.1.0"

  name                = "${local.name_prefix}-alb"
  subnet_ids          = local.alb_wiring.subnet_ids
  security_group_ids  = local.alb_wiring.security_group_ids
  certificate_arn     = var.certificate_arn
  idle_timeout        = var.idle_timeout
  deletion_protection = var.deletion_protection
  access_logs         = local.alb_wiring.access_logs
  web_acl_arn         = var.web_acl_arn
  sns_topic_arns      = local.alb_wiring.sns_topic_arns
}
