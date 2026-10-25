mock_provider "aws" {}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
  vpc_cidr            = "10.40.0.0/20"
  azs                 = ["ap-northeast-1a", "ap-northeast-1c"]
  flow_log            = true
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/flow_log_bucket_arn"]
  values = { insecure_value = "arn:aws:s3:::example-dev-flow-logs-111111111111" }
}

run "reads_only_the_flow_log_bucket" {
  command = plan

  assert {
    condition     = local.ssm_input_strings == { flow_log_bucket_arn = "foundation/flow_log_bucket_arn" } && local.ssm_input_lists == {}
    error_message = "network must read the flow log bucket from foundation and nothing else"
  }
}

run "vpc_is_two_az_without_nat_and_has_the_s3_gateway_endpoint" {
  command = plan

  assert {
    condition     = local.vpc.cidr == "10.40.0.0/20" && local.vpc.azs == tolist(["ap-northeast-1a", "ap-northeast-1c"]) && length(local.vpc.azs) == 2
    error_message = "The VPC must use the given CIDR and two AZs"
  }

  assert {
    condition     = local.vpc.nat_mode == "none"
    error_message = "example5 has no NAT: nat_mode must be none (design K33)"
  }

  assert {
    condition     = local.vpc.gateway_endpoints == toset(["s3"])
    error_message = "The VPC must have exactly the s3 gateway endpoint (design K33)"
  }

  assert {
    condition     = toset(keys(local.vpc.subnets)) == toset(["app", "data"]) && local.vpc.subnets["app"].type == "private" && local.vpc.subnets["data"].type == "isolated"
    error_message = "The VPC must have a private app tier and an isolated data tier, and no public tier"
  }
}

run "flow_log_goes_to_the_foundation_bucket" {
  command = plan

  assert {
    condition     = local.vpc.flow_log == { destination_arn = "arn:aws:s3:::example-dev-flow-logs-111111111111" }
    error_message = "Flow logs must go to the flow log bucket published by foundation"
  }
}

run "flow_log_off_creates_no_flow_log" {
  command = plan

  variables {
    flow_log = false
  }

  assert {
    condition     = local.vpc.flow_log == null
    error_message = "flow_log = false must not configure a flow log"
  }
}

run "publishes_exactly_the_network_keys" {
  command = plan

  override_module {
    target = module.vpc
    outputs = {
      vpc_id          = "vpc-0123456789abcdef0"
      vpc_cidr        = "10.40.0.0/20"
      azs             = ["ap-northeast-1a", "ap-northeast-1c"]
      subnet_ids      = { app = ["subnet-0app1", "subnet-0app2"], data = ["subnet-0dat1", "subnet-0dat2"] }
      subnet_cidrs    = { app = ["10.40.0.0/24", "10.40.1.0/24"], data = ["10.40.5.0/27", "10.40.5.32/27"] }
      route_table_ids = { app = ["rtb-0app1", "rtb-0app2"], data = ["rtb-0dat1", "rtb-0dat2"] }
      nat_gateway_ids = []
    }
  }

  assert {
    condition = toset(keys(local.published_strings)) == toset([
      "vpc_id",
      "vpc_cidr",
      "sg_opensearch_id",
      "sg_firehose_id",
      "sg_sagemaker_id",
      "sg_client_vpn_id",
      "sg_search_admin_id",
    ])
    error_message = "network must publish exactly the String keys of design section 7.2"
  }

  assert {
    condition = toset(keys(local.published_lists)) == toset([
      "azs",
      "subnet_ids_app",
      "subnet_ids_data",
      "subnet_cidrs_data",
    ])
    error_message = "network must publish exactly the StringList keys of design section 7.2"
  }

  assert {
    condition     = local.published_strings["vpc_id"] == "vpc-0123456789abcdef0" && local.published_strings["vpc_cidr"] == "10.40.0.0/20"
    error_message = "vpc_id and vpc_cidr must come from the VPC"
  }

  assert {
    condition = (
      tolist(local.published_lists["azs"]) == tolist(["ap-northeast-1a", "ap-northeast-1c"]) &&
      tolist(local.published_lists["subnet_ids_app"]) == tolist(["subnet-0app1", "subnet-0app2"]) &&
      tolist(local.published_lists["subnet_ids_data"]) == tolist(["subnet-0dat1", "subnet-0dat2"]) &&
      tolist(local.published_lists["subnet_cidrs_data"]) == tolist(["10.40.5.0/27", "10.40.5.32/27"])
    )
    error_message = "The list keys must carry the subnets of the matching tier in AZ order"
  }
}

run "publishes_under_stack_path" {
  command = plan

  assert {
    condition = module.ssm_publish.names == {
      vpc_id             = "/example/dev/network/vpc_id"
      vpc_cidr           = "/example/dev/network/vpc_cidr"
      sg_opensearch_id   = "/example/dev/network/sg_opensearch_id"
      sg_firehose_id     = "/example/dev/network/sg_firehose_id"
      sg_sagemaker_id    = "/example/dev/network/sg_sagemaker_id"
      sg_client_vpn_id   = "/example/dev/network/sg_client_vpn_id"
      sg_search_admin_id = "/example/dev/network/sg_search_admin_id"
      azs                = "/example/dev/network/azs"
      subnet_ids_app     = "/example/dev/network/subnet_ids_app"
      subnet_ids_data    = "/example/dev/network/subnet_ids_data"
      subnet_cidrs_data  = "/example/dev/network/subnet_cidrs_data"
    }
    error_message = "ssm-publish must write the contract keys under the network stack path"
  }
}

