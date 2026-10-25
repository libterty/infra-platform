locals {
  ota_bucket_name = element(split(":::", module.in.strings["ota_bucket_arn"]), 1)

  # Signer names take no hyphens. The certificate is imported into ACM outside Terraform (design K17).
  ota_signing = {
    name            = "${replace(local.name_prefix, "-", "_")}_ota"
    platform_id     = "AWSIoTDeviceManagement-SHA256-ECDSA"
    certificate_arn = var.ota_signing_certificate_arn
  }

  # CI signs the firmware and uploads it to signed/current/firmware.bin before it creates a job from this template; the
  # bucket is versioned, so earlier firmware stays recoverable. Each job is created by CI, not Terraform (design K7).
  ota_job = {
    job_template_id = "${local.name_prefix}-ota"
    description     = "OTA firmware update of ${local.name_prefix} devices"
    document = {
      operation = "firmware-update"
      files     = [{ url = "$${aws:iot:s3-presigned-url:https://s3.amazonaws.com/${local.ota_bucket_name}/signed/current/firmware.bin}" }]
    }
    presigned_url   = { role_arn = module.in.strings["role_ota_presign_arn"], expires_in_sec = 3600 }
    rollout         = { maximum_per_minute = var.ota_rollout.maximum_per_minute }
    abort           = [{ failure_type = "FAILED", threshold_percentage = var.ota_rollout.abort_threshold_percentage, min_number_of_executed_things = 10 }]
    timeout_minutes = 60
  }
}

module "ota_signing" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ota-signing/aws"
  version = "~> 0.1.0"

  name            = local.ota_signing.name
  platform_id     = local.ota_signing.platform_id
  certificate_arn = local.ota_signing.certificate_arn
}

module "ota_job" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/iot-job-template/aws"
  version = "~> 0.1.0"

  job_template_id = local.ota_job.job_template_id
  description     = local.ota_job.description
  document        = local.ota_job.document
  presigned_url   = local.ota_job.presigned_url
  rollout         = local.ota_job.rollout
  abort           = local.ota_job.abort
  timeout_minutes = local.ota_job.timeout_minutes
  tags            = local.awscc_tags
}
