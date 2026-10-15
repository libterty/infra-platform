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

module "gateway" {
  source = "../.."

  name     = "alpha-dev-gateway"
  role_arn = "arn:aws:iam::111111111111:role/alpha-dev-agentcore-gateway"

  targets = {
    # Flat tool inputs can be written inline.
    catalog = {
      type       = "lambda"
      lambda_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-catalog"
      tools = [
        {
          name        = "search_items"
          description = "Search items by keyword"
          properties = {
            query = { type = "string", description = "Keyword", required = true }
            limit = { type = "integer", description = "Maximum number of results" }
          }
        },
      ]
    }

    # Nested tool inputs go through a schema file in S3.
    orders = {
      type               = "lambda"
      lambda_arn         = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-orders"
      tool_schema_s3_uri = "s3://alpha-dev-tool-schemas/orders.json"
    }

    docs = {
      type     = "mcp_server"
      endpoint = "https://mcp.example.com/mcp"
    }
  }

  tags = {
    Project = "alpha"
  }
}

output "gateway_arn" {
  value = module.gateway.gateway_arn
}

output "gateway_url" {
  value = module.gateway.gateway_url
}

output "target_ids" {
  value = module.gateway.target_ids
}
