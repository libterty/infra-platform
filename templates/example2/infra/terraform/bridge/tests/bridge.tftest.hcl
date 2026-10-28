# Tree B is a verbatim copy of the keys the late stacks read; bad tree A values must stop the apply.
mock_provider "aws" {}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
}

# The SSM values are only read here, so fixed ones stand in for them (the mock would return random text).
override_module {
  target = module.in
  outputs = {
    strings = {
      alarm_topic_arn                = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms"
      signing_private_key_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/signing-private-AbCdEf"
      signing_public_key_secret_arn  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/signing-public-GhIjKl"
      agent_runtimes                 = "[\"agent\"]"
      ecr_repository_urls            = "{\"api\":\"111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-api\"}"
      vpc_id                         = "vpc-0aaaaaaa00000001"
      alb_sg_id                      = "sg-0aaaaaaa00000001"
      app_sg_id                      = "sg-0aaaaaaa00000002"
      agent_sg_id                    = "sg-0aaaaaaa00000003"
      bastion_sg_id                  = "sg-0aaaaaaa00000004"
      db_proxy_endpoint              = "example-dev.proxy-abc.ap-northeast-1.rds.amazonaws.com"
      db_secret_arn                  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000"
      rate_limit_redis_endpoint      = "rl.example.cache.amazonaws.com:6379"
      stream_redis_endpoint          = "st.example.cache.amazonaws.com:6379"
      db_name                        = "app"
      stream_shard_count             = "1"
      ecs_execution_role_arn         = "arn:aws:iam::111111111111:role/example-dev-ecs-execution"
      api_task_role_arn              = "arn:aws:iam::111111111111:role/example-dev-api"
      worker_task_role_arn           = "arn:aws:iam::111111111111:role/example-dev-worker"
      import_extract_role_arn        = "arn:aws:iam::111111111111:role/example-dev-import-extract"
      import_load_role_arn           = "arn:aws:iam::111111111111:role/example-dev-import-load"
      agent_runtime_role_arn         = "arn:aws:iam::111111111111:role/example-dev-agent"
      zone_id                        = "Z0123456789ABCDEFGHIJ"
      zone_name                      = "dev.example.com"
      alb_certificate_arn            = "arn:aws:acm:ap-northeast-1:111111111111:certificate/00000000-0000-0000-0000-000000000001"
      cloudfront_certificate_arn     = "arn:aws:acm:us-east-1:111111111111:certificate/00000000-0000-0000-0000-000000000002"
    }
    lists = {
      services          = ["api", "worker"]
      public_subnet_ids = ["subnet-0aaaaaaa00000001", "subnet-0aaaaaaa00000002"]
      app_subnet_ids    = ["subnet-0bbbbbbb00000001", "subnet-0bbbbbbb00000002"]
      agent_subnet_ids  = ["subnet-0ccccccc00000001", "subnet-0ccccccc00000002"]
    }
  }
}

run "publishes_exactly_the_keys_the_late_stacks_read" {
  command = plan

  assert {
    condition = toset(keys(local.published_strings)) == toset([
      "alarm_topic_arn", "signing_private_key_secret_arn", "signing_public_key_secret_arn", "agent_runtimes",
      "ecr_repository_urls", "vpc_id", "alb_sg_id", "app_sg_id", "agent_sg_id", "bastion_sg_id",
      "db_proxy_endpoint", "db_secret_arn", "rate_limit_redis_endpoint", "stream_redis_endpoint", "db_name", "stream_shard_count",
      "ecs_execution_role_arn", "api_task_role_arn", "worker_task_role_arn", "import_extract_role_arn",
      "import_load_role_arn", "agent_runtime_role_arn", "zone_id", "zone_name", "alb_certificate_arn",
      "cloudfront_certificate_arn",
    ])
    error_message = "Tree B strings must be exactly the keys read by the late stacks, plus the zone and the two certificates"
  }

  assert {
    condition     = toset(keys(local.published_lists)) == toset(["services", "public_subnet_ids", "app_subnet_ids", "agent_subnet_ids"])
    error_message = "Tree B lists must be exactly the keys read by the late stacks"
  }
}

run "copies_values_unchanged" {
  command = plan

  assert {
    condition     = local.published_strings == module.in.strings && local.published_lists == module.in.lists
    error_message = "Values must reach tree B exactly as read from tree A"
  }
}

run "writes_to_tree_b" {
  command = plan

  assert {
    condition     = module.ssm_publish.names["vpc_id"] == "/example-shared/dev/infra/vpc_id"
    error_message = "Tree B path must be /<project>-shared/<env>/infra/<key>"
  }
}

