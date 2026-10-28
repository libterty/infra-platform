# One public subdomain zone per env (design D4). The NS delegation in the parent domain is a manual step between this
# stack and certificate; without it the certificate validation waits until it times out.
module "zone" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/route53-zone/aws"
  version = "~> 0.1.0"

  name    = var.domain_name
  comment = "Public zone of ${local.name_prefix}"
}
