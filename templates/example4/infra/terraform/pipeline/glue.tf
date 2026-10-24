locals {
  # Naming rule shared with iam-base (design K21): it builds the workflow ARN and the rule ARN from the same strings, so
  # the tests pin them. glue-etl names the rule and the EVENT trigger <workflow>-s3-event.
  workflow_name = "${local.name_prefix}-raw-to-curated"

  # The job name must start with <name_prefix>-: iam-base grants the bookmark permissions on job/<name_prefix>-*.
  job_name = "${local.workflow_name}-job"

  # One run a day keeps the crawler cost fixed; events run the job only (design K22). 18:00 UTC is 02:00 in Taipei.
  crawlers = {
    raw = {
      role_arn      = module.in.strings["role_glue_crawler_arn"]
      database_name = module.in.strings["raw_database_name"]
      s3_paths      = ["s3://${local.raw_bucket_name}/raw/"]
      schedule      = "cron(0 18 * * ? *)"
    }
  }

  jobs = {
    raw_to_curated = {
      name              = local.job_name
      role_arn          = module.in.strings["role_glue_job_arn"]
      script_location   = "s3://${local.glue_assets_bucket_name}/scripts/raw_to_curated.py"
      execution_class   = "FLEX"
      worker_type       = "G.1X"
      number_of_workers = 2
      default_arguments = {
        "--job-bookmark-option" = "job-bookmark-enable"
        "--TempDir"             = "s3://${local.glue_assets_bucket_name}/tmp/"
        "--raw_database"        = module.in.strings["raw_database_name"]
        "--curated_database"    = module.in.strings["curated_database_name"]
        "--raw_path"            = "s3://${local.raw_bucket_name}/raw/"
        "--curated_path"        = "s3://${local.curated_bucket_name}/"
      }
    }
  }

  # Batch limits are the upper bounds (100 events or 900 seconds); with Firehose buffering 900 seconds that is at most 96 runs a day.
  event_trigger = {
    bucket_name          = local.raw_bucket_name
    key_prefix           = "raw/"
    role_arn             = module.in.strings["role_glue_events_arn"]
    batch_size           = 100
    batch_window_seconds = 900
    actions              = [{ job = local.job_name, arguments = {} }]
  }
}

module "etl" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/glue-etl/aws"
  version = "~> 0.1.0"

  name        = "${local.name_prefix}-etl"
  kms_key_arn = local.kms_key_arn

  crawlers = local.crawlers
  # The module names a job after its map key, so the key is the job name.
  jobs          = { for _, j in local.jobs : j.name => { for k, v in j : k => v if k != "name" } }
  workflow      = { name = local.workflow_name }
  event_trigger = local.event_trigger
}
