mock_provider "aws" {}
mock_provider "awscc" {}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
  deployments = {
    core = {
      thing_group = "core"
      components = {
        "aws.greengrass.Nucleus"       = "2.14.3"
        "aws.greengrass.StreamManager" = "2.2.1"
        "com.example.Inference"        = "1.0.0"
      }
      rollout = { maximum_per_minute = 10 }
      abort   = { threshold_percentage = 10 }
    }
  }
  camera_deployment = { nucleus_version = "2.14.3", stream_manager_version = "2.2.1", edge_connector_version = "1.0.5" }
}

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

run "reads_only_earlier_stack_keys" {
  command = plan

  assert {
    condition = local.ssm_input_strings == {
      kms_key_arn                      = "foundation/kms_key_arn"
      greengrass_artifacts_bucket_name = "storage/greengrass_artifacts_bucket_name"
      thing_group_fleet_arn            = "fleet/thing_group_fleet_arn"
      thing_group_core_arn             = "fleet/thing_group_core_arn"
      edge_connector_asset_ids         = "sitewise/edge_connector_asset_ids"
    } && local.ssm_input_lists == {}
    error_message = "edge must read exactly the keys of earlier stacks it needs"
  }
}

run "awscc_provider_uses_the_aws_region_and_role" {
  command = plan

  assert {
    condition     = length(regexall("(?s)provider \"aws\" \\{\\s*region\\s*=\\s*var\\.aws_region\\b.*?for_each = var\\.deploy_role_arn != \"\" \\? \\[var\\.deploy_role_arn\\] : \\[\\]", file("${path.module}/providers.tf"))) == 1
    error_message = "provider aws must use var.aws_region and assume var.deploy_role_arn"
  }

  assert {
    condition     = length(regexall("provider \"awscc\" \\{\\s*region\\s*=\\s*var\\.aws_region\\s*assume_role\\s*=\\s*var\\.deploy_role_arn != \"\" \\? \\{ role_arn = var\\.deploy_role_arn \\} : null\\s*\\}", file("${path.module}/providers.tf"))) == 1
    error_message = "provider awscc must use the same var.aws_region and var.deploy_role_arn as provider aws (design K4)"
  }

  assert {
    condition     = length(regexall("provider \"", file("${path.module}/providers.tf"))) == 2 && length(regexall("allowed_account_ids\\s*=\\s*\\[var\\.expected_account_id\\]", file("${path.module}/providers.tf"))) == 1
    error_message = "There are exactly the aws and awscc providers, and the aws one keeps the account guard"
  }
}

run "awscc_modules_receive_the_common_tags" {
  command = plan

  assert {
    condition     = local.awscc_tags == { Project = "example", Environment = "dev", Managed = "terraform", Stack = "edge" } && length(regexall("(?m)^\\s*tags\\s*=\\s*local\\.awscc_tags\\s*$", file("${path.module}/components.tf"))) == 1 && length(regexall("(?m)^\\s*tags\\s*=\\s*local\\.awscc_tags\\s*$", file("${path.module}/deployments.tf"))) == 2
    error_message = "Every awscc module call gets the common tags plus Stack = edge (design K3)"
  }
}

# ---- components (design K10) ----

run "one_component_version_per_recipe_file" {
  command = plan

  assert {
    condition     = keys(local.recipes) == ["com.example.Inference/1.0.0"] && keys(module.component) == ["com.example.Inference/1.0.0"]
    error_message = "Each templates/example5/edge/components/<component>/<version>.json is one component version, keyed <component>/<version>"
  }

  assert {
    condition     = alltrue([for k, r in local.recipes : "${jsondecode(r).ComponentName}/${jsondecode(r).ComponentVersion}" == k])
    error_message = "A recipe's ComponentName and ComponentVersion must match its file path"
  }

  assert {
    condition     = jsondecode(local.recipes["com.example.Inference/1.0.0"]).Manifests[0].Artifacts[0].Uri == "s3://example-dev-greengrass-artifacts-111111111111/artifacts/com.example.Inference/1.0.0/inference.zip"
    error_message = "Artifacts must point at artifacts/<component>/<version>/ in the greengrass-artifacts bucket of storage"
  }
}

run "example_component_reads_telemetry_and_publishes_inference" {
  command = plan

  assert {
    condition     = jsondecode(local.recipes["com.example.Inference/1.0.0"]).ComponentConfiguration.DefaultConfiguration.accessControl["aws.greengrass.ipc.mqttproxy"]["com.example.Inference:mqttproxy:1"].resources == ["+/telemetry/+", "+/inference/{iot:thingName}"]
    error_message = "The example component may only subscribe to telemetry topics and publish its own inference topic"
  }
}

