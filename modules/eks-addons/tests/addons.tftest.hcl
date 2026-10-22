# KEDA, CloudWatch observability and system placement. No cluster is contacted: helm is mocked.

mock_provider "helm" {}

variables {
  cluster_name = "alpha-dev"
  region       = "ap-northeast-1"
  vpc_id       = "vpc-0123456789abcdef0"
}

run "keda_and_cloudwatch_off_by_default" {
  command = plan

  assert {
    condition     = length(helm_release.keda) == 0 && length(helm_release.cloudwatch_observability) == 0
    error_message = "KEDA and CloudWatch observability must not be installed by default"
  }
}

run "keda_defaults" {
  command = plan

  variables {
    keda = {}
  }

  assert {
    condition = (
      helm_release.keda[0].name == "keda" &&
      helm_release.keda[0].chart == "keda" &&
      helm_release.keda[0].repository == "https://kedacore.github.io/charts" &&
      helm_release.keda[0].version == "2.21.0" &&
      helm_release.keda[0].namespace == "keda" &&
      helm_release.keda[0].create_namespace &&
      helm_release.keda[0].atomic &&
      helm_release.keda[0].cleanup_on_fail &&
      helm_release.keda[0].timeout == 600
    )
    error_message = "KEDA must be chart kedacore/keda 2.21.0 in namespace keda, atomic"
  }

  assert {
    condition = {
      for s in helm_release.keda[0].set : s.name => s.value
      } == {
      "serviceAccount.operator.name" = "keda-operator"
    }
    error_message = "KEDA must receive the operator service account name"
  }

  assert {
    condition     = yamldecode(helm_release.keda[0].values[0]) == {}
    error_message = "Without placement or extra values KEDA gets empty values"
  }
}

run "keda_overrides" {
  command = plan

  variables {
    keda = {
      chart_version   = "2.22.0"
      namespace       = "autoscaling"
      service_account = "keda-op"
      values          = { logging = { operator = { level = "debug" } } }
    }
  }

  assert {
    condition = (
      helm_release.keda[0].version == "2.22.0" &&
      helm_release.keda[0].namespace == "autoscaling" &&
      [for s in helm_release.keda[0].set : s.value if s.name == "serviceAccount.operator.name"][0] == "keda-op" &&
      yamldecode(helm_release.keda[0].values[0]).logging.operator.level == "debug"
    )
    error_message = "KEDA version, namespace, service account and extra values must be honored"
  }
}

run "cloudwatch_defaults" {
  command = plan

  variables {
    cloudwatch_observability = {}
  }

  assert {
    condition = (
      helm_release.cloudwatch_observability[0].name == "amazon-cloudwatch-observability" &&
      helm_release.cloudwatch_observability[0].chart == "amazon-cloudwatch-observability" &&
      helm_release.cloudwatch_observability[0].repository == "https://aws-observability.github.io/helm-charts" &&
      helm_release.cloudwatch_observability[0].version == "6.7.0" &&
      helm_release.cloudwatch_observability[0].namespace == "amazon-cloudwatch" &&
      helm_release.cloudwatch_observability[0].create_namespace &&
      helm_release.cloudwatch_observability[0].atomic
    )
    error_message = "CloudWatch observability must be chart 6.7.0 in namespace amazon-cloudwatch, atomic"
  }

  assert {
    condition = {
      for s in helm_release.cloudwatch_observability[0].set : s.name => s.value
      } == {
      clusterName                  = "alpha-dev"
      region                       = "ap-northeast-1"
      "agent.serviceAccount.name"  = "cloudwatch-agent"
      "containerInsights.enabled"  = "true"
      "containerLogs.enabled"      = "true"
      "applicationSignals.enabled" = "false"
    }
    error_message = "CloudWatch observability: cluster, region, shared service account, Container Insights and logs on, Application Signals off"
  }

  assert {
    condition     = yamldecode(helm_release.cloudwatch_observability[0].values[0]) == {}
    error_message = "The chart tolerate-all default must stay: no tolerations or node selector in the values"
  }
}

