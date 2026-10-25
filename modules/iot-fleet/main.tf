resource "aws_iot_thing_type" "this" {
  for_each = var.thing_types

  name = each.key

  dynamic "properties" {
    for_each = each.value.description != null || length(each.value.searchable_attributes) > 0 ? [each.value] : []
    content {
      description           = properties.value.description
      searchable_attributes = properties.value.searchable_attributes
    }
  }

  tags = merge(var.tags, { Name = each.key })
}

# A resource cannot reference its own instances, so the hierarchy is created level by level: each level points
# at the parent's resource on the level above, which also gives Terraform the creation order. Groups whose parent
# is missing or in a cycle never land on a level and are rejected by the thing_groups validation.
locals {
  groups_level_0 = { for k, g in var.thing_groups : k => g if g.parent == null }
  groups_level_1 = { for k, g in var.thing_groups : k => g if g.parent != null && contains(keys(local.groups_level_0), coalesce(g.parent, "-")) }
  groups_level_2 = { for k, g in var.thing_groups : k => g if g.parent != null && contains(keys(local.groups_level_1), coalesce(g.parent, "-")) }
  groups_level_3 = { for k, g in var.thing_groups : k => g if g.parent != null && contains(keys(local.groups_level_2), coalesce(g.parent, "-")) }
}

resource "aws_iot_thing_group" "level_0" {
  for_each = local.groups_level_0

  name = each.key

  dynamic "properties" {
    for_each = each.value.description != null || length(each.value.attributes) > 0 ? [each.value] : []
    content {
      description = properties.value.description

      dynamic "attribute_payload" {
        for_each = length(properties.value.attributes) > 0 ? [properties.value.attributes] : []
        content {
          attributes = attribute_payload.value
        }
      }
    }
  }

  tags = merge(var.tags, { Name = each.key })
}

resource "aws_iot_thing_group" "level_1" {
  for_each = local.groups_level_1

  name              = each.key
  parent_group_name = aws_iot_thing_group.level_0[each.value.parent].name

  dynamic "properties" {
    for_each = each.value.description != null || length(each.value.attributes) > 0 ? [each.value] : []
    content {
      description = properties.value.description

      dynamic "attribute_payload" {
        for_each = length(properties.value.attributes) > 0 ? [properties.value.attributes] : []
        content {
          attributes = attribute_payload.value
        }
      }
    }
  }

  tags = merge(var.tags, { Name = each.key })
}

resource "aws_iot_thing_group" "level_2" {
  for_each = local.groups_level_2

  name              = each.key
  parent_group_name = aws_iot_thing_group.level_1[each.value.parent].name

  dynamic "properties" {
    for_each = each.value.description != null || length(each.value.attributes) > 0 ? [each.value] : []
    content {
      description = properties.value.description

      dynamic "attribute_payload" {
        for_each = length(properties.value.attributes) > 0 ? [properties.value.attributes] : []
        content {
          attributes = attribute_payload.value
        }
      }
    }
  }

  tags = merge(var.tags, { Name = each.key })
}

resource "aws_iot_thing_group" "level_3" {
  for_each = local.groups_level_3

  name              = each.key
  parent_group_name = aws_iot_thing_group.level_2[each.value.parent].name

  dynamic "properties" {
    for_each = each.value.description != null || length(each.value.attributes) > 0 ? [each.value] : []
    content {
      description = properties.value.description

      dynamic "attribute_payload" {
        for_each = length(properties.value.attributes) > 0 ? [properties.value.attributes] : []
        content {
          attributes = attribute_payload.value
        }
      }
    }
  }

  tags = merge(var.tags, { Name = each.key })
}

resource "aws_iot_policy" "this" {
  # policies is typed any so documents can differ in shape; encode first to get a map for for_each.
  for_each = { for k, doc in var.policies : k => jsonencode(doc) }

  name   = each.key
  policy = each.value

  tags = merge(var.tags, { Name = each.key })
}

resource "aws_iot_role_alias" "this" {
  count = var.role_alias == null ? 0 : 1

  alias               = var.role_alias.alias
  role_arn            = var.role_alias.role_arn
  credential_duration = var.role_alias.credential_duration

  tags = merge(var.tags, { Name = var.role_alias.alias })
}

resource "aws_iot_provisioning_template" "this" {
  count = var.provisioning_template == null ? 0 : 1

  name                  = var.provisioning_template.name
  description           = var.provisioning_template.description
  type                  = "FLEET_PROVISIONING"
  template_body         = jsonencode(var.provisioning_template.template_body)
  provisioning_role_arn = var.provisioning_template.provisioning_role_arn
  enabled               = var.provisioning_template.enabled

  dynamic "pre_provisioning_hook" {
    for_each = var.provisioning_template.pre_provisioning_hook == null ? [] : [var.provisioning_template.pre_provisioning_hook]
    content {
      target_arn      = pre_provisioning_hook.value.target_arn
      payload_version = pre_provisioning_hook.value.payload_version
    }
  }

  tags = merge(var.tags, { Name = var.provisioning_template.name })
}

# SNI_ONLY needs no verification certificate or private-key proof; DEFAULT would, and is rejected by validation.
resource "aws_iot_ca_certificate" "this" {
  count = var.ca_certificate == null ? 0 : 1

  ca_certificate_pem      = var.ca_certificate.pem
  certificate_mode        = "SNI_ONLY"
  active                  = var.ca_certificate.active
  allow_auto_registration = var.ca_certificate.allow_auto_registration

  dynamic "registration_config" {
    for_each = var.ca_certificate.registration_template == null ? [] : [var.ca_certificate.registration_template]
    content {
      role_arn      = registration_config.value.role_arn
      template_body = jsonencode(registration_config.value.template_body)
    }
  }

  tags = var.tags
}
