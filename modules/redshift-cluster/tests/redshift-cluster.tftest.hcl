mock_provider "aws" {}

override_resource {
  target          = aws_redshift_cluster.this
  override_during = plan
  values = {
    arn                        = "arn:aws:redshift:ap-northeast-1:111111111111:cluster:alpha-dev-wh"
    dns_name                   = "alpha-dev-wh.abcdefghijkl.ap-northeast-1.redshift.amazonaws.com"
    master_password_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:redshift!alpha-dev-wh-dbadmin-AbCdEf"
  }
}

variables {
  name               = "alpha-dev-wh"
  database_name      = "analytics"
  node_type          = "ra3.large"
  number_of_nodes    = 1
  kms_key_arn        = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
  subnet_ids         = ["subnet-0a1b2c3d", "subnet-1a2b3c4d"]
  security_group_ids = ["sg-0a1b2c3d4e5f60718"]
}

# ---- positive -------------------------------------------------------------------------------------------------

run "single_node_ra3_large" {
  command = plan

  assert {
    condition     = aws_redshift_cluster.this.node_type == "ra3.large" && aws_redshift_cluster.this.cluster_type == "single-node" && aws_redshift_cluster.this.number_of_nodes == 1
    error_message = "One ra3.large node must be a single-node cluster"
  }

  assert {
    condition     = aws_redshift_cluster.this.cluster_identifier == "alpha-dev-wh" && aws_redshift_cluster.this.database_name == "analytics" && aws_redshift_cluster.this.master_username == "dbadmin"
    error_message = "Identifier, database and master username must be passed through"
  }
}

run "single_node_ra3_xlplus" {
  command = plan

  variables {
    node_type = "ra3.xlplus"
  }

  assert {
    condition     = aws_redshift_cluster.this.cluster_type == "single-node"
    error_message = "ra3.xlplus allows a single node"
  }
}

run "multi_node" {
  command = plan

  variables {
    node_type       = "ra3.xlplus"
    number_of_nodes = 3
  }

  assert {
    condition     = aws_redshift_cluster.this.cluster_type == "multi-node" && aws_redshift_cluster.this.number_of_nodes == 3
    error_message = "More than one node must be a multi-node cluster"
  }
}

run "multi_node_ra3_4xlarge" {
  command = plan

  variables {
    node_type       = "ra3.4xlarge"
    number_of_nodes = 2
  }

  assert {
    condition     = aws_redshift_cluster.this.node_type == "ra3.4xlarge"
    error_message = "ra3.4xlarge with two nodes must be accepted"
  }
}

run "audit_logs_go_to_cloudwatch" {
  command = plan

  assert {
    condition     = aws_redshift_logging.this.log_destination_type == "cloudwatch"
    error_message = "Audit logs must go to CloudWatch Logs"
  }

  assert {
    condition     = aws_redshift_logging.this.log_exports == toset(["connectionlog", "userlog", "useractivitylog"])
    error_message = "All three log types must be exported"
  }

  assert {
    condition     = aws_redshift_logging.this.bucket_name == null
    error_message = "No S3 bucket may be used for logs"
  }
}

run "parameter_group_requires_ssl" {
  command = plan

  assert {
    condition     = contains([for p in aws_redshift_parameter_group.this.parameter : "${p.name}=${p.value}"], "require_ssl=true")
    error_message = "The parameter group must set require_ssl = true"
  }

  assert {
    condition     = contains([for p in aws_redshift_parameter_group.this.parameter : "${p.name}=${p.value}"], "enable_user_activity_logging=true")
    error_message = "The parameter group must enable user activity logging"
  }

  assert {
    condition     = aws_redshift_cluster.this.cluster_parameter_group_name == aws_redshift_parameter_group.this.name
    error_message = "The cluster must use the parameter group"
  }
}

run "extra_parameters_are_added" {
  command = plan

  variables {
    parameters = { datestyle = "ISO, MDY" }
  }

  assert {
    condition     = contains([for p in aws_redshift_parameter_group.this.parameter : "${p.name}=${p.value}"], "datestyle=ISO, MDY") && contains([for p in aws_redshift_parameter_group.this.parameter : "${p.name}=${p.value}"], "require_ssl=true")
    error_message = "User parameters must be added next to require_ssl"
  }
}

