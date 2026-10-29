# One monthly cost budget for the account (design K12): actual 80%, actual 100% and forecasted 100%.
locals {
  budget_alerts = [
    { type = "ACTUAL", threshold = 80 },
    { type = "ACTUAL", threshold = 100 },
    { type = "FORECASTED", threshold = 100 },
  ]

  budgets = {
    "${local.name_prefix}-monthly" = {
      limit_amount = var.monthly_budget_usd
      time_unit    = "MONTHLY"
      notifications = [for a in local.budget_alerts : {
        comparison     = "GREATER_THAN"
        threshold      = a.threshold
        threshold_type = "PERCENTAGE"
        type           = a.type
        sns_topic_arns = [module.in.strings["alert_topic_arn"]]
        emails         = var.budget_emails
      }]
    }
  }
}

module "budgets" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/budgets/aws"
  version = "~> 0.1.0"

  budgets = local.budgets
}
