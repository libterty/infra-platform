locals {
  ecr_urls = jsondecode(module.shared.strings["ecr_repository_urls"])

  # Extract computes the vectors and load rejects a batch made with another model, so both read the same value. It is
  # not a variable on purpose: changing the model means re-importing everything, which is more than editing a tfvars line.
  embedding_model_id = "amazon.titan-embed-text-v2:0"

  # The bucket name follows the naming rule iam builds its grants from. It is a string here, not a module output, so the
  # functions do not wait for the bucket while the bucket's notifications wait for the functions.
  lambda_s3_invoke = {
    s3_invoke = {
      principal      = "s3.amazonaws.com"
      source_arn     = local.import_bucket_arn
      source_account = var.expected_account_id
    }
  }

  lambdas = {
    "import-extract" = {
      name                           = "${local.name_prefix}-import-extract"
      role_arn                       = module.shared.strings["import_extract_role_arn"]
      image_uri                      = "${local.ecr_urls["import-extract"]}:${var.import_extract_image_tag}"
      memory_size                    = var.import_extract_memory_size
      timeout                        = var.import_extract_timeout
      reserved_concurrent_executions = var.import_extract_reserved_concurrency
      # No database settings: iam gives this role no access to it.
      environment = {
        EMBEDDING_MODEL_ID  = local.embedding_model_id
        EMBEDDING_DIMENSION = "1024"
        IMPORT_BUCKET_NAME  = local.import_bucket_name
      }
      permissions = local.lambda_s3_invoke
    }
    "import-load" = {
      name                           = "${local.name_prefix}-import-load"
      role_arn                       = module.shared.strings["import_load_role_arn"]
      image_uri                      = "${local.ecr_urls["import-load"]}:${var.import_load_image_tag}"
      memory_size                    = var.import_load_memory_size
      timeout                        = var.import_load_timeout
      reserved_concurrent_executions = var.import_load_reserved_concurrency
      environment = {
        EMBEDDING_MODEL_ID = local.embedding_model_id
        IMPORT_BUCKET_NAME = local.import_bucket_name
        DB_HOST            = module.shared.strings["db_proxy_endpoint"]
        DB_NAME            = module.shared.strings["db_name"]
        DB_SSLMODE         = "require"
        DB_SECRET_ARN      = module.shared.strings["db_secret_arn"]
      }
      permissions = local.lambda_s3_invoke
    }
  }
}

module "lambda" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/lambda-function/aws"
  version = "~> 0.1.0"

  for_each = local.lambdas

  name                           = each.value.name
  image_uri                      = each.value.image_uri
  role_arn                       = each.value.role_arn
  memory_size                    = each.value.memory_size
  timeout                        = each.value.timeout
  reserved_concurrent_executions = each.value.reserved_concurrent_executions
  environment                    = each.value.environment
  permissions                    = each.value.permissions
  log_retention_days             = var.lambda_log_retention_days

  vpc = {
    subnet_ids         = module.shared.lists["app_subnet_ids"]
    security_group_ids = [module.shared.strings["app_sg_id"]]
  }

  # Text, the default, on purpose: the metric filters below match the JSON lines the application writes itself, and the
  # JSON log format would wrap every line in another envelope.
  log_format = "Text"
}