run "cluster_is_encrypted_with_the_given_key" {
  command = plan

  assert {
    condition     = aws_redshift_cluster.this.encrypted == "true" && aws_redshift_cluster.this.kms_key_id == var.kms_key_arn
    error_message = "The cluster must be encrypted with the given KMS key"
  }
}

run "final_snapshot_is_taken_by_default" {
  command = plan

  assert {
    condition     = aws_redshift_cluster.this.skip_final_snapshot == false && aws_redshift_cluster.this.final_snapshot_identifier == "alpha-dev-wh-final"
    error_message = "A final snapshot named <name>-final must be taken by default"
  }
}

run "final_snapshot_can_be_skipped" {
  command = plan

  variables {
    skip_final_snapshot = true
  }

  assert {
    condition     = aws_redshift_cluster.this.skip_final_snapshot == true && aws_redshift_cluster.this.final_snapshot_identifier == null
    error_message = "Skipping must drop the final snapshot identifier"
  }
}

run "admin_password_is_managed_with_the_given_kms_key" {
  command = plan

  assert {
    condition     = aws_redshift_cluster.this.manage_master_password == true && aws_redshift_cluster.this.master_password_secret_kms_key_id == var.kms_key_arn
    error_message = "The master password must be managed, with the secret under the given KMS key"
  }

  assert {
    condition     = aws_redshift_cluster.this.master_password == null && aws_redshift_cluster.this.master_password_wo == null
    error_message = "No password may be passed to the cluster"
  }
}

run "cluster_is_never_public" {
  command = plan

  assert {
    condition     = aws_redshift_cluster.this.publicly_accessible == false
    error_message = "publicly_accessible must be false"
  }
}

run "enhanced_vpc_routing_is_on_by_default" {
  command = plan

  assert {
    condition     = aws_redshift_cluster.this.enhanced_vpc_routing == true
    error_message = "enhanced_vpc_routing must default to true"
  }
}

run "network_and_subnet_group" {
  command = plan

  assert {
    condition     = aws_redshift_subnet_group.this.name == "alpha-dev-wh" && length(aws_redshift_subnet_group.this.subnet_ids) == 2
    error_message = "The subnet group must hold the given subnets"
  }

  assert {
    condition     = aws_redshift_cluster.this.cluster_subnet_group_name == aws_redshift_subnet_group.this.name && length(aws_redshift_cluster.this.vpc_security_group_ids) == 1
    error_message = "The cluster must use the subnet group and the given security group"
  }
}

run "retention_defaults_to_seven_days" {
  command = plan

  assert {
    condition     = aws_redshift_cluster.this.automated_snapshot_retention_period == 7
    error_message = "automated snapshots must be kept 7 days by default"
  }
}

run "retention_accepts_the_bounds" {
  command = plan

  variables {
    automated_snapshot_retention_days = 35
  }

  assert {
    condition     = aws_redshift_cluster.this.automated_snapshot_retention_period == 35
    error_message = "35 days must be accepted"
  }
}

run "iam_roles_and_multi_az" {
  command = plan

  variables {
    node_type            = "ra3.xlplus"
    number_of_nodes      = 2
    multi_az             = true
    iam_role_arns        = ["arn:aws:iam::111111111111:role/alpha-dev-redshift"]
    default_iam_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-redshift"
  }

  assert {
    condition     = aws_redshift_cluster.this.multi_az == true && aws_redshift_cluster.this.default_iam_role_arn == "arn:aws:iam::111111111111:role/alpha-dev-redshift" && length(aws_redshift_cluster.this.iam_roles) == 1
    error_message = "multi_az and the IAM roles must be passed through"
  }
}

