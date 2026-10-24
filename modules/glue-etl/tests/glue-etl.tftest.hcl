mock_provider "aws" {}

override_resource {
  target          = aws_glue_workflow.this
  override_during = plan
  values = {
    arn = "arn:aws:glue:ap-northeast-1:111111111111:workflow/alpha-dev-raw-to-curated"
  }
}

override_resource {
  target          = aws_cloudwatch_event_rule.this
  override_during = plan
  values = {
    arn = "arn:aws:events:ap-northeast-1:111111111111:rule/alpha-dev-raw-to-curated-s3-event"
  }
}

variables {
  name        = "alpha-dev-etl"
  kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"

  crawlers = {
    alpha-dev-raw = {
      role_arn      = "arn:aws:iam::111111111111:role/alpha-dev-glue-crawler"
      database_name = "alpha_dev_raw"
      s3_paths      = ["s3://alpha-dev-raw/raw/"]
    }
  }

  jobs = {
    alpha-dev-raw-to-curated = {
      role_arn        = "arn:aws:iam::111111111111:role/alpha-dev-glue-job"
      script_location = "s3://alpha-dev-glue-assets/scripts/raw_to_curated.py"
    }
  }
}

# ---- positive: security configuration, crawler, job -----------------------------------------------------------

run "security_configuration_is_named_after_the_module" {
  command = plan

  assert {
    condition     = aws_glue_security_configuration.this.name == "alpha-dev-etl"
    error_message = "The security configuration must be named after the module"
  }
}

run "security_configuration_encrypts_s3_data_with_the_given_key" {
  command = plan

  assert {
    condition = (
      one(one(aws_glue_security_configuration.this.encryption_configuration).s3_encryption).s3_encryption_mode == "SSE-KMS" &&
      one(one(aws_glue_security_configuration.this.encryption_configuration).s3_encryption).kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    )
    error_message = "S3 data written by jobs must be encrypted with SSE-KMS and the given key"
  }
}

run "security_configuration_encrypts_cloudwatch_logs_with_the_given_key" {
  command = plan

  assert {
    condition = (
      one(one(aws_glue_security_configuration.this.encryption_configuration).cloudwatch_encryption).cloudwatch_encryption_mode == "SSE-KMS" &&
      one(one(aws_glue_security_configuration.this.encryption_configuration).cloudwatch_encryption).kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    )
    error_message = "CloudWatch logs written by Glue must be encrypted with SSE-KMS and the given key"
  }
}

run "security_configuration_encrypts_job_bookmarks_with_the_given_key" {
  command = plan

  assert {
    condition = (
      one(one(aws_glue_security_configuration.this.encryption_configuration).job_bookmarks_encryption).job_bookmarks_encryption_mode == "CSE-KMS" &&
      one(one(aws_glue_security_configuration.this.encryption_configuration).job_bookmarks_encryption).kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    )
    error_message = "Job bookmarks must be encrypted with CSE-KMS and the given key"
  }
}

run "empty_module_still_creates_the_security_configuration_only" {
  command = plan

  variables {
    crawlers = {}
    jobs     = {}
  }

  assert {
    condition     = length(aws_glue_crawler.this) == 0 && length(aws_glue_job.this) == 0 && length(aws_glue_trigger.this) == 0
    error_message = "No crawler, job or trigger without input"
  }

  assert {
    condition     = length(aws_glue_workflow.this) == 0 && length(aws_glue_trigger.event) == 0 && length(aws_cloudwatch_event_rule.this) == 0 && length(aws_cloudwatch_event_target.this) == 0
    error_message = "No workflow or event resources without input"
  }

  assert {
    condition     = output.workflow_name == null && output.workflow_arn == null && output.event_rule_arn == null
    error_message = "Workflow and event outputs must be null without input"
  }
}

run "crawler_attaches_the_security_configuration" {
  command = plan

  variables {
    crawlers = {
      alpha-dev-raw = {
        role_arn      = "arn:aws:iam::111111111111:role/alpha-dev-glue-crawler"
        database_name = "alpha_dev_raw"
        s3_paths      = ["s3://alpha-dev-raw/raw/", "s3://alpha-dev-raw/other/"]
        schedule      = "cron(15 12 * * ? *)"
        table_prefix  = "raw_"
        description   = "Daily crawl of the raw zone"
      }
    }
  }

  assert {
    condition     = aws_glue_crawler.this["alpha-dev-raw"].security_configuration == "alpha-dev-etl"
    error_message = "Every crawler must use the module's security configuration"
  }

  assert {
    condition     = aws_glue_crawler.this["alpha-dev-raw"].name == "alpha-dev-raw" && aws_glue_crawler.this["alpha-dev-raw"].database_name == "alpha_dev_raw"
    error_message = "name and database_name must be passed through"
  }

  assert {
    condition     = aws_glue_crawler.this["alpha-dev-raw"].role == "arn:aws:iam::111111111111:role/alpha-dev-glue-crawler"
    error_message = "The crawler must use the role given as input"
  }

  assert {
    condition     = toset([for t in aws_glue_crawler.this["alpha-dev-raw"].s3_target : t.path]) == toset(["s3://alpha-dev-raw/raw/", "s3://alpha-dev-raw/other/"])
    error_message = "Every s3_paths entry must become an S3 target"
  }

  assert {
    condition     = aws_glue_crawler.this["alpha-dev-raw"].schedule == "cron(15 12 * * ? *)" && aws_glue_crawler.this["alpha-dev-raw"].table_prefix == "raw_"
    error_message = "schedule and table_prefix must be passed through"
  }
}

run "crawler_without_schedule_is_on_demand" {
  command = plan

  assert {
    condition     = aws_glue_crawler.this["alpha-dev-raw"].schedule == null
    error_message = "A crawler without a schedule must not get one"
  }
}

