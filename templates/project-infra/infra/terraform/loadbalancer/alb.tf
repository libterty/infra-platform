locals {
  alb_wiring = {
    subnet_ids         = module.in.lists["subnet_ids_public"]
    security_group_ids = [module.in.strings["sg_alb_id"]]
    sns_topic_arns     = [module.in.strings["alarm_topic_arn"]]
  }
}

module "alb" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/alb/aws"
  version = "~> 0.5.0"

  name                = "${local.name_prefix}-alb"
  subnet_ids          = local.alb_wiring.subnet_ids
  security_group_ids  = local.alb_wiring.security_group_ids
  certificate_arn     = var.certificate_arn
  idle_timeout        = var.idle_timeout
  deletion_protection = var.deletion_protection
  web_acl_arn         = var.web_acl_arn
  sns_topic_arns      = local.alb_wiring.sns_topic_arns
}

# Access logs go through CloudWatch Logs vended delivery; the bucket policy (vended_logs) is set in foundation.
locals {
  alb_access_logs = {
    sources      = { access = { resource_arn = module.alb.alb_arn, log_type = "ALB_ACCESS_LOGS" } }
    destinations = { bucket = { type = "S3", resource_arn = module.in.strings["alb_log_bucket_arn"] } }
    deliveries   = { access = { source = "access", destination = "bucket" } }
  }
}

module "alb_access_logs" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/log-delivery/aws"
  version = "~> 0.2.0"
  count   = var.access_logs_enabled ? 1 : 0

  name_prefix  = "${local.name_prefix}-alb"
  sources      = local.alb_access_logs.sources
  destinations = local.alb_access_logs.destinations
  deliveries   = local.alb_access_logs.deliveries
}
