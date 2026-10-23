data "aws_vpc" "this" {
  id = module.shared.strings["vpc_id"]
}

# Read only in vpc_and_cdn mode.
data "aws_ec2_managed_prefix_list" "cdn_origin_facing" {
  count = var.trusted_proxies == "vpc_and_cdn" ? 1 : 0

  name = "com.amazonaws.global.cloudfront.origin-facing"
}

locals {
  # The two workloads CI deploys with deploy/charts/app; containerimage must have a repository for each.
  workloads = ["api", "worker"]
  # iam allows the worker to publish metrics only into this namespace.
  metric_namespace = "${title(var.project)}/${var.env}"

  ecr_urls = jsondecode(module.shared.strings["ecr_repository_urls"])

  # "*" makes uvicorn take the leftmost X-Forwarded-For entry, which the caller writes itself; CIDRs make it look for
  # the first hop from the right that is not trusted. The CloudFront ranges are sorted because the entries are a set and
  # a different order would change the environment JSON on every plan.
  forwarded_allow_ips = var.trusted_proxies == "any" ? "*" : join(",", concat(
    [data.aws_vpc.this.cidr_block],
    var.trusted_proxies == "vpc_and_cdn"
    ? sort([for e in data.aws_ec2_managed_prefix_list.cdn_origin_facing[0].entries : e.cidr])
    : [],
  ))

  stream_redis = split(":", module.shared.strings["stream_redis_endpoint"])
  rate_redis   = split(":", module.shared.strings["rate_limit_redis_endpoint"])

  # The workloads get secret ARNs and fetch the values with their Pod Identity role (design v4 §8.2).
  common_environment = {
    AWS_REGION                    = var.aws_region
    APP_ENV                       = var.env
    DB_HOST                       = module.shared.strings["db_proxy_endpoint"]
    DB_NAME                       = module.shared.strings["db_name"]
    DB_SSLMODE                    = "require"
    DB_SECRET_ARN                 = module.shared.strings["db_secret_arn"]
    SIGNING_PUBLIC_KEY_SECRET_ARN = module.shared.strings["signing_public_key_secret_arn"]
    STREAM_REDIS_HOST             = local.stream_redis[0]
    STREAM_REDIS_PORT             = local.stream_redis[1]
    STREAM_REDIS_TLS              = "true"
    STREAM_SHARDS                 = module.shared.strings["stream_shard_count"]
    STREAM_LENGTH_CAP             = tostring(var.stream_length_cap)
  }

  api_environment = merge(local.common_environment, {
    PORT                           = tostring(var.app_port)
    SIGNING_PRIVATE_KEY_SECRET_ARN = module.shared.strings["signing_private_key_secret_arn"]
    AGENT_RUNTIME_ARNS             = module.in.strings["agent_runtime_arns"]
    GUARDRAIL_IDS                  = module.in.strings["guardrail_ids"]
    REDIS_HOST                     = local.rate_redis[0]
    REDIS_PORT                     = local.rate_redis[1]
    REDIS_TLS                      = "true"
    CORS_ALLOW_ORIGINS             = join(",", var.cors_allow_origins)
    FORWARDED_ALLOW_IPS            = local.forwarded_allow_ips
  })

  worker_environment = merge(local.common_environment, {
    METRICS_NAMESPACE = local.metric_namespace
  })

}
