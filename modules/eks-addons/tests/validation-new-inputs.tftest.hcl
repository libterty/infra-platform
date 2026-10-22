# Input validation of the 0.2.0 inputs: auto_mode, network_policy, keda, cloudwatch_observability, system_placement.
# One rejected and one accepted case per rule.

mock_provider "helm" {}

variables {
  cluster_name = "alpha-dev"
  region       = "ap-northeast-1"
  vpc_id       = "vpc-0123456789abcdef0"
}

run "auto_mode_accepts_minimal" {
  command = plan
  variables {
    auto_mode = {
      node_role_name = "alpha-dev-eks-node"
      node_classes   = { app = { subnet_selector_terms = [{ tags = { tier = "app" } }], security_group_selector_terms = [{ id = "sg-0123456789abcdef0" }] } }
      node_pools     = { app = { node_class = "app" } }
    }
  }
}

run "auto_mode_rejects_pod_subnet_without_pod_sg" {
  command = plan
  variables {
    auto_mode = {
      node_role_name = "alpha-dev-eks-node"
      node_classes   = { app = { subnet_selector_terms = [{ tags = { tier = "app" } }], security_group_selector_terms = [{ id = "sg-0123456789abcdef0" }], pod_subnet_selector_terms = [{ tags = { tier = "app" } }] } }
      node_pools     = { app = { node_class = "app" } }
    }
  }
  expect_failures = [var.auto_mode]
}

run "auto_mode_rejects_pod_sg_without_pod_subnet" {
  command = plan
  variables {
    auto_mode = {
      node_role_name = "alpha-dev-eks-node"
      node_classes   = { app = { subnet_selector_terms = [{ tags = { tier = "app" } }], security_group_selector_terms = [{ id = "sg-0123456789abcdef0" }], pod_security_group_selector_terms = [{ id = "sg-0123456789abcdef0" }] } }
      node_pools     = { app = { node_class = "app" } }
    }
  }
  expect_failures = [var.auto_mode]
}

run "auto_mode_accepts_both_pod_terms" {
  command = plan
  variables {
    auto_mode = {
      node_role_name = "alpha-dev-eks-node"
      node_classes   = { app = { subnet_selector_terms = [{ tags = { tier = "app" } }], security_group_selector_terms = [{ id = "sg-0123456789abcdef0" }], pod_subnet_selector_terms = [{ tags = { tier = "app" } }], pod_security_group_selector_terms = [{ id = "sg-0123456789abcdef0" }] } }
      node_pools     = { app = { node_class = "app" } }
    }
  }
}

run "auto_mode_rejects_class_named_default" {
  command = plan
  variables {
    auto_mode = {
      node_role_name = "alpha-dev-eks-node"
      node_classes   = { default = { subnet_selector_terms = [{ tags = { tier = "app" } }], security_group_selector_terms = [{ id = "sg-0123456789abcdef0" }] } }
      node_pools     = { app = { node_class = "default" } }
    }
  }
  expect_failures = [var.auto_mode]
}

run "auto_mode_rejects_uppercase_class_name" {
  command = plan
  variables {
    auto_mode = {
      node_role_name = "alpha-dev-eks-node"
      node_classes   = { App = { subnet_selector_terms = [{ tags = { tier = "app" } }], security_group_selector_terms = [{ id = "sg-0123456789abcdef0" }] } }
      node_pools     = { app = { node_class = "App" } }
    }
  }
  expect_failures = [var.auto_mode]
}

run "auto_mode_rejects_pool_with_unknown_class" {
  command = plan
  variables {
    auto_mode = {
      node_role_name = "alpha-dev-eks-node"
      node_classes   = { app = { subnet_selector_terms = [{ tags = { tier = "app" } }], security_group_selector_terms = [{ id = "sg-0123456789abcdef0" }] } }
      node_pools     = { app = { node_class = "missing" } }
    }
  }
  expect_failures = [var.auto_mode]
}

run "auto_mode_rejects_bad_taint_effect" {
  command = plan
  variables {
    auto_mode = {
      node_role_name = "alpha-dev-eks-node"
      node_classes   = { app = { subnet_selector_terms = [{ tags = { tier = "app" } }], security_group_selector_terms = [{ id = "sg-0123456789abcdef0" }] } }
      node_pools     = { app = { node_class = "app", taints = [{ key = "dedicated", effect = "Block" }] } }
    }
  }
  expect_failures = [var.auto_mode]
}

