locals {
  # Naming contract with the ml stack (design K22, K23; same idea as v7 K21): the ml stack creates its EventBridge rule
  # on the default bus with the name <name_prefix>-model-approved. The rule does not exist yet, so its ARN is built from
  # that name; the ml tests must pin the same string. Renaming the rule on either side breaks delivery to this queue.
  model_approved_rule_name = "${local.name_prefix}-model-approved"
  model_approved_rule_arn  = "arn:aws:events:${var.aws_region}:${var.expected_account_id}:rule/${local.model_approved_rule_name}"

  queues = {
    # Failed IoT rule actions. The IoT rule role writes here, so no queue policy (design K23).
    rule_errors = {
      name                = "${local.name_prefix}-rule-errors"
      allowed_source_arns = []
    }
    # Approved model packages for CI to package and deploy (design section 7.4). Only the single ml rule may send.
    model_approved = {
      name                = "${local.name_prefix}-model-approved"
      allowed_source_arns = [local.model_approved_rule_arn]
    }
  }
}

module "queue" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/sqs-queue/aws"
  version  = "~> 0.1.0"
  for_each = local.queues

  name                = each.value.name
  kms_key_arn         = local.kms_key_arn
  allowed_source_arns = each.value.allowed_source_arns
}
