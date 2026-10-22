# Which helm releases exist and what they are given. No cluster is contacted: helm is mocked.

mock_provider "helm" {}

variables {
  cluster_name = "alpha-dev"
  region       = "ap-northeast-1"
  vpc_id       = "vpc-0123456789abcdef0"
}

run "all_null_installs_nothing" {
  command = plan

  assert {
    condition = (
      length(helm_release.load_balancer_controller) == 0 &&
      length(helm_release.karpenter) == 0 &&
      length(helm_release.karpenter_defaults) == 0 &&
      length(helm_release.argo_rollouts) == 0 &&
      length(helm_release.app_namespaces) == 0 &&
      length(helm_release.auto_mode_nodes) == 0 &&
      length(helm_release.system_network_policy) == 0 &&
      length(helm_release.keda) == 0 &&
      length(helm_release.cloudwatch_observability) == 0
    )
    error_message = "With every component null no release may be planned"
  }

  assert {
    condition     = output.releases == {}
    error_message = "releases output must be empty when nothing is installed"
  }
}

run "chart_defaults" {
  command = plan

  variables {
    load_balancer_controller = {}
    karpenter                = { interruption_queue_name = "alpha-dev" }
    argo_rollouts            = {}
  }

  assert {
    condition     = helm_release.load_balancer_controller[0].version == "3.6.1"
    error_message = "LB Controller chart default must be 3.6.1"
  }

  assert {
    condition     = helm_release.karpenter[0].version == "1.15.0"
    error_message = "Karpenter chart default must be 1.15.0"
  }

  assert {
    condition     = helm_release.argo_rollouts[0].version == "2.43.8"
    error_message = "Argo Rollouts chart default must be 2.43.8"
  }

  assert {
    condition = (
      helm_release.load_balancer_controller[0].repository == "https://aws.github.io/eks-charts" &&
      helm_release.load_balancer_controller[0].chart == "aws-load-balancer-controller" &&
      helm_release.load_balancer_controller[0].namespace == "kube-system" &&
      helm_release.load_balancer_controller[0].name == "aws-load-balancer-controller"
    )
    error_message = "LB Controller must come from the eks-charts repository into kube-system"
  }

  assert {
    condition = (
      helm_release.karpenter[0].repository == "oci://public.ecr.aws/karpenter" &&
      helm_release.karpenter[0].chart == "karpenter" &&
      helm_release.karpenter[0].namespace == "kube-system"
    )
    error_message = "Karpenter must come from the public ECR OCI repository into kube-system"
  }

  assert {
    condition = (
      helm_release.argo_rollouts[0].repository == "https://argoproj.github.io/argo-helm" &&
      helm_release.argo_rollouts[0].chart == "argo-rollouts" &&
      helm_release.argo_rollouts[0].namespace == "argo-rollouts"
    )
    error_message = "Argo Rollouts must come from argo-helm into argo-rollouts"
  }

  assert {
    condition = alltrue([
      for r in [helm_release.load_balancer_controller[0], helm_release.karpenter[0], helm_release.argo_rollouts[0]] :
      r.atomic && r.cleanup_on_fail && r.timeout == 600
    ])
    error_message = "Controller releases must be atomic with cleanup_on_fail and a 600 second timeout"
  }
}

run "load_balancer_controller_values" {
  command = plan

  variables {
    load_balancer_controller = {}
  }

  assert {
    condition = {
      for s in helm_release.load_balancer_controller[0].set : s.name => s.value
      } == {
      clusterName           = "alpha-dev"
      region                = "ap-northeast-1"
      vpcId                 = "vpc-0123456789abcdef0"
      "serviceAccount.name" = "aws-load-balancer-controller"
      replicaCount          = "2"
    }
    error_message = "LB Controller must receive clusterName, region, vpcId, serviceAccount.name and replicaCount"
  }
}

run "load_balancer_controller_overrides_and_extra_values" {
  command = plan

  variables {
    load_balancer_controller = {
      chart_version   = "3.7.0"
      service_account = "lbc"
      replica_count   = 3
      values          = { enableShield = false, tolerations = [{ key = "CriticalAddonsOnly", operator = "Exists" }] }
    }
  }

  assert {
    condition     = helm_release.load_balancer_controller[0].version == "3.7.0"
    error_message = "chart_version must be overridable"
  }

  assert {
    condition = (
      [for s in helm_release.load_balancer_controller[0].set : s.value if s.name == "serviceAccount.name"][0] == "lbc" &&
      [for s in helm_release.load_balancer_controller[0].set : s.value if s.name == "replicaCount"][0] == "3"
    )
    error_message = "service_account and replica_count must reach the chart"
  }

  assert {
    condition     = yamldecode(helm_release.load_balancer_controller[0].values[0]).enableShield == false
    error_message = "values must be passed through as YAML"
  }
}