run "auto_mode_accepts_all_taint_effects" {
  command = plan
  variables {
    auto_mode = {
      node_role_name = "alpha-dev-eks-node"
      node_classes   = { app = { subnet_selector_terms = [{ tags = { tier = "app" } }], security_group_selector_terms = [{ id = "sg-0123456789abcdef0" }] } }
      node_pools     = { app = { node_class = "app", taints = [{ key = "a", effect = "NoSchedule" }, { key = "b", effect = "PreferNoSchedule" }, { key = "c", value = "x", effect = "NoExecute" }] } }
    }
  }
}

run "auto_mode_rejects_empty_taint_key" {
  command = plan
  variables {
    auto_mode = {
      node_role_name = "alpha-dev-eks-node"
      node_classes   = { app = { subnet_selector_terms = [{ tags = { tier = "app" } }], security_group_selector_terms = [{ id = "sg-0123456789abcdef0" }] } }
      node_pools     = { app = { node_class = "app", taints = [{ key = "", effect = "NoSchedule" }] } }
    }
  }
  expect_failures = [var.auto_mode]
}

run "auto_mode_rejects_role_arn" {
  command = plan
  variables {
    auto_mode = {
      node_role_name = "arn:aws:iam::111111111111:role/alpha-dev-eks-node"
      node_classes   = { app = { subnet_selector_terms = [{ tags = { tier = "app" } }], security_group_selector_terms = [{ id = "sg-0123456789abcdef0" }] } }
      node_pools     = { app = { node_class = "app" } }
    }
  }
  expect_failures = [var.auto_mode]
}

run "auto_mode_rejects_bad_network_policy" {
  command = plan
  variables {
    auto_mode = {
      node_role_name = "alpha-dev-eks-node"
      node_classes   = { app = { subnet_selector_terms = [{ tags = { tier = "app" } }], security_group_selector_terms = [{ id = "sg-0123456789abcdef0" }], network_policy = "Deny" } }
      node_pools     = { app = { node_class = "app" } }
    }
  }
  expect_failures = [var.auto_mode]
}

run "auto_mode_rejects_bad_event_logs" {
  command = plan
  variables {
    auto_mode = {
      node_role_name = "alpha-dev-eks-node"
      node_classes   = { app = { subnet_selector_terms = [{ tags = { tier = "app" } }], security_group_selector_terms = [{ id = "sg-0123456789abcdef0" }], network_policy_event_logs = "On" } }
      node_pools     = { app = { node_class = "app" } }
    }
  }
  expect_failures = [var.auto_mode]
}

run "auto_mode_rejects_empty_subnet_terms" {
  command = plan
  variables {
    auto_mode = {
      node_role_name = "alpha-dev-eks-node"
      node_classes   = { app = { subnet_selector_terms = [], security_group_selector_terms = [{ id = "sg-0123456789abcdef0" }] } }
      node_pools     = { app = { node_class = "app" } }
    }
  }
  expect_failures = [var.auto_mode]
}

run "auto_mode_rejects_empty_security_group_terms" {
  command = plan
  variables {
    auto_mode = {
      node_role_name = "alpha-dev-eks-node"
      node_classes   = { app = { subnet_selector_terms = [{ tags = { tier = "app" } }], security_group_selector_terms = [] } }
      node_pools     = { app = { node_class = "app" } }
    }
  }
  expect_failures = [var.auto_mode]
}

run "auto_mode_rejects_term_with_id_and_tags" {
  command = plan
  variables {
    auto_mode = {
      node_role_name = "alpha-dev-eks-node"
      node_classes   = { app = { subnet_selector_terms = [{ id = "subnet-0123456789abcdef0", tags = { a = "b" } }], security_group_selector_terms = [{ id = "sg-0123456789abcdef0" }] } }
      node_pools     = { app = { node_class = "app" } }
    }
  }
  expect_failures = [var.auto_mode]
}

run "auto_mode_rejects_term_with_nothing" {
  command = plan
  variables {
    auto_mode = {
      node_role_name = "alpha-dev-eks-node"
      node_classes   = { app = { subnet_selector_terms = [{}], security_group_selector_terms = [{ id = "sg-0123456789abcdef0" }] } }
      node_pools     = { app = { node_class = "app" } }
    }
  }
  expect_failures = [var.auto_mode]
}

run "auto_mode_rejects_subnet_id_in_sg_terms" {
  command = plan
  variables {
    auto_mode = {
      node_role_name = "alpha-dev-eks-node"
      node_classes   = { app = { subnet_selector_terms = [{ tags = { tier = "app" } }], security_group_selector_terms = [{ id = "subnet-0123456789abcdef0" }] } }
      node_pools     = { app = { node_class = "app" } }
    }
  }
  expect_failures = [var.auto_mode]
}

