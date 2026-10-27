locals {
  # <name_prefix>-cam-<id>: the name the iam-base TES policy allows and the sitewise camera model names.
  kvs_streams = {
    for id, c in var.cameras : "${local.name_prefix}-cam-${id}" => { retention_hours = c.retention_hours, device_name = c.core_thing_name }
  }
}

module "kvs" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/kinesis-video-stream/aws"
  version = "~> 0.1.0"
  count   = length(var.cameras) == 0 ? 0 : 1

  kms_key_arn = module.in.strings["kms_key_arn"]
  streams     = local.kvs_streams
}
