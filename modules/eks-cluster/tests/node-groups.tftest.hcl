# Managed node groups: launch template (IMDSv2, encrypted EBS), node group settings and their validations.

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

run "managed_node_group_defaults" {
  command = plan

  assert {
    condition     = length(aws_eks_node_group.this) == 1 && aws_eks_node_group.this["system"].node_group_name == "system"
    error_message = "One node group named after its key"
  }

  assert {
    condition = (
      aws_eks_node_group.this["system"].cluster_name == "alpha-dev" &&
      aws_eks_node_group.this["system"].node_role_arn == "arn:aws:iam::111111111111:role/alpha-dev-eks-node" &&
      aws_eks_node_group.this["system"].subnet_ids == toset(var.subnet_ids)
    )
    error_message = "Node group falls back to the cluster subnets"
  }

  assert {
    condition = (
      aws_eks_node_group.this["system"].ami_type == "AL2023_x86_64_STANDARD" &&
      aws_eks_node_group.this["system"].capacity_type == "ON_DEMAND" &&
      aws_eks_node_group.this["system"].instance_types == tolist(["m7i.large"])
    )
    error_message = "Defaults: AL2023 x86_64, ON_DEMAND"
  }

  assert {
    condition = (
      aws_eks_node_group.this["system"].scaling_config[0].min_size == 1 &&
      aws_eks_node_group.this["system"].scaling_config[0].max_size == 3 &&
      aws_eks_node_group.this["system"].scaling_config[0].desired_size == 2
    )
    error_message = "Scaling must follow the input"
  }

  assert {
    condition     = aws_eks_node_group.this["system"].update_config[0].max_unavailable_percentage == 33
    error_message = "max_unavailable_percentage must default to 33"
  }

  assert {
    condition     = length(aws_eks_node_group.this["system"].launch_template) == 1
    error_message = "The node group must use the module launch template"
  }
}

run "managed_node_group_overrides" {
  command = plan

  variables {
    managed_node_groups = {
      batch = {
        node_role_arn              = "arn:aws:iam::111111111111:role/alpha-dev-eks-node"
        subnet_ids                 = ["subnet-0aaaaaaaaaaaaaaaa"]
        ami_type                   = "AL2023_ARM_64_STANDARD"
        instance_types             = ["m7g.large", "m6g.large"]
        capacity_type              = "SPOT"
        min_size                   = 0
        max_size                   = 10
        desired_size               = 0
        labels                     = { workload = "batch" }
        taints                     = [{ key = "dedicated", value = "batch", effect = "NO_SCHEDULE" }, { key = "spot", effect = "PREFER_NO_SCHEDULE" }]
        max_unavailable_percentage = 50
      }
    }
  }

  assert {
    condition = (
      aws_eks_node_group.this["batch"].subnet_ids == toset(["subnet-0aaaaaaaaaaaaaaaa"]) &&
      aws_eks_node_group.this["batch"].ami_type == "AL2023_ARM_64_STANDARD" &&
      aws_eks_node_group.this["batch"].capacity_type == "SPOT" &&
      aws_eks_node_group.this["batch"].instance_types == tolist(["m7g.large", "m6g.large"])
    )
    error_message = "Overrides must reach the node group"
  }

  assert {
    condition     = aws_eks_node_group.this["batch"].labels == tomap({ workload = "batch" })
    error_message = "Labels must follow the input"
  }

  assert {
    condition     = toset([for t in aws_eks_node_group.this["batch"].taint : "${t.key}:${t.effect}"]) == toset(["dedicated:NO_SCHEDULE", "spot:PREFER_NO_SCHEDULE"])
    error_message = "Taints must follow the input"
  }

  assert {
    condition     = aws_eks_node_group.this["batch"].update_config[0].max_unavailable_percentage == 50
    error_message = "max_unavailable_percentage must follow the input"
  }
}