# ---- deployments (design K11, K12) ----

run "group_deployment_targets_the_fleet_group" {
  command = plan

  assert {
    condition     = local.group_deployments["core"].name == "example-dev-core" && local.group_deployments["core"].target_arn == "arn:aws:iot:ap-northeast-1:111111111111:thinggroup/example-dev-core"
    error_message = "A deployment is named <name_prefix>-<key> and targets the thing group published by fleet"
  }

  assert {
    condition = local.group_deployments["core"].components == {
      "aws.greengrass.Nucleus"       = { version = "2.14.3" }
      "aws.greengrass.StreamManager" = { version = "2.2.1" }
      "com.example.Inference"        = { version = "1.0.0", merge = { TopicPrefix = "example-dev" } }
    }
    error_message = "AWS components keep only the version; custom components get TopicPrefix = <name_prefix>"
  }

  assert {
    condition     = local.group_deployments["core"].rollout == { maximum_per_minute = 10 } && local.group_deployments["core"].abort == [{ failure_type = "FAILED", threshold_percentage = 10, min_number_of_executed_things = 10 }]
    error_message = "Rollout and abort come from tfvars (design section 7.5)"
  }
}

run "deployment_keeps_the_rollback_defaults" {
  command = plan

  assert {
    condition     = length(regexall("failure_handling", file("${path.module}/deployments.tf"))) == 0 && length(regexall("component_update", file("${path.module}/deployments.tf"))) == 0
    error_message = "Deployments keep the module defaults ROLLBACK and NOTIFY_COMPONENTS (design K11)"
  }
}

run "referencing_a_missing_component_version_fails" {
  command = plan

  variables {
    deployments = {
      core = {
        thing_group = "core"
        components  = { "aws.greengrass.Nucleus" = "2.14.3", "com.example.Inference" = "1.0.1" }
        rollout     = { maximum_per_minute = 10 }
        abort       = { threshold_percentage = 10 }
      }
    }
  }

  expect_failures = [output.deployment_names]
}

run "deployment_needs_a_pinned_nucleus" {
  command = plan

  variables {
    deployments = {
      core = {
        thing_group = "core"
        components  = { "com.example.Inference" = "1.0.0" }
        rollout     = { maximum_per_minute = 10 }
        abort       = { threshold_percentage = 10 }
      }
    }
  }

  expect_failures = [var.deployments]
}

run "deployment_thing_group_rejected" {
  command = plan

  variables {
    deployments = {
      core = {
        thing_group = "unverified"
        components  = { "aws.greengrass.Nucleus" = "2.14.3" }
        rollout     = { maximum_per_minute = 10 }
        abort       = { threshold_percentage = 10 }
      }
    }
  }

  expect_failures = [var.deployments]
}

# ---- cameras (design K14) ----

run "no_cameras_create_no_stream_and_no_thing_deployment" {
  command = plan

  assert {
    condition     = length(var.cameras) == 0 && length(module.kvs) == 0 && length(module.camera_deployment) == 0
    error_message = "cameras = {} must create no KVS stream and no thing-level deployment"
  }

  assert {
    condition     = local.published_strings == { kvs_stream_arns = "{}" }
    error_message = "With no cameras, kvs_stream_arns must be {}"
  }
}