run "karpenter_values" {
  command = plan

  variables {
    karpenter = {
      interruption_queue_name = "alpha-dev"
      namespace               = "karpenter"
      service_account         = "karpenter-controller"
    }
  }

  assert {
    condition = {
      for s in helm_release.karpenter[0].set : s.name => s.value
      } == {
      "settings.clusterName"       = "alpha-dev"
      "settings.interruptionQueue" = "alpha-dev"
      "serviceAccount.name"        = "karpenter-controller"
    }
    error_message = "Karpenter must receive settings.clusterName, settings.interruptionQueue and serviceAccount.name"
  }

  assert {
    condition     = helm_release.karpenter[0].namespace == "karpenter" && helm_release.karpenter[0].create_namespace
    error_message = "A non kube-system namespace must be created by the release"
  }
}

run "karpenter_defaults_need_node_class_and_pool" {
  command = plan

  variables {
    karpenter = { interruption_queue_name = "alpha-dev" }
  }

  assert {
    condition     = length(helm_release.karpenter_defaults) == 0
    error_message = "Without default_node_class and default_node_pool the defaults chart must not be installed"
  }
}

run "karpenter_defaults_not_installed_without_node_pool" {
  command = plan

  variables {
    karpenter = {
      interruption_queue_name = "alpha-dev"
      default_node_class = {
        node_role_name               = "alpha-dev-karpenter-node"
        subnet_discovery_tag         = { "karpenter.sh/discovery" = "alpha-dev" }
        security_group_discovery_tag = { "karpenter.sh/discovery" = "alpha-dev" }
      }
    }
  }

  assert {
    condition     = length(helm_release.karpenter_defaults) == 0
    error_message = "default_node_pool = null must skip the defaults chart"
  }
}

run "karpenter_defaults_not_installed_without_node_class" {
  command = plan

  variables {
    karpenter = {
      interruption_queue_name = "alpha-dev"
      default_node_pool       = {}
    }
  }

  assert {
    condition     = length(helm_release.karpenter_defaults) == 0
    error_message = "default_node_class = null must skip the defaults chart"
  }
}

run "karpenter_defaults_installed_with_both" {
  command = plan

  variables {
    karpenter = {
      interruption_queue_name = "alpha-dev"
      default_node_class = {
        node_role_name               = "alpha-dev-karpenter-node"
        subnet_discovery_tag         = { "karpenter.sh/discovery" = "alpha-dev" }
        security_group_discovery_tag = { "karpenter.sh/discovery" = "alpha-dev" }
      }
      default_node_pool = { cpu_limit = 50, capacity_types = ["on-demand", "spot"] }
    }
  }

  assert {
    condition     = length(helm_release.karpenter_defaults) == 1
    error_message = "Both objects set must install the defaults chart"
  }

  assert {
    condition = (
      helm_release.karpenter_defaults[0].name == "karpenter-defaults" &&
      helm_release.karpenter_defaults[0].version == "0.1.0" &&
      helm_release.karpenter_defaults[0].namespace == "kube-system" &&
      helm_release.karpenter_defaults[0].repository == null &&
      endswith(helm_release.karpenter_defaults[0].chart, "/charts/karpenter-defaults")
    )
    error_message = "karpenter-defaults must be the local chart at version 0.1.0 in the Karpenter namespace"
  }

  assert {
    condition = yamldecode(helm_release.karpenter_defaults[0].values[0]) == {
      nodeClass = {
        role              = "alpha-dev-karpenter-node"
        subnetTags        = { "karpenter.sh/discovery" = "alpha-dev" }
        securityGroupTags = { "karpenter.sh/discovery" = "alpha-dev" }
        amiAlias          = "al2023@latest"
      }
      nodePool = {
        cpuLimit      = 50
        capacityTypes = ["on-demand", "spot"]
      }
    }
    error_message = "Chart values must carry the node class and node pool inputs"
  }
}

