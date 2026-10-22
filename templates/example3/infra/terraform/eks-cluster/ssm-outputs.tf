# The versioned EKS contract (design v4 §8.1). Other projects sharing the cluster read these keys directly, without
# bridge. Bump contract_version only when a key is removed or its meaning changes; adding a key keeps the version.
locals {
  contract_version = "1"

  published_strings = {
    contract_version       = local.contract_version
    cluster_name           = module.eks.cluster_name
    cluster_endpoint       = module.eks.endpoint
    cluster_ca_data        = module.eks.certificate_authority_data
    cluster_sg_id          = module.eks.cluster_security_group_id
    service_cidr           = module.eks.service_ipv4_cidr
    app_namespace          = var.app_namespace
    api_service_account    = var.api_service_account
    worker_service_account = var.worker_service_account
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.0"

  ssm_prefix = local.ssm_prefix
  stack      = "eks-cluster"
  strings    = local.published_strings
}
