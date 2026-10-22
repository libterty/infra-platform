mock_provider "aws" {}

# The SSM values are only read here, so fixed ones stand in for them (the mock would return random text).
override_module {
  target = module.shared
  outputs = {
    strings = {
      eks_api_sg_id             = "sg-0aaaaaaa00000005"
      eks_cluster_role_arn      = "arn:aws:iam::111111111111:role/example-dev-eks-cluster"
      eks_node_role_arn         = "arn:aws:iam::111111111111:role/example-dev-eks-node"
      api_pod_role_arn          = "arn:aws:iam::111111111111:role/example-dev-api-pod"
      worker_pod_role_arn       = "arn:aws:iam::111111111111:role/example-dev-worker-pod"
      lb_controller_role_arn    = "arn:aws:iam::111111111111:role/example-dev-lb-controller"
      keda_role_arn             = "arn:aws:iam::111111111111:role/example-dev-keda"
      cloudwatch_agent_role_arn = "arn:aws:iam::111111111111:role/example-dev-cloudwatch-agent"
    }
    lists = {
      app_subnet_ids = ["subnet-0bbbbbbb00000001", "subnet-0bbbbbbb00000002"]
    }
  }
}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
  # Required variables of this stack, so the account checks can plan.
  kubernetes_version           = "1.36"
  cluster_admin_principal_arns = ["arn:aws:iam::111111111111:role/example-dev-eks-admin"]
  addons_apply_principal_arn   = "arn:aws:iam::111111111111:role/example-dev-eks-addons-apply"
  ci_deploy_principal_arn      = "arn:aws:iam::111111111111:role/example-dev-ci-deploy"
}

# ---- reads ----

run "reads_only_tree_b" {
  command = plan

  assert {
    condition = local.shared_input_strings == {
      eks_api_sg_id             = "infra/eks_api_sg_id"
      eks_cluster_role_arn      = "infra/eks_cluster_role_arn"
      eks_node_role_arn         = "infra/eks_node_role_arn"
      api_pod_role_arn          = "infra/api_pod_role_arn"
      worker_pod_role_arn       = "infra/worker_pod_role_arn"
      lb_controller_role_arn    = "infra/lb_controller_role_arn"
      keda_role_arn             = "infra/keda_role_arn"
      cloudwatch_agent_role_arn = "infra/cloudwatch_agent_role_arn"
    }
    error_message = "eks-cluster runs after bridge, so it reads the API SG and the seven EKS roles from tree B"
  }

  assert {
    condition     = local.shared_input_lists == { app_subnet_ids = "infra/app_subnet_ids" }
    error_message = "The control-plane subnets are the app subnets from tree B"
  }
}

# ---- cluster ----

run "cluster_name_matches_the_pod_identity_trust" {
  command = plan

  assert {
    condition     = module.eks.cluster_name == "example-dev"
    error_message = "iam scopes the Pod Identity roles to cluster <project>-<env>; the cluster must have that name"
  }

  assert {
    condition     = module.secrets_key.alias_name == "alias/example-dev-eks-secrets"
    error_message = "The secrets encryption key is created here, named after the cluster"
  }
}

# ---- access entries ----

run "node_entry_is_ec2_with_the_auto_node_policy" {
  command = plan

  assert {
    condition = local.access_entries["node"] == {
      principal_arn = "arn:aws:iam::111111111111:role/example-dev-eks-node"
      type          = "EC2"
      policies      = { auto_node = { policy = "AmazonEKSAutoNodePolicy", namespaces = [] } }
    }
    error_message = "The node role needs an EC2 entry holding AmazonEKSAutoNodePolicy at cluster scope (design v4 K4)"
  }
}

run "ci_deploy_is_limited_to_the_app_namespace" {
  command = plan

  variables {
    app_namespace = "shop"
  }

  assert {
    condition = local.access_entries["ci_deploy"] == {
      principal_arn = "arn:aws:iam::111111111111:role/example-dev-ci-deploy"
      type          = "STANDARD"
      policies      = { edit = { policy = "AmazonEKSEditPolicy", namespaces = ["shop"] } }
    }
    error_message = "CI gets AmazonEKSEditPolicy in app_namespace only, never cluster scope"
  }
}

