# Input validation: one rejected and one accepted case per rule.

mock_provider "helm" {}

variables {
  cluster_name = "alpha-dev"
  region       = "ap-northeast-1"
  vpc_id       = "vpc-0123456789abcdef0"
}

run "cluster_name_rejects_spaces" {
  command = plan
  variables {
    cluster_name = "alpha dev"
  }
  expect_failures = [var.cluster_name]
}

run "region_rejects_garbage" {
  command = plan
  variables {
    region = "tokyo"
  }
  expect_failures = [var.region]
}

run "vpc_id_rejects_subnet_id" {
  command = plan
  variables {
    vpc_id = "subnet-0123456789abcdef0"
  }
  expect_failures = [var.vpc_id]
}

run "lbc_chart_version_rejects_v_prefix" {
  command = plan
  variables {
    load_balancer_controller = { chart_version = "v3.6.0" }
  }
  expect_failures = [var.load_balancer_controller]
}

run "lbc_chart_version_accepts_prerelease" {
  command = plan
  variables {
    load_balancer_controller = { chart_version = "3.7.0-rc.1" }
  }
}

run "lbc_replica_count_rejects_zero" {
  command = plan
  variables {
    load_balancer_controller = { replica_count = 0 }
  }
  expect_failures = [var.load_balancer_controller]
}

run "lbc_service_account_rejects_uppercase" {
  command = plan
  variables {
    load_balancer_controller = { service_account = "LBC" }
  }
  expect_failures = [var.load_balancer_controller]
}

run "lbc_values_rejects_non_object" {
  command = plan
  variables {
    load_balancer_controller = { values = ["a"] }
  }
  expect_failures = [var.load_balancer_controller]
}

run "karpenter_chart_version_rejects_latest" {
  command = plan
  variables {
    karpenter = { chart_version = "latest", interruption_queue_name = "alpha-dev" }
  }
  expect_failures = [var.karpenter]
}

run "karpenter_namespace_rejects_underscore" {
  command = plan
  variables {
    karpenter = { namespace = "my_ns", interruption_queue_name = "alpha-dev" }
  }
  expect_failures = [var.karpenter]
}

run "karpenter_namespace_rejects_64_chars" {
  command = plan
  variables {
    karpenter = { namespace = join("", [for i in range(64) : "a"]), interruption_queue_name = "alpha-dev" }
  }
  expect_failures = [var.karpenter]
}

run "karpenter_namespace_accepts_63_chars" {
  command = plan
  variables {
    karpenter = { namespace = join("", [for i in range(63) : "a"]), interruption_queue_name = "alpha-dev" }
  }
}

run "karpenter_queue_name_rejects_url" {
  command = plan
  variables {
    karpenter = { interruption_queue_name = "https://sqs.ap-northeast-1.amazonaws.com/111111111111/alpha-dev" }
  }
  expect_failures = [var.karpenter]
}

run "karpenter_node_role_rejects_arn" {
  command = plan
  variables {
    karpenter = {
      interruption_queue_name = "alpha-dev"
      default_node_class = {
        node_role_name               = "arn:aws:iam::111111111111:role/alpha-dev-karpenter-node"
        subnet_discovery_tag         = { "karpenter.sh/discovery" = "alpha-dev" }
        security_group_discovery_tag = { "karpenter.sh/discovery" = "alpha-dev" }
      }
    }
  }
  expect_failures = [var.karpenter]
}

run "karpenter_discovery_tag_rejects_empty_map" {
  command = plan
  variables {
    karpenter = {
      interruption_queue_name = "alpha-dev"
      default_node_class = {
        node_role_name               = "alpha-dev-karpenter-node"
        subnet_discovery_tag         = {}
        security_group_discovery_tag = { "karpenter.sh/discovery" = "alpha-dev" }
      }
    }
  }
  expect_failures = [var.karpenter]
}

run "karpenter_ami_alias_rejects_bottlerocket" {
  command = plan
  variables {
    karpenter = {
      interruption_queue_name = "alpha-dev"
      default_node_class = {
        node_role_name               = "alpha-dev-karpenter-node"
        subnet_discovery_tag         = { "karpenter.sh/discovery" = "alpha-dev" }
        security_group_discovery_tag = { "karpenter.sh/discovery" = "alpha-dev" }
        ami_alias                    = "bottlerocket@latest"
      }
    }
  }
  expect_failures = [var.karpenter]
}

run "karpenter_cpu_limit_rejects_zero" {
  command = plan
  variables {
    karpenter = {
      interruption_queue_name = "alpha-dev"
      default_node_pool       = { cpu_limit = 0 }
    }
  }
  expect_failures = [var.karpenter]
}

run "karpenter_cpu_limit_accepts_one" {
  command = plan
  variables {
    karpenter = {
      interruption_queue_name = "alpha-dev"
      default_node_pool       = { cpu_limit = 1 }
    }
  }
}

run "karpenter_capacity_types_rejects_reserved" {
  command = plan
  variables {
    karpenter = {
      interruption_queue_name = "alpha-dev"
      default_node_pool       = { capacity_types = ["on-demand", "reserved"] }
    }
  }
  expect_failures = [var.karpenter]
}

run "karpenter_capacity_types_rejects_empty" {
  command = plan
  variables {
    karpenter = {
      interruption_queue_name = "alpha-dev"
      default_node_pool       = { capacity_types = [] }
    }
  }
  expect_failures = [var.karpenter]
}

run "karpenter_capacity_types_accepts_spot_only" {
  command = plan
  variables {
    karpenter = {
      interruption_queue_name = "alpha-dev"
      default_node_pool       = { capacity_types = ["spot"] }
    }
  }
}

run "argo_namespace_rejects_uppercase" {
  command = plan
  variables {
    argo_rollouts = { namespace = "Argo" }
  }
  expect_failures = [var.argo_rollouts]
}

run "argo_chart_version_rejects_range" {
  command = plan
  variables {
    argo_rollouts = { chart_version = "~> 2.43" }
  }
  expect_failures = [var.argo_rollouts]
}

run "app_namespaces_rejects_uppercase_name" {
  command = plan
  variables {
    app_namespaces = { Payments = {} }
  }
  expect_failures = [var.app_namespaces]
}

run "app_namespaces_rejects_kube_prefix" {
  command = plan
  variables {
    app_namespaces = { "kube-extra" = {} }
  }
  expect_failures = [var.app_namespaces]
}

run "app_namespaces_rejects_default" {
  command = plan
  variables {
    app_namespaces = { default = {} }
  }
  expect_failures = [var.app_namespaces]
}

run "app_namespaces_accepts_rfc1123_name" {
  command = plan
  variables {
    app_namespaces = { "payments-2" = {} }
  }
}

run "overrides_reject_unknown_key" {
  command = plan
  variables {
    chart_repository_overrides = { prometheus = "https://example.com/charts" }
  }
  expect_failures = [var.chart_repository_overrides]
}

run "overrides_reject_non_url" {
  command = plan
  variables {
    chart_repository_overrides = { karpenter = "public.ecr.aws/karpenter" }
  }
  expect_failures = [var.chart_repository_overrides]
}
