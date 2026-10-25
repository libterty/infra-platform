mock_provider "awscc" {}

variables {
  asset_models = {
    alpha-dev-kvs-camera = {
      description = "Camera for the KVS edge connector"
      properties = {
        KinesisVideoStreamName            = { data_type = "STRING", type = "attribute", default_value = "alpha-dev-cam-01" }
        LocalDataRetentionPeriodInMinutes = { data_type = "INTEGER", type = "attribute", default_value = "60" }
        VideoUploadedTimeRange            = { data_type = "DOUBLE", type = "measurement" }
      }
    }
    alpha-dev-kvs-hub = {
      properties = {
        HubName = { data_type = "STRING", type = "attribute", default_value = "Hub Name" }
      }
      hierarchies = {
        ConnectedCameras = "alpha-dev-kvs-camera"
      }
    }
    alpha-dev-sensor = {
      properties = {
        temperature = { data_type = "DOUBLE", type = "measurement", unit = "Celsius" }
      }
    }
  }

  assets = {
    alpha-dev-hub-01 = { model = "alpha-dev-kvs-hub" }
    alpha-dev-cam-01 = {
      model  = "alpha-dev-kvs-camera"
      parent = { asset = "alpha-dev-hub-01", hierarchy = "ConnectedCameras" }
    }
    alpha-dev-sensor-01 = {
      model = "alpha-dev-sensor"
      properties = {
        temperature = { alias = "/alpha/dev/sensor-01/temperature", notification_state = "ENABLED" }
      }
    }
  }

  gateways = {
    alpha-dev-gateway-01 = { core_device_thing_name = "alpha-dev-core-01" }
  }

  tags = { Project = "alpha" }
}

# ---- positive -------------------------------------------------------------------------------------------------

run "asset_models_split_into_child_and_parent_tiers" {
  command = plan

  assert {
    condition     = keys(awscc_iotsitewise_asset_model.child) == ["alpha-dev-kvs-camera"]
    error_message = "A model used as a hierarchy child must be created in the child tier"
  }

  assert {
    condition     = toset(keys(awscc_iotsitewise_asset_model.this)) == toset(["alpha-dev-kvs-hub", "alpha-dev-sensor"])
    error_message = "Every other model must be created in the parent tier"
  }

  assert {
    condition     = awscc_iotsitewise_asset_model.this["alpha-dev-kvs-hub"].asset_model_name == "alpha-dev-kvs-hub" && awscc_iotsitewise_asset_model.child["alpha-dev-kvs-camera"].asset_model_description == "Camera for the KVS edge connector"
    error_message = "Name and description must be passed through"
  }
}

run "properties_map_to_attribute_and_measurement" {
  command = plan

  assert {
    condition = anytrue([for p in awscc_iotsitewise_asset_model.child["alpha-dev-kvs-camera"].asset_model_properties :
      p.name == "KinesisVideoStreamName" && p.logical_id == "KinesisVideoStreamName" && p.data_type == "STRING" && p.type.type_name == "Attribute" && p.type.attribute.default_value == "alpha-dev-cam-01"
    ])
    error_message = "An attribute property must carry its type name and default value"
  }

  assert {
    condition = anytrue([for p in awscc_iotsitewise_asset_model.this["alpha-dev-sensor"].asset_model_properties :
      p.name == "temperature" && p.data_type == "DOUBLE" && p.type.type_name == "Measurement" && p.unit == "Celsius"
    ])
    error_message = "A measurement property must carry its type name and unit"
  }

  assert {
    condition     = length(awscc_iotsitewise_asset_model.child["alpha-dev-kvs-camera"].asset_model_properties) == 3
    error_message = "Every property must be passed through"
  }
}

run "assets_split_into_child_and_parent_tiers" {
  command = plan

  assert {
    condition     = keys(awscc_iotsitewise_asset.child) == ["alpha-dev-cam-01"]
    error_message = "An asset with a parent must be created in the child tier"
  }

  assert {
    condition     = toset(keys(awscc_iotsitewise_asset.this)) == toset(["alpha-dev-hub-01", "alpha-dev-sensor-01"])
    error_message = "Assets without a parent must be created in the parent tier"
  }

  assert {
    condition = anytrue([for p in awscc_iotsitewise_asset.this["alpha-dev-sensor-01"].asset_properties :
      p.logical_id == "temperature" && p.alias == "/alpha/dev/sensor-01/temperature" && p.notification_state == "ENABLED"
    ])
    error_message = "Asset property alias and notification state must be passed through"
  }
}

run "gateway_runs_on_greengrass_v2" {
  command = plan

  assert {
    condition     = awscc_iotsitewise_gateway.this["alpha-dev-gateway-01"].gateway_name == "alpha-dev-gateway-01"
    error_message = "The map key must be the gateway name"
  }

  assert {
    condition     = awscc_iotsitewise_gateway.this["alpha-dev-gateway-01"].gateway_platform.greengrass_v2.core_device_thing_name == "alpha-dev-core-01"
    error_message = "The gateway must run on the given Greengrass v2 core device"
  }
}