run "job_defaults" {
  command = plan

  assert {
    condition     = aws_glue_job.this["alpha-dev-raw-to-curated"].security_configuration == "alpha-dev-etl"
    error_message = "Every job must use the module's security configuration"
  }

  assert {
    condition     = one(aws_glue_job.this["alpha-dev-raw-to-curated"].command).name == "glueetl" && one(aws_glue_job.this["alpha-dev-raw-to-curated"].command).script_location == "s3://alpha-dev-glue-assets/scripts/raw_to_curated.py"
    error_message = "The job must be a Spark ETL job running the given script"
  }

  assert {
    condition     = aws_glue_job.this["alpha-dev-raw-to-curated"].glue_version == "5.1" && aws_glue_job.this["alpha-dev-raw-to-curated"].worker_type == "G.1X" && aws_glue_job.this["alpha-dev-raw-to-curated"].number_of_workers == 2
    error_message = "Defaults must be Glue 5.1, G.1X, 2 workers"
  }

  assert {
    condition     = aws_glue_job.this["alpha-dev-raw-to-curated"].execution_class == "STANDARD" && aws_glue_job.this["alpha-dev-raw-to-curated"].timeout == 60 && aws_glue_job.this["alpha-dev-raw-to-curated"].max_retries == 0
    error_message = "Defaults must be STANDARD, 60 minute timeout, no retries"
  }

  assert {
    condition     = one(aws_glue_job.this["alpha-dev-raw-to-curated"].execution_property).max_concurrent_runs == 1
    error_message = "max_concurrent_runs must default to 1"
  }

  assert {
    condition     = aws_glue_job.this["alpha-dev-raw-to-curated"].role_arn == "arn:aws:iam::111111111111:role/alpha-dev-glue-job"
    error_message = "The job must use the role given as input"
  }
}

run "job_logs_go_to_a_module_owned_encrypted_log_group" {
  command = plan

  variables {
    log_retention_days = 14
  }

  assert {
    condition     = aws_cloudwatch_log_group.job["alpha-dev-raw-to-curated"].name == "/aws-glue/jobs/alpha-dev-etl/alpha-dev-raw-to-curated"
    error_message = "The log group name must be /aws-glue/jobs/<module name>/<job>"
  }

  assert {
    condition     = aws_cloudwatch_log_group.job["alpha-dev-raw-to-curated"].retention_in_days == 14
    error_message = "The log group must use log_retention_days"
  }

  assert {
    condition     = aws_cloudwatch_log_group.job["alpha-dev-raw-to-curated"].kms_key_id == "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    error_message = "The log group must use the given key"
  }

  assert {
    condition = (
      aws_glue_job.this["alpha-dev-raw-to-curated"].default_arguments["--enable-continuous-cloudwatch-log"] == "true" &&
      aws_glue_job.this["alpha-dev-raw-to-curated"].default_arguments["--continuous-log-logGroup"] == "/aws-glue/jobs/alpha-dev-etl/alpha-dev-raw-to-curated"
    )
    error_message = "The job must write continuous logs to its own log group"
  }
}

run "log_retention_defaults_to_30_days" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.job["alpha-dev-raw-to-curated"].retention_in_days == 30
    error_message = "log_retention_days must default to 30"
  }
}

run "job_flex_execution" {
  command = plan

  variables {
    jobs = {
      alpha-dev-raw-to-curated = {
        role_arn            = "arn:aws:iam::111111111111:role/alpha-dev-glue-job"
        script_location     = "s3://alpha-dev-glue-assets/scripts/raw_to_curated.py"
        execution_class     = "FLEX"
        worker_type         = "G.2X"
        number_of_workers   = 4
        glue_version        = "4.0"
        timeout             = 2880
        max_retries         = 1
        max_concurrent_runs = 2
        description         = "Raw to curated"
        default_arguments = {
          "--job-bookmark-option" = "job-bookmark-enable"
        }
      }
    }
  }

  assert {
    condition     = aws_glue_job.this["alpha-dev-raw-to-curated"].execution_class == "FLEX"
    error_message = "execution_class must be passed through"
  }

  assert {
    condition     = aws_glue_job.this["alpha-dev-raw-to-curated"].worker_type == "G.2X" && aws_glue_job.this["alpha-dev-raw-to-curated"].number_of_workers == 4 && aws_glue_job.this["alpha-dev-raw-to-curated"].glue_version == "4.0"
    error_message = "worker settings and glue_version must be passed through"
  }

  assert {
    condition     = aws_glue_job.this["alpha-dev-raw-to-curated"].timeout == 2880 && aws_glue_job.this["alpha-dev-raw-to-curated"].max_retries == 1 && one(aws_glue_job.this["alpha-dev-raw-to-curated"].execution_property).max_concurrent_runs == 2
    error_message = "timeout, max_retries and max_concurrent_runs must be passed through"
  }

  assert {
    condition     = aws_glue_job.this["alpha-dev-raw-to-curated"].default_arguments["--job-bookmark-option"] == "job-bookmark-enable"
    error_message = "Caller default_arguments must be kept next to the logging arguments"
  }
}

run "caller_cannot_override_the_job_log_group" {
  command = plan

  variables {
    jobs = {
      alpha-dev-raw-to-curated = {
        role_arn        = "arn:aws:iam::111111111111:role/alpha-dev-glue-job"
        script_location = "s3://alpha-dev-glue-assets/scripts/raw_to_curated.py"
        default_arguments = {
          "--continuous-log-logGroup" = "/somewhere/else"
        }
      }
    }
  }

  assert {
    condition     = aws_glue_job.this["alpha-dev-raw-to-curated"].default_arguments["--continuous-log-logGroup"] == "/aws-glue/jobs/alpha-dev-etl/alpha-dev-raw-to-curated"
    error_message = "The module's log group must win over a caller-given --continuous-log-logGroup"
  }
}

# ---- positive: workflow and triggers --------------------------------------------------------------------------

