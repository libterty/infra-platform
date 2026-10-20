data "aws_vpc" "this" {
  id = module.shared.strings["vpc_id"]
}

# Read only in vpc_and_cloudfront mode.
data "aws_ec2_managed_prefix_list" "cloudfront_origin_facing" {
  count = var.forwarded_allow_ips_trust == "vpc_and_cloudfront" ? 1 : 0

  name = "com.amazonaws.global.cloudfront.origin-facing"
}

locals {
  ecr_urls = jsondecode(module.shared.strings["ecr_repository_urls"])

  # "*" makes uvicorn take the leftmost X-Forwarded-For entry, which the caller writes itself; CIDRs make it look for
  # the first hop from the right that is not trusted. The CloudFront ranges are sorted because the entries are a set and
  # a different order would register a new task definition on every plan.
  forwarded_allow_ips = var.forwarded_allow_ips_trust == "any" ? "*" : join(",", concat(
    [data.aws_vpc.this.cidr_block],
    var.forwarded_allow_ips_trust == "vpc_and_cloudfront"
    ? sort([for e in data.aws_ec2_managed_prefix_list.cloudfront_origin_facing[0].entries : e.cidr])
    : [],
  ))

  stream_redis = split(":", module.shared.strings["stream_redis_endpoint"])
  rate_redis   = split(":", module.shared.strings["rate_limit_redis_endpoint"])

  # The execution role cannot read secrets, so the tasks get ARNs and fetch the values with their task role.
  common_environment = {
    AWS_REGION                    = var.aws_region
    APP_ENV                       = var.env
    DB_HOST                       = module.shared.strings["db_proxy_endpoint"]
    DB_NAME                       = var.db_name
    DB_SSLMODE                    = "require"
    DB_SECRET_ARN                 = module.shared.strings["db_secret_arn"]
    SIGNING_PUBLIC_KEY_SECRET_ARN = module.shared.strings["signing_public_key_secret_arn"]
    STREAM_REDIS_HOST             = local.stream_redis[0]
    STREAM_REDIS_PORT             = local.stream_redis[1]
    STREAM_REDIS_TLS              = "true"
    STREAM_SHARDS                 = tostring(var.redis_stream_shards)
    STREAM_MAXLEN                 = tostring(var.redis_stream_maxlen)
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

  # Idle streams are cut by middleboxes without a word; probing earlier makes dead peers visible.
  system_controls = {
    "net.ipv4.tcp_keepalive_time"   = "60"
    "net.ipv4.tcp_keepalive_intvl"  = "10"
    "net.ipv4.tcp_keepalive_probes" = "3"
  }
}
