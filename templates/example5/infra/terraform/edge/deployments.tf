locals {
  thing_group_arns = {
    fleet = module.in.strings["thing_group_fleet_arn"]
    core  = module.in.strings["thing_group_core_arn"]
  }

  # Components whose name starts with "aws." are AWS-provided; every other one is a recipe file of this template and
  # gets the topic prefix of this project and env as configuration.
  group_deployments = {
    for k, d in var.deployments : k => {
      name       = "${local.name_prefix}-${k}"
      target_arn = local.thing_group_arns[d.thing_group]
      components = {
        for c, v in d.components : c => {
          for attr, val in { version = v, merge = { TopicPrefix = local.name_prefix } } : attr => val if attr == "version" || !startswith(c, "aws.")
        }
      }
      rollout = { maximum_per_minute = d.rollout.maximum_per_minute }
      abort   = [{ failure_type = "FAILED", threshold_percentage = d.abort.threshold_percentage, min_number_of_executed_things = d.abort.min_number_of_executed_things }]
    }
  }

  # Custom component versions the deployments use; each must have a recipe file (checked in outputs.tf).
  referenced_versions = toset(flatten([
    for d in values(var.deployments) : [for c, v in d.components : "${c}/${v}" if !startswith(c, "aws.")]
  ]))
}

module "deployment" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/greengrass-deployment/aws"
  version  = "~> 0.1.0"
  for_each = local.group_deployments

  name       = each.value.name
  target_arn = each.value.target_arn
  components = each.value.components
  rollout    = each.value.rollout
  abort      = each.value.abort
  tags       = local.awscc_tags

  # A deployment must not reach devices before the component versions it names exist.
  depends_on = [module.component]
}

# KVS edge connector (design K14): it cannot be deployed to thing groups, so each core device with cameras gets a
# thing-level deployment. Its hub asset comes from the sitewise stack.
locals {
  edge_connector_assets = jsondecode(module.in.strings["edge_connector_asset_ids"])
  camera_core_things    = toset([for c in values(var.cameras) : c.core_thing_name])

  camera_deployments = {
    for t in local.camera_core_things : t => {
      name       = "${local.name_prefix}-kvs-${t}"
      target_arn = "arn:aws:iot:${var.aws_region}:${var.expected_account_id}:thing/${t}"
      components = {
        "aws.greengrass.Nucleus"       = { version = var.camera_deployment.nucleus_version }
        "aws.greengrass.StreamManager" = { version = var.camera_deployment.stream_manager_version }
        "aws.iot.EdgeConnectorForKVS"  = { version = var.camera_deployment.edge_connector_version, merge = { SiteWiseAssetIdForHub = try(local.edge_connector_assets.hubs[t], "") } }
      }
    }
  }
}

module "camera_deployment" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/greengrass-deployment/aws"
  version  = "~> 0.1.0"
  for_each = local.camera_deployments

  name       = each.value.name
  target_arn = each.value.target_arn
  components = each.value.components
  rollout    = { maximum_per_minute = 1 }
  abort      = [{ failure_type = "FAILED", threshold_percentage = 100, min_number_of_executed_things = 1 }]
  tags       = local.awscc_tags

  depends_on = [module.kvs]
}
