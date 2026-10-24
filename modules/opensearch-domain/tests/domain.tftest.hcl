# Plan-level behaviour of the domain. No AWS call is made: the provider is mocked and the master secret is a fake.

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

# ---- hot only -------------------------------------------------------------------------------------------------

run "hot_only" {
  command = plan

  assert {
    condition = (
      aws_opensearch_domain.this.domain_name == "alpha-dev-search" &&
      aws_opensearch_domain.this.engine_version == "OpenSearch_2.19" &&
      aws_opensearch_domain.this.cluster_config[0].instance_type == "m7g.large.search" &&
      aws_opensearch_domain.this.cluster_config[0].instance_count == 2
    )
    error_message = "hot tier must carry the given engine version, instance type and count"
  }

  assert {
    condition = (
      aws_opensearch_domain.this.cluster_config[0].dedicated_master_enabled == false &&
      aws_opensearch_domain.this.cluster_config[0].warm_enabled == false &&
      aws_opensearch_domain.this.cluster_config[0].cold_storage_options[0].enabled == false
    )
    error_message = "without dedicated_master, warm and cold_storage none of them may be enabled"
  }

  assert {
    condition = (
      aws_opensearch_domain.this.cluster_config[0].zone_awareness_enabled == true &&
      aws_opensearch_domain.this.cluster_config[0].zone_awareness_config[0].availability_zone_count == 2 &&
      aws_opensearch_domain.this.cluster_config[0].multi_az_with_standby_enabled == false
    )
    error_message = "defaults must be 2 AZs, zone awareness on, standby off"
  }

  assert {
    condition = (
      aws_opensearch_domain.this.ebs_options[0].ebs_enabled == true &&
      aws_opensearch_domain.this.ebs_options[0].volume_type == "gp3" &&
      aws_opensearch_domain.this.ebs_options[0].volume_size == 20
    )
    error_message = "EBS must default to gp3 with the given size"
  }
}

run "hot_only_accepts_t3_data_nodes" {
  command = plan

  variables {
    hot = {
      instance_type  = "t3.medium.search"
      instance_count = 2
      ebs            = { volume_size = 20 }
    }
  }

  assert {
    condition     = aws_opensearch_domain.this.cluster_config[0].instance_type == "t3.medium.search"
    error_message = "T3 data nodes are fine as long as warm is not enabled"
  }
}

run "ebs_throughput_and_iops_pass_through" {
  command = plan

  variables {
    hot = {
      instance_type  = "m7g.large.search"
      instance_count = 2
      ebs            = { volume_size = 100, iops = 4000, throughput = 250 }
    }
  }

  assert {
    condition = (
      aws_opensearch_domain.this.ebs_options[0].iops == 4000 &&
      aws_opensearch_domain.this.ebs_options[0].throughput == 250
    )
    error_message = "iops and throughput must reach ebs_options"
  }
}

# ---- hot, UltraWarm and cold ----------------------------------------------------------------------------------

run "full_tiers" {
  command = plan

  variables {
    dedicated_master = { instance_type = "m7g.large.search", count = 3 }
    warm             = { instance_type = "ultrawarm1.medium.search", count = 2 }
    cold_storage     = true
  }

  assert {
    condition = (
      aws_opensearch_domain.this.cluster_config[0].dedicated_master_enabled == true &&
      aws_opensearch_domain.this.cluster_config[0].dedicated_master_type == "m7g.large.search" &&
      aws_opensearch_domain.this.cluster_config[0].dedicated_master_count == 3
    )
    error_message = "3 dedicated master nodes expected"
  }

  assert {
    condition = (
      aws_opensearch_domain.this.cluster_config[0].warm_enabled == true &&
      aws_opensearch_domain.this.cluster_config[0].warm_type == "ultrawarm1.medium.search" &&
      aws_opensearch_domain.this.cluster_config[0].warm_count == 2
    )
    error_message = "2 UltraWarm nodes expected"
  }

  assert {
    condition     = aws_opensearch_domain.this.cluster_config[0].cold_storage_options[0].enabled == true
    error_message = "cold storage must be enabled"
  }
}

