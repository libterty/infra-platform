# The API Lambda. The execution role (iam stack) has no ECR permissions: Lambda pulls the image with the identity that
# runs this apply, so the image tag must exist in the repository before the apply.
locals {
  api_function = {
    # Must match the naming rule in iam/naming.tf: the role's log permissions are built from this name.
    name                           = "${local.name_prefix}-api"
    image_uri                      = "${module.in.strings["api_repository_url"]}:${var.api_image_tag}"
    role_arn                       = module.in.strings["api_role_arn"]
    architectures                  = ["arm64"]
    memory_size                    = 512
    timeout                        = 10
    reserved_concurrent_executions = var.api_reserved_concurrency
    # The application rejects requests whose origin verify header does not match the secret (design K17); without
    # that check the public execute-api URL bypasses the CloudFront WAF.
    environment = {
      TABLE_NAME                = module.in.strings["table_name"]
      API_SECRET_ARN            = module.in.strings["api_secret_arn"]
      ORIGIN_VERIFY_HEADER_NAME = var.origin_verify_header_name
      ORIGIN_VERIFY_SECRET_ARN  = module.in.strings["origin_verify_secret_arn"]
    }
    permissions = {
      apigateway = {
        principal  = "apigateway.amazonaws.com"
        source_arn = "${module.api.execution_arn}/*/*"
      }
    }
  }
}

module "function" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/lambda-function/aws"
  version = "~> 0.1.1"

  name                           = local.api_function.name
  image_uri                      = local.api_function.image_uri
  role_arn                       = local.api_function.role_arn
  architectures                  = local.api_function.architectures
  memory_size                    = local.api_function.memory_size
  timeout                        = local.api_function.timeout
  reserved_concurrent_executions = local.api_function.reserved_concurrent_executions
  environment                    = local.api_function.environment
  permissions                    = local.api_function.permissions
  log_retention_days             = var.log_retention_days
  log_kms_key_arn                = module.in.strings["kms_key_arn"]
}
