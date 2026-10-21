# Access: access entries, access policy associations, the cluster admin requirement (design J3) and Pod Identity associations.

mock_provider "aws" {
  mock_resource "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:ap-northeast-1:111111111111:cluster/alpha-dev"
      endpoint              = "https://ABCDEF0123456789.gr7.ap-northeast-1.eks.amazonaws.com"
      certificate_authority = [{ data = "Y2VydGlmaWNhdGU=" }]
      identity              = [{ oidc = [{ issuer = "https://oidc.eks.ap-northeast-1.amazonaws.com/id/ABCDEF0123456789" }] }]
    }
  }

  mock_resource "aws_launch_template" {
    defaults = {
      id             = "lt-0123456789abcdef0"
      latest_version = 1
    }
  }
}

variables {
  name               = "alpha-dev"
  kubernetes_version = "1.34"
  subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  kms_key_arn        = "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-2222-3333-4444-555555555555"
  cluster_role_arn   = "arn:aws:iam::111111111111:role/alpha-dev-eks-cluster"

  managed_node_groups = {
    system = {
      node_role_arn  = "arn:aws:iam::111111111111:role/alpha-dev-eks-node"
      instance_types = ["m7i.large"]
      min_size       = 1
      max_size       = 3
      desired_size   = 2
    }
  }

  addons = {
    vpc-cni                = { version = "v1.20.0-eksbuild.1" }
    kube-proxy             = { version = "v1.34.0-eksbuild.1" }
    coredns                = { version = "v1.12.0-eksbuild.1" }
    eks-pod-identity-agent = { version = "v1.3.0-eksbuild.1" }
  }

  access_entries = {
    admin = {
      principal_arn = "arn:aws:iam::111111111111:role/alpha-dev-terraform"
      policies = {
        admin = { policy = "AmazonEKSClusterAdminPolicy" }
      }
    }
  }
}

run "admin_entry_creates_entry_and_association" {
  command = plan

  assert {
    condition = (
      aws_eks_access_entry.this["admin"].cluster_name == "alpha-dev" &&
      aws_eks_access_entry.this["admin"].principal_arn == "arn:aws:iam::111111111111:role/alpha-dev-terraform" &&
      aws_eks_access_entry.this["admin"].type == "STANDARD"
    )
    error_message = "Access entry must follow the input and default to STANDARD"
  }

  assert {
    condition = (
      aws_eks_access_policy_association.this["admin/admin"].policy_arn == "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" &&
      aws_eks_access_policy_association.this["admin/admin"].principal_arn == "arn:aws:iam::111111111111:role/alpha-dev-terraform" &&
      aws_eks_access_policy_association.this["admin/admin"].access_scope[0].type == "cluster" &&
      aws_eks_access_policy_association.this["admin/admin"].access_scope[0].namespaces == null
    )
    error_message = "Empty namespaces must become a cluster scope association"
  }
}

run "namespace_scoped_policy" {
  command = plan

  variables {
    access_entries = {
      admin = {
        principal_arn = "arn:aws:iam::111111111111:role/alpha-dev-terraform"
        policies = {
          admin = { policy = "AmazonEKSClusterAdminPolicy" }
        }
      }
      ci = {
        principal_arn = "arn:aws:iam::111111111111:role/alpha-dev-ci-deploy"
        policies = {
          edit = { policy = "AmazonEKSEditPolicy", namespaces = ["apps", "batch"] }
          view = { policy = "AmazonEKSViewPolicy" }
        }
      }
    }
  }

  assert {
    condition = (
      aws_eks_access_policy_association.this["ci/edit"].policy_arn == "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy" &&
      aws_eks_access_policy_association.this["ci/edit"].access_scope[0].type == "namespace" &&
      aws_eks_access_policy_association.this["ci/edit"].access_scope[0].namespaces == toset(["apps", "batch"])
    )
    error_message = "Namespaces must become a namespace scope association"
  }

  assert {
    condition     = aws_eks_access_policy_association.this["ci/view"].access_scope[0].type == "cluster"
    error_message = "A policy without namespaces is cluster scope"
  }

  assert {
    condition     = length(aws_eks_access_entry.this) == 2 && length(aws_eks_access_policy_association.this) == 3
    error_message = "Two entries and three associations"
  }
}