run "five_master_nodes_are_accepted" {
  command = plan

  variables {
    dedicated_master = { instance_type = "m7g.large.search", count = 5 }
  }

  assert {
    condition     = aws_opensearch_domain.this.cluster_config[0].dedicated_master_count == 5
    error_message = "5 dedicated master nodes are valid"
  }
}

run "standby_with_three_az_and_warm_multiple" {
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
    warm             = { instance_type = "ultrawarm1.medium.search", count = 3 }
  }

  assert {
    condition = (
      aws_opensearch_domain.this.cluster_config[0].multi_az_with_standby_enabled == true &&
      aws_opensearch_domain.this.cluster_config[0].zone_awareness_config[0].availability_zone_count == 3 &&
      aws_opensearch_domain.this.cluster_config[0].warm_count == 3
    )
    error_message = "standby with 3 AZs and 3 warm nodes must plan"
  }
}

# ---- fixed security settings ----------------------------------------------------------------------------------

run "fixed_security_settings" {
  command = plan

  assert {
    condition = (
      aws_opensearch_domain.this.encrypt_at_rest[0].enabled == true &&
      aws_opensearch_domain.this.encrypt_at_rest[0].kms_key_id == var.kms_key_arn
    )
    error_message = "encryption at rest must be on and use the given CMK"
  }

  assert {
    condition     = aws_opensearch_domain.this.node_to_node_encryption[0].enabled == true
    error_message = "node-to-node encryption must be on"
  }

  assert {
    condition = (
      aws_opensearch_domain.this.domain_endpoint_options[0].enforce_https == true &&
      aws_opensearch_domain.this.domain_endpoint_options[0].tls_security_policy == "Policy-Min-TLS-1-2-PFS-2023-10"
    )
    error_message = "HTTPS must be enforced with TLS 1.2 PFS"
  }

  assert {
    condition = (
      aws_opensearch_domain.this.advanced_security_options[0].enabled == true &&
      aws_opensearch_domain.this.advanced_security_options[0].internal_user_database_enabled == true &&
      aws_opensearch_domain.this.advanced_security_options[0].anonymous_auth_enabled == false
    )
    error_message = "FGAC on, internal user database on, anonymous auth off"
  }
}

# ---- master user wired from the secret -----------------------------------------------------------------------

run "master_credentials_come_from_the_secret" {
  command = plan

  assert {
    condition     = data.aws_secretsmanager_secret_version.master.secret_id == var.master_user_secret_arn
    error_message = "the module must read the secret it was given"
  }

  assert {
    condition = (
      aws_opensearch_domain.this.advanced_security_options[0].master_user_options[0].master_user_name == "admin-placeholder" &&
      aws_opensearch_domain.this.advanced_security_options[0].master_user_options[0].master_user_password == "not-a-real-password-1A!"
    )
    error_message = "master user name and password must come from the secret JSON"
  }
}

run "secret_without_username_and_password_is_rejected" {
  command = plan

  override_data {
    target = data.aws_secretsmanager_secret_version.master
    values = {
      secret_string = "{\"user\":\"someone\"}"
    }
  }

  expect_failures = [aws_opensearch_domain.this]
}

# ---- logs ----------------------------------------------------------------------------------------------------

