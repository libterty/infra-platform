# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
# The preconditions stop a plan that would deploy a component version without a recipe (design K10), or cameras the
# sitewise stack does not know.
output "deployment_names" {
  description = "Greengrass 部署名稱（群組部署與攝影機的 thing 部署）。"
  value       = concat([for d in values(local.group_deployments) : d.name], [for d in values(local.camera_deployments) : d.name])

  precondition {
    condition     = length(setsubtract(local.referenced_versions, keys(local.recipes))) == 0
    error_message = "Every custom component version in deployments needs a recipe file templates/example5/edge/components/<component>/<version>.json; missing: ${join(", ", setsubtract(local.referenced_versions, keys(local.recipes)))}."
  }
}

output "kvs_stream_names" {
  description = "KVS stream 名稱；沒有攝影機時是空清單。"
  value       = keys(local.kvs_streams)

  precondition {
    condition = alltrue([for id, c in var.cameras : (
      can(local.edge_connector_assets.cameras[id]) && can(local.edge_connector_assets.hubs[c.core_thing_name])
    )])
    error_message = "Every camera must exist in the sitewise stack (edge_connector_asset_ids); apply sitewise with the same cameras first."
  }
}