run "five_security_groups" {
  command = plan

  assert {
    condition     = toset(keys(local.security_groups)) == toset(["opensearch", "firehose", "sagemaker", "client_vpn", "search_admin"])
    error_message = "network must create exactly the five security groups of the contract"
  }

  assert {
    condition     = local.security_groups["opensearch"].name == "example-dev-opensearch" && local.security_groups["sagemaker"].name == "example-dev-sagemaker" && local.security_groups["search_admin"].name == "example-dev-search-admin"
    error_message = "Security group names must be <name_prefix>-<key with hyphens>"
  }
}

run "sg_rules_are_exactly_the_three_connections_and_sagemaker_in_vpc" {
  command = plan

  assert {
    condition = toset(keys(local.sg_rules)) == toset([
      "firehose_out_opensearch", "opensearch_in_firehose",
      "client_vpn_out_opensearch", "opensearch_in_client_vpn",
      "search_admin_out_opensearch", "opensearch_in_search_admin",
      "sagemaker_in_vpc", "sagemaker_out_vpc",
    ])
    error_message = "There must be one egress and one ingress rule for each OpenSearch caller, the two SageMaker VPC rules, and nothing else"
  }
}

run "firehose_to_opensearch_443" {
  command = plan

  assert {
    condition = (
      local.sg_rules["firehose_out_opensearch"].type == "egress" && local.sg_rules["firehose_out_opensearch"].security_group == "firehose" &&
      local.sg_rules["firehose_out_opensearch"].peer_group == "opensearch" && local.sg_rules["firehose_out_opensearch"].from_port == 443
    )
    error_message = "Firehose must have an egress rule to the OpenSearch group on 443"
  }

  assert {
    condition = (
      local.sg_rules["opensearch_in_firehose"].type == "ingress" && local.sg_rules["opensearch_in_firehose"].security_group == "opensearch" &&
      local.sg_rules["opensearch_in_firehose"].peer_group == "firehose" && local.sg_rules["opensearch_in_firehose"].from_port == 443
    )
    error_message = "OpenSearch must accept 443 from the Firehose group"
  }
}

run "client_vpn_to_opensearch_443" {
  command = plan

  assert {
    condition = (
      local.sg_rules["client_vpn_out_opensearch"].type == "egress" && local.sg_rules["client_vpn_out_opensearch"].security_group == "client_vpn" &&
      local.sg_rules["client_vpn_out_opensearch"].peer_group == "opensearch" && local.sg_rules["client_vpn_out_opensearch"].from_port == 443 &&
      local.sg_rules["opensearch_in_client_vpn"].type == "ingress" && local.sg_rules["opensearch_in_client_vpn"].security_group == "opensearch" &&
      local.sg_rules["opensearch_in_client_vpn"].peer_group == "client_vpn" && local.sg_rules["opensearch_in_client_vpn"].from_port == 443
    )
    error_message = "Client VPN must reach OpenSearch on 443 (egress on the VPN group, ingress on the OpenSearch group)"
  }
}

run "search_admin_to_opensearch_443" {
  command = plan

  assert {
    condition = (
      local.sg_rules["search_admin_out_opensearch"].type == "egress" && local.sg_rules["search_admin_out_opensearch"].security_group == "search_admin" &&
      local.sg_rules["search_admin_out_opensearch"].peer_group == "opensearch" && local.sg_rules["search_admin_out_opensearch"].from_port == 443 &&
      local.sg_rules["opensearch_in_search_admin"].type == "ingress" && local.sg_rules["opensearch_in_search_admin"].security_group == "opensearch" &&
      local.sg_rules["opensearch_in_search_admin"].peer_group == "search_admin" && local.sg_rules["opensearch_in_search_admin"].from_port == 443
    )
    error_message = "The search admin runner must reach OpenSearch on 443 (egress on the runner group, ingress on the OpenSearch group)"
  }
}

# SageMaker endpoint ENIs talk HTTPS inside the VPC only (design section 7.1).
run "sagemaker_443_within_the_vpc" {
  command = plan

  assert {
    condition = (
      local.sg_rules["sagemaker_in_vpc"].type == "ingress" && local.sg_rules["sagemaker_in_vpc"].security_group == "sagemaker" &&
      local.sg_rules["sagemaker_in_vpc"].cidr_ipv4 == "10.40.0.0/20" && local.sg_rules["sagemaker_in_vpc"].from_port == 443 &&
      local.sg_rules["sagemaker_in_vpc"].peer_group == null && !local.sg_rules["sagemaker_in_vpc"].allow_internet
    )
    error_message = "The SageMaker group must accept 443 from the VPC CIDR only"
  }

  assert {
    condition = (
      local.sg_rules["sagemaker_out_vpc"].type == "egress" && local.sg_rules["sagemaker_out_vpc"].security_group == "sagemaker" &&
      local.sg_rules["sagemaker_out_vpc"].cidr_ipv4 == "10.40.0.0/20" && local.sg_rules["sagemaker_out_vpc"].from_port == 443 &&
      local.sg_rules["sagemaker_out_vpc"].peer_group == null
    )
    error_message = "The SageMaker group may send 443 to the VPC CIDR only"
  }
}