run "log_groups_use_the_cmk_and_retention" {
  command = plan

  variables {
    log_retention_days = 90
  }

  # The log group ARN is computed; override it so the domain's log_publishing_options is known at plan.
  override_resource {
    target          = aws_cloudwatch_log_group.this["ES_APPLICATION_LOGS"]
    override_during = plan
    values = {
      arn = "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/OpenSearchService/domains/alpha-dev-search/es-application-logs"
    }
  }

  override_resource {
    target          = aws_cloudwatch_log_group.this["AUDIT_LOGS"]
    override_during = plan
    values = {
      arn = "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/OpenSearchService/domains/alpha-dev-search/audit-logs"
    }
  }

  assert {
    condition     = toset(keys(aws_cloudwatch_log_group.this)) == toset(["ES_APPLICATION_LOGS", "AUDIT_LOGS"])
    error_message = "default log types are ES_APPLICATION_LOGS and AUDIT_LOGS"
  }

  assert {
    condition = alltrue([
      for g in aws_cloudwatch_log_group.this :
      g.kms_key_id == var.kms_key_arn && g.retention_in_days == 90
    ])
    error_message = "every log group must use the CMK and the given retention"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this["AUDIT_LOGS"].name == "/aws/OpenSearchService/domains/alpha-dev-search/audit-logs"
    error_message = "log group names must follow /aws/OpenSearchService/domains/<name>/<type>"
  }

  assert {
    condition     = length(aws_opensearch_domain.this.log_publishing_options) == 2
    error_message = "one log_publishing_options entry per log type"
  }

  assert {
    condition = toset([for o in aws_opensearch_domain.this.log_publishing_options : o.log_type]) == toset(["ES_APPLICATION_LOGS", "AUDIT_LOGS"]) && alltrue([
      for o in aws_opensearch_domain.this.log_publishing_options : o.enabled
    ])
    error_message = "log publishing must be enabled for both default log types"
  }
}

run "log_resource_policy_lets_only_opensearch_write" {
  command = plan

  variables {
    log_types = ["ES_APPLICATION_LOGS", "AUDIT_LOGS", "SEARCH_SLOW_LOGS"]
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.this) == 3
    error_message = "one log group per requested log type"
  }

  assert {
    condition = (
      jsondecode(aws_cloudwatch_log_resource_policy.this.policy_document).Statement[0].Principal.Service == "es.amazonaws.com" &&
      toset(jsondecode(aws_cloudwatch_log_resource_policy.this.policy_document).Statement[0].Action) == toset(["logs:CreateLogStream", "logs:PutLogEvents"])
    )
    error_message = "the resource policy must allow only es.amazonaws.com to create streams and put events"
  }

  assert {
    condition = (
      jsondecode(aws_cloudwatch_log_resource_policy.this.policy_document).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "111111111111" &&
      jsondecode(aws_cloudwatch_log_resource_policy.this.policy_document).Statement[0].Condition.ArnLike["aws:SourceArn"] == "arn:aws:es:ap-northeast-1:111111111111:domain/alpha-dev-search"
    )
    error_message = "the resource policy must be scoped to this account and this domain (confused deputy)"
  }

  assert {
    condition     = length(jsondecode(aws_cloudwatch_log_resource_policy.this.policy_document).Statement[0].Resource) == 3
    error_message = "the resource policy must list exactly the module's log groups"
  }
}

# ---- access policy -------------------------------------------------------------------------------------------

run "access_policy_only_lists_the_given_principals" {
  command = plan

  variables {
    access_principal_arns = [
      "arn:aws:iam::111111111111:role/alpha-dev-firehose",
      "arn:aws:iam::111111111111:role/alpha-dev-ops",
    ]
  }

  assert {
    condition = (
      length(jsondecode(aws_opensearch_domain.this.access_policies).Statement) == 1 &&
      jsondecode(aws_opensearch_domain.this.access_policies).Statement[0].Effect == "Allow" &&
      toset(jsondecode(aws_opensearch_domain.this.access_policies).Statement[0].Principal.AWS) == toset(var.access_principal_arns)
    )
    error_message = "the access policy must allow exactly the given IAM principals"
  }

  assert {
    condition = (
      jsondecode(aws_opensearch_domain.this.access_policies).Statement[0].Resource == "arn:aws:es:ap-northeast-1:111111111111:domain/alpha-dev-search/*" &&
      jsondecode(aws_opensearch_domain.this.access_policies).Statement[0].Action == "es:ESHttp*"
    )
    error_message = "the access policy must be scoped to this domain's data plane"
  }
}

