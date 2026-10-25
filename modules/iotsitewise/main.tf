locals {
  # A resource cannot reference its own instances, so models and assets that sit below a parent are created first,
  # in a separate resource. That is also why hierarchies are limited to two levels.
  child_model_keys = toset(flatten([for _, m in var.asset_models : values(m.hierarchies)]))

  asset_model_ids = merge(
    { for k, m in awscc_iotsitewise_asset_model.child : k => m.asset_model_id },
    { for k, m in awscc_iotsitewise_asset_model.this : k => m.asset_model_id },
  )

  model_properties = { for k, m in var.asset_models : k => [
    for name, p in m.properties : {
      name       = name
      logical_id = name
      data_type  = p.data_type
      unit       = p.unit
      type = {
        type_name   = p.type == "attribute" ? "Attribute" : "Measurement"
        attribute   = p.type == "attribute" ? { default_value = p.default_value } : null
        measurement = null
      }
    }
  ] }

  asset_properties = { for k, a in var.assets : k => [
    for name, p in a.properties : {
      logical_id         = name
      alias              = p.alias
      notification_state = p.notification_state
      unit               = p.unit
    }
  ] }

  tag_lists = { for name in distinct(concat(keys(var.asset_models), keys(var.assets), keys(var.gateways))) : name => [
    for k, v in merge(var.tags, { Name = name }) : { key = k, value = v }
  ] }
}

resource "awscc_iotsitewise_asset_model" "child" {
  for_each = { for k, m in var.asset_models : k => m if contains(local.child_model_keys, k) }

  asset_model_name        = each.key
  asset_model_description = each.value.description
  asset_model_properties  = local.model_properties[each.key]

  tags = local.tag_lists[each.key]
}

resource "awscc_iotsitewise_asset_model" "this" {
  for_each = { for k, m in var.asset_models : k => m if !contains(local.child_model_keys, k) }

  asset_model_name        = each.key
  asset_model_description = each.value.description
  asset_model_properties  = local.model_properties[each.key]

  asset_model_hierarchies = [for name, child in each.value.hierarchies : {
    name                 = name
    logical_id           = name
    child_asset_model_id = awscc_iotsitewise_asset_model.child[child].asset_model_id
  }]

  tags = local.tag_lists[each.key]
}

resource "awscc_iotsitewise_asset" "child" {
  for_each = { for k, a in var.assets : k => a if a.parent != null }

  asset_name       = each.key
  asset_model_id   = local.asset_model_ids[each.value.model]
  asset_properties = local.asset_properties[each.key]

  tags = local.tag_lists[each.key]
}

resource "awscc_iotsitewise_asset" "this" {
  for_each = { for k, a in var.assets : k => a if a.parent == null }

  asset_name       = each.key
  asset_model_id   = local.asset_model_ids[each.value.model]
  asset_properties = local.asset_properties[each.key]

  asset_hierarchies = [for child, a in var.assets : {
    logical_id     = a.parent.hierarchy
    child_asset_id = awscc_iotsitewise_asset.child[child].asset_id
  } if a.parent != null && try(a.parent.asset == each.key, false)]

  tags = local.tag_lists[each.key]
}

resource "awscc_iotsitewise_gateway" "this" {
  for_each = var.gateways

  gateway_name = each.key

  gateway_platform = {
    greengrass_v2 = {
      core_device_thing_name = each.value.core_device_thing_name
    }
  }

  tags = local.tag_lists[each.key]
}
