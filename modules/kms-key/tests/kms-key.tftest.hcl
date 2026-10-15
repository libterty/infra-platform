mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
}

variables {
  name = "alpha-dev"
}

run "key_defaults" {
  command = plan

  assert {
    condition     = aws_kms_key.this.enable_key_rotation == true
    error_message = "Key rotation must be enabled"
  }

  assert {
    condition     = aws_kms_key.this.key_usage == "ENCRYPT_DECRYPT" && aws_kms_key.this.customer_master_key_spec == "SYMMETRIC_DEFAULT"
    error_message = "Key must be a symmetric encrypt/decrypt key"
  }

  assert {
    condition     = aws_kms_key.this.multi_region == false
    error_message = "Key must be single-region"
  }

  assert {
    condition     = aws_kms_key.this.deletion_window_in_days == 30
    error_message = "Default deletion window must be 30 days"
  }

  assert {
    condition     = aws_kms_key.this.tags == tomap({ Name = "alpha-dev" })
    error_message = "Without tags input the only tag is Name"
  }
}

run "tags_are_merged_with_name" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_kms_key.this.tags == tomap({ Project = "alpha", Name = "alpha-dev" })
    error_message = "Input tags must be kept and Name added"
  }
}

run "alias_name" {
  command = plan

  assert {
    condition     = aws_kms_alias.this.name == "alias/alpha-dev"
    error_message = "Alias must be alias/<name>"
  }
}

run "root_statement_first" {
  command = plan

  assert {
    condition     = jsondecode(aws_kms_key_policy.this.policy).Statement[0].Principal.AWS == "arn:aws:iam::111111111111:root"
    error_message = "First statement must grant the account root"
  }

  assert {
    condition     = jsondecode(aws_kms_key_policy.this.policy).Statement[0].Action == "kms:*"
    error_message = "Root statement must allow kms:*"
  }
}

run "no_service_statements_by_default" {
  command = plan

  assert {
    condition     = length(jsondecode(aws_kms_key_policy.this.policy).Statement) == 1
    error_message = "Default policy must contain only the root statement"
  }
}

run "service_principal_statements" {
  command = plan

  variables {
    service_principals = {
      "logs.ap-northeast-1.amazonaws.com" = {
        conditions = [{
          test     = "ArnLike"
          variable = "kms:EncryptionContext:aws:logs:arn"
          values   = ["arn:aws:logs:ap-northeast-1:111111111111:log-group:*"]
        }]
      }
      "cloudwatch.amazonaws.com" = {
        actions = ["kms:Decrypt"]
      }
    }
  }

  assert {
    condition     = length(jsondecode(aws_kms_key_policy.this.policy).Statement) == 3
    error_message = "Two service principals must add two statements"
  }

  assert {
    condition     = jsondecode(aws_kms_key_policy.this.policy).Statement[1].Principal.Service == "cloudwatch.amazonaws.com"
    error_message = "Service statements must follow the root statement in key order"
  }

  assert {
    condition     = jsonencode(jsondecode(aws_kms_key_policy.this.policy).Statement[1].Action) == jsonencode(["kms:Decrypt"])
    error_message = "Explicit actions must be used as given"
  }

  assert {
    condition     = !contains(keys(jsondecode(aws_kms_key_policy.this.policy).Statement[1]), "Condition")
    error_message = "A service without conditions must not get a Condition block"
  }

  assert {
    condition     = jsonencode(jsondecode(aws_kms_key_policy.this.policy).Statement[2].Action) == jsonencode(["kms:Decrypt", "kms:GenerateDataKey*", "kms:DescribeKey"])
    error_message = "Default actions must be Decrypt, GenerateDataKey* and DescribeKey"
  }

  assert {
    condition     = jsonencode(jsondecode(aws_kms_key_policy.this.policy).Statement[2].Condition) == jsonencode({ ArnLike = { "kms:EncryptionContext:aws:logs:arn" = ["arn:aws:logs:ap-northeast-1:111111111111:log-group:*"] } })
    error_message = "Conditions must be copied from the input"
  }

  assert {
    condition     = jsondecode(aws_kms_key_policy.this.policy).Statement[2].Resource == "*"
    error_message = "Service statements apply to the key itself (Resource *)"
  }
}

run "administrator_statement_absent_by_default" {
  command = plan

  assert {
    condition     = length(jsondecode(aws_kms_key_policy.this.policy).Statement) == 1
    error_message = "No administrator statement without administrator_arns"
  }
}

run "administrator_statement_when_given" {
  command = plan

  variables {
    administrator_arns = ["arn:aws:iam::111111111111:role/platform-admin"]
  }

  assert {
    condition     = length(jsondecode(aws_kms_key_policy.this.policy).Statement) == 2
    error_message = "One administrator statement must be added"
  }

  assert {
    condition     = jsonencode(jsondecode(aws_kms_key_policy.this.policy).Statement[1].Principal.AWS) == jsonencode(["arn:aws:iam::111111111111:role/platform-admin"])
    error_message = "Administrator statement must name the given role"
  }

  assert {
    condition     = !contains(jsondecode(aws_kms_key_policy.this.policy).Statement[1].Action, "kms:Decrypt") && !contains(jsondecode(aws_kms_key_policy.this.policy).Statement[1].Action, "kms:*")
    error_message = "Administrators must not get data-plane use or kms:*"
  }
}

