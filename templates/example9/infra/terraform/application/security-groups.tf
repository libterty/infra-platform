# The api tasks accept only the ALB group on the app port. They call ECR, CloudWatch Logs and other AWS APIs through
# the NAT, so egress is HTTPS anywhere.
locals {
  security_groups = {
    api = { name = "${local.name_prefix}-api", description = "api ECS tasks" }
  }

  sg_rules = {
    api_in_alb = {
      security_group = "api"
      type           = "ingress"
      description    = "from the ALB"
      from_port      = var.app_port
      peer_group_id  = module.in.strings["alb_security_group_id"]
    }
    api_out_https = {
      security_group = "api"
      type           = "egress"
      description    = "AWS APIs through the NAT"
      from_port      = 443
      cidr_ipv4      = "0.0.0.0/0"
    }
  }
}

module "sg" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/security-group/aws"
  version = "~> 0.1.1"

  vpc_id          = module.in.strings["vpc_id"]
  security_groups = local.security_groups
  rules           = local.sg_rules
}
