mock_provider "aws" {}

variables {
  tags = { Project = "alpha" }
}

# ---- positive -------------------------------------------------------------------------------------------------

run "empty_inputs_create_nothing" {
  command = plan

  assert {
    condition = (length(aws_iot_thing_type.this) + length(aws_iot_thing_group.level_0) + length(aws_iot_policy.this)
    + length(aws_iot_role_alias.this) + length(aws_iot_provisioning_template.this) + length(aws_iot_ca_certificate.this)) == 0
    error_message = "Nothing must be created without inputs"
  }
}

run "thing_types" {
  command = plan

  variables {
    thing_types = {
      alpha-sensor = {
        description           = "temperature sensor"
        searchable_attributes = ["model", "site"]
      }
    }
  }

  assert {
    condition     = aws_iot_thing_type.this["alpha-sensor"].name == "alpha-sensor"
    error_message = "The map key must be the thing type name"
  }
  assert {
    condition     = one(aws_iot_thing_type.this["alpha-sensor"].properties).searchable_attributes == toset(["model", "site"]) && one(aws_iot_thing_type.this["alpha-sensor"].properties).description == "temperature sensor"
    error_message = "Thing type properties must be passed through"
  }
  assert {
    condition     = aws_iot_thing_type.this["alpha-sensor"].tags["Name"] == "alpha-sensor" && aws_iot_thing_type.this["alpha-sensor"].tags["Project"] == "alpha"
    error_message = "Name must be added to the given tags"
  }
}

run "thing_group_hierarchy" {
  command = plan

  variables {
    thing_groups = {
      alpha-dev = {
        description = "all devices"
      }
      alpha-dev-unverified = {
        parent = "alpha-dev"
      }
      alpha-dev-fleet = {
        parent     = "alpha-dev"
        attributes = { tier = "line-a" }
      }
      alpha-dev-fleet-core = {
        parent = "alpha-dev-fleet"
      }
      alpha-dev-fleet-core-cam = {
        parent = "alpha-dev-fleet-core"
      }
    }
  }

  assert {
    condition     = keys(aws_iot_thing_group.level_0) == ["alpha-dev"] && aws_iot_thing_group.level_0["alpha-dev"].parent_group_name == null
    error_message = "Groups without a parent must be roots"
  }
  assert {
    condition     = toset(keys(aws_iot_thing_group.level_1)) == toset(["alpha-dev-unverified", "alpha-dev-fleet"])
    error_message = "Direct children of a root must be on level 1"
  }
  assert {
    condition     = aws_iot_thing_group.level_1["alpha-dev-fleet"].parent_group_name == "alpha-dev"
    error_message = "Level 1 groups must point at their parent"
  }
  assert {
    condition     = aws_iot_thing_group.level_2["alpha-dev-fleet-core"].parent_group_name == "alpha-dev-fleet" && aws_iot_thing_group.level_3["alpha-dev-fleet-core-cam"].parent_group_name == "alpha-dev-fleet-core"
    error_message = "Deeper groups must point at their parent"
  }
  assert {
    condition     = one(one(aws_iot_thing_group.level_1["alpha-dev-fleet"].properties).attribute_payload).attributes == tomap({ tier = "line-a" })
    error_message = "Group attributes must be passed through"
  }
  assert {
    condition     = one(aws_iot_thing_group.level_0["alpha-dev"].properties).description == "all devices"
    error_message = "Group description must be passed through"
  }
  assert {
    condition     = length(aws_iot_thing_group.level_1["alpha-dev-unverified"].properties) == 0
    error_message = "Groups without description or attributes must not carry a properties block"
  }
  assert {
    condition     = aws_iot_thing_group.level_2["alpha-dev-fleet-core"].tags["Name"] == "alpha-dev-fleet-core"
    error_message = "Name must be added to the group tags"
  }
}

