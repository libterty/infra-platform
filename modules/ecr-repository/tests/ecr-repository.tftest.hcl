mock_provider "aws" {}

variables {
  name = "alpha-dev-api"
}

run "repository_defaults" {
  command = plan

  assert {
    condition     = aws_ecr_repository.this.name == "alpha-dev-api"
    error_message = "Repository name must equal the input"
  }

  assert {
    condition     = aws_ecr_repository.this.image_tag_mutability == "IMMUTABLE"
    error_message = "Tags must be immutable"
  }

  assert {
    condition     = aws_ecr_repository.this.image_scanning_configuration[0].scan_on_push == true
    error_message = "scan_on_push must be enabled"
  }

  assert {
    condition     = aws_ecr_repository.this.force_delete == false
    error_message = "force_delete must be false so destroy fails while images exist"
  }

  assert {
    condition     = aws_ecr_repository.this.tags == tomap({ Name = "alpha-dev-api" })
    error_message = "Only the Name tag must be added by default"
  }
}

run "extra_tags_merge_with_name" {
  command = plan

  variables {
    tags = { Service = "api" }
  }

  assert {
    condition     = aws_ecr_repository.this.tags == tomap({ Name = "alpha-dev-api", Service = "api" })
    error_message = "Extra tags must be merged with Name"
  }
}

run "aes256_without_kms" {
  command = plan

  assert {
    condition     = aws_ecr_repository.this.encryption_configuration[0].encryption_type == "AES256"
    error_message = "kms_key_arn = null must use AES256"
  }
}

run "kms_when_given" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition     = aws_ecr_repository.this.encryption_configuration[0].encryption_type == "KMS"
    error_message = "A key ARN must switch encryption to KMS"
  }

  assert {
    condition     = aws_ecr_repository.this.encryption_configuration[0].kms_key == "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-2222-3333-4444-555555555555"
    error_message = "kms_key must equal the input"
  }
}

run "lifecycle_defaults" {
  command = plan

  assert {
    condition     = aws_ecr_lifecycle_policy.this.repository == "alpha-dev-api"
    error_message = "Lifecycle policy must attach to the repository"
  }

  assert {
    condition     = length(jsondecode(aws_ecr_lifecycle_policy.this.policy).rules) == 2
    error_message = "Exactly two lifecycle rules are expected"
  }

  assert {
    condition = jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[0] == {
      rulePriority = 1
      description  = "Expire untagged images after 7 days"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = 7
      }
      action = { type = "expire" }
    }
    error_message = "Rule 1 must expire untagged images after 7 days"
  }

  assert {
    condition = jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[1] == {
      rulePriority = 2
      description  = "Keep the latest 50 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 50
      }
      action = { type = "expire" }
    }
    error_message = "Rule 2 must expire images beyond the latest 50"
  }
}

run "lifecycle_override" {
  command = plan

  variables {
    lifecycle_rules = { untagged_expire_days = 3, keep_count = 20 }
  }

  assert {
    condition     = jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[0].selection.countNumber == 3
    error_message = "untagged_expire_days must drive rule 1"
  }

  assert {
    condition     = jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[1].selection.countNumber == 20
    error_message = "keep_count must drive rule 2"
  }
}

run "lifecycle_partial_override_keeps_other_default" {
  command = plan

  variables {
    lifecycle_rules = { keep_count = 10 }
  }

  assert {
    condition     = jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[0].selection.countNumber == 7
    error_message = "Unset untagged_expire_days must stay at 7"
  }

  assert {
    condition     = jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[1].selection.countNumber == 10
    error_message = "keep_count must be overridden"
  }
}

run "outputs" {
  command = plan

  override_resource {
    target          = aws_ecr_repository.this
    override_during = plan
    values = {
      repository_url = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-dev-api"
      arn            = "arn:aws:ecr:ap-northeast-1:111111111111:repository/alpha-dev-api"
      registry_id    = "111111111111"
    }
  }

  assert {
    condition     = output.repository_url == "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-dev-api"
    error_message = "repository_url must expose the repository URL"
  }

  assert {
    condition     = output.arn == "arn:aws:ecr:ap-northeast-1:111111111111:repository/alpha-dev-api"
    error_message = "arn must expose the repository ARN"
  }

  assert {
    condition     = output.name == "alpha-dev-api"
    error_message = "name must expose the repository name"
  }

  assert {
    condition     = output.registry_id == "111111111111"
    error_message = "registry_id must expose the account ID"
  }
}

run "name_accepts_simple_and_namespaced" {
  command = plan

  variables {
    name = "team/api"
  }

  assert {
    condition     = aws_ecr_repository.this.name == "team/api"
    error_message = "A namespaced name must be accepted"
  }
}

run "name_accepts_min_length" {
  command = plan

  variables {
    name = "ab"
  }

  assert {
    condition     = aws_ecr_repository.this.name == "ab"
    error_message = "A 2 character name must be accepted"
  }
}

run "name_rejects_uppercase" {
  command = plan

  variables {
    name = "Alpha-api"
  }

  expect_failures = [var.name]
}

run "name_rejects_space" {
  command = plan

  variables {
    name = "alpha api"
  }

  expect_failures = [var.name]
}

run "name_rejects_single_char" {
  command = plan

  variables {
    name = "a"
  }

  expect_failures = [var.name]
}

run "name_rejects_trailing_slash" {
  command = plan

  variables {
    name = "team/"
  }

  expect_failures = [var.name]
}

run "lifecycle_minimums_accept_one" {
  command = plan

  variables {
    lifecycle_rules = { untagged_expire_days = 1, keep_count = 1 }
  }

  assert {
    condition     = jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[1].selection.countNumber == 1
    error_message = "1 must be accepted for both values"
  }
}

run "untagged_expire_days_rejects_zero" {
  command = plan

  variables {
    lifecycle_rules = { untagged_expire_days = 0 }
  }

  expect_failures = [var.lifecycle_rules]
}

run "keep_count_rejects_zero" {
  command = plan

  variables {
    lifecycle_rules = { keep_count = 0 }
  }

  expect_failures = [var.lifecycle_rules]
}
