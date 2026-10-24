# Every validation block has at least one run that must fail. Each run breaks exactly one rule.

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
  name           = "alpha-dev-search"
  engine_version = "OpenSearch_2.19"
  hot = {
    instance_type  = "m7g.large.search"
    instance_count = 2
    ebs            = { volume_size = 20 }
  }
  subnet_ids             = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"]
  security_group_ids     = ["sg-0123456789abcdef0"]
  kms_key_arn            = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
  master_user_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev-opensearch-master-AbCdEf"
}

# ---- tiers ---------------------------------------------------------------------------------------------------

run "warm_without_dedicated_master" {
  command = plan

  variables {
    warm = { instance_type = "ultrawarm1.medium.search", count = 2 }
  }

  expect_failures = [var.warm]
}

run "warm_with_t3_data_nodes" {
  command = plan

  variables {
    hot = {
      instance_type  = "t3.medium.search"
      instance_count = 2
      ebs            = { volume_size = 20 }
    }
    dedicated_master = { instance_type = "m7g.large.search", count = 3 }
    warm             = { instance_type = "ultrawarm1.medium.search", count = 2 }
  }

  expect_failures = [var.warm]
}

run "warm_with_t2_data_nodes" {
  command = plan

  variables {
    hot = {
      instance_type  = "t2.medium.search"
      instance_count = 2
      ebs            = { volume_size = 20 }
    }
    dedicated_master = { instance_type = "m7g.large.search", count = 3 }
    warm             = { instance_type = "ultrawarm1.medium.search", count = 2 }
  }

  expect_failures = [var.warm]
}

run "cold_storage_without_warm" {
  command = plan

  variables {
    dedicated_master = { instance_type = "m7g.large.search", count = 3 }
    cold_storage     = true
  }

  expect_failures = [var.cold_storage]
}

run "two_master_nodes" {
  command = plan

  variables {
    dedicated_master = { instance_type = "m7g.large.search", count = 2 }
  }

  expect_failures = [var.dedicated_master]
}

run "four_master_nodes" {
  command = plan

  variables {
    dedicated_master = { instance_type = "m7g.large.search", count = 4 }
  }

  expect_failures = [var.dedicated_master]
}

run "master_instance_type_without_search_suffix" {
  command = plan

  variables {
    dedicated_master = { instance_type = "m7g.large", count = 3 }
  }

  expect_failures = [var.dedicated_master]
}

run "single_data_node" {
  command = plan

  variables {
    hot = {
      instance_type  = "m7g.large.search"
      instance_count = 1
      ebs            = { volume_size = 20 }
    }
  }

  expect_failures = [var.hot]
}

run "fewer_data_nodes_than_availability_zones" {
  command = plan

  variables {
    availability_zone_count = 3
    subnet_ids              = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb", "subnet-0cccccccccccccccc"]
  }

  expect_failures = [var.hot]
}

run "hot_instance_type_without_search_suffix" {
  command = plan

  variables {
    hot = {
      instance_type  = "m7g.large"
      instance_count = 2
      ebs            = { volume_size = 20 }
    }
  }

  expect_failures = [var.hot]
}

run "hot_volume_type_not_supported" {
  command = plan

  variables {
    hot = {
      instance_type  = "m7g.large.search"
      instance_count = 2
      ebs            = { volume_size = 20, volume_type = "st1" }
    }
  }

  expect_failures = [var.hot]
}

run "hot_volume_size_zero" {
  command = plan

  variables {
    hot = {
      instance_type  = "m7g.large.search"
      instance_count = 2
      ebs            = { volume_size = 0 }
    }
  }

  expect_failures = [var.hot]
}

run "standby_with_warm_not_a_multiple_of_az_count" {
  command = plan

  variables {
    availability_zone_count = 3
    subnet_ids              = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb", "subnet-0cccccccccccccccc"]
    multi_az_with_standby   = true
    hot = {
      instance_type  = "m7g.large.search"
      instance_count = 3
      ebs            = { volume_size = 20 }
    }
    dedicated_master = { instance_type = "m7g.large.search", count = 3 }
    warm             = { instance_type = "ultrawarm1.medium.search", count = 2 }
  }

  expect_failures = [var.warm]
}

