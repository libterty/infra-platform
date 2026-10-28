data "aws_region" "current" {}

resource "aws_cognito_user_pool" "this" {
  name                     = var.name
  user_pool_tier           = var.user_pool_tier
  deletion_protection      = var.deletion_protection ? "ACTIVE" : "INACTIVE"
  username_attributes      = var.sign_in_attributes
  auto_verified_attributes = contains(var.sign_in_attributes, "email") ? ["email"] : []

  mfa_configuration = var.mfa

  dynamic "software_token_mfa_configuration" {
    for_each = var.mfa == "OFF" ? [] : [true]
    content {
      enabled = true
    }
  }

  admin_create_user_config {
    allow_admin_create_user_only = var.admin_create_user_only
  }

  password_policy {
    minimum_length                   = var.password_policy.minimum_length
    require_lowercase                = var.password_policy.require_lowercase
    require_uppercase                = var.password_policy.require_uppercase
    require_numbers                  = var.password_policy.require_numbers
    require_symbols                  = var.password_policy.require_symbols
    temporary_password_validity_days = var.password_policy.temporary_password_validity_days
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # SES is out of scope; the default account has a low daily sending quota.
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  username_configuration {
    case_sensitive = false
  }

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_cognito_user_pool_domain" "this" {
  domain       = var.domain_prefix
  user_pool_id = aws_cognito_user_pool.this.id
}

resource "aws_cognito_resource_server" "this" {
  for_each = var.resource_servers

  user_pool_id = aws_cognito_user_pool.this.id
  identifier   = each.key
  name         = each.value.name

  dynamic "scope" {
    for_each = each.value.scopes
    content {
      scope_name        = scope.key
      scope_description = scope.value
    }
  }
}

resource "aws_cognito_user_pool_client" "this" {
  for_each = var.clients

  name         = each.key
  user_pool_id = aws_cognito_user_pool.this.id

  # Public clients only (browser or mobile apps with PKCE); a secret would end up in state.
  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = each.value.scopes
  supported_identity_providers         = ["COGNITO"]
  callback_urls                        = each.value.callback_urls
  logout_urls                          = each.value.logout_urls

  explicit_auth_flows           = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true

  access_token_validity  = each.value.access_token_minutes
  id_token_validity      = each.value.id_token_minutes
  refresh_token_validity = each.value.refresh_token_days

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  # Custom scopes must exist before a client can request them.
  depends_on = [aws_cognito_resource_server.this]
}