run "launch_template_is_imdsv2_and_encrypted" {
  command = plan

  assert {
    condition     = aws_launch_template.node_group["system"].name == "alpha-dev-system"
    error_message = "Launch template is named <cluster>-<group>"
  }

  assert {
    condition = (
      aws_launch_template.node_group["system"].metadata_options[0].http_tokens == "required" &&
      aws_launch_template.node_group["system"].metadata_options[0].http_put_response_hop_limit == 1 &&
      aws_launch_template.node_group["system"].metadata_options[0].http_endpoint == "enabled"
    )
    error_message = "IMDSv2 must be required with hop limit 1"
  }

  assert {
    condition = (
      aws_launch_template.node_group["system"].block_device_mappings[0].device_name == "/dev/xvda" &&
      tostring(aws_launch_template.node_group["system"].block_device_mappings[0].ebs[0].encrypted) == "true" &&
      aws_launch_template.node_group["system"].block_device_mappings[0].ebs[0].volume_type == "gp3" &&
      aws_launch_template.node_group["system"].block_device_mappings[0].ebs[0].volume_size == 50
    )
    error_message = "Root volume must be an encrypted 50 GiB gp3"
  }

  assert {
    condition     = aws_launch_template.node_group["system"].block_device_mappings[0].ebs[0].kms_key_id == null
    error_message = "Default EBS key when disk_kms_key_arn is not set"
  }

  assert {
    condition     = aws_launch_template.node_group["system"].update_default_version == true
    error_message = "Every launch template version becomes the default"
  }
}

run "launch_template_with_custom_disk" {
  command = plan

  variables {
    managed_node_groups = {
      system = {
        node_role_arn    = "arn:aws:iam::111111111111:role/alpha-dev-eks-node"
        instance_types   = ["m7i.large"]
        min_size         = 1
        max_size         = 3
        desired_size     = 2
        disk_size        = 100
        disk_kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/99999999-2222-3333-4444-555555555555"
      }
    }
    tags = { Project = "alpha" }
  }

  assert {
    condition = (
      aws_launch_template.node_group["system"].block_device_mappings[0].ebs[0].volume_size == 100 &&
      aws_launch_template.node_group["system"].block_device_mappings[0].ebs[0].kms_key_id == "arn:aws:kms:ap-northeast-1:111111111111:key/99999999-2222-3333-4444-555555555555" &&
      tostring(aws_launch_template.node_group["system"].block_device_mappings[0].ebs[0].encrypted) == "true"
    )
    error_message = "disk_size and disk_kms_key_arn must reach the launch template, still encrypted"
  }

  assert {
    condition = (
      length(aws_launch_template.node_group["system"].tag_specifications) == 2 &&
      alltrue([for s in aws_launch_template.node_group["system"].tag_specifications : s.tags["Project"] == "alpha"])
    )
    error_message = "Instances and volumes must carry the tags"
  }
}

run "one_launch_template_per_node_group" {
  command = plan

  variables {
    managed_node_groups = {
      system = {
        node_role_arn  = "arn:aws:iam::111111111111:role/alpha-dev-eks-node"
        instance_types = ["m7i.large"]
        min_size       = 1
        max_size       = 3
        desired_size   = 2
      }
      apps = {
        node_role_arn  = "arn:aws:iam::111111111111:role/alpha-dev-eks-node"
        instance_types = ["m7i.xlarge"]
        min_size       = 1
        max_size       = 6
        desired_size   = 2
      }
    }
  }

  assert {
    condition     = length(aws_launch_template.node_group) == 2 && length(aws_eks_node_group.this) == 2
    error_message = "Each node group gets its own launch template"
  }
}

run "node_group_invalid_ami_type_rejected" {
  command = plan

  variables {
    managed_node_groups = {
      system = {
        node_role_arn  = "arn:aws:iam::111111111111:role/alpha-dev-eks-node"
        ami_type       = "AL2_x86_64"
        instance_types = ["m7i.large"]
        min_size       = 1
        max_size       = 3
        desired_size   = 2
      }
    }
  }

  expect_failures = [var.managed_node_groups]
}

run "node_group_invalid_capacity_type_rejected" {
  command = plan

  variables {
    managed_node_groups = {
      system = {
        node_role_arn  = "arn:aws:iam::111111111111:role/alpha-dev-eks-node"
        capacity_type  = "RESERVED"
        instance_types = ["m7i.large"]
        min_size       = 1
        max_size       = 3
        desired_size   = 2
      }
    }
  }

  expect_failures = [var.managed_node_groups]
}

run "node_group_desired_above_max_rejected" {
  command = plan

  variables {
    managed_node_groups = {
      system = {
        node_role_arn  = "arn:aws:iam::111111111111:role/alpha-dev-eks-node"
        instance_types = ["m7i.large"]
        min_size       = 1
        max_size       = 3
        desired_size   = 4
      }
    }
  }

  expect_failures = [var.managed_node_groups]
}

