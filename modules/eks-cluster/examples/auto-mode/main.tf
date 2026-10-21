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

# Auto Mode: AWS runs compute, load balancing and block storage. The four core add-ons and the EBS CSI driver are built in.
module "eks" {
  source = "../.."

  name               = "alpha-sit"
  kubernetes_version = "1.34"
  subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  kms_key_arn        = "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-2222-3333-4444-555555555555"

  # The cluster role needs sts:TagSession as well as sts:AssumeRole in its trust policy for Auto Mode.
  cluster_role_arn = "arn:aws:iam::111111111111:role/alpha-sit-eks-cluster"

  auto_mode = {
    node_role_arn = "arn:aws:iam::111111111111:role/alpha-sit-eks-auto-node"
  }

  addons = {
    metrics-server = { version = "v0.8.0-eksbuild.1" }
  }

  access_entries = {
    platform = {
      principal_arn = "arn:aws:iam::111111111111:role/alpha-sit-terraform"
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
