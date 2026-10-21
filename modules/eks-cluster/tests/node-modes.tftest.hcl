# Node modes: Fargate profiles, Auto Mode and the exclusion rules between modes (design J2, D17).

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

# ---- Fargate profiles ----

run "managed_node_group_and_fargate_profile" {
  command = plan

  variables {
    fargate_profiles = {
      apps = {
        pod_execution_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-eks-fargate"
        subnet_ids             = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
        selectors = [
          { namespace = "apps" },
          { namespace = "batch", labels = { tier = "worker" } },
        ]
      }
    }
  }

  assert {
    condition = (
      aws_eks_fargate_profile.this["apps"].fargate_profile_name == "apps" &&
      aws_eks_fargate_profile.this["apps"].cluster_name == "alpha-dev" &&
      aws_eks_fargate_profile.this["apps"].pod_execution_role_arn == "arn:aws:iam::111111111111:role/alpha-dev-eks-fargate"
    )
    error_message = "Fargate profile must follow the input"
  }

  assert {
    condition     = length(aws_eks_fargate_profile.this["apps"].selector) == 2
    error_message = "Both selectors must be present"
  }

  assert {
    condition     = length(aws_eks_node_group.this) == 1
    error_message = "The managed node group must still be created"
  }
}

run "fargate_only_cluster" {
  command = plan

  variables {
    managed_node_groups = {}
    fargate_profiles = {
      all = {
        pod_execution_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-eks-fargate"
        subnet_ids             = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
        selectors              = [{ namespace = "kube-system" }, { namespace = "apps" }]
      }
    }
  }

  assert {
    condition     = length(aws_eks_node_group.this) == 0 && length(aws_launch_template.node_group) == 0
    error_message = "No node group and no launch template for a Fargate-only cluster"
  }

  assert {
    condition     = length(aws_eks_fargate_profile.this) == 1
    error_message = "The Fargate profile must be created"
  }
}

run "fargate_profile_without_selectors_rejected" {
  command = plan

  variables {
    fargate_profiles = {
      apps = {
        pod_execution_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-eks-fargate"
        subnet_ids             = ["subnet-0123456789abcdef0"]
        selectors              = []
      }
    }
  }

  expect_failures = [var.fargate_profiles]
}

run "fargate_profile_without_subnets_rejected" {
  command = plan

  variables {
    fargate_profiles = {
      apps = {
        pod_execution_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-eks-fargate"
        subnet_ids             = []
        selectors              = [{ namespace = "apps" }]
      }
    }
  }

  expect_failures = [var.fargate_profiles]
}

run "fargate_profile_bad_role_rejected" {
  command = plan

  variables {
    fargate_profiles = {
      apps = {
        pod_execution_role_arn = "not-an-arn"
        subnet_ids             = ["subnet-0123456789abcdef0"]
        selectors              = [{ namespace = "apps" }]
      }
    }
  }

  expect_failures = [var.fargate_profiles]
}

run "fargate_profile_bad_namespace_rejected" {
  command = plan

  variables {
    fargate_profiles = {
      apps = {
        pod_execution_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-eks-fargate"
        subnet_ids             = ["subnet-0123456789abcdef0"]
        selectors              = [{ namespace = "Apps_1" }]
      }
    }
  }

  expect_failures = [var.fargate_profiles]
}

# ---- Auto Mode ----

run "auto_mode_enables_all_three_settings" {
  command = plan

  variables {
    managed_node_groups = {}
    addons              = {}
    auto_mode = {
      node_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-eks-auto-node"
    }
  }

  assert {
    condition     = aws_eks_cluster.this.compute_config[0].enabled == true
    error_message = "compute_config.enabled must be true"
  }

  assert {
    condition     = aws_eks_cluster.this.kubernetes_network_config[0].elastic_load_balancing[0].enabled == true
    error_message = "elastic_load_balancing.enabled must be true"
  }

  assert {
    condition     = aws_eks_cluster.this.storage_config[0].block_storage[0].enabled == true
    error_message = "block_storage.enabled must be true"
  }

  assert {
    condition = (
      aws_eks_cluster.this.compute_config[0].node_role_arn == "arn:aws:iam::111111111111:role/alpha-dev-eks-auto-node" &&
      aws_eks_cluster.this.compute_config[0].node_pools == toset(["general-purpose", "system"])
    )
    error_message = "compute_config carries the node role and the default node pools"
  }

  assert {
    condition     = aws_eks_cluster.this.bootstrap_self_managed_addons == false
    error_message = "Auto Mode needs bootstrap_self_managed_addons = false"
  }

  assert {
    condition     = length(aws_eks_node_group.this) == 0 && length(aws_launch_template.node_group) == 0
    error_message = "Auto Mode alone creates no node group"
  }
}

run "auto_mode_custom_node_pools" {
  command = plan

  variables {
    managed_node_groups = {}
    addons              = {}
    auto_mode = {
      node_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-eks-auto-node"
      node_pools    = ["system"]
    }
  }

  assert {
    condition     = aws_eks_cluster.this.compute_config[0].node_pools == toset(["system"])
    error_message = "node_pools must follow the input"
  }
}

