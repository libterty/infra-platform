mock_provider "aws" {}
mock_provider "awscc" {}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
}

run "reads_no_ssm_keys" {
  command = plan

  assert {
    condition     = alltrue([for f in fileset(path.module, "*.tf") : !strcontains(file("${path.module}/${f}"), "ssm-read")])
    error_message = "sitewise needs nothing from earlier stacks"
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

run "awscc_module_receives_the_common_tags" {
  command = plan

  assert {
    condition     = local.awscc_tags == { Project = "example", Environment = "dev", Managed = "terraform", Stack = "sitewise" } && length(regexall("(?m)^\\s*tags\\s*=\\s*local\\.awscc_tags\\s*$", file("${path.module}/sitewise.tf"))) == 1
    error_message = "awscc has no default_tags, so the iotsitewise call gets the common tags plus Stack = sitewise (design K3)"
  }
}

# Design section 7.5 and K14: cameras = {} and no gateways create nothing.
run "defaults_create_nothing" {
  command = plan

  assert {
    condition     = length(var.cameras) == 0 && length(var.gateways) == 0 && length(module.sitewise) == 0 && length(regexall("(?s)variable \"cameras\" \\{.*?default  = \\{\\}", file("${path.module}/variables.tf"))) == 1
    error_message = "cameras and gateways default to empty, and then the iotsitewise module must not be called"
  }

  assert {
    condition     = local.published_strings == { edge_connector_asset_ids = "{}" }
    error_message = "With no cameras, edge_connector_asset_ids must be {} (design section 7.2)"
  }

  assert {
    condition     = module.ssm_publish.names == { edge_connector_asset_ids = "/example/dev/sitewise/edge_connector_asset_ids" }
    error_message = "ssm-publish must write the one contract key under the sitewise stack path"
  }
}

run "cameras_build_a_hub_per_core_device_and_a_model_per_camera" {
  command = plan

  variables {
    cameras = {
      gate  = { core_thing_name = "example-dev-core-001", rtsp_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:cam-gate-AbCdEf", retention_hours = 24 }
      dock  = { core_thing_name = "example-dev-core-001", rtsp_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:cam-dock-AbCdEf", retention_hours = 48 }
      store = { core_thing_name = "example-dev-core-002", rtsp_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:cam-store-AbCdEf", retention_hours = 24 }
    }
  }

  assert {
    condition     = length(module.sitewise) == 1
    error_message = "Cameras must call the iotsitewise module"
  }

  assert {
    condition = toset(keys(local.asset_models)) == toset([
      "example-dev-hub-example-dev-core-001", "example-dev-hub-example-dev-core-002",
      "example-dev-cam-gate", "example-dev-cam-dock", "example-dev-cam-store",
    ])
    error_message = "One hub model per core device and one camera model per camera (attribute values live in model defaults)"
  }

  assert {
    condition = local.asset_models["example-dev-hub-example-dev-core-001"].hierarchies == {
      "ConnectedCameras-dock" = "example-dev-cam-dock"
      "ConnectedCameras-gate" = "example-dev-cam-gate"
    } && local.asset_models["example-dev-hub-example-dev-core-001"].properties["HubName"] == { data_type = "STRING", type = "attribute", default_value = "example-dev-core-001" }
    error_message = "A hub model names its core device and has a ConnectedCameras hierarchy to each of its camera models"
  }

  assert {
    condition = local.assets["example-dev-cam-dock"] == {
      model  = "example-dev-cam-dock"
      parent = { asset = "example-dev-hub-example-dev-core-001", hierarchy = "ConnectedCameras-dock" }
    } && local.assets["example-dev-hub-example-dev-core-002"] == { model = "example-dev-hub-example-dev-core-002", parent = null }
    error_message = "Camera assets sit under the hub asset of their core device"
  }
}

run "camera_model_carries_the_edge_connector_attributes" {
  command = plan

  variables {
    cameras = {
      gate = { core_thing_name = "example-dev-core-001", rtsp_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:cam-gate-AbCdEf", retention_hours = 24 }
    }
  }

  assert {
    condition = {
      for k, p in local.asset_models["example-dev-cam-gate"].properties : k => p if p.type == "attribute"
      } == {
      KinesisVideoStreamName            = { data_type = "STRING", type = "attribute", default_value = "example-dev-cam-gate" }
      RTSPStreamSecretARN               = { data_type = "STRING", type = "attribute", default_value = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:cam-gate-AbCdEf" }
      LocalDataRetentionPeriodInMinutes = { data_type = "INTEGER", type = "attribute", default_value = "60" }
      LiveStreamingStartTime            = { data_type = "STRING", type = "attribute", default_value = "-" }
      LiveStreamingDurationInMinutes    = { data_type = "INTEGER", type = "attribute", default_value = "0" }
      CaptureStartTime                  = { data_type = "STRING", type = "attribute", default_value = "-" }
      CaptureDurationInMinutes          = { data_type = "INTEGER", type = "attribute", default_value = "0" }
    }
    error_message = "The camera model must carry the KVS edge connector attributes; the stream name is <name_prefix>-cam-<id>, the KVS name of the edge stack"
  }

  assert {
    condition = {
      for k, p in local.asset_models["example-dev-cam-gate"].properties : k => p.data_type if p.type == "measurement"
      } == {
      VideoUploadRequest      = "STRING"
      VideoUploadedTimeRange  = "DOUBLE"
      VideoRecordedTimeRange  = "DOUBLE"
      CachedVideoAgeOutOnEdge = "DOUBLE"
    }
    error_message = "The camera model must have the four edge connector measurements"
  }
}

run "publishes_camera_and_hub_asset_ids" {
  command = plan

  variables {
    cameras = {
      gate = { core_thing_name = "example-dev-core-001", rtsp_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:cam-gate-AbCdEf", retention_hours = 24 }
    }
  }

  override_module {
    target = module.sitewise
    outputs = {
      asset_model_ids = {}
      asset_ids       = { "example-dev-cam-gate" = "a1111111-0000-0000-0000-000000000001", "example-dev-hub-example-dev-core-001" = "a2222222-0000-0000-0000-000000000002" }
      gateway_ids     = {}
    }
  }

  assert {
    condition = jsondecode(local.published_strings["edge_connector_asset_ids"]) == {
      cameras = { gate = "a1111111-0000-0000-0000-000000000001" }
      hubs    = { "example-dev-core-001" = "a2222222-0000-0000-0000-000000000002" }
    }
    error_message = "edge_connector_asset_ids maps camera ids and core device thing names to their asset ids (SiteWiseAssetIdForHub)"
  }
}

run "gateways_are_prefixed" {
  command = plan

  variables {
    gateways = { line1 = { core_device_thing_name = "example-dev-core-001" } }
  }

  assert {
    condition     = length(module.sitewise) == 1 && local.gateways == { "example-dev-line1" = { core_device_thing_name = "example-dev-core-001" } }
    error_message = "A gateway alone calls the module, named <name_prefix>-<key>"
  }
}

run "camera_on_a_foreign_core_device_rejected" {
  command = plan

  variables {
    cameras = { gate = { core_thing_name = "other-core-001", rtsp_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:cam-gate-AbCdEf", retention_hours = 24 } }
  }

  expect_failures = [var.cameras]
}

run "camera_secret_must_be_a_secret_arn" {
  command = plan

  variables {
    cameras = { gate = { core_thing_name = "example-dev-core-001", rtsp_secret_arn = "rtsp://user:pass@10.0.0.1/stream", retention_hours = 24 } }
  }

  expect_failures = [var.cameras]
}

run "camera_id_format_rejected" {
  command = plan

  variables {
    cameras = { "Gate_1" = { core_thing_name = "example-dev-core-001", rtsp_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:cam-gate-AbCdEf", retention_hours = 24 } }
  }

  expect_failures = [var.cameras]
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