run "all_whitelisted_policies_are_accepted" {
  command = plan

  variables {
    access_entries = {
      admin = {
        principal_arn = "arn:aws:iam::111111111111:role/alpha-dev-terraform"
        policies = {
          cluster_admin = { policy = "AmazonEKSClusterAdminPolicy" }
          admin         = { policy = "AmazonEKSAdminPolicy", namespaces = ["apps"] }
          edit          = { policy = "AmazonEKSEditPolicy", namespaces = ["apps"] }
          view          = { policy = "AmazonEKSViewPolicy", namespaces = ["apps"] }
          admin_view    = { policy = "AmazonEKSAdminViewPolicy", namespaces = ["apps"] }
        }
      }
    }
  }

  assert {
    condition     = length(aws_eks_access_policy_association.this) == 5
    error_message = "All five whitelisted policies must be accepted"
  }
}

run "entry_without_policies_is_allowed_for_another_principal" {
  command = plan

  variables {
    access_entries = {
      admin = {
        principal_arn = "arn:aws:iam::111111111111:role/alpha-dev-terraform"
        policies = {
          admin = { policy = "AmazonEKSClusterAdminPolicy" }
        }
      }
      groups_only = {
        principal_arn = "arn:aws:iam::111111111111:user/someone"
      }
    }
  }

  assert {
    condition     = length(aws_eks_access_entry.this) == 2 && length(aws_eks_access_policy_association.this) == 1
    error_message = "An entry without policies has no association"
  }
}

run "no_access_entries_rejected" {
  command = plan

  variables {
    access_entries = {}
  }

  expect_failures = [var.access_entries]
}

run "no_cluster_admin_rejected" {
  command = plan

  variables {
    access_entries = {
      ci = {
        principal_arn = "arn:aws:iam::111111111111:role/alpha-dev-ci-deploy"
        policies = {
          edit = { policy = "AmazonEKSEditPolicy", namespaces = ["apps"] }
        }
      }
    }
  }

  expect_failures = [var.access_entries]
}

run "namespace_scoped_cluster_admin_is_not_enough" {
  command = plan

  variables {
    access_entries = {
      admin = {
        principal_arn = "arn:aws:iam::111111111111:role/alpha-dev-terraform"
        policies = {
          admin = { policy = "AmazonEKSClusterAdminPolicy", namespaces = ["apps"] }
        }
      }
    }
  }

  expect_failures = [var.access_entries]
}

run "cluster_scope_admin_policy_is_not_cluster_admin" {
  command = plan

  variables {
    access_entries = {
      admin = {
        principal_arn = "arn:aws:iam::111111111111:role/alpha-dev-terraform"
        policies = {
          admin = { policy = "AmazonEKSAdminPolicy" }
        }
      }
    }
  }

  expect_failures = [var.access_entries]
}

run "unknown_policy_rejected" {
  command = plan

  variables {
    access_entries = {
      admin = {
        principal_arn = "arn:aws:iam::111111111111:role/alpha-dev-terraform"
        policies = {
          admin = { policy = "AmazonEKSClusterAdminPolicy" }
          extra = { policy = "AmazonEKSAutoNodePolicy" }
        }
      }
    }
  }

  expect_failures = [var.access_entries]
}

run "policy_given_as_arn_rejected" {
  command = plan

  variables {
    access_entries = {
      admin = {
        principal_arn = "arn:aws:iam::111111111111:role/alpha-dev-terraform"
        policies = {
          admin = { policy = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" }
        }
      }
    }
  }

  expect_failures = [var.access_entries]
}

run "unknown_entry_type_rejected" {
  command = plan

  variables {
    access_entries = {
      admin = {
        principal_arn = "arn:aws:iam::111111111111:role/alpha-dev-terraform"
        policies = {
          admin = { policy = "AmazonEKSClusterAdminPolicy" }
        }
      }
      odd = {
        principal_arn = "arn:aws:iam::111111111111:role/alpha-dev-odd"
        type          = "WINDOWS"
      }
    }
  }

  expect_failures = [var.access_entries]
}

run "policies_on_non_standard_entry_rejected" {
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
        principal_arn = "arn:aws:iam::111111111111:role/alpha-dev-self-managed-node"
        type          = "EC2_LINUX"
        policies = {
          view = { policy = "AmazonEKSViewPolicy" }
        }
      }
    }
  }

  expect_failures = [var.access_entries]
}

