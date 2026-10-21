terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

# EKS Pod Identity role: pods.eks.amazonaws.com needs sts:TagSession as well as sts:AssumeRole.
module "pod_identity" {
  source = "../.."

  name        = "alpha-dev-ebs-csi"
  description = "EBS CSI driver, EKS Pod Identity"

  trust = {
    service_principals = ["pods.eks.amazonaws.com"]
    tag_session        = true
  }

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicyV2",
  ]
}

output "arn" {
  value = module.pod_identity.arn
}
