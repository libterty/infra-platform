# Add-ons: the required set, Pod Identity, conflict resolution and the order against nodes.

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

run "required_addons_present" {
  command = plan

  assert {
    condition     = length(aws_eks_addon.before_compute) + length(aws_eks_addon.after_compute) == 4
    error_message = "All four add-ons must be created"
  }

  assert {
    condition = (
      aws_eks_addon.before_compute["vpc-cni"].addon_name == "vpc-cni" &&
      aws_eks_addon.before_compute["vpc-cni"].addon_version == "v1.20.0-eksbuild.1" &&
      aws_eks_addon.before_compute["vpc-cni"].cluster_name == "alpha-dev"
    )
    error_message = "Add-on name, version and cluster must follow the input"
  }

  assert {
    condition     = aws_eks_addon.before_compute["vpc-cni"].resolve_conflicts_on_update == "OVERWRITE"
    error_message = "resolve_conflicts_on_update must default to OVERWRITE"
  }
}

run "node_independent_addons_are_created_first" {
  command = plan

  assert {
    condition     = toset(keys(aws_eks_addon.before_compute)) == toset(["vpc-cni", "kube-proxy", "eks-pod-identity-agent"])
    error_message = "vpc-cni, kube-proxy and eks-pod-identity-agent do not wait for nodes"
  }

  assert {
    condition     = toset(keys(aws_eks_addon.after_compute)) == toset(["coredns"])
    error_message = "coredns waits for nodes"
  }
}

run "node_dependent_addons_wait_for_nodes" {
  command = plan

  variables {
    addons = {
      vpc-cni                = { version = "v1.20.0-eksbuild.1" }
      kube-proxy             = { version = "v1.34.0-eksbuild.1" }
      coredns                = { version = "v1.12.0-eksbuild.1" }
      eks-pod-identity-agent = { version = "v1.3.0-eksbuild.1" }
      aws-ebs-csi-driver     = { version = "v1.50.0-eksbuild.1" }
      metrics-server         = { version = "v0.8.0-eksbuild.1" }
    }
  }

  assert {
    condition     = toset(keys(aws_eks_addon.after_compute)) == toset(["coredns", "aws-ebs-csi-driver", "metrics-server"])
    error_message = "coredns, ebs-csi and metrics-server must be in the after-compute group"
  }

  assert {
    condition     = length(aws_eks_addon.before_compute) == 3
    error_message = "Only the three node-independent add-ons are created first"
  }
}

run "addon_with_pod_identity_and_configuration" {
  command = plan

  variables {
    addons = {
      vpc-cni                = { version = "v1.20.0-eksbuild.1" }
      kube-proxy             = { version = "v1.34.0-eksbuild.1" }
      coredns                = { version = "v1.12.0-eksbuild.1", configuration_values = jsonencode({ replicaCount = 3 }), resolve_conflicts_on_update = "PRESERVE" }
      eks-pod-identity-agent = { version = "v1.3.0-eksbuild.1" }
      aws-ebs-csi-driver = {
        version               = "v1.50.0-eksbuild.1"
        pod_identity_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-ebs-csi"
        service_account       = "ebs-csi-controller-sa"
      }
    }
  }

  assert {
    condition     = aws_eks_addon.after_compute["coredns"].configuration_values == jsonencode({ replicaCount = 3 })
    error_message = "configuration_values must reach the add-on"
  }

  assert {
    condition     = aws_eks_addon.after_compute["coredns"].resolve_conflicts_on_update == "PRESERVE"
    error_message = "resolve_conflicts_on_update must follow the input"
  }

  assert {
    condition = (
      length(aws_eks_addon.after_compute["aws-ebs-csi-driver"].pod_identity_association) == 1 &&
      one(aws_eks_addon.after_compute["aws-ebs-csi-driver"].pod_identity_association).role_arn == "arn:aws:iam::111111111111:role/alpha-dev-ebs-csi" &&
      one(aws_eks_addon.after_compute["aws-ebs-csi-driver"].pod_identity_association).service_account == "ebs-csi-controller-sa"
    )
    error_message = "The Pod Identity association must carry role and service account"
  }

  assert {
    condition     = length(aws_eks_addon.after_compute["coredns"].pod_identity_association) == 0
    error_message = "No Pod Identity association unless requested"
  }
}

run "missing_vpc_cni_rejected" {
  command = plan

  variables {
    addons = {
      kube-proxy             = { version = "v1.34.0-eksbuild.1" }
      coredns                = { version = "v1.12.0-eksbuild.1" }
      eks-pod-identity-agent = { version = "v1.3.0-eksbuild.1" }
    }
  }

  expect_failures = [var.addons]
}

run "missing_kube_proxy_rejected" {
  command = plan

  variables {
    addons = {
      vpc-cni                = { version = "v1.20.0-eksbuild.1" }
      coredns                = { version = "v1.12.0-eksbuild.1" }
      eks-pod-identity-agent = { version = "v1.3.0-eksbuild.1" }
    }
  }

  expect_failures = [var.addons]
}