run "rejects_an_empty_string_value" {
  command = plan

  override_module {
    target = module.in
    outputs = {
      strings = {
        alarm_topic_arn                = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms"
        signing_private_key_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/signing-private-AbCdEf"
        signing_public_key_secret_arn  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/signing-public-GhIjKl"
        agent_runtimes                 = "[\"agent\"]"
        ecr_repository_urls            = "{\"api\":\"111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-api\"}"
        vpc_id                         = ""
        alb_sg_id                      = "sg-0aaaaaaa00000001"
        app_sg_id                      = "sg-0aaaaaaa00000002"
        agent_sg_id                    = "sg-0aaaaaaa00000003"
        bastion_sg_id                  = "sg-0aaaaaaa00000004"
        db_proxy_endpoint              = "example-dev.proxy-abc.ap-northeast-1.rds.amazonaws.com"
        db_secret_arn                  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000"
        rate_limit_redis_endpoint      = "rl.example.cache.amazonaws.com:6379"
        stream_redis_endpoint          = "st.example.cache.amazonaws.com:6379"
        db_name                        = "app"
        stream_shard_count             = "1"
        ecs_execution_role_arn         = "arn:aws:iam::111111111111:role/example-dev-ecs-execution"
        api_task_role_arn              = "arn:aws:iam::111111111111:role/example-dev-api"
        worker_task_role_arn           = "arn:aws:iam::111111111111:role/example-dev-worker"
        import_extract_role_arn        = "arn:aws:iam::111111111111:role/example-dev-import-extract"
        import_load_role_arn           = "arn:aws:iam::111111111111:role/example-dev-import-load"
        agent_runtime_role_arn         = "arn:aws:iam::111111111111:role/example-dev-agent"
        zone_id                        = "Z0123456789ABCDEFGHIJ"
        zone_name                      = "dev.example.com"
        alb_certificate_arn            = "arn:aws:acm:ap-northeast-1:111111111111:certificate/00000000-0000-0000-0000-000000000001"
        cloudfront_certificate_arn     = "arn:aws:acm:us-east-1:111111111111:certificate/00000000-0000-0000-0000-000000000002"
      }
      lists = {
        services          = ["api", "worker"]
        public_subnet_ids = ["subnet-0aaaaaaa00000001", "subnet-0aaaaaaa00000002"]
        app_subnet_ids    = ["subnet-0bbbbbbb00000001", "subnet-0bbbbbbb00000002"]
        agent_subnet_ids  = ["subnet-0ccccccc00000001", "subnet-0ccccccc00000002"]
      }
    }
  }

  expect_failures = [terraform_data.values_not_empty]
}

run "rejects_a_single_subnet" {
  command = plan

  override_module {
    target = module.in
    outputs = {
      strings = {
        alarm_topic_arn                = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms"
        signing_private_key_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/signing-private-AbCdEf"
        signing_public_key_secret_arn  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/signing-public-GhIjKl"
        agent_runtimes                 = "[\"agent\"]"
        ecr_repository_urls            = "{\"api\":\"111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-api\"}"
        vpc_id                         = "vpc-0aaaaaaa00000001"
        alb_sg_id                      = "sg-0aaaaaaa00000001"
        app_sg_id                      = "sg-0aaaaaaa00000002"
        agent_sg_id                    = "sg-0aaaaaaa00000003"
        bastion_sg_id                  = "sg-0aaaaaaa00000004"
        db_proxy_endpoint              = "example-dev.proxy-abc.ap-northeast-1.rds.amazonaws.com"
        db_secret_arn                  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000"
        rate_limit_redis_endpoint      = "rl.example.cache.amazonaws.com:6379"
        stream_redis_endpoint          = "st.example.cache.amazonaws.com:6379"
        db_name                        = "app"
        stream_shard_count             = "1"
        ecs_execution_role_arn         = "arn:aws:iam::111111111111:role/example-dev-ecs-execution"
        api_task_role_arn              = "arn:aws:iam::111111111111:role/example-dev-api"
        worker_task_role_arn           = "arn:aws:iam::111111111111:role/example-dev-worker"
        import_extract_role_arn        = "arn:aws:iam::111111111111:role/example-dev-import-extract"
        import_load_role_arn           = "arn:aws:iam::111111111111:role/example-dev-import-load"
        agent_runtime_role_arn         = "arn:aws:iam::111111111111:role/example-dev-agent"
        zone_id                        = "Z0123456789ABCDEFGHIJ"
        zone_name                      = "dev.example.com"
        alb_certificate_arn            = "arn:aws:acm:ap-northeast-1:111111111111:certificate/00000000-0000-0000-0000-000000000001"
        cloudfront_certificate_arn     = "arn:aws:acm:us-east-1:111111111111:certificate/00000000-0000-0000-0000-000000000002"
      }
      lists = {
        services          = ["api", "worker"]
        public_subnet_ids = ["subnet-0aaaaaaa00000001", "subnet-0aaaaaaa00000002"]
        app_subnet_ids    = ["subnet-0bbbbbbb00000001"]
        agent_subnet_ids  = ["subnet-0ccccccc00000001", "subnet-0ccccccc00000002"]
      }
    }
  }

  expect_failures = [terraform_data.subnets_span_two_azs]
}

