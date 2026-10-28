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
    tags = merge(local.common_tags, { Stack = "api" })
  }

  dynamic "assume_role" {
    for_each = var.deploy_role_arn != "" ? [var.deploy_role_arn] : []

    content {
      role_arn = assume_role.value
    }
  }
}