run "auto_mode_accepts_subnet_id_term" {
  command = plan
  variables {
    auto_mode = {
      node_role_name = "alpha-dev-eks-node"
      node_classes   = { app = { subnet_selector_terms = [{ id = "subnet-0123456789abcdef0" }], security_group_selector_terms = [{ id = "sg-0123456789abcdef0" }] } }
      node_pools     = { app = { node_class = "app" } }
    }
  }
}

run "auto_mode_rejects_no_pools" {
  command = plan
  variables {
    auto_mode = {
      node_role_name = "alpha-dev-eks-node"
      node_classes   = { app = { subnet_selector_terms = [{ tags = { tier = "app" } }], security_group_selector_terms = [{ id = "sg-0123456789abcdef0" }] } }
      node_pools     = {}
    }
  }
  expect_failures = [var.auto_mode]
}

run "auto_mode_rejects_bad_capacity_type" {
  command = plan
  variables {
    auto_mode = {
      node_role_name = "alpha-dev-eks-node"
      node_classes   = { app = { subnet_selector_terms = [{ tags = { tier = "app" } }], security_group_selector_terms = [{ id = "sg-0123456789abcdef0" }] } }
      node_pools     = { app = { node_class = "app", capacity_types = ["reserved"] } }
    }
  }
  expect_failures = [var.auto_mode]
}

run "auto_mode_rejects_empty_capacity_types" {
  command = plan
  variables {
    auto_mode = {
      node_role_name = "alpha-dev-eks-node"
      node_classes   = { app = { subnet_selector_terms = [{ tags = { tier = "app" } }], security_group_selector_terms = [{ id = "sg-0123456789abcdef0" }] } }
      node_pools     = { app = { node_class = "app", capacity_types = [] } }
    }
  }
  expect_failures = [var.auto_mode]
}

run "auto_mode_rejects_bad_architecture" {
  command = plan
  variables {
    auto_mode = {
      node_role_name = "alpha-dev-eks-node"
      node_classes   = { app = { subnet_selector_terms = [{ tags = { tier = "app" } }], security_group_selector_terms = [{ id = "sg-0123456789abcdef0" }] } }
      node_pools     = { app = { node_class = "app", architectures = ["riscv"] } }
    }
  }
  expect_failures = [var.auto_mode]
}

run "auto_mode_rejects_zero_cpu_limit" {
  command = plan
  variables {
    auto_mode = {
      node_role_name = "alpha-dev-eks-node"
      node_classes   = { app = { subnet_selector_terms = [{ tags = { tier = "app" } }], security_group_selector_terms = [{ id = "sg-0123456789abcdef0" }] } }
      node_pools     = { app = { node_class = "app", cpu_limit = 0 } }
    }
  }
  expect_failures = [var.auto_mode]
}

run "auto_mode_rejects_bad_instance_category" {
  command = plan
  variables {
    auto_mode = {
      node_role_name = "alpha-dev-eks-node"
      node_classes   = { app = { subnet_selector_terms = [{ tags = { tier = "app" } }], security_group_selector_terms = [{ id = "sg-0123456789abcdef0" }] } }
      node_pools     = { app = { node_class = "app", instance_categories = ["C5"] } }
    }
  }
  expect_failures = [var.auto_mode]
}

run "network_policy_accepts_valid" {
  command = plan
  variables {
    network_policy = {
      service_cidr     = "172.20.0.0/16"
      api_server_cidrs = ["10.10.0.0/28"]
      aws_api_cidrs    = ["10.10.1.0/28"]
    }
  }
}

run "network_policy_rejects_bad_service_cidr" {
  command = plan
  variables {
    network_policy = {
      service_cidr     = "172.20.0.0"
      api_server_cidrs = ["10.10.0.0/28"]
      aws_api_cidrs    = ["10.10.1.0/28"]
    }
  }
  expect_failures = [var.network_policy]
}

run "network_policy_rejects_tiny_service_cidr" {
  command = plan
  variables {
    network_policy = {
      service_cidr     = "172.20.0.0/30"
      api_server_cidrs = ["10.10.0.0/28"]
      aws_api_cidrs    = ["10.10.1.0/28"]
    }
  }
  expect_failures = [var.network_policy]
}

run "network_policy_rejects_empty_api_server_cidrs" {
  command = plan
  variables {
    network_policy = {
      service_cidr     = "172.20.0.0/16"
      api_server_cidrs = []
      aws_api_cidrs    = ["10.10.1.0/28"]
    }
  }
  expect_failures = [var.network_policy]
}

