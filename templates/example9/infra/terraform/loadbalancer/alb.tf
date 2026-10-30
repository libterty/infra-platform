# Internal ALB on HTTP:80 (design 8.1). No certificate: the alb module then serves the rules on the HTTP listener, and
# the application stack's ecs-service adds its own target group and listener rule to it.
locals {
  listener_port = 80

  alb = {
    name                = "${local.name_prefix}-alb"
    internal            = true
    subnet_ids          = module.in.lists["app_subnet_ids"]
    security_group_ids  = [module.sg.security_group_ids["alb"]]
    deletion_protection = var.deletion_protection
    sns_topic_arns      = [module.in.strings["alert_topic_arn"]]
  }
}

module "alb" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/alb/aws"
  version = "~> 0.5.1"

  name                = local.alb.name
  internal            = local.alb.internal
  subnet_ids          = local.alb.subnet_ids
  security_group_ids  = local.alb.security_group_ids
  deletion_protection = local.alb.deletion_protection
  sns_topic_arns      = local.alb.sns_topic_arns
}
