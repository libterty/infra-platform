terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.69, < 7.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

locals {
  runtime_arn   = "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/alpha_dev_chat-AbCdEf1234"
  log_group_arn = "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/vendedlogs/bedrock-agentcore/alpha-dev-chat"
}

module "runtime_logs" {
  source = "../.."

  name_prefix = "alpha-dev"

  sources = {
    chat-logs = {
      resource_arn = local.runtime_arn
      log_type     = "APPLICATION_LOGS"
    }
    chat-traces = {
      resource_arn = local.runtime_arn
      log_type     = "TRACES"
    }
  }

  destinations = {
    chat = {
      type         = "CWL"
      resource_arn = local.log_group_arn
    }
    xray-traces = {
      type = "XRAY"
    }
  }

  deliveries = {
    chat-logs = {
      source      = "chat-logs"
      destination = "chat"
    }
    chat-traces = {
      source      = "chat-traces"
      destination = "xray-traces"
    }
  }

  tags = {
    Project = "alpha"
  }
}

output "delivery_ids" {
  value = module.runtime_logs.delivery_ids
}