run "rejects_an_agent_runtimes_value_that_is_not_json" {
  command = plan

  override_module {
    target = module.in
    outputs = {
      strings = {
        alarm_topic_arn                = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms"
        signing_private_key_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/signing-private-AbCdEf"
        signing_public_key_secret_arn  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/signing-public-GhIjKl"
        agent_runtimes                 = "agent"
        ecr_repository_urls            = "{\"api\":\"111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-api\"}"
        vpc_id                         = "vpc-0aaaaaaa00000001"
        alb_sg_id                      = "sg-0aaaaaaa00000001"
        app_sg_id                      = "sg-0aaaaaaa00000002"
        agent_sg_id                    = "sg-0aaaaaaa00000003"
        bastion_sg_id                  = "sg-0aaaaaaa00000004"
        db_proxy_endpoint              = "example-dev.proxy-abc.ap-northeast-1.rds.amazonaws.com"
        db_secret_arn                  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000"
        rate_limit_redis_endpoint      = "rl.example.cache.amazonaws.com:6379"
        stream_redis_endpoint          = "st.example.cache.amazonaws.com:6379"
        db_name                        = "app"
        stream_shard_count             = "1"
        ecs_execution_role_arn         = "arn:aws:iam::111111111111:role/example-dev-ecs-execution"
        api_task_role_arn              = "arn:aws:iam::111111111111:role/example-dev-api"
        worker_task_role_arn           = "arn:aws:iam::111111111111:role/example-dev-worker"
        import_extract_role_arn        = "arn:aws:iam::111111111111:role/example-dev-import-extract"
        import_load_role_arn           = "arn:aws:iam::111111111111:role/example-dev-import-load"
        agent_runtime_role_arn         = "arn:aws:iam::111111111111:role/example-dev-agent"
        zone_id                        = "Z0123456789ABCDEFGHIJ"
        zone_name                      = "dev.example.com"
        alb_certificate_arn            = "arn:aws:acm:ap-northeast-1:111111111111:certificate/00000000-0000-0000-0000-000000000001"
        cloudfront_certificate_arn     = "arn:aws:acm:us-east-1:111111111111:certificate/00000000-0000-0000-0000-000000000002"
      }
      lists = {
        services          = ["api", "worker"]
        public_subnet_ids = ["subnet-0aaaaaaa00000001", "subnet-0aaaaaaa00000002"]
        app_subnet_ids    = ["subnet-0bbbbbbb00000001", "subnet-0bbbbbbb00000002"]
        agent_subnet_ids  = ["subnet-0ccccccc00000001", "subnet-0ccccccc00000002"]
      }
    }
  }

  expect_failures = [terraform_data.json_values_decode]
}

