# HTTP API behind the single CloudFront distribution of the web stack (design K16): every route sits under /api/,
# CloudFront uses the execute-api URL as origin, so that URL stays enabled and there is no custom domain. Same origin
# as the SPA, so no CORS.
locals {
  # Routes are never public by default (design K12): each one names the authorizer or says public = true.
  api_routes = {
    "GET /api/health" = { integration = "function", authorizer = null, scopes = [], public = true }
    "GET /api/items"  = { integration = "function", authorizer = "cognito", scopes = ["${local.api_scope_prefix}/read"], public = false }
    "POST /api/items" = { integration = "function", authorizer = "cognito", scopes = ["${local.api_scope_prefix}/write"], public = false }
  }

  # The resource server identifier of the auth stack.
  api_scope_prefix = "api"

  api = {
    name = "${local.name_prefix}-api"
    jwt_authorizers = {
      cognito = {
        issuer   = module.in.strings["issuer_url"]
        audience = [module.in.strings["spa_client_id"]]
      }
    }
    throttling                   = var.api_throttling
    disable_execute_api_endpoint = false
  }

  access_log_group = {
    name           = "/aws/apigateway/${local.name_prefix}-api-access"
    retention_days = var.log_retention_days
    kms_key_arn    = module.in.strings["kms_key_arn"]
  }
}

module "access_log_group" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/log-group/aws"
  version = "~> 0.1.1"

  name           = local.access_log_group.name
  retention_days = local.access_log_group.retention_days
  kms_key_arn    = local.access_log_group.kms_key_arn
}

module "api" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/apigateway-http/aws"
  version = "~> 0.1.0"

  name            = local.api.name
  jwt_authorizers = local.api.jwt_authorizers
  integrations = {
    function = { lambda_arn = module.function.function_arn }
  }
  routes                       = local.api_routes
  throttling                   = local.api.throttling
  access_log_group_arn         = module.access_log_group.arn
  disable_execute_api_endpoint = local.api.disable_execute_api_endpoint
}
