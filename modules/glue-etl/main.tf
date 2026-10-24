locals {
  event_name = var.event_trigger == null ? null : "${var.workflow.name}-s3-event"
}

# Encryption is not optional: every job and crawler is attached to this configuration, and the key is a required input.
resource "aws_glue_security_configuration" "this" {
  name = var.name

  encryption_configuration {
    s3_encryption {
      s3_encryption_mode = "SSE-KMS"
      kms_key_arn        = var.kms_key_arn
    }

    cloudwatch_encryption {
      cloudwatch_encryption_mode = "SSE-KMS"
      kms_key_arn                = var.kms_key_arn
    }

    job_bookmarks_encryption {
      job_bookmarks_encryption_mode = "CSE-KMS"
      kms_key_arn                   = var.kms_key_arn
    }
  }
}

resource "aws_glue_crawler" "this" {
  for_each = var.crawlers

  name                   = each.key
  role                   = each.value.role_arn
  database_name          = each.value.database_name
  schedule               = each.value.schedule
  table_prefix           = each.value.table_prefix
  description            = each.value.description
  security_configuration = aws_glue_security_configuration.this.name

  dynamic "s3_target" {
    for_each = each.value.s3_paths

    content {
      path = s3_target.value
    }
  }

  tags = merge(var.tags, { Name = each.key })
}

# Created ahead of the jobs so retention and KMS are ours; jobs write their continuous logs here.
resource "aws_cloudwatch_log_group" "job" {
  for_each = var.jobs

  name              = "/aws-glue/jobs/${var.name}/${each.key}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, { Name = "/aws-glue/jobs/${var.name}/${each.key}" })
}

resource "aws_glue_job" "this" {
  for_each = var.jobs

  name                   = each.key
  description            = each.value.description
  role_arn               = each.value.role_arn
  glue_version           = each.value.glue_version
  worker_type            = each.value.worker_type
  number_of_workers      = each.value.number_of_workers
  execution_class        = each.value.execution_class
  timeout                = each.value.timeout
  max_retries            = each.value.max_retries
  security_configuration = aws_glue_security_configuration.this.name

  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = each.value.script_location
  }

  execution_property {
    max_concurrent_runs = each.value.max_concurrent_runs
  }

  # The logging arguments come last so a caller cannot send the logs somewhere unencrypted.
  default_arguments = merge(each.value.default_arguments, {
    "--enable-continuous-cloudwatch-log" = "true"
    "--continuous-log-logGroup"          = aws_cloudwatch_log_group.job[each.key].name
  })

  tags = merge(var.tags, { Name = each.key })
}

resource "aws_glue_workflow" "this" {
  count = var.workflow == null ? 0 : 1

  name                = var.workflow.name
  description         = var.workflow.description
  max_concurrent_runs = var.workflow.max_concurrent_runs

  tags = merge(var.tags, { Name = var.workflow.name })
}

resource "aws_glue_trigger" "this" {
  for_each = var.triggers

  name          = each.key
  type          = each.value.type
  schedule      = each.value.schedule
  enabled       = each.value.enabled
  description   = each.value.description
  workflow_name = each.value.workflow ? one(aws_glue_workflow.this[*].name) : null

  dynamic "predicate" {
    for_each = each.value.predicate == null ? [] : [each.value.predicate]

    content {
      logical = predicate.value.logical

      dynamic "conditions" {
        for_each = predicate.value.conditions

        content {
          job_name     = conditions.value.job
          state        = conditions.value.job == null ? null : conditions.value.state
          crawler_name = conditions.value.crawler
          crawl_state  = conditions.value.crawler == null ? null : conditions.value.state
        }
      }
    }
  }

  dynamic "actions" {
    for_each = each.value.actions

    content {
      job_name     = actions.value.job
      crawler_name = actions.value.crawler
      arguments    = length(actions.value.arguments) == 0 ? null : actions.value.arguments
    }
  }

  tags = merge(var.tags, { Name = each.key })

  # Actions refer to jobs and crawlers by name, so order the creation explicitly.
  depends_on = [aws_glue_job.this, aws_glue_crawler.this]
}

# The start trigger of the workflow: fires after batch_size S3 events or batch_window_seconds after the first one.
resource "aws_glue_trigger" "event" {
  count = var.event_trigger == null ? 0 : 1

  name          = local.event_name
  type          = "EVENT"
  workflow_name = aws_glue_workflow.this[0].name

  event_batching_condition {
    batch_size   = var.event_trigger.batch_size
    batch_window = var.event_trigger.batch_window_seconds
  }

  dynamic "actions" {
    for_each = var.event_trigger.actions

    content {
      job_name     = actions.value.job
      crawler_name = actions.value.crawler
      arguments    = length(actions.value.arguments) == 0 ? null : actions.value.arguments
    }
  }

  tags = merge(var.tags, { Name = local.event_name })

  depends_on = [aws_glue_job.this, aws_glue_crawler.this]
}

# Default bus. S3 sends "Object Created" to it once the bucket has EventBridge notifications on.
# The rule exists only after the EVENT trigger, so no event reaches a workflow that cannot start yet.
resource "aws_cloudwatch_event_rule" "this" {
  count = var.event_trigger == null ? 0 : 1

  name        = local.event_name
  description = "Start the ${var.workflow.name} Glue workflow when objects are created under ${var.event_trigger.key_prefix} in ${var.event_trigger.bucket_name}"

  event_pattern = jsonencode({
    source        = ["aws.s3"]
    "detail-type" = ["Object Created"]
    detail = {
      bucket = { name = [var.event_trigger.bucket_name] }
      object = { key = [{ prefix = var.event_trigger.key_prefix }] }
    }
  })

  tags = merge(var.tags, { Name = local.event_name })

  depends_on = [aws_glue_trigger.event]
}

resource "aws_cloudwatch_event_target" "this" {
  count = var.event_trigger == null ? 0 : 1

  rule      = aws_cloudwatch_event_rule.this[0].name
  target_id = "glue-workflow"
  arn       = aws_glue_workflow.this[0].arn
  role_arn  = var.event_trigger.role_arn
}