run "sg_rules_never_open_beyond_the_vpc" {
  command = plan

  assert {
    condition     = alltrue([for r in values(local.sg_rules) : r.prefix_list_id == null && !r.allow_internet && (r.cidr_ipv4 == null ? r.peer_group != null : (r.cidr_ipv4 == var.vpc_cidr && r.security_group == "sagemaker"))])
    error_message = "Every rule must name a peer security group, except the SageMaker rules, which use the VPC CIDR; no prefix list or internet rule"
  }

  assert {
    condition     = alltrue([for r in values(local.sg_rules) : r.from_port == 443 && (r.cidr_ipv4 != null || (r.type == "ingress" ? r.security_group : r.peer_group) == "opensearch")])
    error_message = "Every rule is HTTPS: the peer rules all lead to OpenSearch"
  }

  assert {
    condition     = alltrue([for r in values(local.sg_rules) : r.peer_group != "opensearch" || r.type == "egress"])
    error_message = "OpenSearch is only ever the target: it appears as a peer only in the callers' egress rules"
  }

  assert {
    condition     = length([for r in values(local.sg_rules) : r if r.type == "egress" && r.security_group == "opensearch"]) == 0
    error_message = "OpenSearch must have no egress rules"
  }
}

# ---- interface endpoints (design K33): only SageMaker runtime, off unless tfvars list it ----

run "interface_endpoints_default_to_none" {
  command = plan

  assert {
    condition     = length(var.interface_endpoint_services) == 0 && length(local.interface_endpoints.services) == 0
    error_message = "No interface endpoint may be created by default"
  }
}

run "interface_endpoint_for_sagemaker_runtime" {
  command = plan

  variables {
    interface_endpoint_services = ["sagemaker.runtime"]
  }

  assert {
    condition     = local.interface_endpoints.services == toset(["sagemaker.runtime"])
    error_message = "Listing sagemaker.runtime must create its interface endpoint"
  }

  assert {
    condition     = tolist(local.interface_endpoints.allowed_cidrs) == tolist(["10.40.0.0/20"])
    error_message = "Only the VPC may reach the interface endpoint on 443"
  }
}

run "interface_endpoint_other_service_rejected" {
  command = plan

  variables {
    interface_endpoint_services = ["ecr.api"]
  }

  expect_failures = [var.interface_endpoint_services]
}

# ---- common.tf and providers.tf guards: the same runs in every stack ----

run "env_format_uppercase_rejected" {
  command = plan

  variables {
    env = "Dev"
  }

  expect_failures = [var.env]
}

run "env_format_too_short_rejected" {
  command = plan

  variables {
    env = "d"
  }

  expect_failures = [var.env]
}

run "env_format_valid_passes" {
  command = plan

  variables {
    env = "dev"
  }

  assert {
    condition     = local.name_prefix == "example-dev" && local.ssm_prefix == "/example/dev"
    error_message = "A valid env must give the name prefix and the SSM prefix"
  }
}

run "project_format_rejected" {
  command = plan

  variables {
    project = "Example"
  }

  expect_failures = [var.project]
}

run "account_must_match_env" {
  command = plan

  variables {
    env                 = "dev"
    expected_account_id = "222222222222"
  }

  expect_failures = [var.expected_account_id]
}

run "account_unknown_env_rejected" {
  command = plan

  variables {
    env                 = "staging"
    expected_account_id = "111111111111"
  }

  expect_failures = [var.expected_account_id]
}

run "account_matching_env_passes" {
  command = plan

  variables {
    env                 = "sit"
    expected_account_id = "222222222222"
  }

  assert {
    condition     = local.name_prefix == "example-sit" && contains(local.accounts_by_env["sit"], var.expected_account_id)
    error_message = "A sit account with env sit must pass"
  }
}

run "account_is_required" {
  command = plan

  variables {
    expected_account_id = null
  }

  expect_failures = [var.expected_account_id]
}

# A default would let a missing tfvars file point at some account silently.
run "account_has_no_default" {
  command = plan

  assert {
    condition     = length(regexall("(?s)variable \"expected_account_id\" \\{[^}]*\\n\\s*default\\s*=", file("${path.module}/common.tf"))) == 0
    error_message = "expected_account_id must not have a default value"
  }
}

run "deploy_role_in_other_account_rejected" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::222222222222:role/deploy"
  }

  expect_failures = [var.deploy_role_arn]
}

run "deploy_role_in_expected_account_passes" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::111111111111:role/deploy"
  }

  assert {
    condition     = var.deploy_role_arn == "arn:aws:iam::111111111111:role/deploy"
    error_message = "A role in the expected account must pass"
  }
}