run "tags_are_converted_to_key_value_lists" {
  command = plan

  assert {
    condition = awscc_iotsitewise_asset_model.this["alpha-dev-kvs-hub"].tags == tolist([
      { key = "Name", value = "alpha-dev-kvs-hub" },
      { key = "Project", value = "alpha" },
    ])
    error_message = "Asset model tags must be a list of key/value objects including Name"
  }

  assert {
    condition = awscc_iotsitewise_asset.child["alpha-dev-cam-01"].tags == tolist([
      { key = "Name", value = "alpha-dev-cam-01" },
      { key = "Project", value = "alpha" },
    ])
    error_message = "Asset tags must be a list of key/value objects including Name"
  }

  assert {
    condition = awscc_iotsitewise_gateway.this["alpha-dev-gateway-01"].tags == tolist([
      { key = "Name", value = "alpha-dev-gateway-01" },
      { key = "Project", value = "alpha" },
    ])
    error_message = "Gateway tags must be a list of key/value objects including Name"
  }
}

run "hierarchies_reference_the_created_children_after_apply" {
  assert {
    condition = one(awscc_iotsitewise_asset_model.this["alpha-dev-kvs-hub"].asset_model_hierarchies) == {
      name                 = "ConnectedCameras"
      logical_id           = "ConnectedCameras"
      child_asset_model_id = awscc_iotsitewise_asset_model.child["alpha-dev-kvs-camera"].asset_model_id
      external_id          = one(awscc_iotsitewise_asset_model.this["alpha-dev-kvs-hub"].asset_model_hierarchies).external_id
      id                   = one(awscc_iotsitewise_asset_model.this["alpha-dev-kvs-hub"].asset_model_hierarchies).id
    }
    error_message = "The model hierarchy must point at the child model"
  }

  assert {
    condition     = awscc_iotsitewise_asset.child["alpha-dev-cam-01"].asset_model_id == awscc_iotsitewise_asset_model.child["alpha-dev-kvs-camera"].asset_model_id
    error_message = "An asset must use the model created in the same call"
  }

  assert {
    condition = (
      one(awscc_iotsitewise_asset.this["alpha-dev-hub-01"].asset_hierarchies).logical_id == "ConnectedCameras" &&
      one(awscc_iotsitewise_asset.this["alpha-dev-hub-01"].asset_hierarchies).child_asset_id == awscc_iotsitewise_asset.child["alpha-dev-cam-01"].asset_id
    )
    error_message = "The parent asset must associate the child asset through the model hierarchy"
  }

  assert {
    condition = (
      output.asset_model_ids["alpha-dev-kvs-camera"] == awscc_iotsitewise_asset_model.child["alpha-dev-kvs-camera"].asset_model_id &&
      output.asset_model_ids["alpha-dev-kvs-hub"] == awscc_iotsitewise_asset_model.this["alpha-dev-kvs-hub"].asset_model_id &&
      length(output.asset_model_ids) == 3
    )
    error_message = "asset_model_ids must cover both tiers"
  }

  assert {
    condition = (
      output.asset_ids["alpha-dev-cam-01"] == awscc_iotsitewise_asset.child["alpha-dev-cam-01"].asset_id &&
      output.asset_ids["alpha-dev-hub-01"] == awscc_iotsitewise_asset.this["alpha-dev-hub-01"].asset_id &&
      length(output.asset_ids) == 3
    )
    error_message = "asset_ids must cover both tiers"
  }

  assert {
    condition     = output.gateway_ids["alpha-dev-gateway-01"] == awscc_iotsitewise_gateway.this["alpha-dev-gateway-01"].gateway_id
    error_message = "gateway_ids must map gateway names to IDs"
  }
}