run "scheduled_trigger" {
  command = plan

  variables {
    triggers = {
      nightly = {
        type     = "SCHEDULED"
        schedule = "cron(0 18 * * ? *)"
        actions  = [{ job = "alpha-dev-raw-to-curated", arguments = { "--run_mode" = "full" } }]
      }
    }
  }

  assert {
    condition     = aws_glue_trigger.this["nightly"].type == "SCHEDULED" && aws_glue_trigger.this["nightly"].schedule == "cron(0 18 * * ? *)"
    error_message = "type and schedule must be passed through"
  }

  assert {
    condition     = one(aws_glue_trigger.this["nightly"].actions).job_name == "alpha-dev-raw-to-curated" && one(aws_glue_trigger.this["nightly"].actions).arguments["--run_mode"] == "full"
    error_message = "The action must start the job with its arguments"
  }

  assert {
    condition     = aws_glue_trigger.this["nightly"].workflow_name == null
    error_message = "A trigger without workflow = true must not join a workflow"
  }
}

run "conditional_trigger_in_a_workflow" {
  command = plan

  variables {
    workflow = { name = "alpha-dev-raw-to-curated" }
    triggers = {
      start-crawl = {
        type     = "SCHEDULED"
        schedule = "cron(0 18 * * ? *)"
        workflow = true
        actions  = [{ crawler = "alpha-dev-raw" }]
      }
      after-crawl = {
        type     = "CONDITIONAL"
        workflow = true
        predicate = {
          conditions = [{ crawler = "alpha-dev-raw", state = "SUCCEEDED" }]
        }
        actions = [{ job = "alpha-dev-raw-to-curated" }]
      }
      after-job = {
        type = "CONDITIONAL"
        predicate = {
          logical    = "ANY"
          conditions = [{ job = "alpha-dev-raw-to-curated", state = "FAILED" }, { job = "alpha-dev-raw-to-curated", state = "TIMEOUT" }]
        }
        actions = [{ crawler = "alpha-dev-raw" }]
      }
    }
  }

  assert {
    condition     = aws_glue_trigger.this["after-crawl"].workflow_name == "alpha-dev-raw-to-curated" && aws_glue_trigger.this["start-crawl"].workflow_name == "alpha-dev-raw-to-curated"
    error_message = "Triggers with workflow = true must join the module's workflow"
  }

  assert {
    condition     = aws_glue_trigger.this["after-job"].workflow_name == null
    error_message = "A trigger without workflow = true must stay outside the workflow"
  }

  assert {
    condition     = one(aws_glue_trigger.this["after-crawl"].predicate).logical == "AND"
    error_message = "predicate.logical must default to AND"
  }

  assert {
    condition     = one(aws_glue_trigger.this["after-crawl"].predicate).conditions[0].crawler_name == "alpha-dev-raw" && one(aws_glue_trigger.this["after-crawl"].predicate).conditions[0].crawl_state == "SUCCEEDED"
    error_message = "A crawler condition must watch the crawler's crawl state"
  }

  assert {
    condition     = one(aws_glue_trigger.this["after-job"].predicate).logical == "ANY" && length(one(aws_glue_trigger.this["after-job"].predicate).conditions) == 2 && one(aws_glue_trigger.this["after-job"].predicate).conditions[0].job_name == "alpha-dev-raw-to-curated" && one(aws_glue_trigger.this["after-job"].predicate).conditions[0].state == "FAILED"
    error_message = "A job condition must watch the job's state"
  }

  assert {
    condition     = one(aws_glue_trigger.this["after-crawl"].actions).job_name == "alpha-dev-raw-to-curated"
    error_message = "The CONDITIONAL action must start the job"
  }
}

run "workflow_is_created_when_given" {
  command = plan

  variables {
    workflow = {
      name                = "alpha-dev-raw-to-curated"
      description         = "Raw to curated"
      max_concurrent_runs = 1
    }
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_glue_workflow.this[0].name == "alpha-dev-raw-to-curated" && aws_glue_workflow.this[0].max_concurrent_runs == 1
    error_message = "The workflow must be created with the given name and concurrency"
  }

  assert {
    condition     = aws_glue_workflow.this[0].tags["Project"] == "alpha" && aws_glue_workflow.this[0].tags["Name"] == "alpha-dev-raw-to-curated"
    error_message = "tags must be merged with Name"
  }

  assert {
    condition     = output.workflow_name == "alpha-dev-raw-to-curated" && output.workflow_arn == "arn:aws:glue:ap-northeast-1:111111111111:workflow/alpha-dev-raw-to-curated"
    error_message = "workflow outputs must expose the workflow"
  }
}

# ---- positive: event trigger ----------------------------------------------------------------------------------

run "event_trigger_starts_the_workflow_from_an_eventbridge_rule" {
  command = plan

  variables {
    workflow = { name = "alpha-dev-raw-to-curated" }
    event_trigger = {
      bucket_name          = "alpha-dev-raw"
      key_prefix           = "raw/"
      role_arn             = "arn:aws:iam::111111111111:role/alpha-dev-glue-events"
      actions              = [{ job = "alpha-dev-raw-to-curated" }]
      batch_size           = 100
      batch_window_seconds = 900
    }
  }

  # The EVENT trigger is the start trigger of the workflow.
  assert {
    condition     = aws_glue_trigger.event[0].type == "EVENT" && aws_glue_trigger.event[0].workflow_name == "alpha-dev-raw-to-curated"
    error_message = "The EVENT trigger must be the start trigger of the workflow"
  }

  assert {
    condition     = aws_glue_trigger.event[0].name == "alpha-dev-raw-to-curated-s3-event"
    error_message = "The EVENT trigger must be named <workflow>-s3-event"
  }

  assert {
    condition     = one(aws_glue_trigger.event[0].event_batching_condition).batch_size == 100 && one(aws_glue_trigger.event[0].event_batching_condition).batch_window == 900
    error_message = "batch_size and batch_window_seconds must become the event batching condition"
  }

  assert {
    condition     = one(aws_glue_trigger.event[0].actions).job_name == "alpha-dev-raw-to-curated"
    error_message = "The EVENT trigger must start the given job"
  }

  # The rule matches S3 "Object Created" events of one bucket and one key prefix on the default bus.
  assert {
    condition     = aws_cloudwatch_event_rule.this[0].name == "alpha-dev-raw-to-curated-s3-event"
    error_message = "The rule must be named <workflow>-s3-event"
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.this[0].event_pattern).source == ["aws.s3"]
    error_message = "The rule must match events from aws.s3"
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.this[0].event_pattern)["detail-type"] == ["Object Created"]
    error_message = "The rule must match Object Created events"
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.this[0].event_pattern).detail.bucket.name == ["alpha-dev-raw"]
    error_message = "The rule must match the given bucket only"
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.this[0].event_pattern).detail.object.key == [{ prefix = "raw/" }]
    error_message = "The rule must match the given key prefix only"
  }

  assert {
    condition     = length(keys(jsondecode(aws_cloudwatch_event_rule.this[0].event_pattern))) == 3 && length(keys(jsondecode(aws_cloudwatch_event_rule.this[0].event_pattern).detail)) == 2
    error_message = "The pattern must contain only source, detail-type and detail (bucket, object)"
  }

  assert {
    condition     = aws_cloudwatch_event_target.this[0].arn == "arn:aws:glue:ap-northeast-1:111111111111:workflow/alpha-dev-raw-to-curated"
    error_message = "The target must be the workflow ARN"
  }

  assert {
    condition     = aws_cloudwatch_event_target.this[0].role_arn == "arn:aws:iam::111111111111:role/alpha-dev-glue-events"
    error_message = "The target must use the role given as input"
  }

  assert {
    condition     = aws_cloudwatch_event_target.this[0].rule == "alpha-dev-raw-to-curated-s3-event"
    error_message = "The target must be attached to the rule"
  }

  assert {
    condition     = output.event_rule_arn == "arn:aws:events:ap-northeast-1:111111111111:rule/alpha-dev-raw-to-curated-s3-event"
    error_message = "event_rule_arn must expose the rule ARN"
  }
}

