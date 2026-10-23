mock_provider "aws" {}
mock_provider "helm" {}

# The SSM values are only read here, so fixed ones stand in for them (the mock would return random text).
override_module {
  target = module.in
  outputs = {
    strings = {
      contract_version = "1"
      cluster_name     = "example-dev"
      cluster_endpoint = "https://ABCDEF0123456789.gr7.ap-northeast-1.eks.amazonaws.com"
      cluster_ca_data  = "Y2VydGlmaWNhdGU="
      cluster_sg_id    = "sg-0aaaaaaa00000007"
      service_cidr     = "172.20.0.0/16"
      app_namespace    = "app"
    }
    lists = {}
  }
}

override_module {
  target = module.shared
  outputs = {
    strings = {
      vpc_id            = "vpc-0aaaaaaa00000001"
      app_sg_id         = "sg-0aaaaaaa00000002"
      node_sg_id        = "sg-0aaaaaaa00000006"
      eks_node_role_arn = "arn:aws:iam::111111111111:role/example-dev-eks-node"
    }
    lists = {
      app_subnet_cidrs = ["10.10.64.0/19", "10.10.96.0/19"]
    }
  }
}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
}

# ---- reads ----

run "reads_the_eks_contract_and_tree_b" {
  command = plan

  assert {
    condition = local.ssm_input_strings == {
      contract_version = "eks-cluster/contract_version"
      cluster_name     = "eks-cluster/cluster_name"
      cluster_endpoint = "eks-cluster/cluster_endpoint"
      cluster_ca_data  = "eks-cluster/cluster_ca_data"
      cluster_sg_id    = "eks-cluster/cluster_sg_id"
      service_cidr     = "eks-cluster/service_cidr"
      app_namespace    = "eks-cluster/app_namespace"
    }
    error_message = "eks-addons reads the versioned EKS contract from tree A"
  }

  assert {
    condition = local.shared_input_strings == {
      vpc_id            = "infra/vpc_id"
      app_sg_id         = "infra/app_sg_id"
      node_sg_id        = "infra/node_sg_id"
      eks_node_role_arn = "infra/eks_node_role_arn"
    } && local.shared_input_lists == { app_subnet_cidrs = "infra/app_subnet_cidrs" }
    error_message = "The network and node role values come from tree B"
  }
}

run "rejects_an_unknown_contract_version" {
  command = plan

  override_module {
    target = module.in
    outputs = {
      strings = {
        contract_version = "2"
        cluster_name     = "example-dev"
        cluster_endpoint = "https://ABCDEF0123456789.gr7.ap-northeast-1.eks.amazonaws.com"
        cluster_ca_data  = "Y2VydGlmaWNhdGU="
        cluster_sg_id    = "sg-0aaaaaaa00000007"
        service_cidr     = "172.20.0.0/16"
        app_namespace    = "app"
      }
      lists = {}
    }
  }

  expect_failures = [terraform_data.eks_contract_version]
}

# ---- node classes and pools (design v4 K1, K3) ----

run "app_class_puts_pods_on_the_app_group" {
  command = plan

  assert {
    condition = local.auto_mode.node_classes["app"] == {
      subnet_selector_terms             = [{ tags = { "eks-node" = "example-dev" } }]
      security_group_selector_terms     = [{ id = "sg-0aaaaaaa00000007" }, { id = "sg-0aaaaaaa00000006" }]
      pod_subnet_selector_terms         = [{ tags = { "eks-pod" = "example-dev" } }]
      pod_security_group_selector_terms = [{ id = "sg-0aaaaaaa00000002" }]
      network_policy                    = "DefaultDeny"
    }
    error_message = "app nodes get the cluster and node groups; app pods get the app group in the eks-pod subnets, under DefaultDeny"
  }

  assert {
    condition     = local.auto_mode.node_role_name == "example-dev-eks-node"
    error_message = "The NodeClasses use the node role that eks-cluster gave an EC2 access entry (a name, not an ARN)"
  }
}

run "system_class_has_no_pod_group" {
  command = plan

  assert {
    condition = local.auto_mode.node_classes["system"] == {
      subnet_selector_terms         = [{ tags = { "eks-node" = "example-dev" } }]
      security_group_selector_terms = [{ id = "sg-0aaaaaaa00000007" }, { id = "sg-0aaaaaaa00000006" }]
      network_policy                = "DefaultDeny"
    }
    error_message = "system pods use the node groups; only the app class has a Pod security group"
  }
}

run "system_pool_is_tainted_and_the_controllers_go_there" {
  command = plan

  variables {
    system_pool_cpu_limit = 8
  }

  assert {
    condition = (
      local.auto_mode.node_pools["system"].node_class == "system" &&
      local.auto_mode.node_pools["system"].taints == [{ key = "CriticalAddonsOnly", effect = "NoSchedule" }] &&
      local.auto_mode.node_pools["system"].cpu_limit == 8
    )
    error_message = "The system pool carries the CriticalAddonsOnly taint and its own CPU limit"
  }

  assert {
    condition = (
      local.auto_mode.node_pools["app"].node_class == "app" &&
      local.auto_mode.node_pools["app"].taints == [] &&
      local.auto_mode.node_pools["app"].cpu_limit == 100
    )
    error_message = "The app pool has no taint"
  }

  assert {
    condition = local.system_placement == {
      node_selector = { "karpenter.sh/nodepool" = "system" }
      tolerations   = [{ key = "CriticalAddonsOnly", operator = "Exists", effect = "NoSchedule" }]
    }
    error_message = "The LB Controller and KEDA select the system pool and tolerate its taint"
  }
}

# ---- NetworkPolicy (design v4 K5, C1-7) ----

run "aws_apis_through_nat_are_open" {
  command = plan

  assert {
    # tolist on both sides: the mocked SSM list is a tuple.
    condition = (
      local.network_policy.service_cidr == "172.20.0.0/16" &&
      tolist(local.network_policy.api_server_cidrs) == tolist(["10.10.64.0/19", "10.10.96.0/19"]) &&
      tolist(local.network_policy.aws_api_cidrs) == tolist(["0.0.0.0/0"])
    )
    error_message = "With NAT, AWS APIs are any address; the API server is the app subnets where the control-plane ENIs sit"
  }
}

run "aws_apis_without_nat_are_the_endpoint_subnets" {
  command = plan

  variables {
    nat_mode = "none"
  }

  assert {
    condition     = tolist(local.network_policy.aws_api_cidrs) == tolist(["10.10.64.0/19", "10.10.96.0/19"])
    error_message = "Without NAT, AWS APIs are only the interface endpoints in the app subnets"
  }
}

run "rejects_an_unknown_nat_mode" {
  command = plan

  variables {
    nat_mode = "single"
  }

  expect_failures = [var.nat_mode]
}

# ---- releases ----

run "installs_the_platform_components" {
  command = plan

  assert {
    condition = toset(keys(module.addons.releases)) == toset([
      "auto_mode_nodes", "system_network_policy", "load_balancer_controller", "keda", "cloudwatch_observability",
      "app_namespaces", "crd_role_aggregation",
    ])
    error_message = "Node pools, NetworkPolicy, the three controllers, the app namespace and the CRD role aggregation; nothing else"
  }

  assert {
    condition = (
      module.addons.releases["load_balancer_controller"].namespace == "kube-system" &&
      module.addons.releases["keda"].namespace == "keda" &&
      module.addons.releases["cloudwatch_observability"].namespace == "amazon-cloudwatch"
    )
    error_message = "The controllers stay at the module defaults that the eks-cluster Pod Identity associations use (design v4 C4-5)"
  }
}