run "rejects_ecr_repository_urls_that_are_not_an_object" {
  command = plan

  override_module {
    target = module.in
    outputs = {
      strings = {
        alarm_topic_arn                = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms"
        signing_private_key_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/signing-private-AbCdEf"
        signing_public_key_secret_arn  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/signing-public-GhIjKl"
        agent_runtimes                 = "[\"agent\"]"
        ecr_repository_urls            = "[]"
        vpc_id                         = "vpc-0aaaaaaa00000001"
        alb_sg_id                      = "sg-0aaaaaaa00000001"
        app_sg_id                      = "sg-0aaaaaaa00000002"
        agent_sg_id                    = "sg-0aaaaaaa00000003"
        bastion_sg_id                  = "sg-0aaaaaaa00000004"
        db_proxy_endpoint              = "example-dev.proxy-abc.ap-northeast-1.rds.amazonaws.com"
        db_secret_arn                  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000"
        rate_limit_redis_endpoint      = "rl.example.cache.amazonaws.com:6379"
        stream_redis_endpoint          = "st.example.cache.amazonaws.com:6379"
        db_name                        = "app"
        stream_shard_count             = "1"
        ecs_execution_role_arn         = "arn:aws:iam::111111111111:role/example-dev-ecs-execution"
        api_task_role_arn              = "arn:aws:iam::111111111111:role/example-dev-api"
        worker_task_role_arn           = "arn:aws:iam::111111111111:role/example-dev-worker"
        import_extract_role_arn        = "arn:aws:iam::111111111111:role/example-dev-import-extract"
        import_load_role_arn           = "arn:aws:iam::111111111111:role/example-dev-import-load"
        agent_runtime_role_arn         = "arn:aws:iam::111111111111:role/example-dev-agent"
        zone_id                        = "Z0123456789ABCDEFGHIJ"
        zone_name                      = "dev.example.com"
        alb_certificate_arn            = "arn:aws:acm:ap-northeast-1:111111111111:certificate/00000000-0000-0000-0000-000000000001"
        cloudfront_certificate_arn     = "arn:aws:acm:us-east-1:111111111111:certificate/00000000-0000-0000-0000-000000000002"
      }
      lists = {
        services          = ["api", "worker"]
        public_subnet_ids = ["subnet-0aaaaaaa00000001", "subnet-0aaaaaaa00000002"]
        app_subnet_ids    = ["subnet-0bbbbbbb00000001", "subnet-0bbbbbbb00000002"]
        agent_subnet_ids  = ["subnet-0ccccccc00000001", "subnet-0ccccccc00000002"]
      }
    }
  }

  expect_failures = [terraform_data.json_values_decode]
}

run "rejects_a_cloudfront_certificate_outside_us_east_1" {
  command = plan

  override_module {
    target = module.in
    outputs = {
      strings = {
        alarm_topic_arn                = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms"
        signing_private_key_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/signing-private-AbCdEf"
        signing_public_key_secret_arn  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/signing-public-GhIjKl"
        agent_runtimes                 = "[\"agent\"]"
        ecr_repository_urls            = "{\"api\":\"111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-api\"}"
        vpc_id                         = "vpc-0aaaaaaa00000001"
        alb_sg_id                      = "sg-0aaaaaaa00000001"
        app_sg_id                      = "sg-0aaaaaaa00000002"
        agent_sg_id                    = "sg-0aaaaaaa00000003"
        bastion_sg_id                  = "sg-0aaaaaaa00000004"
        db_proxy_endpoint              = "example-dev.proxy-abc.ap-northeast-1.rds.amazonaws.com"
        db_secret_arn                  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000"
        rate_limit_redis_endpoint      = "rl.example.cache.amazonaws.com:6379"
        stream_redis_endpoint          = "st.example.cache.amazonaws.com:6379"
        db_name                        = "app"
        stream_shard_count             = "1"
        ecs_execution_role_arn         = "arn:aws:iam::111111111111:role/example-dev-ecs-execution"
        api_task_role_arn              = "arn:aws:iam::111111111111:role/example-dev-api"
        worker_task_role_arn           = "arn:aws:iam::111111111111:role/example-dev-worker"
        import_extract_role_arn        = "arn:aws:iam::111111111111:role/example-dev-import-extract"
        import_load_role_arn           = "arn:aws:iam::111111111111:role/example-dev-import-load"
        agent_runtime_role_arn         = "arn:aws:iam::111111111111:role/example-dev-agent"
        zone_id                        = "Z0123456789ABCDEFGHIJ"
        zone_name                      = "dev.example.com"
        alb_certificate_arn            = "arn:aws:acm:ap-northeast-1:111111111111:certificate/00000000-0000-0000-0000-000000000001"
        cloudfront_certificate_arn     = "arn:aws:acm:ap-northeast-1:111111111111:certificate/00000000-0000-0000-0000-000000000002"
      }
      lists = {
        services          = ["api", "worker"]
        public_subnet_ids = ["subnet-0aaaaaaa00000001", "subnet-0aaaaaaa00000002"]
        app_subnet_ids    = ["subnet-0bbbbbbb00000001", "subnet-0bbbbbbb00000002"]
        agent_subnet_ids  = ["subnet-0ccccccc00000001", "subnet-0ccccccc00000002"]
      }
    }
  }

  expect_failures = [terraform_data.certificates_in_their_regions]
}
