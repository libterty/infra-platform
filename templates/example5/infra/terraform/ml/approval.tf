locals {
  # Naming contract with storage (queues.tf): the model-approved queue policy allows only the rule
  # <name_prefix>-model-approved on the default bus. CI consumes the queue (design section 7.4, K22).
  approved_rule = {
    name = "${local.name_prefix}-model-approved"
    event_pattern = {
      source        = ["aws.sagemaker"]
      "detail-type" = ["SageMaker Model Package State Change"]
      detail        = { ModelPackageGroupName = [module.registry.name], ModelApprovalStatus = ["Approved"] }
    }
    # SQS targets are authorized by the queue policy, so no role.
    targets = { model-approved = { arn = module.in.strings["model_approved_queue_arn"] } }
  }
}

module "approved_rule" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/eventbridge-rule/aws"
  version = "~> 0.1.0"

  name          = local.approved_rule.name
  event_pattern = local.approved_rule.event_pattern
  targets       = local.approved_rule.targets
}