# ---- network -------------------------------------------------------------------------------------------------

run "vpc_options" {
  command = plan

  assert {
    condition = (
      toset(aws_opensearch_domain.this.vpc_options[0].subnet_ids) == toset(var.subnet_ids) &&
      toset(aws_opensearch_domain.this.vpc_options[0].security_group_ids) == toset(var.security_group_ids)
    )
    error_message = "the domain must live in the given subnets and security groups"
  }
}

# ---- optional tuning -----------------------------------------------------------------------------------------

run "tuning_is_off_by_default" {
  command = plan

  assert {
    condition = (
      aws_opensearch_domain.this.auto_tune_options[0].desired_state == "DISABLED" &&
      length(aws_opensearch_domain.this.off_peak_window_options) == 0 &&
      length(aws_opensearch_domain.this.snapshot_options) == 0
    )
    error_message = "Auto-Tune, off-peak window and snapshot hour must be off unless asked for"
  }
}

run "tuning_when_asked_for" {
  command = plan

  variables {
    auto_tune                     = true
    off_peak_window_start         = 18
    automated_snapshot_start_hour = 3
  }

  assert {
    condition = (
      aws_opensearch_domain.this.auto_tune_options[0].desired_state == "ENABLED" &&
      aws_opensearch_domain.this.auto_tune_options[0].use_off_peak_window == true &&
      aws_opensearch_domain.this.off_peak_window_options[0].enabled == true &&
      aws_opensearch_domain.this.off_peak_window_options[0].off_peak_window[0].window_start_time[0].hours == 18 &&
      aws_opensearch_domain.this.snapshot_options[0].automated_snapshot_start_hour == 3
    )
    error_message = "tuning inputs must reach the domain"
  }
}

# ---- tags and outputs ----------------------------------------------------------------------------------------

run "tags_get_a_name" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_opensearch_domain.this.tags["Project"] == "alpha" && aws_opensearch_domain.this.tags["Name"] == "alpha-dev-search"
    error_message = "tags must be merged with Name"
  }
}

run "outputs" {
  command = plan

  override_resource {
    target          = aws_opensearch_domain.this
    override_during = plan
    values = {
      arn                = "arn:aws:es:ap-northeast-1:111111111111:domain/alpha-dev-search"
      endpoint           = "vpc-alpha-dev-search-abc.ap-northeast-1.es.amazonaws.com"
      dashboard_endpoint = "vpc-alpha-dev-search-abc.ap-northeast-1.es.amazonaws.com/_dashboards"
    }
  }

  override_resource {
    target          = aws_cloudwatch_log_group.this["AUDIT_LOGS"]
    override_during = plan
    values = {
      arn = "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/OpenSearchService/domains/alpha-dev-search/audit-logs"
    }
  }

  override_resource {
    target          = aws_cloudwatch_log_group.this["ES_APPLICATION_LOGS"]
    override_during = plan
    values = {
      arn = "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/OpenSearchService/domains/alpha-dev-search/es-application-logs"
    }
  }

  assert {
    condition = (
      output.domain_arn == "arn:aws:es:ap-northeast-1:111111111111:domain/alpha-dev-search" &&
      output.domain_name == "alpha-dev-search" &&
      output.endpoint == "vpc-alpha-dev-search-abc.ap-northeast-1.es.amazonaws.com" &&
      output.dashboard_endpoint == "vpc-alpha-dev-search-abc.ap-northeast-1.es.amazonaws.com/_dashboards"
    )
    error_message = "domain outputs must be exposed"
  }

  assert {
    condition     = length(output.log_group_arns) == 2 && output.log_group_arns["AUDIT_LOGS"] == "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/OpenSearchService/domains/alpha-dev-search/audit-logs"
    error_message = "log_group_arns must be keyed by log type"
  }
}
