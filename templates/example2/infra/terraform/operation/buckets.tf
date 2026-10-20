locals {
  # <project>-<env>-<purpose>-<account>: the iam stack builds its S3 grants from these names.
  import_bucket_name     = "${local.name_prefix}-import-${var.expected_account_id}"
  import_bucket_arn      = "arn:aws:s3:::${local.import_bucket_name}"
  eval_batch_bucket_name = "${local.name_prefix}-eval-batch-${var.expected_account_id}"

  # The eval data stays in the dev account, as in iam.
  eval_batch_enabled = var.env == "dev"

  import_expiration_prefix = "extracted/"
  import_versioning        = { noncurrent_expiration_days = 1 }

  # An upload under incoming/ starts the extraction; the extracted/ handoff starts the load once the extraction marks it
  # ready. The prefixes must not overlap: S3 rejects overlapping prefixes with overlapping suffixes, and plan cannot see it.
  import_notifications = {
    extract = {
      function_arn  = module.lambda["import-extract"].function_arn
      filter_prefix = "incoming/"
    }
    load = {
      function_arn  = module.lambda["import-load"].function_arn
      filter_prefix = "extracted/"
      filter_suffix = "ready.json"
    }
  }
}

module "import_bucket" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/s3-bucket/aws"
  version = "~> 0.2.0"

  name                 = local.import_bucket_name
  versioning           = local.import_versioning
  expiration_days      = var.import_expiration_days
  expiration_prefix    = local.import_expiration_prefix
  lambda_notifications = local.import_notifications
}

module "eval_batch_bucket" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/s3-bucket/aws"
  version = "~> 0.2.0"

  count = local.eval_batch_enabled ? 1 : 0

  name            = local.eval_batch_bucket_name
  expiration_days = 14
}
