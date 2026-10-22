# Auto Mode without built-in node pools and without a node role at cluster creation (design K4, C1-4), plus the
# service_ipv4_cidr output. The node role comes later from an EC2 access entry with AmazonEKSAutoNodePolicy.

mock_provider "aws" {
  mock_resource "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:ap-northeast-1:111111111111:cluster/alpha-dev"
      endpoint              = "https://ABCDEF0123456789.gr7.ap-northeast-1.eks.amazonaws.com"
      certificate_authority = [{ data = "Y2VydGlmaWNhdGU=" }]
      identity              = [{ oidc = [{ issuer = "https://oidc.eks.ap-northeast-1.amazonaws.com/id/ABCDEF0123456789" }] }]
      kubernetes_network_config = {
        service_ipv4_cidr = "172.20.0.0/16"
      }
    }
  }
}

variables {
  name               = "alpha-dev"
  kubernetes_version = "1.34"
  subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  kms_key_arn        = "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-2222-3333-4444-555555555555"
  cluster_role_arn   = "arn:aws:iam::111111111111:role/alpha-dev-eks-cluster"

  auto_mode = {
    node_pools = []
  }

  access_entries = {
    admin = {
      principal_arn = "arn:aws:iam::111111111111:role/alpha-dev-terraform"
      policies = {
        admin = { policy = "AmazonEKSClusterAdminPolicy" }
      }
    }
    auto_nodes = {
      principal_arn = "arn:aws:iam::111111111111:role/alpha-dev-eks-auto-node"
      type          = "EC2"
      policies = {
        node = { policy = "AmazonEKSAutoNodePolicy" }
      }
    }
  }
}

run "auto_mode_without_node_role_and_pools" {
  command = plan

  assert {
    condition     = aws_eks_cluster.this.compute_config[0].enabled == true && aws_eks_cluster.this.compute_config[0].node_role_arn == null
    error_message = "Auto Mode must be enabled with a null node_role_arn"
  }

  assert {
    condition     = length(aws_eks_cluster.this.compute_config[0].node_pools) == 0
    error_message = "node_pools must be empty"
  }
}

run "auto_mode_pools_without_role_rejected" {
  command = plan

  variables {
    auto_mode = {}
  }

  expect_failures = [var.auto_mode]
}

run "auto_mode_invalid_role_rejected" {
  command = plan

  variables {
    auto_mode = {
      node_role_arn = "not-an-arn"
      node_pools    = []
    }
  }

  expect_failures = [var.auto_mode]
}

run "auto_mode_role_with_empty_pools_still_works" {
  command = plan

  variables {
    auto_mode = {
      node_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-eks-auto-node"
      node_pools    = []
    }
  }

  assert {
    condition     = aws_eks_cluster.this.compute_config[0].node_role_arn == "arn:aws:iam::111111111111:role/alpha-dev-eks-auto-node"
    error_message = "A given node role must still be sent"
  }
}

run "empty_pools_without_auto_node_entry_rejected" {
  command = plan

  variables {
    access_entries = {
      admin = {
        principal_arn = "arn:aws:iam::111111111111:role/alpha-dev-terraform"
        policies = {
          admin = { policy = "AmazonEKSClusterAdminPolicy" }
        }
      }
    }
  }

  expect_failures = [aws_eks_cluster.this]
}

run "empty_pools_with_ec2_entry_but_no_policy_rejected" {
  command = plan

  variables {
    access_entries = {
      admin = {
        principal_arn = "arn:aws:iam::111111111111:role/alpha-dev-terraform"
        policies = {
          admin = { policy = "AmazonEKSClusterAdminPolicy" }
        }
      }
      auto_nodes = {
        principal_arn = "arn:aws:iam::111111111111:role/alpha-dev-eks-auto-node"
        type          = "EC2"
      }
    }
  }

  expect_failures = [aws_eks_cluster.this]
}

run "service_cidr_output" {
  command = apply

  assert {
    condition     = output.service_ipv4_cidr == "172.20.0.0/16"
    error_message = "service_ipv4_cidr must expose the cluster service CIDR"
  }
}
