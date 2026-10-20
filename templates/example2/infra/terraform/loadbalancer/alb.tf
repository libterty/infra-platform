locals {
  alb_name               = "${local.name_prefix}-alb"
  access_log_bucket_name = "${local.name_prefix}-alb-access-logs-${var.expected_account_id}"

  # The api paths are matched with their subtree. Priority gaps leave room to add rules without renumbering.
  api_routes = {
    api_stream = { priority = 10, path = "/api/stream" }
    api_quota  = { priority = 20, path = "/api/quota" }
    api_admin  = { priority = 30, path = "/api/admin" }
  }

  listener_rules = merge(
    {
      for k, r in local.api_routes : k => {
        priority      = r.priority
        target_group  = "api"
        path_patterns = [r.path, "${r.path}/*"]
        host_headers  = var.origin_verify_host_headers
        # The alb module defaults to false: without this the rule would silently skip the header condition.
        require_origin_verify = true
      }
    },
    var.dev_page_enabled ? {
      dev_page = {
        priority              = 100
        target_group          = "api"
        path_patterns         = ["/dev/page", "/dev/page/*"]
        host_headers          = []
        require_origin_verify = false
      }
    } : {},
  )
}

module "alb_logs" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/s3-bucket/aws"
  version = "~> 0.2.0"

  name            = local.access_log_bucket_name
  log_delivery    = ["alb_access_logs"]
  expiration_days = var.access_log_retention_days
}

module "alb" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/alb/aws"
  version = "~> 0.3.0"

  name                = local.alb_name
  subnet_ids          = module.shared.lists["public_subnet_ids"]
  security_group_ids  = [module.shared.strings["alb_sg_id"]]
  certificate_arn     = var.certificate_arn
  idle_timeout        = var.idle_timeout
  deletion_protection = var.deletion_protection
  # The object form keeps the association count known at plan time while the Web ACL ARN is not (alb 0.3.0).
  web_acl        = { arn = module.waf.web_acl_arn }
  sns_topic_arns = [module.shared.strings["alarm_topic_arn"]]

  vpc_id = module.shared.strings["vpc_id"]
  target_groups = {
    api = {
      port                 = var.app_port
      deregistration_delay = var.deregistration_delay
      health_check         = { path = "/health" }
    }
  }
  listener_rules = local.listener_rules

  origin_verify_header_name  = var.origin_verify_header_name
  origin_verify_header_value = var.origin_verify_header_value

  access_logs = { bucket = module.alb_logs.bucket_name, prefix = local.name_prefix }

  # ALB checks write access to the bucket when access logs are switched on, and the bucket policy is a separate
  # resource inside the module; depending on the bucket name alone would let the ALB be created before the policy.
  depends_on = [module.alb_logs]
}
