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

module "auth" {
  source = "../.."

  name          = "alpha-dev-users"
  domain_prefix = "alpha-dev-login"

  resource_servers = {
    alpha = {
      name   = "alpha-api"
      scopes = { "items.read" = "Read items", "items.write" = "Write items" }
    }
  }

  clients = {
    spa = {
      callback_urls = ["https://app.dev.example.com/callback", "http://localhost:5173/callback"]
      logout_urls   = ["https://app.dev.example.com/"]
      scopes        = ["openid", "email", "alpha/items.read", "alpha/items.write"]
    }
  }

  tags = {
    Project = "alpha"
  }
}

output "issuer_url" {
  value = module.auth.issuer_url
}

output "client_ids" {
  value = module.auth.client_ids
}
