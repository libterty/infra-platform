# The fn function (design 8.1, D6, D9). The pipeline deploys it by publishing a version and moving the alias; Terraform
# only creates it with the bootstrap image. The execution role has no ECR permissions: Lambda pulls the image with the
# identity that runs this apply, so the bootstrap image must be in the repository first (K10).
locals {
  fn_function = {
    # Must match iam/naming.tf: the fn-build role and the pipeline's Lambda deploy action are scoped to this name,
    # and the role's log permissions to /aws/lambda/<name>.
    name             = "${local.name_prefix}-fn"
    image_uri        = "${module.in.strings["fn_repository_url"]}:${var.fn_bootstrap_image_tag}"
    role_arn         = module.in.strings["fn_role_arn"]
    architectures    = ["arm64"]
    memory_size      = var.fn_memory_size
    timeout          = var.fn_timeout
    alias            = "live"
    pipeline_managed = true
  }
}

module "fn" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/lambda-function/aws"
  version = "~> 0.2.0"

  name               = local.fn_function.name
  image_uri          = local.fn_function.image_uri
  role_arn           = local.fn_function.role_arn
  architectures      = local.fn_function.architectures
  memory_size        = local.fn_function.memory_size
  timeout            = local.fn_function.timeout
  alias              = local.fn_function.alias
  pipeline_managed   = local.fn_function.pipeline_managed
  log_retention_days = var.log_retention_days
  log_kms_key_arn    = module.in.strings["kms_key_arn"]
}