run "node_group_desired_below_min_rejected" {
  command = plan

  variables {
    managed_node_groups = {
      system = {
        node_role_arn  = "arn:aws:iam::111111111111:role/alpha-dev-eks-node"
        instance_types = ["m7i.large"]
        min_size       = 2
        max_size       = 3
        desired_size   = 1
      }
    }
  }

  expect_failures = [var.managed_node_groups]
}

run "node_group_without_instance_types_rejected" {
  command = plan

  variables {
    managed_node_groups = {
      system = {
        node_role_arn  = "arn:aws:iam::111111111111:role/alpha-dev-eks-node"
        instance_types = []
        min_size       = 1
        max_size       = 3
        desired_size   = 2
      }
    }
  }

  expect_failures = [var.managed_node_groups]
}

run "node_group_bad_taint_effect_rejected" {
  command = plan

  variables {
    managed_node_groups = {
      system = {
        node_role_arn  = "arn:aws:iam::111111111111:role/alpha-dev-eks-node"
        instance_types = ["m7i.large"]
        min_size       = 1
        max_size       = 3
        desired_size   = 2
        taints         = [{ key = "dedicated", effect = "NoSchedule" }]
      }
    }
  }

  expect_failures = [var.managed_node_groups]
}

run "node_group_bad_max_unavailable_rejected" {
  command = plan

  variables {
    managed_node_groups = {
      system = {
        node_role_arn              = "arn:aws:iam::111111111111:role/alpha-dev-eks-node"
        instance_types             = ["m7i.large"]
        min_size                   = 1
        max_size                   = 3
        desired_size               = 2
        max_unavailable_percentage = 0
      }
    }
  }

  expect_failures = [var.managed_node_groups]
}

run "node_group_small_disk_rejected" {
  command = plan

  variables {
    managed_node_groups = {
      system = {
        node_role_arn  = "arn:aws:iam::111111111111:role/alpha-dev-eks-node"
        instance_types = ["m7i.large"]
        min_size       = 1
        max_size       = 3
        desired_size   = 2
        disk_size      = 10
      }
    }
  }

  expect_failures = [var.managed_node_groups]
}

run "node_group_kms_alias_rejected" {
  command = plan

  variables {
    managed_node_groups = {
      system = {
        node_role_arn    = "arn:aws:iam::111111111111:role/alpha-dev-eks-node"
        instance_types   = ["m7i.large"]
        min_size         = 1
        max_size         = 3
        desired_size     = 2
        disk_kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:alias/ebs"
      }
    }
  }

  expect_failures = [var.managed_node_groups]
}

run "node_group_bad_role_rejected" {
  command = plan

  variables {
    managed_node_groups = {
      system = {
        node_role_arn  = "alpha-dev-eks-node"
        instance_types = ["m7i.large"]
        min_size       = 1
        max_size       = 3
        desired_size   = 2
      }
    }
  }

  expect_failures = [var.managed_node_groups]
}

run "node_group_bad_key_rejected" {
  command = plan

  variables {
    managed_node_groups = {
      "Bad Key" = {
        node_role_arn  = "arn:aws:iam::111111111111:role/alpha-dev-eks-node"
        instance_types = ["m7i.large"]
        min_size       = 1
        max_size       = 3
        desired_size   = 2
      }
    }
  }

  expect_failures = [var.managed_node_groups]
}

run "node_group_empty_subnets_rejected" {
  command = plan

  variables {
    managed_node_groups = {
      system = {
        node_role_arn  = "arn:aws:iam::111111111111:role/alpha-dev-eks-node"
        subnet_ids     = []
        instance_types = ["m7i.large"]
        min_size       = 1
        max_size       = 3
        desired_size   = 2
      }
    }
  }

  expect_failures = [var.managed_node_groups]
}

run "node_group_malformed_subnet_rejected" {
  command = plan

  variables {
    managed_node_groups = {
      system = {
        node_role_arn  = "arn:aws:iam::111111111111:role/alpha-dev-eks-node"
        subnet_ids     = ["not-a-subnet"]
        instance_types = ["m7i.large"]
        min_size       = 1
        max_size       = 3
        desired_size   = 2
      }
    }
  }

  expect_failures = [var.managed_node_groups]
}