run "event_trigger_batch_boundaries_are_accepted" {
  command = plan

  variables {
    workflow = { name = "alpha-dev-raw-to-curated" }
    event_trigger = {
      bucket_name          = "alpha-dev-raw"
      key_prefix           = "raw/"
      role_arn             = "arn:aws:iam::111111111111:role/alpha-dev-glue-events"
      actions              = [{ job = "alpha-dev-raw-to-curated" }]
      batch_size           = 1
      batch_window_seconds = 1
    }
  }

  assert {
    condition     = one(aws_glue_trigger.event[0].event_batching_condition).batch_size == 1 && one(aws_glue_trigger.event[0].event_batching_condition).batch_window == 1
    error_message = "batch_size 1 and batch_window_seconds 1 are valid"
  }
}

run "event_trigger_window_defaults_to_900_seconds" {
  command = plan

  variables {
    workflow = { name = "alpha-dev-raw-to-curated" }
    event_trigger = {
      bucket_name = "alpha-dev-raw"
      key_prefix  = "raw/"
      role_arn    = "arn:aws:iam::111111111111:role/alpha-dev-glue-events"
      actions     = [{ job = "alpha-dev-raw-to-curated" }]
      batch_size  = 50
    }
  }

  assert {
    condition     = one(aws_glue_trigger.event[0].event_batching_condition).batch_size == 50 && one(aws_glue_trigger.event[0].event_batching_condition).batch_window == 900
    error_message = "batch_window_seconds must default to 900, the Glue default and maximum"
  }
}

run "event_trigger_max_batch_size_and_window_are_accepted" {
  command = plan

  variables {
    workflow = { name = "alpha-dev-raw-to-curated" }
    event_trigger = {
      bucket_name          = "alpha-dev-raw"
      key_prefix           = "raw/"
      role_arn             = "arn:aws:iam::111111111111:role/alpha-dev-glue-events"
      actions              = [{ crawler = "alpha-dev-raw" }]
      batch_size           = 100
      batch_window_seconds = 900
    }
  }

  assert {
    condition     = one(aws_glue_trigger.event[0].actions).crawler_name == "alpha-dev-raw"
    error_message = "An EVENT trigger may start a crawler"
  }
}

run "event_trigger_can_share_the_workflow_with_a_conditional_trigger" {
  command = plan

  variables {
    workflow = { name = "alpha-dev-raw-to-curated" }
    event_trigger = {
      bucket_name = "alpha-dev-raw"
      key_prefix  = "raw/"
      role_arn    = "arn:aws:iam::111111111111:role/alpha-dev-glue-events"
      actions     = [{ job = "alpha-dev-raw-to-curated" }]
      batch_size  = 100
    }
    triggers = {
      after-job = {
        type     = "CONDITIONAL"
        workflow = true
        predicate = {
          conditions = [{ job = "alpha-dev-raw-to-curated", state = "SUCCEEDED" }]
        }
        actions = [{ crawler = "alpha-dev-raw" }]
      }
    }
  }

  assert {
    condition     = aws_glue_trigger.this["after-job"].workflow_name == "alpha-dev-raw-to-curated" && aws_glue_trigger.event[0].workflow_name == "alpha-dev-raw-to-curated"
    error_message = "The EVENT trigger and a CONDITIONAL trigger must share the workflow"
  }
}

# ---- positive: tags and outputs -------------------------------------------------------------------------------

run "outputs" {
  command = plan

  assert {
    condition     = output.security_configuration_name == "alpha-dev-etl"
    error_message = "security_configuration_name must be the security configuration name"
  }

  assert {
    condition     = join(",", output.job_names) == "alpha-dev-raw-to-curated" && join(",", output.crawler_names) == "alpha-dev-raw"
    error_message = "job_names and crawler_names must list the names"
  }
}

run "tags_are_merged_with_name" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_glue_job.this["alpha-dev-raw-to-curated"].tags["Project"] == "alpha" && aws_glue_job.this["alpha-dev-raw-to-curated"].tags["Name"] == "alpha-dev-raw-to-curated"
    error_message = "Job tags must be merged with Name"
  }

  assert {
    condition     = aws_glue_crawler.this["alpha-dev-raw"].tags["Project"] == "alpha" && aws_glue_crawler.this["alpha-dev-raw"].tags["Name"] == "alpha-dev-raw"
    error_message = "Crawler tags must be merged with Name"
  }
}

