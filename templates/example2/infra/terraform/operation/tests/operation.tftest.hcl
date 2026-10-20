mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
}

variables {
  project                  = "example"
  env                      = "dev"
  expected_account_id      = "111111111111"
  import_extract_image_tag = "0.1.0"
  import_load_image_tag    = "0.1.0"
}

override_module {
  target = module.shared
  outputs = {
    strings = {
      app_sg_id               = "sg-0123456789abcdef0"
      bastion_sg_id           = "sg-0fedcba9876543210"
      import_extract_role_arn = "arn:aws:iam::111111111111:role/example-dev-import-extract"
      import_load_role_arn    = "arn:aws:iam::111111111111:role/example-dev-import-load"
      db_proxy_endpoint       = "example-dev-proxy.proxy-abc.ap-northeast-1.rds.amazonaws.com"
      db_name                 = "app"
      db_secret_arn           = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000"
      ecr_repository_urls = jsonencode({
        import-extract = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-import-extract"
        import-load    = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-import-load"
      })
    }
    lists = {
      app_subnet_ids = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0bbbbbbbbbbbbbbb2"]
    }
  }
}

# ---- reads ----

run "reads_only_tree_b" {
  command = plan

  assert {
    condition = local.shared_input_strings == {
      app_sg_id               = "infra/app_sg_id"
      bastion_sg_id           = "infra/bastion_sg_id"
      import_extract_role_arn = "infra/import_extract_role_arn"
      import_load_role_arn    = "infra/import_load_role_arn"
      db_proxy_endpoint       = "infra/db_proxy_endpoint"
      db_name                 = "infra/db_name"
      db_secret_arn           = "infra/db_secret_arn"
      ecr_repository_urls     = "infra/ecr_repository_urls"
    } && local.shared_input_lists == { app_subnet_ids = "infra/app_subnet_ids" }
    error_message = "operation reads the security groups, the two Lambda roles, the database and the repositories from tree B"
  }
}

# ---- bastion ----

run "bastion_is_off_by_default_and_creates_nothing" {
  command = plan

  assert {
    condition     = length(module.bastion_role) == 0 && length(module.bastion) == 0
    error_message = "bastion_enabled = false creates neither the role nor the instance"
  }
}

run "bastion_enabled_creates_the_role_with_a_profile_and_the_instance" {
  command = plan

  variables {
    bastion_enabled = true
  }

  assert {
    condition     = length(module.bastion_role) == 1 && length(module.bastion) == 1
    error_message = "One role and one instance"
  }

  assert {
    condition     = local.bastion_name == "example-dev-bastion" && module.bastion_role[0].name == "example-dev-bastion"
    error_message = "The role and the instance profile are named after the bastion"
  }
}

run "bastion_policy_is_limited_to_session_manager_actions" {
  command = plan

  assert {
    condition = alltrue([
      for s in local.bastion_policy.Statement :
      alltrue([for a in s.Action : anytrue([for p in ["ssm:", "ssmmessages:", "ec2messages:"] : startswith(a, p)])])
    ])
    error_message = "The bastion role only needs the Session Manager agent actions, never a data or admin action"
  }

  assert {
    condition     = !anytrue([for s in local.bastion_policy.Statement : anytrue([for a in s.Action : endswith(a, "*")])])
    error_message = "No wildcard actions"
  }
}

run "bastion_trusts_ec2_only" {
  command = plan

  assert {
    condition     = local.bastion_trust.service_principals == toset(["ec2.amazonaws.com"]) && local.bastion_trust.source_account == "111111111111"
    error_message = "Only EC2 in this account assumes the bastion role"
  }
}

# ---- eval-batch bucket ----

run "dev_has_the_eval_batch_bucket" {
  command = plan

  assert {
    condition     = length(module.eval_batch_bucket) == 1 && local.eval_batch_bucket_name == "example-dev-eval-batch-111111111111"
    error_message = "The eval-batch bucket exists in dev and follows <project>-<env>-eval-batch-<account>"
  }
}