run "no_wildcard_principal" {
  command = plan

  variables {
    administrator_arns = ["arn:aws:iam::111111111111:user/ops"]
    service_principals = { "sns.amazonaws.com" = {} }
  }

  assert {
    condition     = alltrue([for s in jsondecode(aws_kms_key_policy.this.policy).Statement : !strcontains(jsonencode(s.Principal), "\"*\"")])
    error_message = "No statement may use a * principal"
  }
}

run "outputs" {
  command = plan

  override_resource {
    target          = aws_kms_key.this
    override_during = plan
    values = {
      arn    = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
      key_id = "1234abcd-12ab-34cd-56ef-1234567890ab"
    }
  }

  override_resource {
    target          = aws_kms_alias.this
    override_during = plan
    values = {
      arn = "arn:aws:kms:ap-northeast-1:111111111111:alias/alpha-dev"
    }
  }

  assert {
    condition     = output.key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    error_message = "key_arn must expose the key ARN"
  }

  assert {
    condition     = output.key_id == "1234abcd-12ab-34cd-56ef-1234567890ab"
    error_message = "key_id must expose the key ID"
  }

  assert {
    condition     = output.alias_name == "alias/alpha-dev"
    error_message = "alias_name must be alias/<name>"
  }

  assert {
    condition     = output.alias_arn == "arn:aws:kms:ap-northeast-1:111111111111:alias/alpha-dev"
    error_message = "alias_arn must expose the alias ARN"
  }
}

run "deletion_window_too_small" {
  command = plan
  variables { deletion_window_in_days = 6 }
  expect_failures = [var.deletion_window_in_days]
}

run "deletion_window_too_large" {
  command = plan
  variables { deletion_window_in_days = 31 }
  expect_failures = [var.deletion_window_in_days]
}

run "deletion_window_bounds_pass" {
  command = plan
  variables { deletion_window_in_days = 7 }

  assert {
    condition     = aws_kms_key.this.deletion_window_in_days == 7
    error_message = "7 days must be accepted"
  }
}

run "deletion_window_upper_bound_passes" {
  command = plan
  variables { deletion_window_in_days = 30 }

  assert {
    condition     = aws_kms_key.this.deletion_window_in_days == 30
    error_message = "30 days must be accepted"
  }
}

run "name_rejects_aws_prefix" {
  command = plan
  variables { name = "aws/foo" }
  expect_failures = [var.name]
}

run "name_rejects_space" {
  command = plan
  variables { name = "alpha dev" }
  expect_failures = [var.name]
}

run "name_accepts_valid" {
  command = plan
  variables { name = "alpha-dev" }

  assert {
    condition     = aws_kms_alias.this.name == "alias/alpha-dev"
    error_message = "alpha-dev must be accepted"
  }
}

run "service_principal_rejects_star" {
  command = plan
  variables { service_principals = { "*" = {} } }
  expect_failures = [var.service_principals]
}

run "service_principal_rejects_wrong_suffix" {
  command = plan
  variables { service_principals = { "logs.amazonaws.org" = {} } }
  expect_failures = [var.service_principals]
}

run "service_principal_accepts_regional" {
  command = plan
  variables { service_principals = { "logs.ap-northeast-1.amazonaws.com" = {} } }

  assert {
    condition     = length(jsondecode(aws_kms_key_policy.this.policy).Statement) == 2
    error_message = "A regional service principal must be accepted"
  }
}

run "service_actions_reject_star" {
  command = plan
  variables { service_principals = { "sns.amazonaws.com" = { actions = ["*"] } } }
  expect_failures = [var.service_principals]
}

run "service_actions_reject_kms_star" {
  command = plan
  variables { service_principals = { "sns.amazonaws.com" = { actions = ["kms:*"] } } }
  expect_failures = [var.service_principals]
}

run "service_actions_accept_prefix_wildcard" {
  command = plan
  variables { service_principals = { "sns.amazonaws.com" = { actions = ["kms:GenerateDataKey*"] } } }

  assert {
    condition     = length(jsondecode(aws_kms_key_policy.this.policy).Statement) == 2
    error_message = "kms:GenerateDataKey* must be accepted"
  }
}

run "administrator_arn_rejects_wildcard" {
  command = plan
  variables { administrator_arns = ["arn:aws:iam::111111111111:role/*"] }
  expect_failures = [var.administrator_arns]
}

run "administrator_arn_rejects_bare_star" {
  command = plan
  variables { administrator_arns = ["*"] }
  expect_failures = [var.administrator_arns]
}

run "administrator_arn_rejects_non_role" {
  command = plan
  variables { administrator_arns = ["arn:aws:iam::111111111111:root"] }
  expect_failures = [var.administrator_arns]
}

run "administrator_arn_accepts_user" {
  command = plan
  variables { administrator_arns = ["arn:aws:iam::111111111111:user/ops"] }

  assert {
    condition     = length(jsondecode(aws_kms_key_policy.this.policy).Statement) == 2
    error_message = "A user ARN must be accepted"
  }
}
