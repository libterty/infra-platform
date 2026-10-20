# Plans the real rds, iam-role, elasticache-redis and log-metric-alarm modules together (nothing but the SSM reads is
# overridden), so Terraform builds the whole dependency graph. A cycle between the Proxy role and the cluster would
# fail here (design section 7, R2).
mock_provider "aws" {}

mock_provider "random" {}

variables {
  project               = "example"
  env                   = "dev"
  expected_account_id   = "111111111111"
  engine_version        = "16.6"
  db_instance_class     = "db.t4g.medium"
  connections_threshold = 300
  redis = {
    "rate-limit" = { node_type = "cache.t4g.small" }
    "stream"     = { node_type = "cache.t4g.small", num_node_groups = 2 }
  }
}

override_module {
  target = module.in
  outputs = {
    strings = {
      alarm_topic_arn = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms"
      db_sg_id        = "sg-0aaaaaaa00000004"
      db_proxy_sg_id  = "sg-0aaaaaaa00000005"
      cache_sg_id     = "sg-0aaaaaaa00000006"
    }
    lists = {
      db_subnet_ids = ["subnet-0ddddddd00000001", "subnet-0ddddddd00000002"]
    }
  }
}

override_data {
  target = data.aws_kms_alias.secretsmanager
  values = { target_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

run "proxy_role_and_cluster_have_no_dependency_cycle" {
  command = plan

  assert {
    condition     = module.db.deployment == "aurora" && module.proxy_role.name == "example-dev-rds-proxy"
    error_message = "The cluster, the Proxy and the Proxy role must plan together"
  }
}

run "real_modules_accept_the_wiring" {
  command = plan

  assert {
    condition     = toset(keys(module.redis)) == toset(["rate-limit", "stream"]) && module.db.database_name == "app"
    error_message = "The modules must accept the inputs this stack builds, including their own validations"
  }

  assert {
    condition     = length(module.partition_alarms.alarm_names) == 3
    error_message = "Three partition alarms must be planned against the cluster log group"
  }
}
