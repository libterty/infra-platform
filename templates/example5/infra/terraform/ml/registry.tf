# <name_prefix>-models: the iam-base pipeline role may register models only to this group (iam-base naming.tf).
module "registry" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/sagemaker-model-registry/aws"
  version = "~> 0.1.0"

  name        = "${local.name_prefix}-models"
  description = "Models of ${local.name_prefix}; new versions wait for manual approval"
}
