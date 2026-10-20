locals {
  published_strings = {
    db_endpoint        = module.db.writer_endpoint
    db_reader_endpoint = module.db.reader_endpoint
    db_proxy_endpoint  = module.db.proxy_endpoint
    db_secret_arn      = module.db.master_user_secret_arn
    # Redis endpoints are host:port; clients need a cluster-aware client and TLS.
    rate_limit_redis_endpoint = "${module.redis["rate-limit"].configuration_endpoint}:${module.redis["rate-limit"].port}"
    stream_redis_endpoint     = "${module.redis["stream"].configuration_endpoint}:${module.redis["stream"].port}"
    stream_redis_id           = module.redis["stream"].replication_group_id
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.0"

  ssm_prefix = local.ssm_prefix
  stack      = "database"
  strings    = local.published_strings
}
