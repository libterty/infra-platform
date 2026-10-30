# Failed pipeline runs go to the alert topic of foundation (K7); its topic policy and the shared key already allow
# events.amazonaws.com. Only FAILED: started, succeeded, stopped and superseded runs are not alerts.
locals {
  failure_rule = {
    name = "${local.name_prefix}-pipeline-failed"
    event_pattern = {
      source        = ["aws.codepipeline"]
      "detail-type" = ["CodePipeline Pipeline Execution State Change"]
      detail = {
        pipeline = sort(values(local.pipeline_names))
        state    = ["FAILED"]
      }
    }
  }
}

module "failure_rule" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/eventbridge-rule/aws"
  version = "~> 0.1.0"

  name          = local.failure_rule.name
  event_pattern = local.failure_rule.event_pattern
  targets       = { alerts = { arn = module.in.strings["alert_topic_arn"] } }
}