run "outputs_are_published" {
  command = plan

  assert {
    condition     = output.endpoint_address == "alpha-dev-wh.abcdefghijkl.ap-northeast-1.redshift.amazonaws.com" && output.port == 5439
    error_message = "endpoint_address and port must be published"
  }

  assert {
    condition     = output.database_name == "analytics" && output.cluster_identifier == "alpha-dev-wh"
    error_message = "database_name and cluster_identifier must be published"
  }

  assert {
    condition     = output.admin_secret_arn == "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:redshift!alpha-dev-wh-dbadmin-AbCdEf" && output.arn == "arn:aws:redshift:ap-northeast-1:111111111111:cluster:alpha-dev-wh"
    error_message = "admin_secret_arn and arn must be published"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "dc2_rejected" {
  command = plan

  variables {
    node_type = "dc2.large"
  }

  expect_failures = [var.node_type]
}

run "non_existing_ra3_size_rejected" {
  command = plan

  variables {
    node_type = "ra3.bogus"
  }

  expect_failures = [var.node_type]
}

run "single_node_ra3_4xlarge_rejected" {
  command = plan

  variables {
    node_type       = "ra3.4xlarge"
    number_of_nodes = 1
  }

  expect_failures = [var.number_of_nodes]
}

run "single_node_ra3_16xlarge_rejected" {
  command = plan

  variables {
    node_type       = "ra3.16xlarge"
    number_of_nodes = 1
  }

  expect_failures = [var.number_of_nodes]
}

run "zero_nodes_rejected" {
  command = plan

  variables {
    number_of_nodes = 0
  }

  expect_failures = [var.number_of_nodes]
}

run "too_many_nodes_rejected" {
  command = plan

  variables {
    number_of_nodes = 129
  }

  expect_failures = [var.number_of_nodes]
}

run "retention_above_35_rejected" {
  command = plan

  variables {
    automated_snapshot_retention_days = 36
  }

  expect_failures = [var.automated_snapshot_retention_days]
}

run "retention_negative_rejected" {
  command = plan

  variables {
    automated_snapshot_retention_days = -1
  }

  expect_failures = [var.automated_snapshot_retention_days]
}

run "one_subnet_rejected" {
  command = plan

  variables {
    subnet_ids = ["subnet-0a1b2c3d"]
  }

  expect_failures = [var.subnet_ids]
}

run "duplicate_subnets_do_not_count_twice" {
  command = plan

  variables {
    subnet_ids = ["subnet-0a1b2c3d", "subnet-0a1b2c3d"]
  }

  expect_failures = [var.subnet_ids]
}

run "malformed_subnet_rejected" {
  command = plan

  variables {
    subnet_ids = ["subnet-0a1b2c3d", "nope"]
  }

  expect_failures = [var.subnet_ids]
}

run "malformed_security_group_rejected" {
  command = plan

  variables {
    security_group_ids = ["sg-nope"]
  }

  expect_failures = [var.security_group_ids]
}

run "alias_kms_key_rejected" {
  command = plan

  variables {
    kms_key_arn = "alias/alpha"
  }

  expect_failures = [var.kms_key_arn]
}

run "invalid_name_rejected" {
  command = plan

  variables {
    name = "Alpha_WH"
  }

  expect_failures = [var.name]
}

run "name_with_double_hyphen_rejected" {
  command = plan

  variables {
    name = "alpha--wh"
  }

  expect_failures = [var.name]
}

run "invalid_database_name_rejected" {
  command = plan

  variables {
    database_name = "1-bad"
  }

  expect_failures = [var.database_name]
}

run "invalid_master_username_rejected" {
  command = plan

  variables {
    master_username = "Admin User"
  }

  expect_failures = [var.master_username]
}

run "overriding_require_ssl_rejected" {
  command = plan

  variables {
    parameters = { require_ssl = "false" }
  }

  expect_failures = [var.parameters]
}

run "overriding_user_activity_logging_rejected" {
  command = plan

  variables {
    parameters = { enable_user_activity_logging = "false" }
  }

  expect_failures = [var.parameters]
}

run "default_role_must_be_attached" {
  command = plan

  variables {
    iam_role_arns        = ["arn:aws:iam::111111111111:role/a"]
    default_iam_role_arn = "arn:aws:iam::111111111111:role/b"
  }

  expect_failures = [var.default_iam_role_arn]
}

run "malformed_role_arn_rejected" {
  command = plan

  variables {
    iam_role_arns = ["role/a"]
  }

  expect_failures = [var.iam_role_arns]
}