run "karpenter_default_pool_defaults" {
  command = plan

  variables {
    karpenter = {
      interruption_queue_name = "alpha-dev"
      default_node_class = {
        node_role_name               = "alpha-dev-karpenter-node"
        subnet_discovery_tag         = { "karpenter.sh/discovery" = "alpha-dev" }
        security_group_discovery_tag = { "karpenter.sh/discovery" = "alpha-dev" }
        ami_alias                    = "al2023@v20250101"
      }
      default_node_pool = {}
    }
  }

  assert {
    condition = (
      yamldecode(helm_release.karpenter_defaults[0].values[0]).nodePool.cpuLimit == 100 &&
      yamldecode(helm_release.karpenter_defaults[0].values[0]).nodePool.capacityTypes == ["on-demand"] &&
      yamldecode(helm_release.karpenter_defaults[0].values[0]).nodeClass.amiAlias == "al2023@v20250101"
    )
    error_message = "default_node_pool = {} must give cpu_limit 100 and on-demand only; ami_alias must be passed"
  }
}

run "karpenter_null_never_installs_defaults" {
  command = plan

  # default_node_class and default_node_pool are attributes of the karpenter object, so they cannot be set without it.
  variables {
    karpenter = null
  }

  assert {
    condition     = length(helm_release.karpenter) == 0 && length(helm_release.karpenter_defaults) == 0
    error_message = "karpenter = null must install neither Karpenter nor its defaults"
  }
}

run "argo_rollouts_values" {
  command = plan

  variables {
    argo_rollouts = {
      chart_version = "2.44.0"
      namespace     = "rollouts"
      values        = { dashboard = { enabled = true } }
    }
  }

  assert {
    condition = (
      helm_release.argo_rollouts[0].version == "2.44.0" &&
      helm_release.argo_rollouts[0].namespace == "rollouts" &&
      helm_release.argo_rollouts[0].create_namespace &&
      yamldecode(helm_release.argo_rollouts[0].values[0]).dashboard.enabled == true
    )
    error_message = "Argo Rollouts must honor chart_version, namespace and values"
  }
}

run "app_namespaces_empty_installs_nothing" {
  command = plan

  variables {
    app_namespaces = {}
  }

  assert {
    condition     = length(helm_release.app_namespaces) == 0
    error_message = "An empty app_namespaces must not install the chart"
  }
}

run "app_namespaces_installed" {
  command = plan

  variables {
    app_namespaces = {
      payments = { labels = { team = "pay" } }
      web      = {}
    }
  }

  assert {
    condition = (
      helm_release.app_namespaces[0].name == "app-namespaces" &&
      helm_release.app_namespaces[0].version == "0.1.0" &&
      helm_release.app_namespaces[0].namespace == "kube-system" &&
      endswith(helm_release.app_namespaces[0].chart, "/charts/app-namespaces")
    )
    error_message = "app-namespaces must be the local chart at version 0.1.0"
  }

  assert {
    condition = yamldecode(helm_release.app_namespaces[0].values[0]) == {
      namespaces = {
        payments = { labels = { team = "pay" } }
        web      = { labels = {} }
      }
    }
    error_message = "Chart values must list every namespace with its labels"
  }
}

run "chart_repository_overrides" {
  command = plan

  variables {
    load_balancer_controller = {}
    karpenter                = { interruption_queue_name = "alpha-dev" }
    argo_rollouts            = {}
    chart_repository_overrides = {
      load_balancer_controller = "oci://111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/mirror"
      karpenter                = "oci://111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/karpenter-mirror"
    }
  }

  assert {
    condition     = helm_release.load_balancer_controller[0].repository == "oci://111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/mirror"
    error_message = "LB Controller repository override must apply"
  }

  assert {
    condition     = helm_release.karpenter[0].repository == "oci://111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/karpenter-mirror"
    error_message = "Karpenter repository override must apply"
  }

  assert {
    condition     = helm_release.argo_rollouts[0].repository == "https://argoproj.github.io/argo-helm"
    error_message = "A component without an override keeps its default repository"
  }
}

run "outputs_list_installed_releases_only" {
  command = plan

  variables {
    load_balancer_controller = {}
    app_namespaces           = { web = {} }
  }

  assert {
    condition = output.releases == {
      load_balancer_controller = {
        name      = "aws-load-balancer-controller"
        namespace = "kube-system"
        version   = "3.6.1"
      }
      app_namespaces = {
        name      = "app-namespaces"
        namespace = "kube-system"
        version   = "0.1.0"
      }
    }
    error_message = "releases must contain exactly the installed components with name, namespace and version"
  }
}

run "karpenter_values_are_passed" {
  command = plan

  variables {
    karpenter = {
      interruption_queue_name = "alpha-dev"
      values = {
        controller = { image = { repository = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/karpenter/controller" } }
      }
    }
  }

  assert {
    condition     = strcontains(helm_release.karpenter[0].values[0], "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/karpenter/controller")
    error_message = "karpenter.values must reach the release values"
  }
}
