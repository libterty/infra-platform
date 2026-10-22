# Auto Mode node classes and pools (local chart auto-mode-nodes) and the LB Controller flags that depend on it.
# No cluster is contacted: helm is mocked.

mock_provider "helm" {}

variables {
  cluster_name = "alpha-dev"
  region       = "ap-northeast-1"
  vpc_id       = "vpc-0123456789abcdef0"
}

run "auto_mode_null_installs_nothing" {
  command = plan

  variables {
    load_balancer_controller = {}
  }

  assert {
    condition     = length(helm_release.auto_mode_nodes) == 0
    error_message = "auto_mode = null must not install the node chart"
  }

  assert {
    condition = (
      length([for s in helm_release.load_balancer_controller[0].set : s if s.name == "enableServiceMutatorWebhook"]) == 0 &&
      length([for s in helm_release.load_balancer_controller[0].set : s if s.name == "createIngressClassResource"]) == 0
    )
    error_message = "Without auto_mode the LB Controller flags must stay at the chart defaults"
  }
}

run "node_chart_release" {
  command = plan

  variables {
    auto_mode = {
      node_role_name = "alpha-dev-eks-node"
      node_classes = {
        app = {
          subnet_selector_terms         = [{ tags = { tier = "app" } }]
          security_group_selector_terms = [{ id = "sg-0123456789abcdef0" }]
        }
      }
      node_pools = {
        app = { node_class = "app" }
      }
    }
  }

  assert {
    condition = (
      helm_release.auto_mode_nodes[0].name == "auto-mode-nodes" &&
      helm_release.auto_mode_nodes[0].version == "0.1.0" &&
      helm_release.auto_mode_nodes[0].namespace == "kube-system" &&
      helm_release.auto_mode_nodes[0].repository == null &&
      endswith(helm_release.auto_mode_nodes[0].chart, "/charts/auto-mode-nodes") &&
      helm_release.auto_mode_nodes[0].atomic &&
      helm_release.auto_mode_nodes[0].cleanup_on_fail
    )
    error_message = "auto-mode-nodes must be the local chart at version 0.1.0, atomic, in kube-system"
  }

  assert {
    condition = output.releases.auto_mode_nodes == {
      name      = "auto-mode-nodes"
      namespace = "kube-system"
      version   = "0.1.0"
    }
    error_message = "releases must list auto_mode_nodes"
  }
}

run "node_class_defaults" {
  command = plan

  variables {
    auto_mode = {
      node_role_name = "alpha-dev-eks-node"
      node_classes = {
        system = {
          subnet_selector_terms         = [{ tags = { tier = "app" } }]
          security_group_selector_terms = [{ id = "sg-0123456789abcdef0" }, { tags = { tier = "node" } }]
        }
      }
      node_pools = {
        system = { node_class = "system" }
      }
    }
  }

  assert {
    condition     = yamldecode(helm_release.auto_mode_nodes[0].values[0]).nodeRoleName == "alpha-dev-eks-node"
    error_message = "The node role name must reach the chart"
  }

  assert {
    condition = yamldecode(helm_release.auto_mode_nodes[0].values[0]).nodeClasses.system == {
      subnetSelectorTerms           = [{ tags = { tier = "app" } }]
      securityGroupSelectorTerms    = [{ id = "sg-0123456789abcdef0" }, { tags = { tier = "node" } }]
      podSubnetSelectorTerms        = []
      podSecurityGroupSelectorTerms = []
      networkPolicy                 = "DefaultDeny"
      networkPolicyEventLogs        = "Disabled"
    }
    error_message = "A node class without pod terms must carry empty pod terms, DefaultDeny and event logs Disabled"
  }
}

