locals {
  alb_name               = "${local.name_prefix}-alb"
  access_log_bucket_name = "${local.name_prefix}-alb-access-logs-${var.expected_account_id}"

  # The api paths are matched with their subtree. Priority gaps leave room to add rules without renumbering.
  api_routes = {
    api_stream = { priority = 10, path = "/api/stream" }
    api_quota  = { priority = 20, path = "/api/quota" }
    api_admin  = { priority = 30, path = "/api/admin" }
  }

  # With a canary the api rules forward to both target groups by weight; the breaker rewrites only these rules.
  api_target = var.canary == null ? { target_group = "api", forward = null } : {
    target_group = null
    forward = {
      targets = {
        stable = { target_group = "api", target_group_arn = null, weight = 100 - var.canary.weight }
        canary = { target_group = "api-canary", target_group_arn = null, weight = var.canary.weight }
      }
      stickiness_duration = null
    }
  }

  api_target_group = {
    port                 = var.app_port
    deregistration_delay = var.deregistration_delay
    health_check         = { path = "/health" }
  }
  target_groups = merge(
    { api = local.api_target_group },
    var.canary == null ? {} : { "api-canary" = local.api_target_group },
  )

  listener_rules = merge(
    {
      for k, r in local.api_routes : k => {
        priority      = r.priority
        target_group  = local.api_target.target_group
        forward       = local.api_target.forward
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
        forward               = null
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
  version = "~> 0.3.0"

  name            = local.access_log_bucket_name
  log_delivery    = ["vended_logs"]
  expiration_days = var.access_log_retention_days
}

module "alb" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/alb/aws"
  version = "~> 0.5.0"

  name                = local.alb_name
  subnet_ids          = module.shared.lists["public_subnet_ids"]
  security_group_ids  = [module.shared.strings["alb_sg_id"]]
  certificate_arn     = var.certificate_arn
  idle_timeout        = var.idle_timeout
  deletion_protection = var.deletion_protection
  # The object form keeps the association count known at plan time while the Web ACL ARN is not (alb 0.3.0).
  web_acl        = { arn = module.waf.web_acl_arn }
  sns_topic_arns = [module.shared.strings["alarm_topic_arn"]]

  vpc_id         = module.shared.strings["vpc_id"]
  target_groups  = local.target_groups
  listener_rules = local.listener_rules

  origin_verify_header_name  = var.origin_verify_header_name
  origin_verify_header_value = var.origin_verify_header_value
}

# Access logs go through CloudWatch Logs vended delivery into the bucket above (vended_logs).
locals {
  alb_access_logs = {
    sources      = { access = { resource_arn = module.alb.alb_arn, log_type = "ALB_ACCESS_LOGS" } }
    destinations = { bucket = { type = "S3", resource_arn = module.alb_logs.arn } }
    deliveries   = { access = { source = "access", destination = "bucket" } }
  }
}

module "alb_access_logs" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/log-delivery/aws"
  version = "~> 0.2.0"

  name_prefix  = local.alb_name
  sources      = local.alb_access_logs.sources
  destinations = local.alb_access_logs.destinations
  deliveries   = local.alb_access_logs.deliveries

  # The bucket policy is a separate resource inside s3-bucket; depending on the ARN alone would let the delivery be
  # created before CloudWatch Logs is allowed to write.
  depends_on = [module.alb_logs]
}
