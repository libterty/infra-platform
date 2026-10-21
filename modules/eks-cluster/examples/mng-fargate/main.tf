terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.69, < 7.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

# A managed node group for system pods and a Fargate profile for the app namespace.
# Fargate pods cannot use EKS Pod Identity. Give them AWS access with IRSA (iam-oidc-provider and the federated trust of iam-role).
module "eks" {
  source = "../.."

  name               = "alpha-dev"
  kubernetes_version = "1.34"
  subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  kms_key_arn        = "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-2222-3333-4444-555555555555"
  cluster_role_arn   = "arn:aws:iam::111111111111:role/alpha-dev-eks-cluster"

  managed_node_groups = {
    system = {
      node_role_arn  = "arn:aws:iam::111111111111:role/alpha-dev-eks-node"
      instance_types = ["m7i.large"]
      min_size       = 2
      max_size       = 4
      desired_size   = 2
    }
  }

  fargate_profiles = {
    apps = {
      pod_execution_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-eks-fargate"
      subnet_ids             = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
      selectors              = [{ namespace = "apps" }]
    }
  }

  addons = {
    vpc-cni                = { version = "v1.20.0-eksbuild.1" }
    kube-proxy             = { version = "v1.34.0-eksbuild.1" }
    coredns                = { version = "v1.12.0-eksbuild.1" }
    eks-pod-identity-agent = { version = "v1.3.0-eksbuild.1" }
  }

  access_entries = {
    platform = {
      principal_arn = "arn:aws:iam::111111111111:role/alpha-dev-terraform"
      policies = {
        admin = { policy = "AmazonEKSClusterAdminPolicy" }
      }
    }
  }

  tags = {
    Project = "alpha"
  }
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "oidc_issuer_url" {
  value = module.eks.oidc_issuer_url
}
