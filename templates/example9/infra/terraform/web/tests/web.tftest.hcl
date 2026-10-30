mock_provider "aws" {}

variables {
  project             = "cicd"
  env                 = "dev"
  expected_account_id = "111111111111"
}

# The distribution outputs are unknown in a plan; fixed values make the wiring checkable.
override_module {
  target = module.cdn
  outputs = {
    distribution_id = "E0000000000001"
    arn             = "arn:aws:cloudfront::111111111111:distribution/E0000000000001"
    domain_name     = "d1234567890abc.cloudfront.net"
    hosted_zone_id  = "Z2FDTNDATAQYW2"
    oac_ids         = { site = "E0000000000OAC" }
  }
}

override_module {
  target = module.site_bucket
  outputs = {
    bucket_name                 = "cicd-dev-web-111111111111"
    arn                         = "arn:aws:s3:::cicd-dev-web-111111111111"
    bucket_regional_domain_name = "cicd-dev-web-111111111111.s3.ap-northeast-1.amazonaws.com"
  }
}

run "reads_nothing" {
  command = plan

  assert {
    condition     = !fileexists("${path.module}/ssm-inputs.tf") && alltrue([for f in fileset(path.module, "*.tf") : !strcontains(file("${path.module}/${f}"), "ssm-read")])
    error_message = "web needs nothing from earlier stacks and must not read SSM"
  }
}

# iam/naming.tf builds the pipeline role's S3 deploy permission from this name.
run "bucket_name_matches_the_iam_naming_rule" {
  command = plan

  assert {
    condition     = local.site_bucket.name == "cicd-dev-web-111111111111" && local.site_bucket.never_expire
    error_message = "The web bucket must be <name_prefix>-web-<account> and keep its files until they are replaced"
  }
}

# Design 4: CloudFront reaches S3 through OAC and the bucket policy names only this distribution.
run "bucket_policy_allows_only_this_distribution" {
  command = plan

  assert {
    condition     = local.site_bucket_readers == ["arn:aws:cloudfront::111111111111:distribution/E0000000000001"]
    error_message = "The web bucket must let exactly this distribution read it"
  }

  assert {
    condition     = length(regexall("(?m)^\\s*cloudfront_distribution_arns\\s*=\\s*local\\.site_bucket_readers\\s*$", file("${path.module}/buckets.tf"))) == 1
    error_message = "The web bucket may grant CloudFront access only to local.site_bucket_readers"
  }

  assert {
    condition     = !strcontains(file("${path.module}/buckets.tf"), "kms_key_arn")
    error_message = "The web bucket uses SSE-S3: CloudFront cannot read objects encrypted with the shared key"
  }

  assert {
    condition     = local.cdn.origins == { site = { type = "s3", domain_name = "cicd-dev-web-111111111111.s3.ap-northeast-1.amazonaws.com" } }
    error_message = "The only origin must be the bucket's regional domain, so the module puts an OAC on it"
  }
}

run "distribution_serves_the_spa" {
  command = plan

  assert {
    condition = (
      local.cdn.name == "cicd-dev-web" &&
      local.cdn.price_class == "PriceClass_200" &&
      local.cdn.default_behavior == { origin = "site" } &&
      local.cdn.default_root_object == "index.html" &&
      local.cdn.spa_fallback
    )
    error_message = "The distribution serves index.html from S3 with the SPA fallback"
  }
}

# The web-invalidate role (iam) may only invalidate a distribution with exactly these tags, which the provider's
# default_tags put on every resource of this stack.
run "distribution_carries_the_tags_iam_expects" {
  command = plan

  assert {
    condition     = merge(local.common_tags, { Stack = "web" }) == { Project = "cicd", Environment = "dev", Managed = "terraform", Stack = "web" }
    error_message = "The distribution tags must equal web_distribution_tags in iam/naming.tf"
  }

  assert {
    condition     = length(regexall("(?m)^\\s*tags\\s*=\\s*merge\\(local\\.common_tags, \\{ Stack = \"web\" \\}\\)\\s*$", file("${path.module}/providers.tf"))) == 1
    error_message = "providers.tf must tag every resource with common_tags plus Stack = web"
  }

  assert {
    condition     = length(regexall("(?m)^\\s*tags\\s*=", file("${path.module}/distribution.tf"))) == 0
    error_message = "The distribution must not override the default tags the web-invalidate condition depends on"
  }
}

run "publishes_the_deploy_targets" {
  command = plan

  assert {
    condition     = local.published_strings == { web_bucket_name = "cicd-dev-web-111111111111", distribution_id = "E0000000000001" }
    error_message = "web must publish the web bucket and the distribution ID (design 8.3)"
  }

  assert {
    condition     = module.ssm_publish.names == { web_bucket_name = "/cicd/dev/web/web_bucket_name", distribution_id = "/cicd/dev/web/distribution_id" }
    error_message = "ssm-publish must write the keys under the web path"
  }
}

# ---- common.tf and providers.tf guards: the same runs in every stack ----

run "env_format_uppercase_rejected" {
  command = plan

  variables {
    env = "Dev"
  }

  expect_failures = [var.env]
}

run "env_format_too_short_rejected" {
  command = plan

  variables {
    env = "d"
  }

  expect_failures = [var.env]
}

run "env_format_valid_passes" {
  command = plan

  variables {
    env = "dev"
  }

  assert {
    condition     = local.name_prefix == "cicd-dev" && local.ssm_prefix == "/cicd/dev"
    error_message = "A valid env must give the name prefix and the SSM prefix"
  }
}

run "project_format_rejected" {
  command = plan

  variables {
    project = "Cicd"
  }

  expect_failures = [var.project]
}

run "account_must_match_env" {
  command = plan

  variables {
    env                 = "dev"
    expected_account_id = "222222222222"
  }

  expect_failures = [var.expected_account_id]
}

run "account_unknown_env_rejected" {
  command = plan

  variables {
    env                 = "staging"
    expected_account_id = "111111111111"
  }

  expect_failures = [var.expected_account_id]
}

run "account_matching_env_passes" {
  command = plan

  variables {
    env                 = "sit"
    expected_account_id = "222222222222"
  }

  assert {
    condition     = local.name_prefix == "cicd-sit" && contains(local.accounts_by_env["sit"], var.expected_account_id)
    error_message = "A sit account with env sit must pass"
  }
}

run "account_is_required" {
  command = plan

  variables {
    expected_account_id = null
  }

  expect_failures = [var.expected_account_id]
}

# A default would let a missing tfvars file point at some account silently.
run "account_has_no_default" {
  command = plan

  assert {
    condition     = length(regexall("(?s)variable \"expected_account_id\" \\{[^}]*\\n\\s*default\\s*=", file("${path.module}/common.tf"))) == 0
    error_message = "expected_account_id must not have a default value"
  }
}

run "deploy_role_in_other_account_rejected" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::222222222222:role/deploy"
  }

  expect_failures = [var.deploy_role_arn]
}

run "deploy_role_in_expected_account_passes" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::111111111111:role/deploy"
  }

  assert {
    condition     = var.deploy_role_arn == "arn:aws:iam::111111111111:role/deploy"
    error_message = "A role in the expected account must pass"
  }
}