# ---- negative: module inputs ----------------------------------------------------------------------------------

run "kms_alias_arn_rejected" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:alias/alpha-dev"
  }

  expect_failures = [var.kms_key_arn]
}

run "kms_key_arn_is_required" {
  command = plan

  variables {
    kms_key_arn = null
  }

  expect_failures = [var.kms_key_arn]
}

run "invalid_name_rejected" {
  command = plan

  variables {
    name = "alpha dev/etl"
  }

  expect_failures = [var.name]
}

run "log_retention_not_accepted_by_cloudwatch_rejected" {
  command = plan

  variables {
    log_retention_days = 10
  }

  expect_failures = [var.log_retention_days]
}

# ---- negative: crawlers ---------------------------------------------------------------------------------------

run "crawler_s3_path_not_s3_rejected" {
  command = plan

  variables {
    crawlers = {
      alpha-dev-raw = {
        role_arn      = "arn:aws:iam::111111111111:role/alpha-dev-glue-crawler"
        database_name = "alpha_dev_raw"
        s3_paths      = ["https://example.com/raw/"]
      }
    }
  }

  expect_failures = [var.crawlers]
}

run "crawler_without_s3_paths_rejected" {
  command = plan

  variables {
    crawlers = {
      alpha-dev-raw = {
        role_arn      = "arn:aws:iam::111111111111:role/alpha-dev-glue-crawler"
        database_name = "alpha_dev_raw"
        s3_paths      = []
      }
    }
  }

  expect_failures = [var.crawlers]
}

run "crawler_schedule_not_cron_rejected" {
  command = plan

  variables {
    crawlers = {
      alpha-dev-raw = {
        role_arn      = "arn:aws:iam::111111111111:role/alpha-dev-glue-crawler"
        database_name = "alpha_dev_raw"
        s3_paths      = ["s3://alpha-dev-raw/raw/"]
        schedule      = "rate(1 day)"
      }
    }
  }

  expect_failures = [var.crawlers]
}

run "crawler_role_not_an_iam_role_arn_rejected" {
  command = plan

  variables {
    crawlers = {
      alpha-dev-raw = {
        role_arn      = "alpha-dev-glue-crawler"
        database_name = "alpha_dev_raw"
        s3_paths      = ["s3://alpha-dev-raw/raw/"]
      }
    }
  }

  expect_failures = [var.crawlers]
}

# ---- negative: jobs -------------------------------------------------------------------------------------------

run "job_script_not_s3_rejected" {
  command = plan

  variables {
    jobs = {
      alpha-dev-raw-to-curated = {
        role_arn        = "arn:aws:iam::111111111111:role/alpha-dev-glue-job"
        script_location = "/local/raw_to_curated.py"
      }
    }
  }

  expect_failures = [var.jobs]
}

run "job_role_not_an_iam_role_arn_rejected" {
  command = plan

  variables {
    jobs = {
      alpha-dev-raw-to-curated = {
        role_arn        = "alpha-dev-glue-job"
        script_location = "s3://alpha-dev-glue-assets/scripts/raw_to_curated.py"
      }
    }
  }

  expect_failures = [var.jobs]
}

run "job_unknown_worker_type_rejected" {
  command = plan

  variables {
    jobs = {
      alpha-dev-raw-to-curated = {
        role_arn        = "arn:aws:iam::111111111111:role/alpha-dev-glue-job"
        script_location = "s3://alpha-dev-glue-assets/scripts/raw_to_curated.py"
        worker_type     = "G.3X"
      }
    }
  }

  expect_failures = [var.jobs]
}

run "job_streaming_worker_type_rejected" {
  command = plan

  variables {
    jobs = {
      alpha-dev-raw-to-curated = {
        role_arn        = "arn:aws:iam::111111111111:role/alpha-dev-glue-job"
        script_location = "s3://alpha-dev-glue-assets/scripts/raw_to_curated.py"
        worker_type     = "G.025X"
      }
    }
  }

  expect_failures = [var.jobs]
}

run "job_unknown_glue_version_rejected" {
  command = plan

  variables {
    jobs = {
      alpha-dev-raw-to-curated = {
        role_arn        = "arn:aws:iam::111111111111:role/alpha-dev-glue-job"
        script_location = "s3://alpha-dev-glue-assets/scripts/raw_to_curated.py"
        glue_version    = "1.0"
      }
    }
  }

  expect_failures = [var.jobs]
}

run "job_unknown_execution_class_rejected" {
  command = plan

  variables {
    jobs = {
      alpha-dev-raw-to-curated = {
        role_arn        = "arn:aws:iam::111111111111:role/alpha-dev-glue-job"
        script_location = "s3://alpha-dev-glue-assets/scripts/raw_to_curated.py"
        execution_class = "SPOT"
      }
    }
  }

  expect_failures = [var.jobs]
}

run "job_flex_with_a_large_worker_rejected" {
  command = plan

  variables {
    jobs = {
      alpha-dev-raw-to-curated = {
        role_arn        = "arn:aws:iam::111111111111:role/alpha-dev-glue-job"
        script_location = "s3://alpha-dev-glue-assets/scripts/raw_to_curated.py"
        execution_class = "FLEX"
        worker_type     = "G.4X"
      }
    }
  }

  expect_failures = [var.jobs]
}

run "job_one_worker_rejected" {
  command = plan

  variables {
    jobs = {
      alpha-dev-raw-to-curated = {
        role_arn          = "arn:aws:iam::111111111111:role/alpha-dev-glue-job"
        script_location   = "s3://alpha-dev-glue-assets/scripts/raw_to_curated.py"
        number_of_workers = 1
      }
    }
  }

  expect_failures = [var.jobs]
}

run "job_timeout_zero_rejected" {
  command = plan

  variables {
    jobs = {
      alpha-dev-raw-to-curated = {
        role_arn        = "arn:aws:iam::111111111111:role/alpha-dev-glue-job"
        script_location = "s3://alpha-dev-glue-assets/scripts/raw_to_curated.py"
        timeout         = 0
      }
    }
  }

  expect_failures = [var.jobs]
}

