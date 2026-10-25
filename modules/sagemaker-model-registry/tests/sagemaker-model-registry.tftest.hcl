mock_provider "aws" {}

override_resource {
  target          = aws_sagemaker_model_package_group.this
  override_during = plan
  values = {
    arn = "arn:aws:sagemaker:ap-northeast-1:111111111111:model-package-group/alpha-dev-detector"
  }
}

variables {
  name = "alpha-dev-detector"
}

# ---- positive -------------------------------------------------------------------------------------------------

run "group_only" {
  command = plan

  assert {
    condition     = aws_sagemaker_model_package_group.this.model_package_group_name == "alpha-dev-detector"
    error_message = "The group name must be passed through"
  }

  assert {
    condition     = length(aws_sagemaker_model_package_group_policy.this) == 0
    error_message = "No resource policy without cross-account principals"
  }

  assert {
    condition     = aws_sagemaker_model_package_group.this.tags["Name"] == "alpha-dev-detector"
    error_message = "Name must be added to the tags"
  }
}

run "description_and_tags" {
  command = plan

  variables {
    description = "Defect detector models"
    tags        = { Project = "alpha" }
  }

  assert {
    condition     = aws_sagemaker_model_package_group.this.model_package_group_description == "Defect detector models"
    error_message = "The description must be passed through"
  }

  assert {
    condition     = aws_sagemaker_model_package_group.this.tags["Project"] == "alpha" && aws_sagemaker_model_package_group.this.tags["Name"] == "alpha-dev-detector"
    error_message = "Name must be merged into the given tags"
  }
}

run "cross_account_read_policy" {
  command = plan

  variables {
    cross_account_read_principals = [
      "222222222222",
      "arn:aws:iam::222222222222:role/alpha-sit-inference",
    ]
  }

  assert {
    condition     = length(aws_sagemaker_model_package_group_policy.this) == 1
    error_message = "A resource policy must be created when principals are given"
  }

  assert {
    condition     = aws_sagemaker_model_package_group_policy.this[0].model_package_group_name == "alpha-dev-detector"
    error_message = "The policy must attach to the group"
  }

  assert {
    condition = jsondecode(aws_sagemaker_model_package_group_policy.this[0].resource_policy) == {
      Version = "2012-10-17"
      Statement = [
        {
          Sid       = "ReadModelPackageGroup"
          Effect    = "Allow"
          Principal = { AWS = ["arn:aws:iam::222222222222:root", "arn:aws:iam::222222222222:role/alpha-sit-inference"] }
          Action    = ["sagemaker:DescribeModelPackageGroup"]
          Resource  = "arn:aws:sagemaker:ap-northeast-1:111111111111:model-package-group/alpha-dev-detector"
        },
        {
          Sid       = "ReadModelPackages"
          Effect    = "Allow"
          Principal = { AWS = ["arn:aws:iam::222222222222:root", "arn:aws:iam::222222222222:role/alpha-sit-inference"] }
          Action    = ["sagemaker:CreateModel", "sagemaker:DescribeModelPackage", "sagemaker:ListModelPackages"]
          Resource  = "arn:aws:sagemaker:ap-northeast-1:111111111111:model-package/alpha-dev-detector/*"
        },
      ]
    }
    error_message = "The resource policy must grant read-only access on the group and its packages"
  }

  assert {
    condition = alltrue([for s in jsondecode(aws_sagemaker_model_package_group_policy.this[0].resource_policy).Statement :
      s.Effect == "Allow" && s.Resource != "*" && alltrue([for a in s.Action : !strcontains(a, "*") && !contains(["sagemaker:UpdateModelPackage", "sagemaker:DeleteModelPackage", "sagemaker:CreateModelPackage"], a)]) && !contains(s.Principal.AWS, "*")
    ])
    error_message = "The policy must not contain wildcards or write actions"
  }
}

run "outputs" {
  command = plan

  assert {
    condition     = output.name == "alpha-dev-detector"
    error_message = "name output must be the group name"
  }

  assert {
    condition     = output.arn == "arn:aws:sagemaker:ap-northeast-1:111111111111:model-package-group/alpha-dev-detector"
    error_message = "arn output must be the group ARN"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "wildcard_principal_rejected" {
  command = plan

  variables {
    cross_account_read_principals = ["*"]
  }

  expect_failures = [var.cross_account_read_principals]
}

run "wildcard_role_arn_rejected" {
  command = plan

  variables {
    cross_account_read_principals = ["arn:aws:iam::222222222222:role/*"]
  }

  expect_failures = [var.cross_account_read_principals]
}

run "short_account_id_rejected" {
  command = plan

  variables {
    cross_account_read_principals = ["22222222222"]
  }

  expect_failures = [var.cross_account_read_principals]
}

run "user_arn_rejected" {
  command = plan

  variables {
    cross_account_read_principals = ["arn:aws:iam::222222222222:user/alice"]
  }

  expect_failures = [var.cross_account_read_principals]
}

run "invalid_name_rejected" {
  command = plan

  variables {
    name = "alpha_dev_detector"
  }

  expect_failures = [var.name]
}

run "name_too_long_rejected" {
  command = plan

  variables {
    name = "alpha-dev-detector-${format("%045d", 0)}"
  }

  expect_failures = [var.name]
}

run "description_too_long_rejected" {
  command = plan

  variables {
    description = format("%01025d", 0)
  }

  expect_failures = [var.description]
}
