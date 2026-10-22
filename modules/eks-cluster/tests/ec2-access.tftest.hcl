# EC2 access entries and AmazonEKSAutoNodePolicy (design K4): which policies each entry type may hold.

mock_provider "aws" {
  mock_resource "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:ap-northeast-1:111111111111:cluster/alpha-dev"
      endpoint              = "https://ABCDEF0123456789.gr7.ap-northeast-1.eks.amazonaws.com"
      certificate_authority = [{ data = "Y2VydGlmaWNhdGU=" }]
      identity              = [{ oidc = [{ issuer = "https://oidc.eks.ap-northeast-1.amazonaws.com/id/ABCDEF0123456789" }] }]
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

run "ec2_entry_with_auto_node_policy" {
  command = plan

  assert {
    condition     = aws_eks_access_entry.this["auto_nodes"].type == "EC2"
    error_message = "EC2 type must be passed through"
  }

  assert {
    condition = (
      aws_eks_access_policy_association.this["auto_nodes/node"].policy_arn == "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAutoNodePolicy" &&
      aws_eks_access_policy_association.this["auto_nodes/node"].access_scope[0].type == "cluster"
    )
    error_message = "AmazonEKSAutoNodePolicy must be a cluster scope association with the full policy ARN"
  }
}

run "auto_node_policy_on_standard_rejected" {
  command = plan

  variables {
    access_entries = {
      admin = {
        principal_arn = "arn:aws:iam::111111111111:role/alpha-dev-terraform"
        policies = {
          admin = { policy = "AmazonEKSClusterAdminPolicy" }
          node  = { policy = "AmazonEKSAutoNodePolicy" }
        }
      }
    }
  }

  expect_failures = [var.access_entries]
}

run "auto_node_policy_namespaced_rejected" {
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
        policies = {
          node = { policy = "AmazonEKSAutoNodePolicy", namespaces = ["apps"] }
        }
      }
    }
  }

  expect_failures = [var.access_entries]
}

run "ec2_entry_with_admin_policy_rejected" {
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
        policies = {
          node = { policy = "AmazonEKSClusterAdminPolicy" }
        }
      }
    }
  }

  expect_failures = [var.access_entries]
}

run "ec2_linux_entry_with_policy_still_rejected" {
  command = plan

  variables {
    access_entries = {
      admin = {
        principal_arn = "arn:aws:iam::111111111111:role/alpha-dev-terraform"
        policies = {
          admin = { policy = "AmazonEKSClusterAdminPolicy" }
        }
      }
      nodes = {
        principal_arn = "arn:aws:iam::111111111111:role/alpha-dev-eks-auto-node"
        type          = "EC2_LINUX"
        policies = {
          node = { policy = "AmazonEKSAutoNodePolicy" }
        }
      }
    }
  }

  expect_failures = [var.access_entries]
}