run "node_class_pod_terms_come_together" {
  command = plan

  variables {
    auto_mode = {
      node_role_name = "alpha-dev-eks-node"
      node_classes = {
        app = {
          subnet_selector_terms             = [{ tags = { tier = "app" } }]
          security_group_selector_terms     = [{ id = "sg-0123456789abcdef0" }]
          pod_subnet_selector_terms         = [{ tags = { tier = "app" } }]
          pod_security_group_selector_terms = [{ id = "sg-0fedcba9876543210" }]
          network_policy                    = "DefaultAllow"
          network_policy_event_logs         = "Enabled"
        }
      }
      node_pools = {
        app = { node_class = "app" }
      }
    }
  }

  assert {
    condition = (
      yamldecode(helm_release.auto_mode_nodes[0].values[0]).nodeClasses.app.podSubnetSelectorTerms == [{ tags = { tier = "app" } }] &&
      yamldecode(helm_release.auto_mode_nodes[0].values[0]).nodeClasses.app.podSecurityGroupSelectorTerms == [{ id = "sg-0fedcba9876543210" }]
    )
    error_message = "Pod subnet and pod security group terms must both reach the chart"
  }

  assert {
    condition = (
      yamldecode(helm_release.auto_mode_nodes[0].values[0]).nodeClasses.app.networkPolicy == "DefaultAllow" &&
      yamldecode(helm_release.auto_mode_nodes[0].values[0]).nodeClasses.app.networkPolicyEventLogs == "Enabled"
    )
    error_message = "network_policy and network_policy_event_logs must be passed"
  }
}

run "node_pool_values" {
  command = plan

  variables {
    auto_mode = {
      node_role_name = "alpha-dev-eks-node"
      node_classes = {
        app    = { subnet_selector_terms = [{ tags = { tier = "app" } }], security_group_selector_terms = [{ id = "sg-0123456789abcdef0" }] }
        system = { subnet_selector_terms = [{ tags = { tier = "app" } }], security_group_selector_terms = [{ id = "sg-0123456789abcdef0" }] }
      }
      node_pools = {
        app = {
          node_class          = "app"
          capacity_types      = ["on-demand", "spot"]
          instance_categories = ["c", "m"]
          cpu_limit           = 200
        }
        system = {
          node_class = "system"
          taints     = [{ key = "CriticalAddonsOnly", value = "true", effect = "NoSchedule" }, { key = "dedicated", effect = "NoExecute" }]
          labels     = { "workload-tier" = "system" }
        }
      }
    }
  }

  assert {
    condition = yamldecode(helm_release.auto_mode_nodes[0].values[0]).nodePools.app == {
      nodeClass          = "app"
      taints             = []
      labels             = {}
      capacityTypes      = ["on-demand", "spot"]
      instanceCategories = ["c", "m"]
      architectures      = ["amd64"]
      cpuLimit           = 200
    }
    error_message = "The app pool must carry its class, capacity types, instance categories and cpu limit; no taints"
  }

  assert {
    condition = yamldecode(helm_release.auto_mode_nodes[0].values[0]).nodePools.system == {
      nodeClass = "system"
      taints = [
        { key = "CriticalAddonsOnly", value = "true", effect = "NoSchedule" },
        { key = "dedicated", effect = "NoExecute" },
      ]
      labels             = { "workload-tier" = "system" }
      capacityTypes      = ["on-demand"]
      instanceCategories = []
      architectures      = ["amd64"]
      cpuLimit           = 100
    }
    error_message = "The system pool must carry its taints (value optional), labels and the defaults"
  }
}

run "lb_controller_flags_forced_under_auto_mode" {
  command = plan

  variables {
    load_balancer_controller = {
      values = { enableServiceMutatorWebhook = true, createIngressClassResource = true }
    }
    auto_mode = {
      node_role_name = "alpha-dev-eks-node"
      node_classes = {
        app = { subnet_selector_terms = [{ tags = { tier = "app" } }], security_group_selector_terms = [{ id = "sg-0123456789abcdef0" }] }
      }
      node_pools = {
        app = { node_class = "app" }
      }
    }
  }

  # set wins over values in Helm, so the user values above cannot turn the flags back on.
  assert {
    condition = (
      [for s in helm_release.load_balancer_controller[0].set : s.value if s.name == "enableServiceMutatorWebhook"] == ["false"] &&
      [for s in helm_release.load_balancer_controller[0].set : s.value if s.name == "createIngressClassResource"] == ["false"]
    )
    error_message = "auto_mode must force enableServiceMutatorWebhook and createIngressClassResource to false through set"
  }

  assert {
    condition = {
      for s in helm_release.load_balancer_controller[0].set : s.name => s.value
      } == {
      clusterName                 = "alpha-dev"
      region                      = "ap-northeast-1"
      vpcId                       = "vpc-0123456789abcdef0"
      "serviceAccount.name"       = "aws-load-balancer-controller"
      replicaCount                = "2"
      enableServiceMutatorWebhook = "false"
      createIngressClassResource  = "false"
    }
    error_message = "The forced flags are added to the existing set entries"
  }
}
