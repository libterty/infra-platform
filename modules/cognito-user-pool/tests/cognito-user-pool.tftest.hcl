mock_provider "aws" {
  override_data {
    target = data.aws_region.current
    values = { region = "ap-northeast-1" }
  }
}

override_resource {
  target = aws_cognito_user_pool.this
  values = {
    id  = "ap-northeast-1_AbCdEfGhI"
    arn = "arn:aws:cognito-idp:ap-northeast-1:111111111111:userpool/ap-northeast-1_AbCdEfGhI"
  }
}

override_resource {
  target = aws_cognito_user_pool_client.this["spa"]
  values = {
    id = "1example23456789"
  }
}

variables {
  name          = "alpha-dev-users"
  domain_prefix = "alpha-dev-login"

  resource_servers = {
    alpha = {
      name   = "alpha-api"
      scopes = { "items.read" = "Read items", "items.write" = "Write items" }
    }
  }

  clients = {
    spa = {
      callback_urls = ["https://app.dev.example.com/callback", "http://localhost:5173/callback"]
      logout_urls   = ["https://app.dev.example.com/"]
      scopes        = ["openid", "email", "alpha/items.read"]
    }
  }
}

# ---- positive -------------------------------------------------------------------------------------------------

run "user_pool_defaults" {
  command = plan

  assert {
    condition     = aws_cognito_user_pool.this.name == "alpha-dev-users" && aws_cognito_user_pool.this.user_pool_tier == "ESSENTIALS"
    error_message = "The pool must keep its name and default to the ESSENTIALS tier"
  }

  assert {
    condition     = aws_cognito_user_pool.this.deletion_protection == "ACTIVE"
    error_message = "Deletion protection must be on by default"
  }

  assert {
    condition     = aws_cognito_user_pool.this.username_attributes == toset(["email"]) && aws_cognito_user_pool.this.auto_verified_attributes == toset(["email"])
    error_message = "Users sign in with email by default and email is auto-verified"
  }

  assert {
    condition     = aws_cognito_user_pool.this.admin_create_user_config[0].allow_admin_create_user_only == true
    error_message = "Self sign-up must be off by default"
  }

  assert {
    condition     = aws_cognito_user_pool.this.mfa_configuration == "OPTIONAL" && aws_cognito_user_pool.this.software_token_mfa_configuration[0].enabled == true
    error_message = "MFA must default to OPTIONAL with TOTP"
  }

  assert {
    condition     = aws_cognito_user_pool.this.password_policy[0].minimum_length == 12 && aws_cognito_user_pool.this.password_policy[0].require_lowercase && aws_cognito_user_pool.this.password_policy[0].require_uppercase && aws_cognito_user_pool.this.password_policy[0].require_numbers
    error_message = "The password policy must default to 12 chars with upper, lower and digits"
  }

  assert {
    condition     = aws_cognito_user_pool.this.email_configuration[0].email_sending_account == "COGNITO_DEFAULT"
    error_message = "Email must be sent with the Cognito default account"
  }

  assert {
    condition     = length(aws_cognito_user_pool.this.account_recovery_setting[0].recovery_mechanism) == 1 && one(aws_cognito_user_pool.this.account_recovery_setting[0].recovery_mechanism).name == "verified_email"
    error_message = "Account recovery must only use a verified email"
  }
}

run "mfa_off_disables_totp" {
  command = plan

  variables {
    mfa = "OFF"
  }

  assert {
    condition     = aws_cognito_user_pool.this.mfa_configuration == "OFF" && length(aws_cognito_user_pool.this.software_token_mfa_configuration) == 0
    error_message = "MFA OFF must not configure TOTP"
  }
}

run "deletion_protection_can_be_turned_off" {
  command = plan

  variables {
    deletion_protection = false
  }

  assert {
    condition     = aws_cognito_user_pool.this.deletion_protection == "INACTIVE"
    error_message = "deletion_protection = false must map to INACTIVE"
  }
}

