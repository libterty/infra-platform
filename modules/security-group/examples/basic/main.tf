terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

module "sg" {
  source = "../.."

  vpc_id = "vpc-0123456789abcdef0"

  security_groups = {
    alb      = { name = "alpha-dev-alb", description = "ALB" }
    api      = { name = "alpha-dev-api", description = "api service" }
    db_proxy = { name = "alpha-dev-db-proxy", description = "RDS Proxy" }
    db       = { name = "alpha-dev-db", description = "database" }
  }

  rules = {
    alb_in_https  = { security_group = "alb", type = "ingress", description = "clients", from_port = 443, cidr_ipv4 = "0.0.0.0/0", allow_internet = true }
    alb_out_api   = { security_group = "alb", type = "egress", description = "to api", from_port = 8080, peer_group = "api" }
    api_in_alb    = { security_group = "api", type = "ingress", description = "from alb", from_port = 8080, peer_group = "alb" }
    api_out_https = { security_group = "api", type = "egress", description = "AWS APIs", from_port = 443, cidr_ipv4 = "0.0.0.0/0" }
    api_out_proxy = { security_group = "api", type = "egress", description = "to db proxy", from_port = 5432, peer_group = "db_proxy" }
    proxy_in_api  = { security_group = "db_proxy", type = "ingress", description = "from api", from_port = 5432, peer_group = "api" }
    proxy_out_db  = { security_group = "db_proxy", type = "egress", description = "to db", from_port = 5432, peer_group = "db" }
    db_in_proxy   = { security_group = "db", type = "ingress", description = "from db proxy", from_port = 5432, peer_group = "db_proxy" }
  }

  tags = {
    Project = "alpha"
  }
}

output "security_group_ids" {
  value = module.sg.security_group_ids
}
