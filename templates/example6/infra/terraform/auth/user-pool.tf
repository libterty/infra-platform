# Users of the SPA. The SPA is a public client (authorization code with PKCE, no client secret, design D5) served from
# app.<zone> by the web stack; the API checks access tokens for the scopes of the resource server below.
locals {
  app_url = "https://app.${module.in.strings["zone_name"]}"

  # The identifier is the prefix of every scope the SPA asks for (<identifier>/<scope>) and the API requires.
  api_resource_server = "api"

  spa_client = {
    callback_urls = concat(["${local.app_url}/callback"], [for o in var.local_dev_origins : "${o}/callback"])
    logout_urls   = concat(["${local.app_url}/"], [for o in var.local_dev_origins : "${o}/"])
    scopes        = ["openid", "email", "${local.api_resource_server}/read", "${local.api_resource_server}/write"]
  }

  user_pool = {
    name                = "${local.name_prefix}-users"
    user_pool_tier      = "ESSENTIALS"
    mfa                 = "OPTIONAL"
    domain_prefix       = var.domain_prefix
    deletion_protection = var.deletion_protection
    resource_servers = {
      (local.api_resource_server) = {
        name   = "${local.name_prefix}-api"
        scopes = { read = "Read items", write = "Create and change items" }
      }
    }
    clients = { spa = local.spa_client }
  }
}

module "user_pool" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/cognito-user-pool/aws"
  version = "~> 0.1.0"

  name                = local.user_pool.name
  user_pool_tier      = local.user_pool.user_pool_tier
  mfa                 = local.user_pool.mfa
  domain_prefix       = local.user_pool.domain_prefix
  deletion_protection = local.user_pool.deletion_protection
  resource_servers    = local.user_pool.resource_servers
  clients             = local.user_pool.clients
}