run "sit_has_no_eval_batch_bucket" {
  command = plan

  variables {
    env                 = "sit"
    expected_account_id = "222222222222"
  }

  assert {
    condition     = length(module.eval_batch_bucket) == 0
    error_message = "The eval data stays in the dev account"
  }
}

# ---- import bucket and notifications ----

run "import_bucket_follows_the_naming_rule_iam_uses" {
  command = plan

  assert {
    condition     = local.import_bucket_name == "example-dev-import-111111111111" && local.import_bucket_arn == "arn:aws:s3:::example-dev-import-111111111111"
    error_message = "iam grants the Lambda roles access by this name"
  }
}

run "uploads_trigger_extract_and_the_handoff_triggers_load" {
  command = plan

  assert {
    condition     = local.import_notifications["extract"].filter_prefix == "incoming/" && local.import_notifications["load"].filter_prefix == "extracted/"
    error_message = "incoming/ starts the extraction and the extracted/ handoff starts the load"
  }

  assert {
    condition     = try(local.import_notifications["extract"].filter_suffix, null) == null && local.import_notifications["load"].filter_suffix == "ready.json"
    error_message = "Only the load trigger filters on a suffix"
  }

  assert {
    condition     = !startswith(local.import_notifications["load"].filter_prefix, local.import_notifications["extract"].filter_prefix) && !startswith(local.import_notifications["extract"].filter_prefix, local.import_notifications["load"].filter_prefix)
    error_message = "S3 rejects notifications whose prefixes overlap when the suffixes could overlap too"
  }
}

run "import_bucket_keeps_versions_and_expires_only_the_handoff_prefix" {
  command = plan

  assert {
    condition     = local.import_expiration_prefix == "extracted/" && local.import_versioning.noncurrent_expiration_days >= 1
    error_message = "Uploads are kept; the intermediate result expires, and old versions are cleaned up"
  }
}

# ---- Lambda functions ----

run "each_lambda_uses_its_own_role" {
  command = plan

  assert {
    condition     = local.lambdas["import-extract"].role_arn == "arn:aws:iam::111111111111:role/example-dev-import-extract" && local.lambdas["import-load"].role_arn == "arn:aws:iam::111111111111:role/example-dev-import-load"
    error_message = "import-extract and import-load run with the roles iam made for them, not a shared one"
  }
}

run "lambda_log_groups_follow_the_naming_rule_iam_uses" {
  command = plan

  assert {
    condition     = module.lambda["import-extract"].log_group_name == "/aws/lambda/example-dev-import-extract" && module.lambda["import-load"].log_group_name == "/aws/lambda/example-dev-import-load"
    error_message = "iam lets each role write only /aws/lambda/<project>-<env>-<function>"
  }
}

run "lambda_images_come_from_the_repositories_with_the_tags" {
  command = plan

  assert {
    condition = (
      local.lambdas["import-extract"].image_uri == "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-import-extract:0.1.0" &&
      local.lambdas["import-load"].image_uri == "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-import-load:0.1.0"
    )
    error_message = "Image URI is repository URL plus tag"
  }
}

run "only_import_load_connects_to_the_database" {
  command = plan

  assert {
    condition     = !contains(keys(local.lambdas["import-extract"].environment), "DB_HOST") && !contains(keys(local.lambdas["import-extract"].environment), "DB_SECRET_ARN")
    error_message = "import-extract has no database access in iam, so it gets no database settings"
  }

  assert {
    condition     = local.lambdas["import-load"].environment["DB_HOST"] == "example-dev-proxy.proxy-abc.ap-northeast-1.rds.amazonaws.com" && startswith(local.lambdas["import-load"].environment["DB_SECRET_ARN"], "arn:")
    error_message = "import-load connects through the proxy and reads the secret by ARN"
  }
}

run "both_lambdas_use_the_same_embedding_model" {
  command = plan

  assert {
    condition     = local.lambdas["import-extract"].environment["EMBEDDING_MODEL_ID"] == local.lambdas["import-load"].environment["EMBEDDING_MODEL_ID"]
    error_message = "extract computes the vectors and load rejects a mismatch, so the two must agree"
  }
}

