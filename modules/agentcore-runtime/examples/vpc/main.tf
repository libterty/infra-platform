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

# ARNs and IDs are placeholders for values a real stack reads from SSM.
module "agent" {
  source = "../.."

  name          = "alpha_dev_agent"
  role_arn      = "arn:aws:iam::111111111111:role/alpha-dev-agent-runtime"
  container_uri = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-agent:1.4.2"

  network = {
    subnet_ids         = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"]
    security_group_ids = ["sg-0cccccccccccccccc"]
  }

  environment_variables = {
    LOG_LEVEL               = "INFO"
    DB_SECRET_ARN           = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev-agent-db-AbCdEf"
    TRACELOOP_TRACE_CONTENT = "false"
  }

  tags = {
    Project = "alpha"
  }
}

output "runtime_arn" {
  value = module.agent.runtime_arn
}

output "workload_identity_arn" {
  value = module.agent.workload_identity_arn
}