run "job_timeout_above_2880_rejected" {
  command = plan

  variables {
    jobs = {
      alpha-dev-raw-to-curated = {
        role_arn        = "arn:aws:iam::111111111111:role/alpha-dev-glue-job"
        script_location = "s3://alpha-dev-glue-assets/scripts/raw_to_curated.py"
        timeout         = 2881
      }
    }
  }

  expect_failures = [var.jobs]
}

run "job_name_with_a_slash_rejected" {
  command = plan

  variables {
    jobs = {
      "alpha/dev" = {
        role_arn        = "arn:aws:iam::111111111111:role/alpha-dev-glue-job"
        script_location = "s3://alpha-dev-glue-assets/scripts/raw_to_curated.py"
      }
    }
  }

  expect_failures = [var.jobs]
}

run "job_negative_max_retries_rejected" {
  command = plan

  variables {
    jobs = {
      alpha-dev-raw-to-curated = {
        role_arn        = "arn:aws:iam::111111111111:role/alpha-dev-glue-job"
        script_location = "s3://alpha-dev-glue-assets/scripts/raw_to_curated.py"
        max_retries     = -1
      }
    }
  }

  expect_failures = [var.jobs]
}

run "job_zero_max_concurrent_runs_rejected" {
  command = plan

  variables {
    jobs = {
      alpha-dev-raw-to-curated = {
        role_arn            = "arn:aws:iam::111111111111:role/alpha-dev-glue-job"
        script_location     = "s3://alpha-dev-glue-assets/scripts/raw_to_curated.py"
        max_concurrent_runs = 0
      }
    }
  }

  expect_failures = [var.jobs]
}

run "crawler_name_with_a_slash_rejected" {
  command = plan

  variables {
    crawlers = {
      "alpha/dev" = {
        role_arn      = "arn:aws:iam::111111111111:role/alpha-dev-glue-crawler"
        database_name = "alpha_dev_raw"
        s3_paths      = ["s3://alpha-dev-raw/raw/"]
      }
    }
  }

  expect_failures = [var.crawlers]
}

run "trigger_name_with_a_slash_rejected" {
  command = plan

  variables {
    triggers = {
      "alpha/nightly" = {
        type     = "SCHEDULED"
        schedule = "cron(0 18 * * ? *)"
        actions  = [{ job = "alpha-dev-raw-to-curated" }]
      }
    }
  }

  expect_failures = [var.triggers]
}

# ---- negative: workflow and triggers --------------------------------------------------------------------------

run "workflow_name_with_a_space_rejected" {
  command = plan

  variables {
    workflow = { name = "raw to curated" }
  }

  expect_failures = [var.workflow]
}

run "trigger_unknown_type_rejected" {
  command = plan

  variables {
    triggers = {
      nightly = {
        type     = "ON_DEMAND"
        schedule = "cron(0 18 * * ? *)"
        actions  = [{ job = "alpha-dev-raw-to-curated" }]
      }
    }
  }

  expect_failures = [var.triggers]
}

run "scheduled_trigger_without_schedule_rejected" {
  command = plan

  variables {
    triggers = {
      nightly = {
        type    = "SCHEDULED"
        actions = [{ job = "alpha-dev-raw-to-curated" }]
      }
    }
  }

  expect_failures = [var.triggers]
}

run "scheduled_trigger_schedule_not_cron_rejected" {
  command = plan

  variables {
    triggers = {
      nightly = {
        type     = "SCHEDULED"
        schedule = "every night"
        actions  = [{ job = "alpha-dev-raw-to-curated" }]
      }
    }
  }

  expect_failures = [var.triggers]
}

run "scheduled_trigger_with_predicate_rejected" {
  command = plan

  variables {
    triggers = {
      nightly = {
        type     = "SCHEDULED"
        schedule = "cron(0 18 * * ? *)"
        predicate = {
          conditions = [{ job = "alpha-dev-raw-to-curated", state = "SUCCEEDED" }]
        }
        actions = [{ job = "alpha-dev-raw-to-curated" }]
      }
    }
  }

  expect_failures = [var.triggers]
}

run "conditional_trigger_without_predicate_rejected" {
  command = plan

  variables {
    triggers = {
      after = {
        type    = "CONDITIONAL"
        actions = [{ job = "alpha-dev-raw-to-curated" }]
      }
    }
  }

  expect_failures = [var.triggers]
}

run "conditional_trigger_with_schedule_rejected" {
  command = plan

  variables {
    triggers = {
      after = {
        type     = "CONDITIONAL"
        schedule = "cron(0 18 * * ? *)"
        predicate = {
          conditions = [{ job = "alpha-dev-raw-to-curated", state = "SUCCEEDED" }]
        }
        actions = [{ job = "alpha-dev-raw-to-curated" }]
      }
    }
  }

  expect_failures = [var.triggers]
}

run "conditional_trigger_with_empty_conditions_rejected" {
  command = plan

  variables {
    triggers = {
      after = {
        type      = "CONDITIONAL"
        predicate = { conditions = [] }
        actions   = [{ job = "alpha-dev-raw-to-curated" }]
      }
    }
  }

  expect_failures = [var.triggers]
}

run "predicate_logical_unknown_rejected" {
  command = plan

  variables {
    triggers = {
      after = {
        type = "CONDITIONAL"
        predicate = {
          logical    = "OR"
          conditions = [{ job = "alpha-dev-raw-to-curated", state = "SUCCEEDED" }]
        }
        actions = [{ job = "alpha-dev-raw-to-curated" }]
      }
    }
  }

  expect_failures = [var.triggers]
}

run "predicate_job_state_unknown_rejected" {
  command = plan

  variables {
    triggers = {
      after = {
        type = "CONDITIONAL"
        predicate = {
          conditions = [{ job = "alpha-dev-raw-to-curated", state = "RUNNING" }]
        }
        actions = [{ job = "alpha-dev-raw-to-curated" }]
      }
    }
  }

  expect_failures = [var.triggers]
}

