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

# Roles come from the iam stack (built with iam-role); this module only takes their ARNs.
module "eks" {
  source = "../.."

  name               = "alpha-dev"
  kubernetes_version = "1.34"
  subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  kms_key_arn        = "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-2222-3333-4444-555555555555"
  cluster_role_arn   = "arn:aws:iam::111111111111:role/alpha-dev-eks-cluster"

  # A small managed node group runs Karpenter itself and the core add-ons; Karpenter provisions everything else.
  managed_node_groups = {
    system = {
      node_role_arn  = "arn:aws:iam::111111111111:role/alpha-dev-eks-node"
      ami_type       = "AL2023_ARM_64_STANDARD"
      instance_types = ["m7g.large"]
      min_size       = 2
      max_size       = 3
      desired_size   = 2
      taints         = [{ key = "CriticalAddonsOnly", effect = "NO_SCHEDULE" }]
    }
  }

  # The Karpenter node role must be a different role from the managed node group role.
  karpenter = {
    node_role_arn       = "arn:aws:iam::111111111111:role/alpha-dev-karpenter-node"
    controller_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-karpenter-controller"
  }

  addons = {
    vpc-cni                = { version = "v1.20.0-eksbuild.1" }
    kube-proxy             = { version = "v1.34.0-eksbuild.1" }
    coredns                = { version = "v1.12.0-eksbuild.1" }
    eks-pod-identity-agent = { version = "v1.3.0-eksbuild.1" }
    metrics-server         = { version = "v0.8.0-eksbuild.1" }
    aws-ebs-csi-driver = {
      version               = "v1.50.0-eksbuild.1"
      pod_identity_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-ebs-csi"
      service_account       = "ebs-csi-controller-sa"
    }
  }

  access_entries = {
    # The role that runs terraform apply. Without a cluster scope AmazonEKSClusterAdminPolicy the module refuses to plan.
    platform = {
      principal_arn = "arn:aws:iam::111111111111:role/alpha-dev-terraform"
      policies = {
        admin = { policy = "AmazonEKSClusterAdminPolicy" }
      }
    }
    # CI deploys Helm releases into two namespaces. Its IAM role only needs eks:DescribeCluster.
    ci = {
      principal_arn = "arn:aws:iam::111111111111:role/alpha-dev-ci-deploy"
      policies = {
        apps = { policy = "AmazonEKSEditPolicy", namespaces = ["apps", "batch"] }
      }
    }
  }

  pod_identity_associations = {
    lb-controller = {
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
      role_arn        = "arn:aws:iam::111111111111:role/alpha-dev-lb-controller"
    }
  }

  tags = {
    Project = "alpha"
  }
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "karpenter_interruption_queue_name" {
  value = module.eks.karpenter_interruption_queue_name
}