run "s3_may_invoke_each_lambda_only_from_the_import_bucket_of_this_account" {
  command = plan

  assert {
    condition = alltrue([
      for f in values(local.lambdas) :
      f.permissions["s3_invoke"].principal == "s3.amazonaws.com" &&
      f.permissions["s3_invoke"].source_account == "111111111111" &&
      f.permissions["s3_invoke"].source_arn == "arn:aws:s3:::example-dev-import-111111111111"
    ])
    error_message = "A bucket ARN has no account id, so source_account is what stops another account's bucket of the same name"
  }
}

run "lambda_limits_accept_the_maximum" {
  command = plan

  variables {
    import_extract_memory_size          = 10240
    import_extract_timeout              = 900
    import_extract_reserved_concurrency = 100
    import_load_memory_size             = 128
    import_load_timeout                 = 1
    import_load_reserved_concurrency    = 0
  }

  assert {
    condition     = local.lambdas["import-extract"].memory_size == 10240 && local.lambdas["import-load"].timeout == 1
    error_message = "The edges of the Lambda ranges are accepted"
  }
}

run "rejects_memory_above_the_lambda_maximum" {
  command = plan

  variables {
    import_extract_memory_size = 10241
  }

  expect_failures = [var.import_extract_memory_size]
}

run "rejects_memory_below_the_lambda_minimum" {
  command = plan

  variables {
    import_load_memory_size = 127
  }

  expect_failures = [var.import_load_memory_size]
}

run "rejects_a_timeout_above_fifteen_minutes" {
  command = plan

  variables {
    import_load_timeout = 901
  }

  expect_failures = [var.import_load_timeout]
}

run "rejects_a_zero_timeout" {
  command = plan

  variables {
    import_extract_timeout = 0
  }

  expect_failures = [var.import_extract_timeout]
}

run "rejects_negative_concurrency" {
  command = plan

  variables {
    import_extract_reserved_concurrency = -1
  }

  expect_failures = [var.import_extract_reserved_concurrency]
}

run "rejects_the_latest_image_tag" {
  command = plan

  variables {
    import_load_image_tag = "latest"
  }

  expect_failures = [var.import_load_image_tag]
}

# ---- ETL metrics ----

run "etl_counts_are_metrics_without_alarms" {
  command = plan

  assert {
    condition     = toset(keys(local.etl_metrics)) == toset(["import_load_rejected", "import_load_failed", "import_load_succeeded"])
    error_message = "Rejected, failed and succeeded loads are counted"
  }

  assert {
    condition     = local.metric_namespace == "Example/dev"
    error_message = "Custom metrics live in <Project>/<env>"
  }

  assert {
    condition     = alltrue([for m in values(local.etl_metrics) : startswith(m.pattern, "{ $.event = ")])
    error_message = "The filters read JSON lines the application writes, so the Lambda log format must stay Text"
  }

  assert {
    condition     = toset(keys(module.etl_metrics.metric_names)) == toset(["import_load_rejected", "import_load_failed", "import_load_succeeded"])
    error_message = "The module creates one filter per metric"
  }
}

# ---- publishing ----

run "publishes_the_bucket_and_the_function_names" {
  command = plan

  override_module {
    target  = module.import_bucket
    outputs = { bucket_name = "example-dev-import-111111111111", arn = "arn:aws:s3:::example-dev-import-111111111111" }
  }

  assert {
    condition = module.ssm_publish.names == {
      import_bucket_name           = "/example/dev/operation/import_bucket_name"
      import_extract_function_name = "/example/dev/operation/import_extract_function_name"
      import_load_function_name    = "/example/dev/operation/import_load_function_name"
    }
    error_message = "operation publishes three keys under its own path"
  }

  assert {
    condition     = local.published_strings.import_extract_function_name == "example-dev-import-extract"
    error_message = "Function names are <project>-<env>-<function>"
  }
}