run "predicate_crawler_state_unknown_rejected" {
  command = plan

  variables {
    triggers = {
      after = {
        type = "CONDITIONAL"
        predicate = {
          conditions = [{ crawler = "alpha-dev-raw", state = "TIMEOUT" }]
        }
        actions = [{ job = "alpha-dev-raw-to-curated" }]
      }
    }
  }

  expect_failures = [var.triggers]
}

run "predicate_condition_with_job_and_crawler_rejected" {
  command = plan

  variables {
    triggers = {
      after = {
        type = "CONDITIONAL"
        predicate = {
          conditions = [{ job = "alpha-dev-raw-to-curated", crawler = "alpha-dev-raw", state = "SUCCEEDED" }]
        }
        actions = [{ job = "alpha-dev-raw-to-curated" }]
      }
    }
  }

  expect_failures = [var.triggers]
}

run "predicate_pointing_to_a_missing_job_rejected" {
  command = plan

  variables {
    triggers = {
      after = {
        type = "CONDITIONAL"
        predicate = {
          conditions = [{ job = "no-such-job", state = "SUCCEEDED" }]
        }
        actions = [{ job = "alpha-dev-raw-to-curated" }]
      }
    }
  }

  expect_failures = [var.triggers]
}

run "predicate_pointing_to_a_missing_crawler_rejected" {
  command = plan

  variables {
    triggers = {
      after = {
        type = "CONDITIONAL"
        predicate = {
          conditions = [{ crawler = "no-such-crawler", state = "SUCCEEDED" }]
        }
        actions = [{ job = "alpha-dev-raw-to-curated" }]
      }
    }
  }

  expect_failures = [var.triggers]
}

run "trigger_pointing_to_a_missing_job_rejected" {
  command = plan

  variables {
    triggers = {
      nightly = {
        type     = "SCHEDULED"
        schedule = "cron(0 18 * * ? *)"
        actions  = [{ job = "no-such-job" }]
      }
    }
  }

  expect_failures = [var.triggers]
}

run "trigger_pointing_to_a_missing_crawler_rejected" {
  command = plan

  variables {
    triggers = {
      nightly = {
        type     = "SCHEDULED"
        schedule = "cron(0 18 * * ? *)"
        actions  = [{ crawler = "no-such-crawler" }]
      }
    }
  }

  expect_failures = [var.triggers]
}

run "trigger_action_with_job_and_crawler_rejected" {
  command = plan

  variables {
    triggers = {
      nightly = {
        type     = "SCHEDULED"
        schedule = "cron(0 18 * * ? *)"
        actions  = [{ job = "alpha-dev-raw-to-curated", crawler = "alpha-dev-raw" }]
      }
    }
  }

  expect_failures = [var.triggers]
}

run "trigger_action_with_neither_job_nor_crawler_rejected" {
  command = plan

  variables {
    triggers = {
      nightly = {
        type     = "SCHEDULED"
        schedule = "cron(0 18 * * ? *)"
        actions  = [{}]
      }
    }
  }

  expect_failures = [var.triggers]
}

run "trigger_without_actions_rejected" {
  command = plan

  variables {
    triggers = {
      nightly = {
        type     = "SCHEDULED"
        schedule = "cron(0 18 * * ? *)"
        actions  = []
      }
    }
  }

  expect_failures = [var.triggers]
}

run "trigger_in_a_workflow_without_workflow_rejected" {
  command = plan

  variables {
    triggers = {
      nightly = {
        type     = "SCHEDULED"
        schedule = "cron(0 18 * * ? *)"
        workflow = true
        actions  = [{ job = "alpha-dev-raw-to-curated" }]
      }
    }
  }

  expect_failures = [var.triggers]
}

# ---- negative: event trigger ----------------------------------------------------------------------------------

run "event_trigger_without_workflow_rejected" {
  command = plan

  variables {
    event_trigger = {
      bucket_name = "alpha-dev-raw"
      key_prefix  = "raw/"
      role_arn    = "arn:aws:iam::111111111111:role/alpha-dev-glue-events"
      actions     = [{ job = "alpha-dev-raw-to-curated" }]
      batch_size  = 100
    }
  }

  expect_failures = [var.event_trigger]
}

run "event_trigger_batch_size_zero_rejected" {
  command = plan

  variables {
    workflow = { name = "alpha-dev-raw-to-curated" }
    event_trigger = {
      bucket_name = "alpha-dev-raw"
      key_prefix  = "raw/"
      role_arn    = "arn:aws:iam::111111111111:role/alpha-dev-glue-events"
      actions     = [{ job = "alpha-dev-raw-to-curated" }]
      batch_size  = 0
    }
  }

  expect_failures = [var.event_trigger]
}

run "event_trigger_batch_size_101_rejected" {
  command = plan

  variables {
    workflow = { name = "alpha-dev-raw-to-curated" }
    event_trigger = {
      bucket_name = "alpha-dev-raw"
      key_prefix  = "raw/"
      role_arn    = "arn:aws:iam::111111111111:role/alpha-dev-glue-events"
      actions     = [{ job = "alpha-dev-raw-to-curated" }]
      batch_size  = 101
    }
  }

  expect_failures = [var.event_trigger]
}

run "event_trigger_window_zero_rejected" {
  command = plan

  variables {
    workflow = { name = "alpha-dev-raw-to-curated" }
    event_trigger = {
      bucket_name          = "alpha-dev-raw"
      key_prefix           = "raw/"
      role_arn             = "arn:aws:iam::111111111111:role/alpha-dev-glue-events"
      actions              = [{ job = "alpha-dev-raw-to-curated" }]
      batch_size           = 100
      batch_window_seconds = 0
    }
  }

  expect_failures = [var.event_trigger]
}

run "event_trigger_window_901_rejected" {
  command = plan

  variables {
    workflow = { name = "alpha-dev-raw-to-curated" }
    event_trigger = {
      bucket_name          = "alpha-dev-raw"
      key_prefix           = "raw/"
      role_arn             = "arn:aws:iam::111111111111:role/alpha-dev-glue-events"
      actions              = [{ job = "alpha-dev-raw-to-curated" }]
      batch_size           = 100
      batch_window_seconds = 901
    }
  }

  expect_failures = [var.event_trigger]
}