run "public_spa_client_with_code_flow" {
  command = plan

  assert {
    condition     = aws_cognito_user_pool_client.this["spa"].generate_secret == false
    error_message = "Clients must never have a secret"
  }

  assert {
    condition     = aws_cognito_user_pool_client.this["spa"].allowed_oauth_flows == toset(["code"]) && aws_cognito_user_pool_client.this["spa"].allowed_oauth_flows_user_pool_client == true
    error_message = "Clients must only use the authorization code flow"
  }

  assert {
    condition     = aws_cognito_user_pool_client.this["spa"].explicit_auth_flows == toset(["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"])
    error_message = "Only SRP and refresh token auth flows are allowed"
  }

  assert {
    condition     = aws_cognito_user_pool_client.this["spa"].prevent_user_existence_errors == "ENABLED" && aws_cognito_user_pool_client.this["spa"].enable_token_revocation == true
    error_message = "User existence errors must be hidden and token revocation enabled"
  }

  assert {
    condition     = aws_cognito_user_pool_client.this["spa"].supported_identity_providers == toset(["COGNITO"])
    error_message = "Only the Cognito user pool identity provider is supported"
  }

  assert {
    condition     = aws_cognito_user_pool_client.this["spa"].allowed_oauth_scopes == toset(["openid", "email", "alpha/items.read"])
    error_message = "Scopes must be passed through"
  }

  assert {
    condition     = aws_cognito_user_pool_client.this["spa"].callback_urls == toset(["https://app.dev.example.com/callback", "http://localhost:5173/callback"]) && aws_cognito_user_pool_client.this["spa"].logout_urls == toset(["https://app.dev.example.com/"])
    error_message = "Callback and logout URLs must be passed through"
  }

  assert {
    condition = (
      aws_cognito_user_pool_client.this["spa"].access_token_validity == 60 &&
      aws_cognito_user_pool_client.this["spa"].id_token_validity == 60 &&
      aws_cognito_user_pool_client.this["spa"].refresh_token_validity == 30 &&
      aws_cognito_user_pool_client.this["spa"].token_validity_units[0].access_token == "minutes" &&
      aws_cognito_user_pool_client.this["spa"].token_validity_units[0].id_token == "minutes" &&
      aws_cognito_user_pool_client.this["spa"].token_validity_units[0].refresh_token == "days"
    )
    error_message = "Token validity must default to 60 minutes, 60 minutes and 30 days with explicit units"
  }
}

run "resource_server_and_domain" {
  command = plan

  assert {
    condition     = aws_cognito_resource_server.this["alpha"].identifier == "alpha" && aws_cognito_resource_server.this["alpha"].name == "alpha-api"
    error_message = "The resource server must use the key as identifier"
  }

  assert {
    condition     = length(aws_cognito_resource_server.this["alpha"].scope) == 2 && contains([for s in aws_cognito_resource_server.this["alpha"].scope : s.scope_name], "items.read")
    error_message = "Resource server scopes must be passed through"
  }

  assert {
    condition     = aws_cognito_user_pool_domain.this.domain == "alpha-dev-login"
    error_message = "The prefix domain must use domain_prefix"
  }
}