run "network_policy_rejects_open_api_server_cidr" {
  command = plan
  variables {
    network_policy = {
      service_cidr     = "172.20.0.0/16"
      api_server_cidrs = ["0.0.0.0/0"]
      aws_api_cidrs    = ["10.10.1.0/28"]
    }
  }
  expect_failures = [var.network_policy]
}

run "network_policy_rejects_bad_api_server_cidr" {
  command = plan
  variables {
    network_policy = {
      service_cidr     = "172.20.0.0/16"
      api_server_cidrs = ["10.10.0.0/33"]
      aws_api_cidrs    = ["10.10.1.0/28"]
    }
  }
  expect_failures = [var.network_policy]
}

run "network_policy_rejects_empty_aws_api_cidrs" {
  command = plan
  variables {
    network_policy = {
      service_cidr     = "172.20.0.0/16"
      api_server_cidrs = ["10.10.0.0/28"]
      aws_api_cidrs    = []
    }
  }
  expect_failures = [var.network_policy]
}

run "network_policy_rejects_bad_aws_api_cidr" {
  command = plan
  variables {
    network_policy = {
      service_cidr     = "172.20.0.0/16"
      api_server_cidrs = ["10.10.0.0/28"]
      aws_api_cidrs    = ["not-a-cidr"]
    }
  }
  expect_failures = [var.network_policy]
}

run "network_policy_accepts_open_aws_api_cidr_for_nat" {
  command = plan
  variables {
    network_policy = {
      service_cidr     = "172.20.0.0/16"
      api_server_cidrs = ["10.10.0.0/28"]
      aws_api_cidrs    = ["0.0.0.0/0"]
    }
  }
}

run "keda_rejects_v_prefix" {
  command = plan
  variables {
    keda = { chart_version = "v2.21.0" }
  }
  expect_failures = [var.keda]
}

run "keda_rejects_bad_namespace" {
  command = plan
  variables {
    keda = { namespace = "Keda" }
  }
  expect_failures = [var.keda]
}

run "keda_rejects_bad_service_account" {
  command = plan
  variables {
    keda = { service_account = "Keda_Op" }
  }
  expect_failures = [var.keda]
}

run "keda_rejects_non_object_values" {
  command = plan
  variables {
    keda = { values = "x" }
  }
  expect_failures = [var.keda]
}

run "keda_accepts_defaults" {
  command = plan
  variables {
    keda = {}
  }
}

run "cloudwatch_rejects_v_prefix" {
  command = plan
  variables {
    cloudwatch_observability = { chart_version = "v6.7.0" }
  }
  expect_failures = [var.cloudwatch_observability]
}

run "cloudwatch_rejects_bad_namespace" {
  command = plan
  variables {
    cloudwatch_observability = { namespace = "Amazon_CloudWatch" }
  }
  expect_failures = [var.cloudwatch_observability]
}

run "cloudwatch_rejects_bad_service_account" {
  command = plan
  variables {
    cloudwatch_observability = { service_account = "Cloud Watch" }
  }
  expect_failures = [var.cloudwatch_observability]
}

run "cloudwatch_rejects_non_object_values" {
  command = plan
  variables {
    cloudwatch_observability = { values = "x" }
  }
  expect_failures = [var.cloudwatch_observability]
}

run "cloudwatch_accepts_defaults" {
  command = plan
  variables {
    cloudwatch_observability = {}
  }
}

run "system_placement_rejects_bad_toleration_effect" {
  command = plan
  variables {
    system_placement = { tolerations = [{ key = "a", effect = "Never" }] }
  }
  expect_failures = [var.system_placement]
}

run "system_placement_rejects_bad_toleration_operator" {
  command = plan
  variables {
    system_placement = { tolerations = [{ key = "a", operator = "Like" }] }
  }
  expect_failures = [var.system_placement]
}

run "system_placement_rejects_empty_node_selector_key" {
  command = plan
  variables {
    system_placement = { node_selector = { "" = "x" } }
  }
  expect_failures = [var.system_placement]
}

run "system_placement_accepts_valid" {
  command = plan
  variables {
    system_placement = { node_selector = { tier = "system" }, tolerations = [{ key = "a", operator = "Equal", value = "b", effect = "NoExecute" }] }
  }
}

run "overrides_accept_keda_and_cloudwatch_keys" {
  command = plan
  variables {
    chart_repository_overrides = { keda = "https://example.com/keda", cloudwatch_observability = "oci://example.com/cw" }
  }
}
