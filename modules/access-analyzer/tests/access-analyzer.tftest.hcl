mock_provider "aws" {}

override_resource {
  target          = aws_accessanalyzer_analyzer.this
  override_during = plan
  values          = { arn = "arn:aws:access-analyzer:ap-northeast-1:111111111111:analyzer/alpha-dev-account" }
}

variables {
  name = "alpha-dev-account"
}

# ---- positive -------------------------------------------------------------------------------------------------

run "account_analyzer_defaults" {
  command = plan

  assert {
    condition     = aws_accessanalyzer_analyzer.this.type == "ACCOUNT"
    error_message = "The default type must be ACCOUNT (external access, free)"
  }

  assert {
    condition     = aws_accessanalyzer_analyzer.this.analyzer_name == "alpha-dev-account"
    error_message = "The analyzer name must equal the name input"
  }

  assert {
    condition     = length(aws_accessanalyzer_analyzer.this.configuration) == 0
    error_message = "External access analyzers must not carry an unused access configuration"
  }

  assert {
    condition     = length(aws_accessanalyzer_archive_rule.this) == 0
    error_message = "Without archive_rules no archive rule is created"
  }

  assert {
    condition     = aws_accessanalyzer_analyzer.this.tags == tomap({ Name = "alpha-dev-account" })
    error_message = "Without tags input the only tag is Name"
  }

  assert {
    condition     = output.arn == "arn:aws:access-analyzer:ap-northeast-1:111111111111:analyzer/alpha-dev-account"
    error_message = "arn must expose the analyzer ARN"
  }
}

run "organization_analyzer" {
  command = plan

  variables {
    name   = "alpha-dev-organization"
    type   = "ORGANIZATION"
    region = "ap-northeast-1"
  }

  assert {
    condition     = aws_accessanalyzer_analyzer.this.type == "ORGANIZATION"
    error_message = "type ORGANIZATION must be passed through"
  }

  assert {
    condition     = aws_accessanalyzer_analyzer.this.region == "ap-northeast-1"
    error_message = "The analyzer must be placed in the given region"
  }
}

run "archive_rules" {
  command = plan

  variables {
    archive_rules = {
      trusted-account = [
        { criteria = "principal.AWS", eq = ["222222222222"] },
        { criteria = "isPublic", eq = ["false"] },
      ]
      ignore-kms = [
        { criteria = "resourceType", eq = ["AWS::KMS::Key"] },
      ]
    }
  }

  assert {
    condition     = toset(keys(aws_accessanalyzer_archive_rule.this)) == toset(["trusted-account", "ignore-kms"])
    error_message = "One archive rule per map key"
  }

  assert {
    condition     = alltrue([for k, r in aws_accessanalyzer_archive_rule.this : r.rule_name == k && r.analyzer_name == "alpha-dev-account"])
    error_message = "Each rule must use the map key as its name and belong to this analyzer"
  }
}

# Unset operators are computed by the provider and leave the filter set unknown at plan, so this rule sets all four.
run "archive_rule_filter_is_passed_through" {
  command = plan

  variables {
    archive_rules = {
      public-kms = [
        { criteria = "resourceType", eq = ["AWS::KMS::Key"], neq = ["AWS::S3::Bucket"], contains = ["Key"], exists = true },
      ]
    }
  }

  assert {
    condition = [for f in aws_accessanalyzer_archive_rule.this["public-kms"].filter : {
      criteria = f.criteria, eq = tolist(f.eq), neq = tolist(f.neq), contains = tolist(f.contains), exists = f.exists
      }] == [{
      criteria = "resourceType", eq = tolist(["AWS::KMS::Key"]), neq = tolist(["AWS::S3::Bucket"]), contains = tolist(["Key"]), exists = "true"
    }]
    error_message = "Filter criteria and operators must be passed through, exists as the string the provider expects"
  }
}

run "unused_access_analyzer" {
  command = plan

  variables {
    type                   = "ACCOUNT_UNUSED_ACCESS"
    unused_access_age_days = 90
  }

  assert {
    condition     = aws_accessanalyzer_analyzer.this.configuration[0].unused_access[0].unused_access_age == 90
    error_message = "Unused access analyzers must carry the given age"
  }
}

run "unused_access_without_age_uses_service_default" {
  command = plan

  variables {
    type = "ORGANIZATION_UNUSED_ACCESS"
  }

  assert {
    condition     = length(aws_accessanalyzer_analyzer.this.configuration) == 0
    error_message = "Without unused_access_age_days the service default applies"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "age_on_external_access_type_rejected" {
  command = plan

  variables {
    unused_access_age_days = 90
  }

  expect_failures = [var.unused_access_age_days]
}

run "age_out_of_range_rejected" {
  command = plan

  variables {
    type                   = "ACCOUNT_UNUSED_ACCESS"
    unused_access_age_days = 366
  }

  expect_failures = [var.unused_access_age_days]
}

run "unknown_type_rejected" {
  command = plan

  variables {
    type = "ACCOUNT_INTERNAL"
  }

  expect_failures = [var.type]
}

run "bad_name_rejected" {
  command = plan

  variables {
    name = "alpha dev"
  }

  expect_failures = [var.name]
}

run "archive_rule_without_filters_rejected" {
  command = plan

  variables {
    archive_rules = { empty = [] }
  }

  expect_failures = [var.archive_rules]
}

run "filter_without_operator_rejected" {
  command = plan

  variables {
    archive_rules = { broken = [{ criteria = "isPublic" }] }
  }

  expect_failures = [var.archive_rules]
}
