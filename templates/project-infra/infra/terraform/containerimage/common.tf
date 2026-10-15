variable "project" {
  description = "Project name; the first part of every resource name and of the SSM path."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,15}$", var.project))
    error_message = "project must be 2-16 chars of lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "env" {
  description = "Environment name. It is the only environment name: file names, resource names, SSM paths and state keys all use it."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,11}$", var.env))
    error_message = "env must be 2-12 lowercase letters or digits, starting with a letter."
  }
}

variable "aws_region" {
  description = "Region of every resource in this stack."
  type        = string
  default     = "ap-northeast-1"
}

variable "expected_account_id" {
  description = "Account the resources live in. No default: a missing tfvars file must fail instead of pointing at some account."
  type        = string

  validation {
    condition     = try(contains(lookup(local.accounts_by_env, var.env, []), var.expected_account_id), false)
    error_message = "expected_account_id is not registered for this env in common.tf."
  }
}

locals {
  # Edit this table after copying the template. A new env must be added to every stack's common.tf; CI checks they stay identical.
  accounts_by_env = {
    dev  = ["111111111111"]
    prod = ["222222222222"]
  }

  name_prefix = "${var.project}-${var.env}"
  ssm_prefix  = "/${var.project}/${var.env}"

  common_tags = {
    Project     = var.project
    Environment = var.env
    Managed     = "terraform"
  }
}