run "without_auto_mode_all_three_settings_are_false" {
  command = plan

  assert {
    condition     = aws_eks_cluster.this.compute_config[0].enabled == false
    error_message = "compute_config.enabled must be false without auto_mode"
  }

  assert {
    condition     = aws_eks_cluster.this.kubernetes_network_config[0].elastic_load_balancing[0].enabled == false
    error_message = "elastic_load_balancing.enabled must be false without auto_mode"
  }

  assert {
    condition     = aws_eks_cluster.this.storage_config[0].block_storage[0].enabled == false
    error_message = "block_storage.enabled must be false without auto_mode"
  }

  assert {
    condition     = aws_eks_cluster.this.compute_config[0].node_pools == null && aws_eks_cluster.this.compute_config[0].node_role_arn == null
    error_message = "No node pools or node role without auto_mode"
  }
}

run "auto_mode_unknown_node_pool_rejected" {
  command = plan

  variables {
    managed_node_groups = {}
    addons              = {}
    auto_mode = {
      node_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-eks-auto-node"
      node_pools    = ["general-purpose", "gpu"]
    }
  }

  expect_failures = [var.auto_mode]
}

run "auto_mode_bad_role_rejected" {
  command = plan

  variables {
    managed_node_groups = {}
    addons              = {}
    auto_mode = {
      node_role_arn = "alpha-dev-eks-auto-node"
    }
  }

  expect_failures = [var.auto_mode]
}

run "auto_mode_with_fargate_is_allowed" {
  command = plan

  variables {
    managed_node_groups = {}
    addons              = {}
    auto_mode = {
      node_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-eks-auto-node"
    }
    fargate_profiles = {
      apps = {
        pod_execution_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-eks-fargate"
        subnet_ids             = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
        selectors              = [{ namespace = "apps" }]
      }
    }
  }

  assert {
    condition     = aws_eks_cluster.this.compute_config[0].enabled == true && length(aws_eks_fargate_profile.this) == 1
    error_message = "Auto Mode and Fargate profiles may coexist (D17)"
  }
}

run "auto_mode_with_managed_node_group_is_allowed" {
  command = plan

  variables {
    addons = {}
    auto_mode = {
      node_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-eks-auto-node"
    }
  }

  assert {
    condition     = aws_eks_cluster.this.compute_config[0].enabled == true && length(aws_eks_node_group.this) == 1
    error_message = "Auto Mode and managed node groups may coexist"
  }
}

# ---- exclusion rules ----

run "no_node_mode_rejected" {
  command = plan

  variables {
    managed_node_groups = {}
  }

  expect_failures = [aws_eks_cluster.this]
}

run "fargate_alone_satisfies_at_least_one_mode" {
  command = plan

  variables {
    managed_node_groups = {}
    fargate_profiles = {
      apps = {
        pod_execution_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-eks-fargate"
        subnet_ids             = ["subnet-0123456789abcdef0"]
        selectors              = [{ namespace = "apps" }]
      }
    }
  }

  assert {
    condition     = length(aws_eks_fargate_profile.this) == 1
    error_message = "A Fargate profile alone is a valid node mode"
  }
}

run "auto_mode_alone_satisfies_at_least_one_mode" {
  command = plan

  variables {
    managed_node_groups = {}
    addons              = {}
    auto_mode = {
      node_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-eks-auto-node"
    }
  }

  assert {
    condition     = aws_eks_cluster.this.compute_config[0].enabled == true
    error_message = "Auto Mode alone is a valid node mode"
  }
}

run "auto_mode_with_karpenter_rejected" {
  command = plan

  variables {
    auto_mode = {
      node_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-eks-auto-node"
    }
    karpenter = {
      node_role_arn       = "arn:aws:iam::111111111111:role/alpha-dev-karpenter-node"
      controller_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-karpenter-controller"
    }
  }

  expect_failures = [var.karpenter]
}

run "karpenter_without_managed_node_group_rejected" {
  command = plan

  variables {
    managed_node_groups = {}
    fargate_profiles = {
      apps = {
        pod_execution_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-eks-fargate"
        subnet_ids             = ["subnet-0123456789abcdef0"]
        selectors              = [{ namespace = "apps" }]
      }
    }
    karpenter = {
      node_role_arn       = "arn:aws:iam::111111111111:role/alpha-dev-karpenter-node"
      controller_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-karpenter-controller"
    }
  }

  expect_failures = [var.karpenter]
}

run "karpenter_with_managed_node_group_is_allowed" {
  command = plan

  variables {
    karpenter = {
      node_role_arn       = "arn:aws:iam::111111111111:role/alpha-dev-karpenter-node"
      controller_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-karpenter-controller"
    }
  }

  assert {
    condition     = length(aws_eks_node_group.this) == 1 && length(aws_sqs_queue.karpenter) == 1
    error_message = "Karpenter next to a managed node group is valid"
  }
}

run "fargate_profile_bad_name_rejected" {
  command = plan

  variables {
    fargate_profiles = {
      "Apps Profile" = {
        pod_execution_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-eks-fargate"
        subnet_ids             = ["subnet-0123456789abcdef0"]
        selectors              = [{ namespace = "apps" }]
      }
    }
  }

  expect_failures = [var.fargate_profiles]
}
