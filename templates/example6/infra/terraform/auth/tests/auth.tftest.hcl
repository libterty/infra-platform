mock_provider "aws" {}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
  domain_prefix       = "example-dev-login"
  local_dev_origins   = ["http://localhost:5173"]
  deletion_protection = false
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["dns/zone_name"]
  values = { insecure_value = "dev.example.com" }
}

run "reads_only_the_zone_name" {
  command = plan

  assert {
    condition     = local.ssm_input_strings == { zone_name = "dns/zone_name" } && local.ssm_input_lists == {}
    error_message = "auth may read only dns/zone_name, to build the app URLs"
  }
}

# Design 8.1: the SPA on app.<zone> plus, in dev, the local dev server.
run "spa_client_urls_follow_the_app_domain" {
  command = plan

  assert {
    condition = (
      local.spa_client.callback_urls == ["https://app.dev.example.com/callback", "http://localhost:5173/callback"] &&
      local.spa_client.logout_urls == ["https://app.dev.example.com/", "http://localhost:5173/"]
    )
    error_message = "The SPA client must call back to app.<zone>/callback and, in dev, to the local dev server"
  }
}

run "sit_has_no_local_urls" {
  command = plan

  variables {
    env                 = "sit"
    expected_account_id = "222222222222"
    local_dev_origins   = []
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["dns/zone_name"]
    values = { insecure_value = "sit.example.com" }
  }

  assert {
    condition = (
      local.spa_client.callback_urls == ["https://app.sit.example.com/callback"] &&
      local.spa_client.logout_urls == ["https://app.sit.example.com/"]
    )
    error_message = "Without local dev origins the client only knows app.<zone>"
  }
}

# Design 8.1: resource server api with read and write; the SPA asks for both plus the OpenID scopes.
run "resource_server_and_scopes" {
  command = plan

  assert {
    condition = (
      keys(local.user_pool.resource_servers) == ["api"] &&
      keys(local.user_pool.resource_servers["api"].scopes) == ["read", "write"]
    )
    error_message = "The resource server must be api with the scopes read and write"
  }

  assert {
    condition     = local.spa_client.scopes == ["openid", "email", "api/read", "api/write"]
    error_message = "The SPA client must ask for openid, email, api/read and api/write"
  }

  assert {
    condition     = keys(local.user_pool.clients) == ["spa"]
    error_message = "auth has exactly one client, the SPA"
  }
}

# Design 8.3: ESSENTIALS with optional TOTP MFA in every env.
run "pool_settings" {
  command = plan

  assert {
    condition = (
      local.user_pool.name == "example-dev-users" &&
      local.user_pool.user_pool_tier == "ESSENTIALS" &&
      local.user_pool.mfa == "OPTIONAL" &&
      local.user_pool.domain_prefix == "example-dev-login" &&
      local.user_pool.deletion_protection == false
    )
    error_message = "The pool must be <name_prefix>-users, ESSENTIALS, MFA OPTIONAL, with the tfvars prefix and deletion protection"
  }
}

run "publishes_exactly_the_auth_keys" {
  command = plan

  override_module {
    target = module.user_pool
    outputs = {
      user_pool_id  = "ap-northeast-1_AbCdEfGhI"
      user_pool_arn = "arn:aws:cognito-idp:ap-northeast-1:111111111111:userpool/ap-northeast-1_AbCdEfGhI"
      issuer_url    = "https://cognito-idp.ap-northeast-1.amazonaws.com/ap-northeast-1_AbCdEfGhI"
      client_ids    = { spa = "1example23456789abcdefghij" }
      hosted_ui_url = "https://example-dev-login.auth.ap-northeast-1.amazoncognito.com"
    }
  }

  assert {
    condition = local.published_strings == {
      issuer_url    = "https://cognito-idp.ap-northeast-1.amazonaws.com/ap-northeast-1_AbCdEfGhI"
      spa_client_id = "1example23456789abcdefghij"
      user_pool_arn = "arn:aws:cognito-idp:ap-northeast-1:111111111111:userpool/ap-northeast-1_AbCdEfGhI"
    }
    error_message = "auth must publish exactly issuer_url, spa_client_id and user_pool_arn (design 8.2)"
  }

  assert {
    condition = module.ssm_publish.names == {
      issuer_url    = "/example/dev/auth/issuer_url"
      spa_client_id = "/example/dev/auth/spa_client_id"
      user_pool_arn = "/example/dev/auth/user_pool_arn"
    }
    error_message = "ssm-publish must write the keys under the auth path"
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
    condition     = local.name_prefix == "example-dev" && local.ssm_prefix == "/example/dev"
    error_message = "A valid env must give the name prefix and the SSM prefix"
  }
}

run "project_format_rejected" {
  command = plan

  variables {
    project = "Example"
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
    condition     = local.name_prefix == "example-sit" && contains(local.accounts_by_env["sit"], var.expected_account_id)
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
