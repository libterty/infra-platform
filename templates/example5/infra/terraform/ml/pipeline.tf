# The definition lives in templates/example5/ml/pipelines/training.json (design K20): a minimal example that preprocesses,
# trains and registers the model as PendingManualApproval. It has never run on SageMaker. The images are placeholders
# for repositories <name_prefix>-preprocess, -train and -inference in this account (the only ones the iam-base roles
# may pull); replace the file with the export of the SageMaker Python SDK (pipeline.definition()). The ${...} values
# are filled per env here.
locals {
  pipeline = {
    name = "${local.name_prefix}-training"
    definition = templatefile("${path.module}/../../../ml/pipelines/training.json", {
      account_id               = var.expected_account_id
      region                   = var.aws_region
      name_prefix              = local.name_prefix
      ml_bucket                = module.in.strings["ml_bucket_name"]
      role_arn                 = module.in.strings["role_sagemaker_pipeline_arn"]
      model_package_group_name = module.registry.name
    })
    role_arn = module.in.strings["role_sagemaker_pipeline_arn"]
  }
}

module "pipeline" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/sagemaker-pipeline/aws"
  version = "~> 0.1.0"

  name        = local.pipeline.name
  definition  = local.pipeline.definition
  role_arn    = local.pipeline.role_arn
  description = "Weekly training of ${local.name_prefix}"
}
