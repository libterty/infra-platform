locals {
  # <Project>/<env>: the namespace iam lets the services publish into.
  metric_namespace = "${title(var.project)}/${var.env}"

  # Counts only, no alarms: "rejected" is a problem with what was delivered, "failed" is ours, "succeeded" is the
  # baseline that tells a quiet system from a broken one.
  etl_load_metrics = {
    import_load_rejected = {
      pattern     = "{ $.event = \"import_load_rejected\" }"
      metric_name = "ImportLoadRejected"
    }
    import_load_failed = {
      pattern     = "{ $.event = \"import_load_failed\" }"
      metric_name = "ImportLoadFailed"
    }
    import_load_succeeded = {
      pattern     = "{ $.event = \"import_load_succeeded\" }"
      metric_name = "ImportLoadSucceeded"
    }
  }

  # The extract side only has the "rejected" outcome; a failure there shows in the function's own Errors metric.
  etl_extract_metrics = {
    import_extract_rejected = {
      pattern     = "{ $.event = \"import_extract_rejected\" }"
      metric_name = "ImportExtractRejected"
    }
  }
}

module "etl_load_metrics" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/log-metric-alarm/aws"
  version = "~> 0.2.0"

  name_prefix    = "${local.name_prefix}-etl-load"
  log_group_name = module.lambda["import-load"].log_group_name
  namespace      = local.metric_namespace
  metrics        = local.etl_load_metrics
}

module "etl_extract_metrics" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/log-metric-alarm/aws"
  version = "~> 0.2.0"

  name_prefix    = "${local.name_prefix}-etl-extract"
  log_group_name = module.lambda["import-extract"].log_group_name
  namespace      = local.metric_namespace
  metrics        = local.etl_extract_metrics
}
