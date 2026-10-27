locals {
  # IoT rules put device telemetry here; Firehose reads it (design section 7.1). Provisioned with one shard
  # (design section 7.5); 24 hours is the shortest retention and carries no extra charge.
  stream = {
    name            = "${local.name_prefix}-telemetry"
    mode            = "PROVISIONED"
    shard_count     = 1
    retention_hours = 24
  }
}

module "stream" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/kinesis-stream/aws"
  version = "~> 0.1.0"

  name            = local.stream.name
  kms_key_arn     = local.kms_key_arn
  mode            = local.stream.mode
  shard_count     = local.stream.shard_count
  retention_hours = local.stream.retention_hours
}