run "cameras_create_streams_and_one_deployment_per_core_device" {
  command = plan

  variables {
    cameras = {
      gate  = { core_thing_name = "example-dev-core-001", rtsp_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:cam-gate-AbCdEf", retention_hours = 24 }
      store = { core_thing_name = "example-dev-core-002", rtsp_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:cam-store-AbCdEf", retention_hours = 48 }
    }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["sitewise/edge_connector_asset_ids"]
    values = { insecure_value = "{\"cameras\":{\"gate\":\"a1\",\"store\":\"a2\"},\"hubs\":{\"example-dev-core-001\":\"h1\",\"example-dev-core-002\":\"h2\"}}" }
  }

  assert {
    condition = local.kvs_streams == {
      "example-dev-cam-gate"  = { retention_hours = 24, device_name = "example-dev-core-001" }
      "example-dev-cam-store" = { retention_hours = 48, device_name = "example-dev-core-002" }
    } && length(module.kvs) == 1
    error_message = "Each camera gets a KVS stream <name_prefix>-cam-<id>, the name the iam-base TES policy allows"
  }

  assert {
    condition     = toset(keys(module.camera_deployment)) == toset(["example-dev-core-001", "example-dev-core-002"])
    error_message = "The edge connector cannot be deployed to groups: one thing-level deployment per core device"
  }

  assert {
    condition = local.camera_deployments["example-dev-core-001"].target_arn == "arn:aws:iot:ap-northeast-1:111111111111:thing/example-dev-core-001" && local.camera_deployments["example-dev-core-001"].components == {
      "aws.greengrass.Nucleus"       = { version = "2.14.3" }
      "aws.greengrass.StreamManager" = { version = "2.2.1" }
      "aws.iot.EdgeConnectorForKVS"  = { version = "1.0.5", merge = { SiteWiseAssetIdForHub = "h1" } }
    }
    error_message = "The thing deployment runs the edge connector with the hub asset published by sitewise"
  }
}

run "camera_missing_in_sitewise_fails" {
  command = plan

  variables {
    cameras = {
      gate  = { core_thing_name = "example-dev-core-001", rtsp_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:cam-gate-AbCdEf", retention_hours = 24 }
      store = { core_thing_name = "example-dev-core-002", rtsp_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:cam-store-AbCdEf", retention_hours = 48 }
    }
  }

  expect_failures = [output.kvs_stream_names]
}

run "publishes_exactly_the_edge_keys" {
  command = plan

  override_module {
    target  = module.deployment["core"]
    outputs = { deployment_id = "d-core" }
  }

  assert {
    condition     = local.published_lists == { deployment_ids = ["d-core"] } && local.published_strings == { kvs_stream_arns = "{}" }
    error_message = "edge publishes deployment_ids (StringList) and kvs_stream_arns (JSON) (design section 7.2)"
  }

  assert {
    condition     = module.ssm_publish.names == { deployment_ids = "/example/dev/edge/deployment_ids", kvs_stream_arns = "/example/dev/edge/kvs_stream_arns" }
    error_message = "ssm-publish must write the contract keys under the edge stack path"
  }
}

# ---- common.tf and providers.tf guards: the same runs in every stack ----

run "env_format_uppercase_rejected" {
  command = plan

  variables {
    env = "Dev"
  }

  expect_failures = [var.env]
}

run "env_format_too_short_rejected" {
  command = plan

  variables {
    env = "d"
  }

  expect_failures = [var.env]
}

run "env_format_valid_passes" {
  command = plan

  variables {
    env = "dev"
  }

  assert {
    condition     = local.name_prefix == "example-dev" && local.ssm_prefix == "/example/dev"
    error_message = "A valid env must give the name prefix and the SSM prefix"
  }
}

run "project_format_rejected" {
  command = plan

  variables {
    project = "Example"
  }

  expect_failures = [var.project]
}

run "account_must_match_env" {
  command = plan

  variables {
    env                 = "dev"
    expected_account_id = "222222222222"
  }

  expect_failures = [var.expected_account_id]
}

run "account_unknown_env_rejected" {
  command = plan

  variables {
    env                 = "staging"
    expected_account_id = "111111111111"
  }

  expect_failures = [var.expected_account_id]
}

run "account_matching_env_passes" {
  command = plan

  variables {
    env                 = "sit"
    expected_account_id = "222222222222"
  }

  assert {
    condition     = local.name_prefix == "example-sit" && contains(local.accounts_by_env["sit"], var.expected_account_id)
    error_message = "A sit account with env sit must pass"
  }
}

run "account_is_required" {
  command = plan

  variables {
    expected_account_id = null
  }

  expect_failures = [var.expected_account_id]
}

# A default would let a missing tfvars file point at some account silently.
run "account_has_no_default" {
  command = plan

  assert {
    condition     = length(regexall("(?s)variable \"expected_account_id\" \\{[^}]*\\n\\s*default\\s*=", file("${path.module}/common.tf"))) == 0
    error_message = "expected_account_id must not have a default value"
  }
}

run "deploy_role_in_other_account_rejected" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::222222222222:role/deploy"
  }

  expect_failures = [var.deploy_role_arn]
}

run "deploy_role_in_expected_account_passes" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::111111111111:role/deploy"
  }

  assert {
    condition     = var.deploy_role_arn == "arn:aws:iam::111111111111:role/deploy"
    error_message = "A role in the expected account must pass"
  }
}
