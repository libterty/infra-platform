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

module "memory" {
  source = "../.."

  name              = "alpha_dev_chat"
  description       = "Chat history for the alpha agent"
  event_expiry_days = 90

  strategies = {
    facts = {
      type       = "SEMANTIC"
      namespaces = ["/actors/{actorId}/facts"]
    }
    summary = {
      type       = "SUMMARIZATION"
      namespaces = ["/summaries/{actorId}/{sessionId}"]
    }
  }

  tags = {
    Project = "alpha"
  }
}

output "memory_id" {
  value = module.memory.memory_id
}

output "memory_arn" {
  value = module.memory.memory_arn
}

output "strategy_ids" {
  value = module.memory.strategy_ids
}
