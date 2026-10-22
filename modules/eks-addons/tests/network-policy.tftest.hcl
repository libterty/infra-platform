# NetworkPolicy controller switch and the system NetworkPolicies (local chart system-network-policy).
# No cluster is contacted: helm is mocked.

mock_provider "helm" {}

variables {
  cluster_name = "alpha-dev"
  region       = "ap-northeast-1"
  vpc_id       = "vpc-0123456789abcdef0"
}

run "network_policy_null_installs_nothing" {
  command = plan

  variables {
    load_balancer_controller = {}
    keda                     = {}
  }

  assert {
    condition     = length(helm_release.system_network_policy) == 0
    error_message = "network_policy = null must not install the policy chart"
  }
}

run "network_policy_release" {
  command = plan

  variables {
    network_policy = {
      service_cidr     = "172.20.0.0/16"
      api_server_cidrs = ["10.10.0.0/28", "10.10.0.16/28"]
      aws_api_cidrs    = ["10.10.1.0/28"]
    }
  }

  assert {
    condition = (
      helm_release.system_network_policy[0].name == "system-network-policy" &&
      helm_release.system_network_policy[0].version == "0.1.0" &&
      helm_release.system_network_policy[0].namespace == "kube-system" &&
      helm_release.system_network_policy[0].repository == null &&
      endswith(helm_release.system_network_policy[0].chart, "/charts/system-network-policy") &&
      helm_release.system_network_policy[0].atomic
    )
    error_message = "system-network-policy must be the local chart at version 0.1.0, atomic, in kube-system"
  }

  assert {
    condition     = yamldecode(helm_release.system_network_policy[0].values[0]).enableNetworkPolicyController == true
    error_message = "The amazon-vpc-cni ConfigMap switch must be on"
  }

  assert {
    condition     = yamldecode(helm_release.system_network_policy[0].values[0]).policies == {}
    error_message = "With no controller installed there is no system policy, only the ConfigMap"
  }

  assert {
    condition     = output.releases.system_network_policy.name == "system-network-policy"
    error_message = "releases must list system_network_policy"
  }
}

run "lb_controller_policy" {
  command = plan

  variables {
    load_balancer_controller = {}
    network_policy = {
      service_cidr     = "172.20.0.0/16"
      api_server_cidrs = ["10.10.0.0/28", "10.10.0.16/28"]
      aws_api_cidrs    = ["10.10.1.0/28"]
    }
  }

  assert {
    condition = yamldecode(helm_release.system_network_policy[0].values[0]).policies.load_balancer_controller == {
      namespace = "kube-system"
      podSelector = {
        "app.kubernetes.io/name" = "aws-load-balancer-controller"
      }
      ingress = [
        { cidrs = ["10.10.0.0/28", "10.10.0.16/28"], sameNamespace = false, ports = [{ port = 9443, protocol = "TCP" }] },
      ]
      egress = [
        { cidrs = ["10.10.0.0/28", "10.10.0.16/28"], sameNamespace = false, ports = [{ port = 443, protocol = "TCP" }] },
        { cidrs = ["172.20.0.10/32"], sameNamespace = false, ports = [{ port = 53, protocol = "UDP" }, { port = 53, protocol = "TCP" }] },
        { cidrs = ["10.10.1.0/28"], sameNamespace = false, ports = [{ port = 443, protocol = "TCP" }] },
        { cidrs = ["169.254.170.23/32"], sameNamespace = false, ports = [{ port = 80, protocol = "TCP" }] },
      ]
    }
    error_message = "The LB Controller policy must select only its own pods in kube-system: webhook 9443 from the API server CIDRs; egress to API server 443, DNS 53 UDP+TCP at the service CIDR .10, AWS APIs 443 and the Pod Identity agent"
  }

  assert {
    condition     = yamldecode(helm_release.system_network_policy[0].values[0]).namespaces == []
    error_message = "kube-system already exists: the chart must not create it"
  }
}