run "outputs" {
  command = apply

  assert {
    condition     = output.user_pool_id == "ap-northeast-1_AbCdEfGhI" && output.user_pool_arn == "arn:aws:cognito-idp:ap-northeast-1:111111111111:userpool/ap-northeast-1_AbCdEfGhI"
    error_message = "user_pool_id and user_pool_arn must come from the pool"
  }

  assert {
    condition     = output.issuer_url == "https://cognito-idp.ap-northeast-1.amazonaws.com/ap-northeast-1_AbCdEfGhI"
    error_message = "issuer_url must be the Cognito issuer of the pool"
  }

  assert {
    condition     = output.client_ids == { spa = "1example23456789" }
    error_message = "client_ids must map client keys to ids"
  }

  assert {
    condition     = output.hosted_ui_url == "https://alpha-dev-login.auth.ap-northeast-1.amazoncognito.com"
    error_message = "hosted_ui_url must be the prefix domain URL"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "http_callback_not_localhost_rejected" {
  command = plan

  variables {
    clients = {
      spa = {
        callback_urls = ["http://app.dev.example.com/callback"]
        scopes        = ["openid"]
      }
    }
  }

  expect_failures = [var.clients]
}

run "http_logout_not_localhost_rejected" {
  command = plan

  variables {
    clients = {
      spa = {
        callback_urls = ["https://app.dev.example.com/callback"]
        logout_urls   = ["http://localhost.example.com/"]
        scopes        = ["openid"]
      }
    }
  }

  expect_failures = [var.clients]
}

run "empty_callback_urls_rejected" {
  command = plan

  variables {
    clients = {
      spa = {
        callback_urls = []
        scopes        = ["openid"]
      }
    }
  }

  expect_failures = [var.clients]
}

run "unknown_resource_server_scope_rejected" {
  command = plan

  variables {
    clients = {
      spa = {
        callback_urls = ["https://app.dev.example.com/callback"]
        scopes        = ["openid", "alpha/items.delete"]
      }
    }
  }

  expect_failures = [var.clients]
}

run "unknown_standard_scope_rejected" {
  command = plan

  variables {
    clients = {
      spa = {
        callback_urls = ["https://app.dev.example.com/callback"]
        scopes        = ["phone"]
      }
    }
  }

  expect_failures = [var.clients]
}

run "access_token_below_5_minutes_rejected" {
  command = plan

  variables {
    clients = {
      spa = {
        callback_urls        = ["https://app.dev.example.com/callback"]
        scopes               = ["openid"]
        access_token_minutes = 4
      }
    }
  }

  expect_failures = [var.clients]
}

run "id_token_above_one_day_rejected" {
  command = plan

  variables {
    clients = {
      spa = {
        callback_urls    = ["https://app.dev.example.com/callback"]
        scopes           = ["openid"]
        id_token_minutes = 1441
      }
    }
  }

  expect_failures = [var.clients]
}

run "refresh_token_above_ten_years_rejected" {
  command = plan

  variables {
    clients = {
      spa = {
        callback_urls      = ["https://app.dev.example.com/callback"]
        scopes             = ["openid"]
        refresh_token_days = 3651
      }
    }
  }

  expect_failures = [var.clients]
}

run "domain_prefix_with_cognito_rejected" {
  command = plan

  variables {
    domain_prefix = "alpha-cognito-login"
  }

  expect_failures = [var.domain_prefix]
}

run "domain_prefix_with_aws_rejected" {
  command = plan

  variables {
    domain_prefix = "alpha-aws-login"
  }

  expect_failures = [var.domain_prefix]
}

run "domain_prefix_upper_case_rejected" {
  command = plan

  variables {
    domain_prefix = "Alpha-Login"
  }

  expect_failures = [var.domain_prefix]
}

run "unknown_tier_rejected" {
  command = plan

  variables {
    user_pool_tier = "ENTERPRISE"
  }

  expect_failures = [var.user_pool_tier]
}

run "unknown_mfa_rejected" {
  command = plan

  variables {
    mfa = "SMS"
  }

  expect_failures = [var.mfa]
}

run "short_password_rejected" {
  command = plan

  variables {
    password_policy = { minimum_length = 8 }
  }

  expect_failures = [var.password_policy]
}

run "unknown_sign_in_attribute_rejected" {
  command = plan

  variables {
    sign_in_attributes = ["preferred_username"]
  }

  expect_failures = [var.sign_in_attributes]
}

run "resource_server_scope_with_slash_rejected" {
  command = plan

  variables {
    resource_servers = {
      alpha = {
        name   = "alpha-api"
        scopes = { "items/read" = "Read items" }
      }
    }
    clients = {
      spa = {
        callback_urls = ["https://app.dev.example.com/callback"]
        scopes        = ["openid"]
      }
    }
  }

  expect_failures = [var.resource_servers]
}