run "policy_document_is_json_encoded" {
  command = plan

  variables {
    policies = {
      alpha-dev-device = {
        Version = "2012-10-17"
        Statement = [
          {
            Effect   = "Allow"
            Action   = "iot:Connect"
            Resource = "arn:aws:iot:ap-northeast-1:111111111111:client/$${iot:Connection.Thing.ThingName}"
          },
          {
            Effect   = "Allow"
            Action   = ["iot:Publish", "iot:Receive"]
            Resource = ["arn:aws:iot:ap-northeast-1:111111111111:topic/alpha/dev/$${iot:Connection.Thing.ThingName}/*"]
          },
        ]
      }
      alpha-dev-claim = {
        Version = "2012-10-17"
        Statement = [{
          Effect   = "Allow"
          Action   = ["iot:Publish", "iot:Receive"]
          Resource = ["arn:aws:iot:ap-northeast-1:111111111111:topic/$aws/certificates/create/*"]
        }]
      }
    }
  }

  assert {
    condition     = jsondecode(aws_iot_policy.this["alpha-dev-device"].policy).Statement[0].Resource == "arn:aws:iot:ap-northeast-1:111111111111:client/$${iot:Connection.Thing.ThingName}"
    error_message = "The policy document must be JSON-encoded as given"
  }
  assert {
    condition     = alltrue([for p in aws_iot_policy.this : !contains(flatten([for s in jsondecode(p.policy).Statement : s.Resource]), "*")])
    error_message = "No policy may grant Resource *"
  }
  assert {
    condition     = aws_iot_policy.this["alpha-dev-claim"].name == "alpha-dev-claim" && aws_iot_policy.this["alpha-dev-claim"].tags["Name"] == "alpha-dev-claim"
    error_message = "The map key must be the policy name and Name tag"
  }
}

run "wildcard_action_on_scoped_resource_is_accepted" {
  command = plan

  variables {
    policies = {
      alpha-dev-core = {
        Version = "2012-10-17"
        Statement = [{
          Effect   = "Allow"
          Action   = "iot:*"
          Resource = "arn:aws:iot:ap-northeast-1:111111111111:client/alpha-dev-core-*"
        }]
      }
    }
  }

  assert {
    condition     = length(aws_iot_policy.this) == 1
    error_message = "iot:* scoped to a resource pattern must be accepted"
  }
}

run "role_alias_with_default_duration" {
  command = plan

  variables {
    role_alias = {
      alias    = "alpha-dev-tes"
      role_arn = "arn:aws:iam::111111111111:role/alpha-dev-greengrass-tes"
    }
  }

  assert {
    condition     = aws_iot_role_alias.this[0].alias == "alpha-dev-tes" && aws_iot_role_alias.this[0].role_arn == "arn:aws:iam::111111111111:role/alpha-dev-greengrass-tes"
    error_message = "Role alias must be passed through"
  }
  assert {
    condition     = aws_iot_role_alias.this[0].credential_duration == 3600
    error_message = "credential_duration must default to 3600"
  }
}

run "provisioning_template_without_hook" {
  command = plan

  variables {
    provisioning_template = {
      name                  = "alpha-dev-fleet"
      provisioning_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-iot-provisioning"
      enabled               = true
      template_body = {
        Parameters = { SerialNumber = { Type = "String" } }
        Resources  = {}
      }
    }
  }

  assert {
    condition     = aws_iot_provisioning_template.this[0].type == "FLEET_PROVISIONING"
    error_message = "The template type must be FLEET_PROVISIONING"
  }
  assert {
    condition     = jsondecode(aws_iot_provisioning_template.this[0].template_body).Parameters.SerialNumber.Type == "String"
    error_message = "template_body must be JSON-encoded"
  }
  assert {
    condition     = length(aws_iot_provisioning_template.this[0].pre_provisioning_hook) == 0
    error_message = "No hook must be attached when pre_provisioning_hook is null"
  }
  assert {
    condition     = aws_iot_provisioning_template.this[0].enabled == true && aws_iot_provisioning_template.this[0].name == "alpha-dev-fleet"
    error_message = "name and enabled must be passed through"
  }
}

run "provisioning_template_with_hook" {
  command = plan

  variables {
    provisioning_template = {
      name                  = "alpha-dev-fleet"
      provisioning_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-iot-provisioning"
      enabled               = false
      template_body         = { Resources = {} }
      pre_provisioning_hook = {
        target_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-provisioning-hook"
      }
    }
  }

  assert {
    condition     = one(aws_iot_provisioning_template.this[0].pre_provisioning_hook).target_arn == "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-provisioning-hook"
    error_message = "The hook target must be passed through"
  }
  assert {
    condition     = one(aws_iot_provisioning_template.this[0].pre_provisioning_hook).payload_version == "2020-04-01"
    error_message = "payload_version must default to 2020-04-01"
  }
}