run "non_standard_entry_without_policies_is_allowed" {
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
        principal_arn = "arn:aws:iam::111111111111:role/alpha-dev-self-managed-node"
        type          = "EC2_LINUX"
      }
    }
  }

  assert {
    condition     = aws_eks_access_entry.this["nodes"].type == "EC2_LINUX"
    error_message = "EC2_LINUX entries are allowed without policies"
  }
}

run "principal_must_be_a_role_or_user_arn" {
  command = plan

  variables {
    access_entries = {
      admin = {
        principal_arn = "alpha-dev-terraform"
        policies = {
          admin = { policy = "AmazonEKSClusterAdminPolicy" }
        }
      }
    }
  }

  expect_failures = [var.access_entries]
}

run "bad_namespace_rejected" {
  command = plan

  variables {
    access_entries = {
      admin = {
        principal_arn = "arn:aws:iam::111111111111:role/alpha-dev-terraform"
        policies = {
          admin = { policy = "AmazonEKSClusterAdminPolicy" }
          edit  = { policy = "AmazonEKSEditPolicy", namespaces = ["Apps"] }
        }
      }
    }
  }

  expect_failures = [var.access_entries]
}

run "pod_identity_associations" {
  command = plan

  variables {
    pod_identity_associations = {
      lb-controller = {
        namespace       = "kube-system"
        service_account = "aws-load-balancer-controller"
        role_arn        = "arn:aws:iam::111111111111:role/alpha-dev-lb-controller"
      }
      argo-rollouts = {
        namespace       = "argo-rollouts"
        service_account = "argo-rollouts"
        role_arn        = "arn:aws:iam::111111111111:role/alpha-dev-argo-rollouts"
      }
    }
  }

  assert {
    condition = (
      aws_eks_pod_identity_association.this["lb-controller"].cluster_name == "alpha-dev" &&
      aws_eks_pod_identity_association.this["lb-controller"].namespace == "kube-system" &&
      aws_eks_pod_identity_association.this["lb-controller"].service_account == "aws-load-balancer-controller" &&
      aws_eks_pod_identity_association.this["lb-controller"].role_arn == "arn:aws:iam::111111111111:role/alpha-dev-lb-controller"
    )
    error_message = "Association must follow the input"
  }

  assert {
    condition     = length(aws_eks_pod_identity_association.this) == 2
    error_message = "Two associations"
  }
}

run "no_pod_identity_associations_by_default" {
  command = plan

  assert {
    condition     = length(aws_eks_pod_identity_association.this) == 0
    error_message = "No associations unless requested"
  }
}

run "pod_identity_bad_role_rejected" {
  command = plan

  variables {
    pod_identity_associations = {
      lb-controller = {
        namespace       = "kube-system"
        service_account = "aws-load-balancer-controller"
        role_arn        = "not-an-arn"
      }
    }
  }

  expect_failures = [var.pod_identity_associations]
}

run "pod_identity_bad_namespace_rejected" {
  command = plan

  variables {
    pod_identity_associations = {
      lb-controller = {
        namespace       = "Kube_System"
        service_account = "aws-load-balancer-controller"
        role_arn        = "arn:aws:iam::111111111111:role/alpha-dev-lb-controller"
      }
    }
  }

  expect_failures = [var.pod_identity_associations]
}

run "pod_identity_bad_service_account_rejected" {
  command = plan

  variables {
    pod_identity_associations = {
      lb-controller = {
        namespace       = "kube-system"
        service_account = "Bad Name"
        role_arn        = "arn:aws:iam::111111111111:role/alpha-dev-lb-controller"
      }
    }
  }

  expect_failures = [var.pod_identity_associations]
}
