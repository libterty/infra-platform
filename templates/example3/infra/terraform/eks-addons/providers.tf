variable "deploy_role_arn" {
  description = "Role the providers assume in the resource account. Empty runs as the caller's own identity. Either way that identity must be addons_apply_principal_arn of the eks-cluster stack, which holds the cluster admin access entry."
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
    tags = merge(local.common_tags, { Stack = "eks-addons" })
  }

  dynamic "assume_role" {
    for_each = var.deploy_role_arn != "" ? [var.deploy_role_arn] : []

    content {
      role_arn = assume_role.value
    }
  }
}

# The endpoint is private (design v4 §7): run this stack from the VPC or a network connected to it.
# exec runs aws eks get-token on every call, so the token never expires in the middle of a long apply.
provider "helm" {
  kubernetes = {
    host                   = module.in.strings["cluster_endpoint"]
    cluster_ca_certificate = base64decode(module.in.strings["cluster_ca_data"])

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = concat(
        ["eks", "get-token", "--cluster-name", module.in.strings["cluster_name"], "--region", var.aws_region],
        var.deploy_role_arn != "" ? ["--role-arn", var.deploy_role_arn] : [],
      )
    }
  }
}
