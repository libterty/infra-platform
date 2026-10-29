# High and critical findings go to the alert topic of foundation (design K13); its topic policy and the governance key
# already allow events.amazonaws.com. GuardDuty rates HIGH from 7.0 and CRITICAL from 9.0. GuardDuty findings also
# reach Security Hub, so the Security Hub rule skips them to avoid a second mail for the same finding.
locals {
  finding_rules = {
    guardduty = {
      name = "${local.name_prefix}-guardduty-findings"
      event_pattern = {
        source        = ["aws.guardduty"]
        "detail-type" = ["GuardDuty Finding"]
        detail        = { severity = [{ numeric = [">=", 7] }] }
      }
    }
    securityhub = {
      name = "${local.name_prefix}-securityhub-findings"
      event_pattern = {
        source        = ["aws.securityhub"]
        "detail-type" = ["Security Hub Findings - Imported"]
        detail = {
          findings = {
            Severity    = { Label = ["HIGH", "CRITICAL"] }
            RecordState = ["ACTIVE"]
            ProductName = [{ "anything-but" = ["GuardDuty"] }]
          }
        }
      }
    }
  }

  finding_targets = {
    alerts = { arn = module.in.strings["alert_topic_arn"] }
  }
}

module "finding_rule" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/eventbridge-rule/aws"
  version  = "~> 0.1.0"
  for_each = local.finding_rules

  name          = each.value.name
  event_pattern = each.value.event_pattern
  targets       = local.finding_targets
}
