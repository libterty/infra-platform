mock_provider "aws" {}

override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "111111111111" }
}

# ---- positive -------------------------------------------------------------------------------------------------

run "default_three_types" {
  command = plan

  assert {
    condition     = aws_inspector2_enabler.this.resource_types == toset(["EC2", "ECR", "LAMBDA"])
    error_message = "EC2, ECR and LAMBDA must be enabled by default; Lambda code scanning stays off (K8)"
  }

  assert {
    condition     = aws_inspector2_enabler.this.account_ids == toset(["111111111111"])
    error_message = "The current account must be used when account_ids is empty"
  }

  assert {
    condition     = length(aws_inspector2_organization_configuration.this) == 0
    error_message = "No organization configuration unless given"
  }

  assert {
    condition     = output.enabled_resource_types == tolist(["EC2", "ECR", "LAMBDA"])
    error_message = "enabled_resource_types must list the enabled types sorted"
  }
}

run "member_accounts_and_lambda_code" {
  command = plan

  variables {
    region         = "us-east-1"
    account_ids    = ["222222222222", "333333333333"]
    resource_types = ["LAMBDA", "LAMBDA_CODE"]
  }

  assert {
    condition     = aws_inspector2_enabler.this.account_ids == toset(["222222222222", "333333333333"])
    error_message = "account_ids must be passed through"
  }

  assert {
    condition     = aws_inspector2_enabler.this.resource_types == toset(["LAMBDA", "LAMBDA_CODE"])
    error_message = "resource_types must be passed through"
  }

  assert {
    condition     = aws_inspector2_enabler.this.region == "us-east-1"
    error_message = "region must be set on the enabler"
  }
}

run "organization_auto_enable" {
  command = plan

  variables {
    region = "ap-northeast-1"
    organization = {
      auto_enable = { ec2 = true, ecr = true, lambda = true }
    }
  }

  assert {
    condition = (
      aws_inspector2_organization_configuration.this[0].auto_enable[0].ec2 == true &&
      aws_inspector2_organization_configuration.this[0].auto_enable[0].ecr == true &&
      aws_inspector2_organization_configuration.this[0].auto_enable[0].lambda == true &&
      aws_inspector2_organization_configuration.this[0].auto_enable[0].lambda_code == false
    )
    error_message = "auto_enable must be passed through, with Lambda code scanning off by default"
  }

  assert {
    condition     = aws_inspector2_organization_configuration.this[0].region == "ap-northeast-1"
    error_message = "region must be set on the organization configuration"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "unknown_resource_type_rejected" {
  command = plan

  variables {
    resource_types = ["EC2", "S3"]
  }

  expect_failures = [var.resource_types]
}

run "empty_resource_types_rejected" {
  command = plan

  variables {
    resource_types = []
  }

  expect_failures = [var.resource_types]
}

run "lambda_code_without_lambda_rejected" {
  command = plan

  variables {
    resource_types = ["EC2", "LAMBDA_CODE"]
  }

  expect_failures = [var.resource_types]
}

run "invalid_account_id_rejected" {
  command = plan

  variables {
    account_ids = ["22222222222"]
  }

  expect_failures = [var.account_ids]
}

run "organization_lambda_code_without_lambda_rejected" {
  command = plan

  variables {
    organization = {
      auto_enable = { ec2 = true, ecr = true, lambda = false, lambda_code = true }
    }
  }

  expect_failures = [var.organization]
}

run "invalid_region_rejected" {
  command = plan

  variables {
    region = "ap_northeast_1"
  }

  expect_failures = [var.region]
}
