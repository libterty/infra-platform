project             = "example"
env                 = "dev"
expected_account_id = "111111111111"

# Greengrass deployments, one per thing group (each target has exactly one deployment; components left out are removed
# from the devices). Versions of custom components must have a recipe file under templates/example5/edge/components.
# aws.greengrass.Nucleus is pinned so an unrelated change never upgrades it (design K12). The AWS component versions
# are placeholders: pin the versions you have tested.
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

# Thing-level deployments of the KVS edge connector, used only when cameras is not empty. Keep the nucleus version
# equal to the group deployments.
camera_deployment = {
  nucleus_version        = "2.14.3"
  stream_manager_version = "2.2.1"
  edge_connector_version = "1.0.5"
}

# No cameras (design section 7.5). Must be identical to cameras in sitewise/envs/dev.tfvars.
cameras = {}