run "missing_coredns_rejected" {
  command = plan

  variables {
    addons = {
      vpc-cni                = { version = "v1.20.0-eksbuild.1" }
      kube-proxy             = { version = "v1.34.0-eksbuild.1" }
      eks-pod-identity-agent = { version = "v1.3.0-eksbuild.1" }
    }
  }

  expect_failures = [var.addons]
}

run "missing_pod_identity_agent_rejected" {
  command = plan

  variables {
    addons = {
      vpc-cni    = { version = "v1.20.0-eksbuild.1" }
      kube-proxy = { version = "v1.34.0-eksbuild.1" }
      coredns    = { version = "v1.12.0-eksbuild.1" }
    }
  }

  expect_failures = [var.addons]
}

run "no_addons_without_auto_mode_rejected" {
  command = plan

  variables {
    addons = {}
  }

  expect_failures = [var.addons]
}

run "auto_mode_does_not_need_the_core_addons" {
  command = plan

  variables {
    managed_node_groups = {}
    addons              = {}
    auto_mode = {
      node_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-eks-auto-node"
    }
  }

  assert {
    condition     = length(aws_eks_addon.before_compute) == 0 && length(aws_eks_addon.after_compute) == 0
    error_message = "Auto Mode with no add-ons creates none"
  }
}

run "auto_mode_accepts_metrics_server" {
  command = plan

  variables {
    managed_node_groups = {}
    addons = {
      metrics-server = { version = "v0.8.0-eksbuild.1" }
    }
    auto_mode = {
      node_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-eks-auto-node"
    }
  }

  assert {
    condition     = toset(keys(aws_eks_addon.after_compute)) == toset(["metrics-server"])
    error_message = "metrics-server is allowed with Auto Mode (design J6)"
  }
}

run "addon_without_version_rejected" {
  command = plan

  variables {
    addons = {
      vpc-cni                = { version = "" }
      kube-proxy             = { version = "v1.34.0-eksbuild.1" }
      coredns                = { version = "v1.12.0-eksbuild.1" }
      eks-pod-identity-agent = { version = "v1.3.0-eksbuild.1" }
    }
  }

  expect_failures = [var.addons]
}

run "addon_unknown_conflict_resolution_rejected" {
  command = plan

  variables {
    addons = {
      vpc-cni                = { version = "v1.20.0-eksbuild.1", resolve_conflicts_on_update = "FORCE" }
      kube-proxy             = { version = "v1.34.0-eksbuild.1" }
      coredns                = { version = "v1.12.0-eksbuild.1" }
      eks-pod-identity-agent = { version = "v1.3.0-eksbuild.1" }
    }
  }

  expect_failures = [var.addons]
}

run "addon_pod_identity_role_without_service_account_rejected" {
  command = plan

  variables {
    addons = {
      vpc-cni                = { version = "v1.20.0-eksbuild.1", pod_identity_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-vpc-cni" }
      kube-proxy             = { version = "v1.34.0-eksbuild.1" }
      coredns                = { version = "v1.12.0-eksbuild.1" }
      eks-pod-identity-agent = { version = "v1.3.0-eksbuild.1" }
    }
  }

  expect_failures = [var.addons]
}

run "addon_service_account_without_pod_identity_role_rejected" {
  command = plan

  variables {
    addons = {
      vpc-cni                = { version = "v1.20.0-eksbuild.1", service_account = "aws-node" }
      kube-proxy             = { version = "v1.34.0-eksbuild.1" }
      coredns                = { version = "v1.12.0-eksbuild.1" }
      eks-pod-identity-agent = { version = "v1.3.0-eksbuild.1" }
    }
  }

  expect_failures = [var.addons]
}

run "addon_bad_pod_identity_role_rejected" {
  command = plan

  variables {
    addons = {
      vpc-cni                = { version = "v1.20.0-eksbuild.1", pod_identity_role_arn = "not-an-arn", service_account = "aws-node" }
      kube-proxy             = { version = "v1.34.0-eksbuild.1" }
      coredns                = { version = "v1.12.0-eksbuild.1" }
      eks-pod-identity-agent = { version = "v1.3.0-eksbuild.1" }
    }
  }

  expect_failures = [var.addons]
}

run "addon_bad_name_rejected" {
  command = plan

  variables {
    addons = {
      vpc-cni                = { version = "v1.20.0-eksbuild.1" }
      kube-proxy             = { version = "v1.34.0-eksbuild.1" }
      coredns                = { version = "v1.12.0-eksbuild.1" }
      eks-pod-identity-agent = { version = "v1.3.0-eksbuild.1" }
      "Bad Name"             = { version = "v1.0.0" }
    }
  }

  expect_failures = [var.addons]
}