run "keda_policy" {
  command = plan

  variables {
    keda = { namespace = "autoscaling" }
    network_policy = {
      service_cidr     = "172.20.0.0/16"
      api_server_cidrs = ["10.10.0.0/28"]
      aws_api_cidrs    = ["10.10.1.0/28"]
    }
  }

  assert {
    condition = yamldecode(helm_release.system_network_policy[0].values[0]).policies.keda == {
      namespace   = "autoscaling"
      podSelector = {}
      ingress = [
        { cidrs = ["10.10.0.0/28"], sameNamespace = false, ports = [{ port = 6443, protocol = "TCP" }, { port = 9443, protocol = "TCP" }] },
        { cidrs = [], sameNamespace = true, ports = [{ port = 9666, protocol = "TCP" }] },
      ]
      egress = [
        { cidrs = ["10.10.0.0/28"], sameNamespace = false, ports = [{ port = 443, protocol = "TCP" }] },
        { cidrs = ["172.20.0.10/32"], sameNamespace = false, ports = [{ port = 53, protocol = "UDP" }, { port = 53, protocol = "TCP" }] },
        { cidrs = ["10.10.1.0/28"], sameNamespace = false, ports = [{ port = 443, protocol = "TCP" }] },
        { cidrs = ["169.254.170.23/32"], sameNamespace = false, ports = [{ port = 80, protocol = "TCP" }] },
        { cidrs = [], sameNamespace = true, ports = [{ port = 9666, protocol = "TCP" }] },
      ]
    }
    error_message = "KEDA policy: API server to metrics apiserver 6443 and webhook 9443, operator gRPC 9666 inside the namespace, plus the common egress"
  }

  assert {
    condition     = yamldecode(helm_release.system_network_policy[0].values[0]).namespaces == ["autoscaling"]
    error_message = "The chart must create the KEDA namespace so the policy can exist before the controller"
  }
}

run "cloudwatch_policy" {
  command = plan

  variables {
    cloudwatch_observability = {}
    network_policy = {
      service_cidr     = "172.20.0.0/16"
      api_server_cidrs = ["10.10.0.0/28"]
      aws_api_cidrs    = ["10.10.1.0/28"]
    }
  }

  assert {
    condition = (
      yamldecode(helm_release.system_network_policy[0].values[0]).policies.cloudwatch_observability.namespace == "amazon-cloudwatch" &&
      yamldecode(helm_release.system_network_policy[0].values[0]).policies.cloudwatch_observability.podSelector == {} &&
      yamldecode(helm_release.system_network_policy[0].values[0]).policies.cloudwatch_observability.ingress == [
        { cidrs = ["10.10.0.0/28"], sameNamespace = false, ports = [{ port = 9443, protocol = "TCP" }] },
      ] &&
      length(yamldecode(helm_release.system_network_policy[0].values[0]).policies.cloudwatch_observability.egress) == 4
    )
    error_message = "CloudWatch policy: operator webhook 9443 from the API server, and the common egress"
  }

  assert {
    condition     = yamldecode(helm_release.system_network_policy[0].values[0]).namespaces == ["amazon-cloudwatch"]
    error_message = "The chart must create the amazon-cloudwatch namespace"
  }
}

run "all_policies_and_namespaces_sorted" {
  command = plan

  variables {
    load_balancer_controller = {}
    keda                     = {}
    cloudwatch_observability = {}
    network_policy = {
      service_cidr     = "172.20.0.0/24"
      api_server_cidrs = ["10.10.0.0/28"]
      aws_api_cidrs    = ["10.10.1.0/28"]
    }
  }

  assert {
    condition     = keys(yamldecode(helm_release.system_network_policy[0].values[0]).policies) == ["cloudwatch_observability", "keda", "load_balancer_controller"]
    error_message = "One policy per installed component"
  }

  assert {
    condition     = yamldecode(helm_release.system_network_policy[0].values[0]).namespaces == ["amazon-cloudwatch", "keda"]
    error_message = "Namespaces other than kube-system, sorted"
  }

  assert {
    condition     = yamldecode(helm_release.system_network_policy[0].values[0]).policies.keda.egress[1].cidrs == ["172.20.0.10/32"]
    error_message = "The DNS resolver is the .10 of the service CIDR"
  }
}
