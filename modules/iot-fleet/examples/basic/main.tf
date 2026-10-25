terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

locals {
  iot_arn = "arn:aws:iot:ap-northeast-1:111111111111"
}

module "iot_fleet" {
  source = "../.."

  thing_types = {
    alpha-sensor = { searchable_attributes = ["model"] }
  }

  thing_groups = {
    alpha-dev            = { description = "all alpha dev devices" }
    alpha-dev-unverified = { parent = "alpha-dev" }
    alpha-dev-fleet      = { parent = "alpha-dev" }
  }

  policies = {
    alpha-dev-device = {
      Version = "2012-10-17"
      Statement = [
        {
          Effect   = "Allow"
          Action   = "iot:Connect"
          Resource = "${local.iot_arn}:client/$${iot:Connection.Thing.ThingName}"
        },
        {
          Effect   = "Allow"
          Action   = ["iot:Publish", "iot:Receive"]
          Resource = "${local.iot_arn}:topic/alpha/dev/$${iot:Connection.Thing.ThingName}/*"
        },
        {
          Effect   = "Allow"
          Action   = "iot:Subscribe"
          Resource = "${local.iot_arn}:topicfilter/alpha/dev/$${iot:Connection.Thing.ThingName}/*"
        },
      ]
    }
  }

  role_alias = {
    alias    = "alpha-dev-tes"
    role_arn = "arn:aws:iam::111111111111:role/alpha-dev-greengrass-tes"
  }

  # No pre-provisioning hook: see the README section on the trade-off and its compensating controls.
  provisioning_template = {
    name                  = "alpha-dev-fleet"
    provisioning_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-iot-provisioning"
    enabled               = true
    template_body = {
      Parameters = {
        SerialNumber                = { Type = "String" }
        "AWS::IoT::Certificate::Id" = { Type = "String" }
      }
      Resources = {
        thing = {
          Type = "AWS::IoT::Thing"
          Properties = {
            ThingName   = { "Fn::Join" = ["", ["alpha-dev-", { Ref = "SerialNumber" }]] }
            ThingGroups = ["alpha-dev-unverified"]
          }
        }
        certificate = {
          Type       = "AWS::IoT::Certificate"
          Properties = { CertificateId = { Ref = "AWS::IoT::Certificate::Id" }, Status = "ACTIVE" }
        }
        policy = {
          Type       = "AWS::IoT::Policy"
          Properties = { PolicyName = "alpha-dev-device" }
        }
      }
    }
  }

  tags = { Project = "alpha" }
}

output "thing_group_arns" {
  value = module.iot_fleet.thing_group_arns
}
