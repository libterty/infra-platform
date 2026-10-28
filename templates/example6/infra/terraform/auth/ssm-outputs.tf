locals {
  published_strings = {
    issuer_url    = module.user_pool.issuer_url
    spa_client_id = module.user_pool.client_ids["spa"]
    user_pool_arn = module.user_pool.user_pool_arn
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  stack      = "auth"
  strings    = local.published_strings
}
