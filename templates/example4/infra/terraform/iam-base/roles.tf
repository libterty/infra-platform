locals {
  roles = {
    # Trust only. The policy needs the OpenSearch domain ARN, which exists after the search stack; iam-app attaches it.
    firehose = {
      name     = "${local.name_prefix}-firehose"
      trust    = { service_principals = ["firehose.amazonaws.com"], source_account = var.expected_account_id, source_arn = null }
      policies = {}
    }
    glue_crawler = {
      name  = "${local.name_prefix}-glue-crawler"
      trust = { service_principals = ["glue.amazonaws.com"], source_account = var.expected_account_id, source_arn = null }
      policies = {
        crawl-and-catalog = jsonencode({ Version = "2012-10-17", Statement = local.glue_crawler_statements })
      }
    }
    glue_job = {
      name  = "${local.name_prefix}-glue-job"
      trust = { service_principals = ["glue.amazonaws.com"], source_account = var.expected_account_id, source_arn = null }
      policies = {
        etl-data-catalog-and-logs = jsonencode({ Version = "2012-10-17", Statement = local.glue_job_statements })
      }
    }
    # EventBridge assumes this role to call the workflow; the trust names the single rule.
    glue_events = {
      name  = "${local.name_prefix}-glue-events"
      trust = { service_principals = ["events.amazonaws.com"], source_account = var.expected_account_id, source_arn = local.event_rule_arn }
      policies = {
        notify-workflow = jsonencode({ Version = "2012-10-17", Statement = local.glue_events_statements })
      }
    }
    # Provisioned clusters and Serverless namespaces assume the role through different service principals.
    redshift = {
      name  = "${local.name_prefix}-redshift"
      trust = { service_principals = ["redshift.amazonaws.com", "redshift-serverless.amazonaws.com"], source_account = var.expected_account_id, source_arn = null }
      policies = {
        read-curated = jsonencode({ Version = "2012-10-17", Statement = local.redshift_statements })
      }
    }
    quicksight_vpc = {
      name  = "${local.name_prefix}-quicksight-vpc"
      trust = { service_principals = ["quicksight.amazonaws.com"], source_account = var.expected_account_id, source_arn = null }
      policies = {
        connection-network = jsonencode({ Version = "2012-10-17", Statement = local.quicksight_vpc_statements })
      }
    }
  }
}

module "role" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/iam-role/aws"
  version  = "~> 0.4.1"
  for_each = local.roles

  name            = each.value.name
  trust           = each.value.trust
  inline_policies = each.value.policies
}