run "event_trigger_role_not_an_iam_role_arn_rejected" {
  command = plan

  variables {
    workflow = { name = "alpha-dev-raw-to-curated" }
    event_trigger = {
      bucket_name = "alpha-dev-raw"
      key_prefix  = "raw/"
      role_arn    = "alpha-dev-glue-events"
      actions     = [{ job = "alpha-dev-raw-to-curated" }]
      batch_size  = 100
    }
  }

  expect_failures = [var.event_trigger]
}

run "event_trigger_empty_key_prefix_rejected" {
  command = plan

  variables {
    workflow = { name = "alpha-dev-raw-to-curated" }
    event_trigger = {
      bucket_name = "alpha-dev-raw"
      key_prefix  = ""
      role_arn    = "arn:aws:iam::111111111111:role/alpha-dev-glue-events"
      actions     = [{ job = "alpha-dev-raw-to-curated" }]
      batch_size  = 100
    }
  }

  expect_failures = [var.event_trigger]
}

run "event_trigger_key_prefix_with_leading_slash_rejected" {
  command = plan

  variables {
    workflow = { name = "alpha-dev-raw-to-curated" }
    event_trigger = {
      bucket_name = "alpha-dev-raw"
      key_prefix  = "/raw/"
      role_arn    = "arn:aws:iam::111111111111:role/alpha-dev-glue-events"
      actions     = [{ job = "alpha-dev-raw-to-curated" }]
      batch_size  = 100
    }
  }

  expect_failures = [var.event_trigger]
}

run "event_trigger_invalid_bucket_name_rejected" {
  command = plan

  variables {
    workflow = { name = "alpha-dev-raw-to-curated" }
    event_trigger = {
      bucket_name = "Alpha_Dev_Raw"
      key_prefix  = "raw/"
      role_arn    = "arn:aws:iam::111111111111:role/alpha-dev-glue-events"
      actions     = [{ job = "alpha-dev-raw-to-curated" }]
      batch_size  = 100
    }
  }

  expect_failures = [var.event_trigger]
}

run "event_trigger_pointing_to_a_missing_job_rejected" {
  command = plan

  variables {
    workflow = { name = "alpha-dev-raw-to-curated" }
    event_trigger = {
      bucket_name = "alpha-dev-raw"
      key_prefix  = "raw/"
      role_arn    = "arn:aws:iam::111111111111:role/alpha-dev-glue-events"
      actions     = [{ job = "no-such-job" }]
      batch_size  = 100
    }
  }

  expect_failures = [var.event_trigger]
}

run "event_trigger_without_actions_rejected" {
  command = plan

  variables {
    workflow = { name = "alpha-dev-raw-to-curated" }
    event_trigger = {
      bucket_name = "alpha-dev-raw"
      key_prefix  = "raw/"
      role_arn    = "arn:aws:iam::111111111111:role/alpha-dev-glue-events"
      actions     = []
      batch_size  = 100
    }
  }

  expect_failures = [var.event_trigger]
}

run "event_trigger_workflow_name_too_long_for_the_rule_rejected" {
  command = plan

  variables {
    workflow = { name = join("", [for i in range(56) : "a"]) }
    event_trigger = {
      bucket_name = "alpha-dev-raw"
      key_prefix  = "raw/"
      role_arn    = "arn:aws:iam::111111111111:role/alpha-dev-glue-events"
      actions     = [{ job = "alpha-dev-raw-to-curated" }]
      batch_size  = 100
    }
  }

  expect_failures = [var.event_trigger]
}

# ---- a workflow has a single start trigger ----------------------------------------------------------------------

run "event_trigger_with_a_conditional_workflow_trigger_is_accepted" {
  command = plan

  variables {
    workflow = { name = "alpha-dev-raw-to-curated" }
    event_trigger = {
      bucket_name = "alpha-dev-raw"
      key_prefix  = "raw/"
      role_arn    = "arn:aws:iam::111111111111:role/alpha-dev-glue-events"
      actions     = [{ job = "alpha-dev-raw-to-curated" }]
      batch_size  = 100
    }
    triggers = {
      after-job = {
        type     = "CONDITIONAL"
        workflow = true
        predicate = {
          conditions = [{ job = "alpha-dev-raw-to-curated", state = "SUCCEEDED" }]
        }
        actions = [{ crawler = "alpha-dev-raw" }]
      }
    }
  }

  assert {
    condition     = aws_glue_trigger.this["after-job"].workflow_name == "alpha-dev-raw-to-curated"
    error_message = "A CONDITIONAL trigger can follow the event start trigger in the same workflow"
  }
}

run "event_trigger_with_a_scheduled_workflow_trigger_rejected" {
  command = plan

  variables {
    workflow = { name = "alpha-dev-raw-to-curated" }
    event_trigger = {
      bucket_name = "alpha-dev-raw"
      key_prefix  = "raw/"
      role_arn    = "arn:aws:iam::111111111111:role/alpha-dev-glue-events"
      actions     = [{ job = "alpha-dev-raw-to-curated" }]
      batch_size  = 100
    }
    triggers = {
      nightly = {
        type     = "SCHEDULED"
        schedule = "cron(0 1 * * ? *)"
        workflow = true
        actions  = [{ crawler = "alpha-dev-raw" }]
      }
    }
  }

  expect_failures = [var.event_trigger]
}

run "two_scheduled_workflow_triggers_rejected" {
  command = plan

  variables {
    workflow = { name = "alpha-dev-raw-to-curated" }
    triggers = {
      nightly = {
        type     = "SCHEDULED"
        schedule = "cron(0 1 * * ? *)"
        workflow = true
        actions  = [{ crawler = "alpha-dev-raw" }]
      }
      hourly = {
        type     = "SCHEDULED"
        schedule = "cron(0 * * * ? *)"
        workflow = true
        actions  = [{ job = "alpha-dev-raw-to-curated" }]
      }
    }
  }

  expect_failures = [var.triggers]
}
