# The ALB is internal and serves HTTP only, so both directions stay inside the VPC CIDR. The api service's own group
# lives in the application stack (applied later) and admits this group; the egress here cannot name that group yet,
# so it allows the app port towards the VPC CIDR.
locals {
  security_groups = {
    alb = { name = "${local.name_prefix}-alb", description = "Internal application load balancer" }
  }

  sg_rules = {
    alb_in_http_vpc = {
      security_group = "alb"
      type           = "ingress"
      description    = "HTTP from inside the VPC"
      from_port      = local.listener_port
      cidr_ipv4      = module.in.strings["vpc_cidr"]
    }
    alb_out_app_vpc = {
      security_group = "alb"
      type           = "egress"
      description    = "to the api tasks"
      from_port      = var.app_port
      cidr_ipv4      = module.in.strings["vpc_cidr"]
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
