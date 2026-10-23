# The breaker of the canary (design v4 §6.1, lb-traffic-breaker): alarms on the canary target group, and a Lambda that
# sets the weighted api rules to stable 100 when one fires. Its role lives here, not in the iam stack, because it is
# scoped to the rule ARNs of this stack, which iam runs too early to know.
locals {
  breaker_enabled  = try(var.canary.breaker, null) != null
  breaker_name     = "${local.name_prefix}-traffic-breaker"
  breaker_settings = local.breaker_enabled ? var.canary.breaker : null

  # Alarm names carry the breaker key, which allows lowercase letters, digits and hyphens only.
  breakers = local.breaker_enabled ? {
    for k in keys(local.api_routes) : replace(k, "_", "-") => {
      rule_arn                       = module.alb.listener_rule_arns[k]
      stable_target_group_arn        = module.alb.target_group_arns["api"]
      canary_target_group_arn_suffix = module.alb.target_group_arn_suffixes["api-canary"]
      error_rate_percent             = local.breaker_settings.error_rate_percent
      min_requests                   = local.breaker_settings.min_requests
      min_healthy_hosts              = local.breaker_settings.min_healthy_hosts
    }
  } : {}

  breaker_image_uri = local.breaker_enabled ? "${jsondecode(module.shared.strings["ecr_repository_urls"])["traffic-breaker"]}:${local.breaker_settings.image_tag}" : null

  breaker_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RewriteWeightedRules"
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:ModifyRule", "elasticloadbalancing:AddTags"]
        Resource = [for b in values(local.breakers) : b.rule_arn]
      },
      {
        # Describe actions do not support resource-level permissions.
        Sid      = "ReadRules"
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:DescribeListeners", "elasticloadbalancing:DescribeRules"]
        Resource = "*"
      },
      {
        # lambda-function creates the log group; the role only writes to it.
        Sid      = "WriteLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.aws_region}:${var.expected_account_id}:log-group:/aws/lambda/${local.breaker_name}:*"
      },
    ]
  })
}

module "breaker_role" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/iam-role/aws"
  version = "~> 0.4.0"

  count = local.breaker_enabled ? 1 : 0

  name            = local.breaker_name
  trust           = { service_principals = ["lambda.amazonaws.com"], source_account = var.expected_account_id }
  inline_policies = { breaker = local.breaker_policy }
}

module "breaker_function" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/lambda-function/aws"
  version = "~> 0.1.0"

  count = local.breaker_enabled ? 1 : 0

  name        = local.breaker_name
  image_uri   = local.breaker_image_uri
  role_arn    = module.breaker_role[0].arn
  environment = { BREAKER_CONFIG = module.breaker[0].lambda_config_json }
  permissions = module.breaker[0].lambda_permissions
}

module "breaker" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/lb-traffic-breaker/aws"
  version = "~> 0.1.0"

  count = local.breaker_enabled ? 1 : 0

  name                     = "${local.name_prefix}-canary"
  load_balancer_type       = "application"
  load_balancer_arn_suffix = module.alb.alb_arn_suffix
  breakers                 = local.breakers
  lambda_function_arn      = module.breaker_function[0].function_arn
  sns_topic_arns           = [module.shared.strings["alarm_topic_arn"]]
}