run "sni_only_ca_certificate" {
  command = plan

  variables {
    ca_certificate = {
      pem = "-----BEGIN CERTIFICATE-----\nMIIBplaceholder\n-----END CERTIFICATE-----\n"
    }
  }

  assert {
    condition     = aws_iot_ca_certificate.this[0].certificate_mode == "SNI_ONLY"
    error_message = "certificate_mode must be SNI_ONLY"
  }
  assert {
    condition     = aws_iot_ca_certificate.this[0].verification_certificate_pem == null
    error_message = "No verification certificate is sent"
  }
  assert {
    condition     = aws_iot_ca_certificate.this[0].active == true && aws_iot_ca_certificate.this[0].allow_auto_registration == false
    error_message = "The CA must default to active without auto-registration"
  }
}

run "ca_certificate_with_registration_template" {
  command = plan

  variables {
    ca_certificate = {
      pem                     = "-----BEGIN CERTIFICATE-----\nMIIBplaceholder\n-----END CERTIFICATE-----\n"
      allow_auto_registration = true
      registration_template = {
        role_arn      = "arn:aws:iam::111111111111:role/alpha-dev-iot-jitp"
        template_body = { Resources = {} }
      }
    }
  }

  assert {
    condition     = jsondecode(one(aws_iot_ca_certificate.this[0].registration_config).template_body) == { Resources = {} }
    error_message = "The registration template must be JSON-encoded"
  }
  assert {
    condition     = one(aws_iot_ca_certificate.this[0].registration_config).role_arn == "arn:aws:iam::111111111111:role/alpha-dev-iot-jitp"
    error_message = "The registration role must be passed through"
  }
}

