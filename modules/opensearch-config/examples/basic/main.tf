terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
    opensearch = {
      source  = "opensearch-project/opensearch"
      version = ">= 2.6.0, < 3.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

# The master credentials are read as an ephemeral value, so they never reach this configuration's state.
ephemeral "aws_secretsmanager_secret_version" "master" {
  secret_id = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev-opensearch-master-AbCdEf"
}

# The provider belongs to the caller. This configuration must run from a network that can reach the domain endpoint.
provider "opensearch" {
  url               = "https://vpc-alpha-dev-search-abc123.ap-northeast-1.es.amazonaws.com"
  username          = jsondecode(ephemeral.aws_secretsmanager_secret_version.master.secret_string).username
  password          = jsondecode(ephemeral.aws_secretsmanager_secret_version.master.secret_string).password
  sign_aws_requests = false
}

module "search_config" {
  source = "../.."

  ism_policies = {
    logs = {
      index_patterns  = ["firehose-*"]
      warm_days       = 3
      cold_days       = 7
      delete_days     = 30
      timestamp_field = "@timestamp"
    }
  }

  writer_roles = {
    firehose_writer = {
      index_patterns    = ["firehose-*"]
      backend_role_arns = ["arn:aws:iam::111111111111:role/alpha-dev-firehose"]
    }
  }

  role_mappings = {
    ultrawarm_manager = { backend_role_arns = ["arn:aws:iam::111111111111:role/alpha-dev-ops"] }
    cold_manager      = { backend_role_arns = ["arn:aws:iam::111111111111:role/alpha-dev-ops"] }
  }

  index_templates = {
    firehose = {
      index_patterns   = ["firehose-*"]
      number_of_shards = 1
      mappings         = jsonencode({ properties = { "@timestamp" = { type = "date" } } })
    }
  }
}

output "ism_policy_ids" {
  value = module.search_config.ism_policy_ids
}