run "empty_inputs_create_nothing" {
  command = plan

  variables {
    asset_models = {}
    assets       = {}
    gateways     = {}
  }

  assert {
    condition = (
      length(awscc_iotsitewise_asset_model.this) + length(awscc_iotsitewise_asset_model.child) +
      length(awscc_iotsitewise_asset.this) + length(awscc_iotsitewise_asset.child) + length(awscc_iotsitewise_gateway.this)
    ) == 0
    error_message = "Empty maps must create nothing"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "asset_model_not_in_call_rejected" {
  command = plan

  variables {
    assets = { alpha-dev-x = { model = "alpha-dev-missing" } }
  }

  expect_failures = [var.assets]
}

run "parent_asset_not_in_call_rejected" {
  command = plan

  variables {
    assets = {
      alpha-dev-cam-01 = { model = "alpha-dev-kvs-camera", parent = { asset = "alpha-dev-missing", hierarchy = "ConnectedCameras" } }
    }
  }

  expect_failures = [var.assets]
}

run "parent_hierarchy_not_in_parent_model_rejected" {
  command = plan

  variables {
    assets = {
      alpha-dev-hub-01 = { model = "alpha-dev-kvs-hub" }
      alpha-dev-cam-01 = { model = "alpha-dev-kvs-camera", parent = { asset = "alpha-dev-hub-01", hierarchy = "Cameras" } }
    }
  }

  expect_failures = [var.assets]
}

run "child_model_does_not_match_hierarchy_rejected" {
  command = plan

  variables {
    assets = {
      alpha-dev-hub-01    = { model = "alpha-dev-kvs-hub" }
      alpha-dev-sensor-01 = { model = "alpha-dev-sensor", parent = { asset = "alpha-dev-hub-01", hierarchy = "ConnectedCameras" } }
    }
  }

  expect_failures = [var.assets]
}

# A third level cannot match any hierarchy, because a child model never has hierarchies of its own.
run "asset_nesting_deeper_than_two_levels_rejected" {
  command = plan

  variables {
    assets = {
      alpha-dev-hub-01 = { model = "alpha-dev-kvs-hub", parent = { asset = "alpha-dev-hub-02", hierarchy = "ConnectedCameras" } }
      alpha-dev-hub-02 = { model = "alpha-dev-kvs-hub" }
      alpha-dev-cam-01 = { model = "alpha-dev-kvs-camera", parent = { asset = "alpha-dev-hub-01", hierarchy = "ConnectedCameras" } }
    }
  }

  expect_failures = [var.assets]
}

run "asset_property_not_in_model_rejected" {
  command = plan

  variables {
    assets = {
      alpha-dev-sensor-01 = { model = "alpha-dev-sensor", properties = { humidity = { alias = "/alpha/dev/sensor-01/humidity" } } }
    }
  }

  expect_failures = [var.assets]
}

run "asset_notification_state_rejected" {
  command = plan

  variables {
    assets = {
      alpha-dev-sensor-01 = { model = "alpha-dev-sensor", properties = { temperature = { notification_state = "ON" } } }
    }
  }

  expect_failures = [var.assets]
}

run "invalid_asset_name_rejected" {
  command = plan

  variables {
    assets = { "alpha dev/x" = { model = "alpha-dev-sensor" } }
  }

  expect_failures = [var.assets]
}

run "property_type_rejected" {
  command = plan

  variables {
    asset_models = {
      alpha-dev-sensor = { properties = { temperature = { data_type = "DOUBLE", type = "metric" } } }
    }
    assets = {}
  }

  expect_failures = [var.asset_models]
}

run "property_data_type_rejected" {
  command = plan

  variables {
    asset_models = {
      alpha-dev-sensor = { properties = { temperature = { data_type = "FLOAT", type = "measurement" } } }
    }
    assets = {}
  }

  expect_failures = [var.asset_models]
}

run "default_value_on_measurement_rejected" {
  command = plan

  variables {
    asset_models = {
      alpha-dev-sensor = { properties = { temperature = { data_type = "DOUBLE", type = "measurement", default_value = "0" } } }
    }
    assets = {}
  }

  expect_failures = [var.asset_models]
}

run "model_without_properties_or_hierarchies_rejected" {
  command = plan

  variables {
    asset_models = { alpha-dev-empty = {} }
    assets       = {}
  }

  expect_failures = [var.asset_models]
}

run "hierarchy_child_model_not_in_call_rejected" {
  command = plan

  variables {
    asset_models = {
      alpha-dev-kvs-hub = {
        properties  = { HubName = { data_type = "STRING", type = "attribute" } }
        hierarchies = { ConnectedCameras = "alpha-dev-missing" }
      }
    }
    assets = {}
  }

  expect_failures = [var.asset_models]
}

run "model_nesting_deeper_than_two_levels_rejected" {
  command = plan

  variables {
    asset_models = {
      alpha-dev-site = {
        properties  = { SiteName = { data_type = "STRING", type = "attribute" } }
        hierarchies = { Hubs = "alpha-dev-kvs-hub" }
      }
      alpha-dev-kvs-hub = {
        properties  = { HubName = { data_type = "STRING", type = "attribute" } }
        hierarchies = { ConnectedCameras = "alpha-dev-kvs-camera" }
      }
      alpha-dev-kvs-camera = {
        properties = { KinesisVideoStreamName = { data_type = "STRING", type = "attribute" } }
      }
    }
    assets = {}
  }

  expect_failures = [var.asset_models]
}

run "invalid_asset_model_name_rejected" {
  command = plan

  variables {
    asset_models = { "alpha dev/model" = { properties = { p = { data_type = "STRING", type = "attribute" } } } }
    assets       = {}
  }

  expect_failures = [var.asset_models]
}

run "invalid_thing_name_rejected" {
  command = plan

  variables {
    gateways = { alpha-dev-gateway-01 = { core_device_thing_name = "alpha dev core" } }
  }

  expect_failures = [var.gateways]
}

run "invalid_gateway_name_rejected" {
  command = plan

  variables {
    gateways = { "alpha/dev" = { core_device_thing_name = "alpha-dev-core-01" } }
  }

  expect_failures = [var.gateways]
}
