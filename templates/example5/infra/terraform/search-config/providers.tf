variable "deploy_role_arn" {
  description = "Role the provider assumes in the resource account. Empty runs as the caller's own identity."
  type        = string
  default     = ""

  validation {
    condition     = var.deploy_role_arn == "" || try(split(":", var.deploy_role_arn)[4], "") == var.expected_account_id
    error_message = "deploy_role_arn must be empty or a role in expected_account_id."
  }
}

provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.expected_account_id]

  default_tags {
    tags = merge(local.common_tags, { Stack = "search-config" })
  }

  dynamic "assume_role" {
    for_each = var.deploy_role_arn != "" ? [var.deploy_role_arn] : []

    content {
      role_arn = assume_role.value
    }
  }
}

# The master credentials are read as an ephemeral value: they never reach this stack's state or plan file (v7 design K19).
# This is the only ephemeral block in the templates; the provider below is why it lives in the stack, not in a module.
# count exists for one reason: mock providers cannot open ephemeral resources, so terraform test sets
# read_master_secret = false. Every real run keeps the default true.
ephemeral "aws_secretsmanager_secret_version" "master" {
  count = var.read_master_secret ? 1 : 0

  secret_id = module.in.strings["opensearch_master_secret_arn"]
}

locals {
  opensearch_url    = "https://${module.in.strings["opensearch_endpoint"]}"
  opensearch_secret = var.read_master_secret ? jsondecode(ephemeral.aws_secretsmanager_secret_version.master[0].secret_string) : { username = "", password = "" }
}

# The domain is in the VPC: run this stack from a network that reaches it (Client VPN or a runner inside the VPC).
# Basic auth with the master user; sign_aws_requests = false because the access policy does not apply to basic auth.
provider "opensearch" {
  url               = local.opensearch_url
  username          = local.opensearch_secret.username
  password          = local.opensearch_secret.password
  sign_aws_requests = false
}
