terraform {
  required_version = ">= 1.10"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0, < 4.0"
    }
  }
}

locals {
  cluster_name = "alpha-dev"
  region       = "ap-northeast-1"

  # In a real stack these come from the eks-cluster stack (remote state or a data source), after its apply.
  cluster_endpoint = "https://ABCDEF0123456789.gr7.ap-northeast-1.eks.amazonaws.com"
  cluster_ca_data  = "Y2VydGlmaWNhdGU="
}

# exec runs aws eks get-token on every call, so the token never expires in the middle of a long apply.
# Do not set token next to exec, and do not use the token of aws_eks_cluster_auth: it lives for 15 minutes.
provider "helm" {
  kubernetes = {
    host                   = local.cluster_endpoint
    cluster_ca_certificate = base64decode(local.cluster_ca_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", local.region]
    }
  }
}

module "eks_addons" {
  source = "../.."

  cluster_name = local.cluster_name
  region       = local.region
  vpc_id       = "vpc-0123456789abcdef0"

  # Roles and Pod Identity associations for the three controllers are made outside this module (iam-role, eks-cluster).
  load_balancer_controller = {}

  karpenter = {
    interruption_queue_name = "alpha-dev" # eks-cluster output karpenter_interruption_queue_name

    default_node_class = {
      node_role_name               = "alpha-dev-karpenter-node"
      subnet_discovery_tag         = { "karpenter.sh/discovery" = "alpha-dev" }
      security_group_discovery_tag = { "karpenter.sh/discovery" = "alpha-dev" }
    }
    default_node_pool = {}
  }

  argo_rollouts = {}

  # A CI role with the Edit access policy cannot create namespaces, so they are created here.
  app_namespaces = {
    apps  = { labels = { team = "platform" } }
    batch = {}
  }
}

output "releases" {
  value = module.eks_addons.releases
}
