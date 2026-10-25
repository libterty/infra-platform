# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
mock_provider "aws" {}
mock_provider "awscc" {}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/greengrass_artifacts_bucket_name"]
  values = { insecure_value = "example-dev-greengrass-artifacts-111111111111" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["fleet/thing_group_fleet_arn"]
  values = { insecure_value = "arn:aws:iot:ap-northeast-1:111111111111:thinggroup/example-dev-fleet" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["fleet/thing_group_core_arn"]
  values = { insecure_value = "arn:aws:iot:ap-northeast-1:111111111111:thinggroup/example-dev-core" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["sitewise/edge_connector_asset_ids"]
  values = { insecure_value = "{}" }
}

run "tfvars_env_and_account_correspond" {
  command = plan

  assert {
    condition     = contains(["dev", "sit"], var.env)
    error_message = "env must be dev or sit; these are the only environments"
  }

  assert {
    condition     = var.expected_account_id == (var.env == "dev" ? "111111111111" : "222222222222")
    error_message = "dev must point at the placeholder account 111111111111 and sit at 222222222222"
  }
}

# Design section 7.5: dev rolls out 10 per minute aborting at 10 %, sit 20 per minute aborting at 5 %.
run "tfvars_rollout_matches_the_env" {
  command = plan

  assert {
    condition     = alltrue([for d in values(var.deployments) : d.rollout.maximum_per_minute == (var.env == "dev" ? 10 : 20) && d.abort.threshold_percentage == (var.env == "dev" ? 10 : 5)])
    error_message = "dev must roll out 10 per minute aborting at 10 %, sit 20 per minute aborting at 5 %"
  }
}

run "tfvars_pin_the_nucleus_and_deploy_the_example" {
  command = plan

  assert {
    condition     = alltrue([for d in values(var.deployments) : contains(keys(d.components), "aws.greengrass.Nucleus") && contains(keys(d.components), "aws.greengrass.StreamManager")])
    error_message = "Every deployment pins aws.greengrass.Nucleus and runs aws.greengrass.StreamManager (design K12)"
  }

  assert {
    condition     = var.deployments["core"].components["com.example.Inference"] == "1.0.0" && var.deployments["core"].thing_group == "core"
    error_message = "The core group runs the example component"
  }

  assert {
    condition     = alltrue([for d in values(var.deployments) : d.components["aws.greengrass.Nucleus"] == var.camera_deployment.nucleus_version])
    error_message = "Thing-level camera deployments must pin the same nucleus as the group deployments"
  }
}

# Design section 7.5: no cameras.
run "tfvars_create_no_camera_resources" {
  command = plan

  assert {
    condition     = length(var.cameras) == 0 && length(module.kvs) == 0 && length(module.camera_deployment) == 0
    error_message = "dev and sit tfvars must not create KVS streams or camera deployments"
  }
}
