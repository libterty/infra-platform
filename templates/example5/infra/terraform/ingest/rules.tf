locals {
  # Rule names cannot contain hyphens. The iam-base trust of the iot-rule role is limited to rule/<this prefix>_*.
  rule_prefix = replace(local.name_prefix, "-", "_")
  stream_name = element(split("/", local.stream_arn), 1)

  # Devices publish to <name_prefix>/telemetry/<thing>, core devices their inference results to
  # <name_prefix>/inference/<thing> (fleet policies). Both go to the stream; Firehose delivers them to S3 and
  # OpenSearch (design K15). Documents for OpenSearch carry @timestamp from the device (the ISM cold transition of
  # search-config needs it).
  kinesis_action = [{
    stream_name   = local.stream_name
    role_arn      = module.in.strings["role_iot_rule_arn"]
    partition_key = "$${topic(3)}"
  }]

  rules = {
    "${local.rule_prefix}_telemetry" = {
      sql         = "SELECT *, topic(3) AS thing_name, 'telemetry' AS kind FROM '${local.name_prefix}/telemetry/+'"
      description = "Device telemetry to the Kinesis stream"
      actions     = { kinesis = local.kinesis_action }
    }
    "${local.rule_prefix}_inference" = {
      sql         = "SELECT *, topic(3) AS thing_name, 'inference' AS kind FROM '${local.name_prefix}/inference/+'"
      description = "Edge inference results to the Kinesis stream"
      actions     = { kinesis = local.kinesis_action }
    }
  }

  # Shared by every rule: failed actions go to the rule-errors queue of storage, which alarms on it.
  error_action = {
    sqs = {
      queue_url  = module.in.strings["rule_errors_queue_url"]
      role_arn   = module.in.strings["role_iot_rule_arn"]
      use_base64 = false
    }
  }
}

module "rules" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/iot-topic-rule/aws"
  version = "~> 0.1.0"

  rules        = local.rules
  error_action = local.error_action
}
