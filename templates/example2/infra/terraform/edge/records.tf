# api.<zone> is what clients use (both alias types: the distribution has IPv6 on). origin-api.<zone> is the name
# CloudFront resolves to reach the ALB; it stays public because the ALB is public (design D3).
locals {
  dns_records = merge(
    {
      for type in ["A", "AAAA"] : "api_${lower(type)}" => {
        name  = local.api_domain
        type  = type
        alias = { name = module.cdn.domain_name, zone_id = module.cdn.hosted_zone_id }
      }
    },
    {
      origin_api_a = {
        name  = local.origin_domain
        type  = "A"
        alias = { name = module.in.strings["alb_dns_name"], zone_id = module.in.strings["alb_zone_id"] }
      }
    },
  )
}

module "records" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/route53-record/aws"
  version = "~> 0.1.0"

  zone_id = module.shared.strings["zone_id"]
  records = local.dns_records
}