run "warm_type_not_ultrawarm" {
  command = plan

  variables {
    dedicated_master = { instance_type = "m7g.large.search", count = 3 }
    warm             = { instance_type = "ultrawarm1.small.search", count = 2 }
  }

  expect_failures = [var.warm]
}

run "warm_type_oi2_is_not_accepted" {
  command = plan

  variables {
    dedicated_master = { instance_type = "m7g.large.search", count = 3 }
    warm             = { instance_type = "oi2.large.search", count = 2 }
  }

  expect_failures = [var.warm]
}

run "warm_count_zero" {
  command = plan

  variables {
    dedicated_master = { instance_type = "m7g.large.search", count = 3 }
    warm             = { instance_type = "ultrawarm1.medium.search", count = 0 }
  }

  expect_failures = [var.warm]
}

run "availability_zone_count_one" {
  command = plan

  variables {
    availability_zone_count = 1
    subnet_ids              = ["subnet-0aaaaaaaaaaaaaaaa"]
  }

  expect_failures = [var.availability_zone_count]
}

run "availability_zone_count_four" {
  command = plan

  variables {
    availability_zone_count = 4
  }

  expect_failures = [var.availability_zone_count]
}

run "subnet_count_differs_from_az_count" {
  command = plan

  variables {
    availability_zone_count = 3
    hot = {
      instance_type  = "m7g.large.search"
      instance_count = 3
      ebs            = { volume_size = 20 }
    }
  }

  expect_failures = [var.subnet_ids]
}

# ---- identity ------------------------------------------------------------------------------------------------

run "name_with_uppercase" {
  command = plan

  variables {
    name = "Alpha-Dev-Search"
  }

  expect_failures = [var.name]
}

run "name_too_short" {
  command = plan

  variables {
    name = "ab"
  }

  expect_failures = [var.name]
}

run "name_longer_than_28" {
  command = plan

  variables {
    name = "alpha-dev-search-with-a-very-long-name"
  }

  expect_failures = [var.name]
}

run "engine_version_without_prefix" {
  command = plan

  variables {
    engine_version = "2.19"
  }

  expect_failures = [var.engine_version]
}

run "engine_version_elasticsearch" {
  command = plan

  variables {
    engine_version = "Elasticsearch_7.10"
  }

  expect_failures = [var.engine_version]
}

run "kms_key_alias" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:alias/alpha"
  }

  expect_failures = [var.kms_key_arn]
}

# ---- secret and principals -----------------------------------------------------------------------------------

run "secret_arn_is_a_kms_key" {
  command = plan

  variables {
    master_user_secret_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
  }

  expect_failures = [var.master_user_secret_arn]
}

run "secret_arn_is_a_bare_name" {
  command = plan

  variables {
    master_user_secret_arn = "alpha-dev-opensearch-master"
  }

  expect_failures = [var.master_user_secret_arn]
}

run "principal_is_wildcard" {
  command = plan

  variables {
    access_principal_arns = ["*"]
  }

  expect_failures = [var.access_principal_arns]
}

run "principal_arn_contains_wildcard" {
  command = plan

  variables {
    access_principal_arns = ["arn:aws:iam::111111111111:role/*"]
  }

  expect_failures = [var.access_principal_arns]
}

run "principal_is_not_an_iam_arn" {
  command = plan

  variables {
    access_principal_arns = ["arn:aws:s3:::some-bucket"]
  }

  expect_failures = [var.access_principal_arns]
}

# ---- logs and tuning -----------------------------------------------------------------------------------------

run "unknown_log_type" {
  command = plan

  variables {
    log_types = ["ES_APPLICATION_LOGS", "EVERYTHING"]
  }

  expect_failures = [var.log_types]
}

run "retention_not_a_cloudwatch_value" {
  command = plan

  variables {
    log_retention_days = 45
  }

  expect_failures = [var.log_retention_days]
}

run "off_peak_hour_24" {
  command = plan

  variables {
    off_peak_window_start = 24
  }

  expect_failures = [var.off_peak_window_start]
}

run "snapshot_hour_24" {
  command = plan

  variables {
    automated_snapshot_start_hour = 24
  }

  expect_failures = [var.automated_snapshot_start_hour]
}
