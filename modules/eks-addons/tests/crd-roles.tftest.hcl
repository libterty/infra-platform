# aggregate_crd_roles: lets a namespace-scoped edit or admin (for example AmazonEKSEditPolicy) manage the custom
# resources that application charts create. No cluster is contacted: helm is mocked.

mock_provider "helm" {}

variables {
  cluster_name = "alpha-dev"
  region       = "ap-northeast-1"
  vpc_id       = "vpc-0123456789abcdef0"
}

run "off_by_default" {
  command = plan

  variables {
    load_balancer_controller = {}
    keda                     = {}
  }

  assert {
    condition     = length(helm_release.crd_role_aggregation) == 0
    error_message = "Without aggregate_crd_roles no aggregation release may be planned"
  }

  assert {
    condition     = !contains([for s in helm_release.keda[0].set : s.name], "rbac.aggregateToDefaultRoles")
    error_message = "Without aggregate_crd_roles the KEDA chart default for rbac.aggregateToDefaultRoles is kept"
  }
}

run "aggregates_target_group_bindings_with_the_lb_controller" {
  command = plan

  variables {
    aggregate_crd_roles      = true
    load_balancer_controller = {}
  }

  assert {
    condition     = length(helm_release.crd_role_aggregation) == 1
    error_message = "With the LB Controller installed, the TargetGroupBinding roles are installed"
  }

  assert {
    condition = (
      helm_release.crd_role_aggregation[0].name == "crd-role-aggregation" &&
      helm_release.crd_role_aggregation[0].namespace == "kube-system" &&
      endswith(helm_release.crd_role_aggregation[0].chart, "/charts/crd-role-aggregation")
    )
    error_message = "The roles come from the local chart crd-role-aggregation, with its release Secret in kube-system"
  }

  assert {
    condition     = yamldecode(helm_release.crd_role_aggregation[0].values[0]) == { targetGroupBindings = true }
    error_message = "The chart gets only the components whose roles it renders"
  }

  assert {
    condition     = output.releases["crd_role_aggregation"].name == "crd-role-aggregation"
    error_message = "The releases output lists the aggregation release"
  }
}

run "no_lb_controller_no_target_group_binding_roles" {
  command = plan

  variables {
    aggregate_crd_roles = true
    keda                = {}
  }

  assert {
    condition     = length(helm_release.crd_role_aggregation) == 0
    error_message = "Without the LB Controller the TargetGroupBinding CRD does not exist, so no roles for it"
  }
}

run "turns_on_the_keda_aggregation" {
  command = plan

  variables {
    aggregate_crd_roles = true
    keda                = { values = { rbac = { aggregateToDefaultRoles = false } } }
  }

  assert {
    condition     = [for s in helm_release.keda[0].set : s.value if s.name == "rbac.aggregateToDefaultRoles"] == ["true"]
    error_message = "KEDA ships its own aggregated roles; the module turns them on through set, which wins over values"
  }
}