run "admins_and_the_addons_runner_are_cluster_admins" {
  command = plan

  variables {
    cluster_admin_principal_arns = ["arn:aws:iam::111111111111:role/example-dev-eks-admin", "arn:aws:iam::111111111111:user/someone"]
  }

  assert {
    condition = toset(keys(local.access_entries)) == toset([
      "node", "addons_apply", "ci_deploy",
      "admin-arn:aws:iam::111111111111:role/example-dev-eks-admin", "admin-arn:aws:iam::111111111111:user/someone",
    ])
    error_message = "One entry per admin, plus the node, eks-addons and CI entries; nothing else"
  }

  assert {
    condition = alltrue([
      for k, e in local.access_entries : e.type == "STANDARD" && e.policies == { admin = { policy = "AmazonEKSClusterAdminPolicy", namespaces = [] } }
      if k != "node" && k != "ci_deploy"
    ])
    error_message = "Admins and the eks-addons runner hold AmazonEKSClusterAdminPolicy at cluster scope"
  }

  assert {
    condition     = local.access_entries["addons_apply"].principal_arn == "arn:aws:iam::111111111111:role/example-dev-eks-addons-apply"
    error_message = "The eks-addons runner entry uses addons_apply_principal_arn"
  }
}

run "rejects_no_admin" {
  command = plan

  variables {
    cluster_admin_principal_arns = []
  }

  expect_failures = [var.cluster_admin_principal_arns]
}

run "rejects_an_empty_ci_principal" {
  command = plan

  variables {
    ci_deploy_principal_arn = ""
  }

  expect_failures = [var.ci_deploy_principal_arn]
}

run "rejects_an_empty_addons_principal" {
  command = plan

  variables {
    addons_apply_principal_arn = ""
  }

  expect_failures = [var.addons_apply_principal_arn]
}

run "rejects_one_principal_in_two_roles" {
  command = plan

  variables {
    ci_deploy_principal_arn = "arn:aws:iam::111111111111:role/example-dev-eks-addons-apply"
  }

  expect_failures = [var.ci_deploy_principal_arn]
}

run "rejects_an_admin_that_is_also_the_addons_runner" {
  command = plan

  variables {
    cluster_admin_principal_arns = ["arn:aws:iam::111111111111:role/example-dev-eks-addons-apply"]
  }

  expect_failures = [var.ci_deploy_principal_arn]
}

run "rejects_a_duplicated_admin" {
  command = plan

  variables {
    cluster_admin_principal_arns = ["arn:aws:iam::111111111111:role/example-dev-eks-admin", "arn:aws:iam::111111111111:role/example-dev-eks-admin"]
  }

  expect_failures = [var.ci_deploy_principal_arn]
}

# ---- Pod Identity ----

run "pod_identity_links_each_service_account_to_its_role" {
  command = plan

  assert {
    condition = local.pod_identity_associations == {
      api              = { namespace = "app", service_account = "api", role_arn = "arn:aws:iam::111111111111:role/example-dev-api-pod" }
      worker           = { namespace = "app", service_account = "worker", role_arn = "arn:aws:iam::111111111111:role/example-dev-worker-pod" }
      lb_controller    = { namespace = "kube-system", service_account = "aws-load-balancer-controller", role_arn = "arn:aws:iam::111111111111:role/example-dev-lb-controller" }
      keda             = { namespace = "keda", service_account = "keda-operator", role_arn = "arn:aws:iam::111111111111:role/example-dev-keda" }
      cloudwatch_agent = { namespace = "amazon-cloudwatch", service_account = "cloudwatch-agent", role_arn = "arn:aws:iam::111111111111:role/example-dev-cloudwatch-agent" }
    }
    error_message = "api and worker in app_namespace, the three controllers at the eks-addons module defaults, each with its own role"
  }
}

run "rejects_api_and_worker_sharing_a_service_account" {
  command = plan

  variables {
    worker_service_account = "api"
  }

  expect_failures = [var.worker_service_account]
}

run "rejects_a_kube_system_app_namespace" {
  command = plan

  variables {
    app_namespace = "kube-system"
  }

  expect_failures = [var.app_namespace]
}

# ---- contract ----

run "publishes_the_versioned_eks_contract" {
  command = plan

  assert {
    condition = toset(keys(local.published_strings)) == toset([
      "contract_version", "cluster_name", "cluster_endpoint", "cluster_ca_data", "cluster_sg_id", "service_cidr",
      "app_namespace", "api_service_account", "worker_service_account",
    ])
    error_message = "eks-cluster publishes exactly the keys of design v4 §8.1"
  }

  assert {
    condition     = local.published_strings["contract_version"] == "1" && local.published_strings["cluster_name"] == "example-dev"
    error_message = "The contract starts at version 1 and names the cluster"
  }

  assert {
    condition = (
      local.published_strings["app_namespace"] == "app" &&
      local.published_strings["api_service_account"] == "api" &&
      local.published_strings["worker_service_account"] == "worker"
    )
    error_message = "The chart reads the namespace and ServiceAccount names from SSM so the Pod Identity associations match"
  }

  assert {
    condition     = module.ssm_publish.names["contract_version"] == "/example/dev/eks-cluster/contract_version"
    error_message = "The contract lives in tree A under /<project>/<env>/eks-cluster/"
  }
}
