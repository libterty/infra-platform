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

module "guardrail" {
  source = "../.."

  name                    = "alpha-dev-input"
  blocked_input_message   = "Sorry, I cannot help with that request."
  blocked_output_message  = "Sorry, I cannot provide that answer."
  cross_region_profile_id = "apac.guardrail.v1:0"

  content_filters = {
    HATE          = { input_strength = "HIGH", output_strength = "HIGH" }
    INSULTS       = { input_strength = "HIGH", output_strength = "HIGH" }
    SEXUAL        = { input_strength = "HIGH", output_strength = "HIGH" }
    VIOLENCE      = { input_strength = "HIGH", output_strength = "HIGH" }
    MISCONDUCT    = { input_strength = "HIGH", output_strength = "HIGH" }
    PROMPT_ATTACK = { input_strength = "HIGH", output_strength = "NONE" }
  }

  managed_word_lists = ["PROFANITY"]

  tags = {
    Project = "alpha"
  }
}

output "guardrail_id" {
  value = module.guardrail.guardrail_id
}

output "guardrail_version" {
  value = module.guardrail.version
}
