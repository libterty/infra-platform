# Plan-level behaviour of the search stack. No AWS call is made: the provider is mocked, the SSM reads are overridden
# with values of the shape the earlier stacks publish, and the master secret is a fake.
mock_provider "aws" {
  mock_data "aws_secretsmanager_secret_version" {
    defaults = {
      secret_string = "{\"username\":\"admin-placeholder\",\"password\":\"not-a-real-password-1A!\"}"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "ap-northeast-1"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111111111111"
    }
  }
}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"

  engine_version = "OpenSearch_2.19"
  hot = {
    instance_type  = "m7g.large.search"
    instance_count = 2
    ebs            = { volume_size = 20 }
  }
  dedicated_master = { instance_type = "m7g.large.search", count = 3 }
  warm             = { instance_type = "ultrawarm1.medium.search", count = 2 }
  cold_storage     = true
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/alarm_topic_arn"]
  values = { insecure_value = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/opensearch_master_secret_arn"]
  values = { insecure_value = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev-opensearch-master-AbCdEf" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/subnet_ids_data"]
  values = { insecure_value = "subnet-0dda0001,subnet-0dda0002" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/sg_opensearch_id"]
  values = { insecure_value = "sg-0aaaaaaa00000001" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_firehose_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-dev-firehose" }
}

run "reads_only_keys_published_earlier" {
  command = plan

  assert {
    condition = local.ssm_input_strings == {
      kms_key_arn                  = "foundation/kms_key_arn"
      alarm_topic_arn              = "foundation/alarm_topic_arn"
      opensearch_master_secret_arn = "foundation/opensearch_master_secret_arn"
      sg_opensearch_id             = "network/sg_opensearch_id"
      role_firehose_arn            = "iam-base/role_firehose_arn"
    }
    error_message = "search must read the shared key, the alarm topic and the master secret from foundation, the SG from network and the Firehose role from iam-base"
  }

  assert {
    condition     = local.ssm_input_lists == { subnet_ids_data = "network/subnet_ids_data" }
    error_message = "search must read only the data subnets as a list"
  }
}

run "domain_is_wired_to_the_shared_inputs" {
  command = plan

  assert {
    condition = (
      local.domain.name == "example-dev-search" &&
      local.domain.kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" &&
      local.domain.master_user_secret_arn == "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev-opensearch-master-AbCdEf"
    )
    error_message = "The domain must be named <name_prefix>-search and use the shared key and the foundation master secret"
  }

  assert {
    condition     = jsonencode(local.domain.subnet_ids) == jsonencode(["subnet-0dda0001", "subnet-0dda0002"]) && local.domain.availability_zone_count == 2
    error_message = "The domain must sit in the two data subnets, one per AZ"
  }

  assert {
    condition     = local.domain.security_group_ids == ["sg-0aaaaaaa00000001"]
    error_message = "The domain must use only the opensearch security group of the network stack"
  }
}

run "access_policy_lists_only_the_firehose_role" {
  command = plan

  assert {
    condition     = local.domain.access_principal_arns == ["arn:aws:iam::111111111111:role/example-dev-firehose"]
    error_message = "access_principal_arns must hold exactly the iam-base Firehose role and nothing else"
  }

  assert {
    condition     = alltrue([for p in local.domain.access_principal_arns : !strcontains(p, "*")])
    error_message = "No access principal may be a wildcard"
  }
}

run "domain_takes_the_tier_sizes_from_variables" {
  command = plan

  assert {
    condition = (
      local.domain.engine_version == "OpenSearch_2.19" &&
      local.domain.hot.instance_count == 2 &&
      local.domain.dedicated_master.count == 3 &&
      local.domain.warm.count == 2 &&
      local.domain.cold_storage
    )
    error_message = "The stack must pass hot, master, warm and cold settings through unchanged"
  }

  assert {
    condition     = module.domain.domain_name == "example-dev-search"
    error_message = "The module output must carry the domain name"
  }
}

run "publishes_exactly_the_search_contract" {
  command = plan

  assert {
    condition     = toset(keys(local.published_strings)) == toset(["opensearch_domain_arn", "opensearch_domain_name", "opensearch_endpoint"])
    error_message = "search must publish opensearch_domain_arn, opensearch_domain_name and opensearch_endpoint and nothing else"
  }

  assert {
    condition = module.ssm_publish.names == {
      opensearch_domain_arn  = "/example/dev/search/opensearch_domain_arn"
      opensearch_domain_name = "/example/dev/search/opensearch_domain_name"
      opensearch_endpoint    = "/example/dev/search/opensearch_endpoint"
    }
    error_message = "ssm-publish must write the three contract keys under the search stack path"
  }
}

run "full_tiering_alarms" {
  command = plan

  assert {
    condition = toset(keys(local.alarms)) == toset([
      "cluster_status_red",
      "free_storage_space",
      "jvm_memory_pressure",
      "warm_jvm_memory_pressure",
      "hot_to_warm_migration_failed",
      "warm_to_cold_migration_failed",
    ])
    error_message = "With warm and cold on, search must alarm on red status, hot storage, JVM pressure, warm JVM pressure and both migrations"
  }

  assert {
    condition = alltrue([
      for a in values(local.alarms) : a.metric.namespace == "AWS/ES" && a.metric.dimensions == { DomainName = "example-dev-search", ClientId = "111111111111" }
    ])
    error_message = "Every alarm must use the AWS/ES namespace and the per-domain, per-client dimensions (DomainName, ClientId = account id)"
  }

  assert {
    condition = (
      local.alarms["cluster_status_red"].metric.metric_name == "ClusterStatus.red" &&
      local.alarms["cluster_status_red"].metric.statistic == "Maximum" &&
      local.alarms["cluster_status_red"].threshold == 1
    )
    error_message = "A red cluster must alarm at a Maximum of 1"
  }

  # 25% of one node's 20 GiB volume, in MiB (the metric is in MiB).
  assert {
    condition = (
      local.alarms["free_storage_space"].metric.metric_name == "FreeStorageSpace" &&
      local.alarms["free_storage_space"].metric.statistic == "Minimum" &&
      local.alarms["free_storage_space"].comparison_operator == "LessThanOrEqualToThreshold" &&
      local.alarms["free_storage_space"].threshold == 5120
    )
    error_message = "Free storage must alarm when the fullest node is down to 25% of its volume (5120 MiB for 20 GiB)"
  }

  assert {
    condition = (
      local.alarms["jvm_memory_pressure"].metric.metric_name == "JVMMemoryPressure" &&
      local.alarms["jvm_memory_pressure"].metric.statistic == "Maximum" &&
      local.alarms["jvm_memory_pressure"].threshold == 95 &&
      local.alarms["warm_jvm_memory_pressure"].metric.metric_name == "WarmJVMMemoryPressure" &&
      local.alarms["warm_jvm_memory_pressure"].metric.statistic == "Maximum" &&
      local.alarms["warm_jvm_memory_pressure"].threshold == 95
    )
    error_message = "JVM pressure alarms (data and warm nodes) must fire at 95 percent, Maximum"
  }

  assert {
    condition = (
      local.alarms["hot_to_warm_migration_failed"].metric.metric_name == "HotToWarmMigrationFailureCount" &&
      local.alarms["warm_to_cold_migration_failed"].metric.metric_name == "WarmToColdMigrationFailureCount" &&
      local.alarms["hot_to_warm_migration_failed"].metric.statistic == "Sum" &&
      local.alarms["warm_to_cold_migration_failed"].metric.statistic == "Sum"
    )
    error_message = "Both ISM migration failure counts must alarm on Sum"
  }
}

run "hot_only_has_no_warm_or_cold_alarms" {
  command = plan

  variables {
    dedicated_master = null
    warm             = null
    cold_storage     = false
  }

  assert {
    condition     = toset(keys(local.alarms)) == toset(["cluster_status_red", "free_storage_space", "jvm_memory_pressure"])
    error_message = "Without warm, only the three data-node alarms may exist"
  }
}

run "warm_without_cold_has_no_cold_migration_alarm" {
  command = plan

  variables {
    cold_storage = false
  }

  assert {
    condition     = contains(keys(local.alarms), "hot_to_warm_migration_failed") && !contains(keys(local.alarms), "warm_to_cold_migration_failed")
    error_message = "The warm-to-cold alarm needs cold storage; the hot-to-warm one needs only warm"
  }
}

run "alarms_go_to_the_foundation_topic" {
  command = plan

  assert {
    condition     = toset(keys(module.alarms.alarm_names)) == toset(keys(local.alarms))
    error_message = "The alarm module must create one alarm per entry of local.alarms"
  }
}
