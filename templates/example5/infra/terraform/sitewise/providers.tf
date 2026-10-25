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
    tags = merge(local.common_tags, { Stack = "sitewise" })
  }

  dynamic "assume_role" {
    for_each = var.deploy_role_arn != "" ? [var.deploy_role_arn] : []

    content {
      role_arn = assume_role.value
    }
  }
}

# awscc has no allowed_account_ids and no default_tags (design K3, K4). It uses the same region and role as the aws
# provider above, and the aws provider's allowed_account_ids stops a run against the wrong account before awscc acts.
# In awscc, assume_role is an attribute, not a block.
provider "awscc" {
  region      = var.aws_region
  assume_role = var.deploy_role_arn != "" ? { role_arn = var.deploy_role_arn } : null
}