run "cloudwatch_overrides" {
  command = plan

  variables {
    cloudwatch_observability = {
      chart_version       = "6.8.0"
      namespace           = "observability"
      service_account     = "cw-agent"
      container_logs      = false
      application_signals = true
      values              = { agent = { resources = { limits = { memory = "1Gi" } } } }
    }
  }

  assert {
    condition = (
      helm_release.cloudwatch_observability[0].version == "6.8.0" &&
      helm_release.cloudwatch_observability[0].namespace == "observability" &&
      [for s in helm_release.cloudwatch_observability[0].set : s.value if s.name == "agent.serviceAccount.name"][0] == "cw-agent" &&
      [for s in helm_release.cloudwatch_observability[0].set : s.value if s.name == "containerLogs.enabled"][0] == "false" &&
      [for s in helm_release.cloudwatch_observability[0].set : s.value if s.name == "applicationSignals.enabled"][0] == "true" &&
      yamldecode(helm_release.cloudwatch_observability[0].values[0]).agent.resources.limits.memory == "1Gi"
    )
    error_message = "CloudWatch observability overrides must reach the release"
  }
}

run "system_placement_applies_to_lbc_and_keda_only" {
  command = plan

  variables {
    load_balancer_controller = {}
    keda                     = {}
    cloudwatch_observability = {}
    argo_rollouts            = {}
    system_placement = {
      node_selector = { "workload-tier" = "system" }
      tolerations   = [{ key = "CriticalAddonsOnly", operator = "Exists", effect = "NoSchedule" }]
    }
  }

  assert {
    condition = alltrue([
      for v in [
        yamldecode(helm_release.load_balancer_controller[0].values[0]),
        yamldecode(helm_release.keda[0].values[0]),
      ] :
      v.nodeSelector == { "workload-tier" = "system" } &&
      v.tolerations == [{ key = "CriticalAddonsOnly", operator = "Exists", effect = "NoSchedule" }]
    ])
    error_message = "LB Controller and KEDA must get the node selector and tolerations at the chart top level"
  }

  assert {
    condition = (
      yamldecode(helm_release.cloudwatch_observability[0].values[0]) == {} &&
      yamldecode(helm_release.argo_rollouts[0].values[0]) == {}
    )
    error_message = "CloudWatch DaemonSets must keep tolerating everything; other releases are not placed"
  }
}

run "system_placement_wins_over_user_values" {
  command = plan

  variables {
    keda = { values = { nodeSelector = { other = "pool" }, replicaCount = 1 } }
    system_placement = {
      node_selector = { "workload-tier" = "system" }
    }
  }

  assert {
    condition = (
      yamldecode(helm_release.keda[0].values[0]).nodeSelector == { "workload-tier" = "system" } &&
      yamldecode(helm_release.keda[0].values[0]).replicaCount == 1 &&
      yamldecode(helm_release.keda[0].values[0]).tolerations == []
    )
    error_message = "system_placement must win over the same keys in values; other keys stay"
  }
}

run "toleration_nulls_are_dropped" {
  command = plan

  variables {
    keda = {}
    system_placement = {
      tolerations = [{ operator = "Exists" }]
    }
  }

  assert {
    condition     = yamldecode(helm_release.keda[0].values[0]).tolerations == [{ operator = "Exists" }]
    error_message = "Unset toleration fields must not be rendered as null"
  }
}

run "chart_repository_overrides_for_new_components" {
  command = plan

  variables {
    keda                     = {}
    cloudwatch_observability = {}
    chart_repository_overrides = {
      keda                     = "oci://111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/keda-mirror"
      cloudwatch_observability = "oci://111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/cw-mirror"
    }
  }

  assert {
    condition = (
      helm_release.keda[0].repository == "oci://111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/keda-mirror" &&
      helm_release.cloudwatch_observability[0].repository == "oci://111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/cw-mirror"
    )
    error_message = "keda and cloudwatch_observability repository overrides must apply"
  }
}
