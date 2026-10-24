# Run by scripts/validate.sh with -var-file=envs/examples/provisioned.tfvars; it checks the example that switches to a cluster.
mock_provider "aws" {}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/sg_redshift_id"]
  values = { insecure_value = "sg-0aaaaaaa00000004" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_redshift_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-placeholder-redshift" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/subnet_ids_data"]
  values = { insecure_value = "subnet-0dda0001,subnet-0dda0002" }
}

run "example_builds_only_the_cluster" {
  command = plan

  assert {
    condition     = var.warehouse_mode == "provisioned" && length(module.provisioned) == 1 && length(module.serverless) == 0
    error_message = "The example must build one provisioned cluster and no serverless namespace"
  }

  assert {
    condition     = terraform_data.warehouse_mode_guard.triggers_replace == "provisioned"
    error_message = "The guard must be bound to warehouse_mode"
  }
}

# Design section 7.3 and 7.5: single-node ra3.large.
run "example_is_a_single_node_ra3_large" {
  command = plan

  assert {
    condition     = var.provisioned.node_type == "ra3.large" && var.provisioned.number_of_nodes == 1
    error_message = "The example must show a single-node ra3.large cluster"
  }
}