run "outputs_after_apply" {
  command = apply

  variables {
    thing_types  = { alpha-sensor = {} }
    thing_groups = { alpha-dev = {}, alpha-dev-fleet = { parent = "alpha-dev" } }
    role_alias = {
      alias    = "alpha-dev-tes"
      role_arn = "arn:aws:iam::111111111111:role/alpha-dev-greengrass-tes"
    }
    provisioning_template = {
      name                  = "alpha-dev-fleet"
      provisioning_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-iot-provisioning"
      enabled               = true
      template_body         = { Resources = {} }
    }
  }

  override_resource {
    target = aws_iot_thing_group.level_1["alpha-dev-fleet"]
    values = { arn = "arn:aws:iot:ap-northeast-1:111111111111:thinggroup/alpha-dev-fleet" }
  }

  override_resource {
    target = aws_iot_role_alias.this[0]
    values = { arn = "arn:aws:iot:ap-northeast-1:111111111111:rolealias/alpha-dev-tes" }
  }

  assert {
    condition     = output.thing_group_arns["alpha-dev-fleet"] == "arn:aws:iot:ap-northeast-1:111111111111:thinggroup/alpha-dev-fleet" && length(output.thing_group_arns) == 2
    error_message = "thing_group_arns must cover every level"
  }
  assert {
    condition     = output.role_alias_arn == "arn:aws:iot:ap-northeast-1:111111111111:rolealias/alpha-dev-tes"
    error_message = "role_alias_arn must be the role alias ARN"
  }
  assert {
    condition     = output.provisioning_template_name == "alpha-dev-fleet" && keys(output.thing_type_arns) == ["alpha-sensor"]
    error_message = "provisioning_template_name and thing_type_arns must be exported"
  }
  assert {
    condition     = output.ca_certificate_id == null && output.policy_names == {}
    error_message = "Outputs of resources not created must be empty"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "unknown_parent_rejected" {
  command = plan

  variables {
    thing_groups = { alpha-dev-fleet = { parent = "alpha-dev" } }
  }

  expect_failures = [var.thing_groups]
}

run "group_cycle_rejected" {
  command = plan

  variables {
    thing_groups = {
      alpha-a = { parent = "alpha-b" }
      alpha-b = { parent = "alpha-a" }
    }
  }

  expect_failures = [var.thing_groups]
}

run "group_hierarchy_too_deep_rejected" {
  command = plan

  variables {
    thing_groups = {
      alpha-1 = {}
      alpha-2 = { parent = "alpha-1" }
      alpha-3 = { parent = "alpha-2" }
      alpha-4 = { parent = "alpha-3" }
      alpha-5 = { parent = "alpha-4" }
    }
  }

  expect_failures = [var.thing_groups]
}

run "policy_iot_wildcard_on_all_resources_rejected" {
  command = plan

  variables {
    policies = {
      alpha-dev-device = {
        Version   = "2012-10-17"
        Statement = [{ Effect = "Allow", Action = ["iot:Connect", "iot:*"], Resource = ["*"] }]
      }
    }
  }

  expect_failures = [var.policies]
}

run "policy_star_action_on_all_resources_rejected" {
  command = plan

  variables {
    policies = {
      alpha-dev-device = {
        Version   = "2012-10-17"
        Statement = [{ Effect = "Allow", Action = "*", Resource = "*" }]
      }
    }
  }

  expect_failures = [var.policies]
}

run "policy_without_statements_rejected" {
  command = plan

  variables {
    policies = {
      alpha-dev-device = { Version = "2012-10-17" }
    }
  }

  expect_failures = [var.policies]
}

run "credential_duration_below_range_rejected" {
  command = plan

  variables {
    role_alias = {
      alias               = "alpha-dev-tes"
      role_arn            = "arn:aws:iam::111111111111:role/alpha-dev-greengrass-tes"
      credential_duration = 899
    }
  }

  expect_failures = [var.role_alias]
}

run "credential_duration_above_range_rejected" {
  command = plan

  variables {
    role_alias = {
      alias               = "alpha-dev-tes"
      role_arn            = "arn:aws:iam::111111111111:role/alpha-dev-greengrass-tes"
      credential_duration = 43201
    }
  }

  expect_failures = [var.role_alias]
}

run "role_alias_role_arn_format_rejected" {
  command = plan

  variables {
    role_alias = {
      alias    = "alpha-dev-tes"
      role_arn = "alpha-dev-greengrass-tes"
    }
  }

  expect_failures = [var.role_alias]
}

run "provisioning_role_arn_format_rejected" {
  command = plan

  variables {
    provisioning_template = {
      name                  = "alpha-dev-fleet"
      provisioning_role_arn = "arn:aws:iam::111111111111:user/alpha"
      enabled               = true
      template_body         = { Resources = {} }
    }
  }

  expect_failures = [var.provisioning_template]
}

run "hook_target_not_lambda_rejected" {
  command = plan

  variables {
    provisioning_template = {
      name                  = "alpha-dev-fleet"
      provisioning_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-iot-provisioning"
      enabled               = true
      template_body         = { Resources = {} }
      pre_provisioning_hook = { target_arn = "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-hook" }
    }
  }

  expect_failures = [var.provisioning_template]
}

run "ca_mode_default_rejected" {
  command = plan

  variables {
    ca_certificate = {
      pem  = "-----BEGIN CERTIFICATE-----\nMIIBplaceholder\n-----END CERTIFICATE-----\n"
      mode = "DEFAULT"
    }
  }

  expect_failures = [var.ca_certificate]
}

run "ca_pem_format_rejected" {
  command = plan

  variables {
    ca_certificate = {
      pem = "not a certificate"
    }
  }

  expect_failures = [var.ca_certificate]
}

run "ca_registration_role_arn_format_rejected" {
  command = plan

  variables {
    ca_certificate = {
      pem = "-----BEGIN CERTIFICATE-----\nMIIBplaceholder\n-----END CERTIFICATE-----\n"
      registration_template = {
        role_arn      = "alpha-dev-iot-jitp"
        template_body = { Resources = {} }
      }
    }
  }

  expect_failures = [var.ca_certificate]
}

run "thing_type_name_rejected" {
  command = plan

  variables {
    thing_types = { "alpha sensor" = {} }
  }

  expect_failures = [var.thing_types]
}

run "too_many_searchable_attributes_rejected" {
  command = plan

  variables {
    thing_types = { alpha-sensor = { searchable_attributes = ["a", "b", "c", "d"] } }
  }

  expect_failures = [var.thing_types]
}

run "thing_group_name_rejected" {
  command = plan

  variables {
    thing_groups = { "alpha/dev" = {} }
  }

  expect_failures = [var.thing_groups]
}

run "policy_name_rejected" {
  command = plan

  variables {
    policies = {
      "alpha dev" = {
        Version   = "2012-10-17"
        Statement = [{ Effect = "Allow", Action = "iot:Connect", Resource = "arn:aws:iot:ap-northeast-1:111111111111:client/alpha" }]
      }
    }
  }

  expect_failures = [var.policies]
}

run "role_alias_name_rejected" {
  command = plan

  variables {
    role_alias = {
      alias    = "alpha/dev"
      role_arn = "arn:aws:iam::111111111111:role/alpha-dev-greengrass-tes"
    }
  }

  expect_failures = [var.role_alias]
}

run "provisioning_template_name_rejected" {
  command = plan

  variables {
    provisioning_template = {
      name                  = "alpha.dev.fleet"
      provisioning_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-iot-provisioning"
      enabled               = true
      template_body         = { Resources = {} }
    }
  }

  expect_failures = [var.provisioning_template]
}
