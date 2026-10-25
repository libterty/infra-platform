locals {
  # The pipeline ARN is the one the iam-base scheduler role may start (naming rule <name_prefix>-training).
  schedules = {
    "${local.name_prefix}-weekly-training" = {
      expression = "cron(0 3 ? * MON *)"
      timezone   = "Asia/Taipei"
      state      = var.training_schedule_state
      target     = { arn = module.pipeline.pipeline_arn, role_arn = module.in.strings["role_scheduler_arn"] }
    }
  }
}

module "schedule" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/scheduler-schedule/aws"
  version = "~> 0.1.0"

  kms_key_arn = module.in.strings["kms_key_arn"]
  schedules   = local.schedules
}
